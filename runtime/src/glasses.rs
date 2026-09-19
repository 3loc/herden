//! The deliberately small HTTP boundary used by the optional Even G2 HUD.
//!
//! This lives in the Host process.  It is intentionally not an alternative
//! transport for the iOS app or the JSON API: it projects Agent status and
//! accepts only two explicit, opt-in controls.

use std::collections::HashMap;
use std::fs::{self, OpenOptions};
use std::io::{self, BufRead, BufReader, Read, Write};
use std::net::{IpAddr, SocketAddr, TcpListener, TcpStream};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use base64::Engine as _;
use getrandom::getrandom;
use serde::{Deserialize, Serialize};

use crate::api::client::ApiClient;
use crate::api::schema::Request;

pub const HUD_PROTOCOL_VERSION: u32 = 1;
pub const DEFAULT_PORT: u16 = 8791;
const MAX_CLIENTS: usize = 8;
const MAX_REQUEST_BYTES: usize = 8 * 1024;
const MAX_OUTPUT_CHARS: usize = 96 * 1024;
const OUTPUT_LINES: u32 = 1_000;
const SNAPSHOT_INTERVAL: Duration = Duration::from_secs(1);
const KEEPALIVE_INTERVAL: Duration = Duration::from_secs(15);

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Settings {
    pub enabled: bool,
    pub bind: String,
    pub port: u16,
    pub controls: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct Credential {
    token: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct RuntimeStatus {
    enabled: bool,
    listener: String,
    state: String,
    controls: bool,
    clients: usize,
    detail: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
struct Agent {
    id: String,
    name: String,
    kind: String,
    space: String,
    status: String,
    pinned: bool,
}

#[derive(Debug, Clone, Serialize)]
struct Snapshot {
    protocol_version: u32,
    #[serde(rename = "type")]
    kind: &'static str,
    revision: u64,
    at: u64,
    inventory_valid: bool,
    stale: bool,
    controls_allowed: bool,
    agents: Vec<Agent>,
    wake: Vec<String>,
    summary: String,
}

#[derive(Debug, Clone, Serialize)]
struct AgentOutput {
    agent_id: String,
    text: String,
    source: &'static str,
}

#[derive(Debug, Clone)]
struct Projection {
    snapshot: Snapshot,
    previous: HashMap<String, String>,
    recent_commands: HashMap<String, Instant>,
}

impl Projection {
    fn offline(controls: bool) -> Self {
        Self {
            snapshot: Snapshot {
                protocol_version: HUD_PROTOCOL_VERSION,
                kind: "snapshot",
                revision: 0,
                at: now_millis(),
                inventory_valid: false,
                stale: true,
                controls_allowed: controls,
                agents: Vec::new(),
                wake: Vec::new(),
                summary: "Host inventory unavailable".into(),
            },
            previous: HashMap::new(),
            recent_commands: HashMap::new(),
        }
    }

    fn refresh(&mut self, settings: &Settings) {
        let result = list_agents();
        let Ok(raw_agents) = result else {
            self.snapshot.at = now_millis();
            self.snapshot.inventory_valid = false;
            self.snapshot.stale = true;
            self.snapshot.controls_allowed = settings.controls;
            self.snapshot.wake.clear();
            self.snapshot.summary = "Host inventory unavailable".into();
            self.snapshot.revision = self.snapshot.revision.saturating_add(1);
            return;
        };

        let agents = order_agents(raw_agents);
        let next: HashMap<_, _> = agents
            .iter()
            .map(|agent| (agent.id.clone(), agent.status.clone()))
            .collect();
        let wake = agents
            .iter()
            .filter(|agent| {
                matches!(agent.status.as_str(), "blocked" | "failed" | "done")
                    && self
                        .previous
                        .get(&agent.id)
                        .is_some_and(|prior| prior != &agent.status)
            })
            .map(|agent| agent.id.clone())
            .collect();

        self.snapshot = Snapshot {
            protocol_version: HUD_PROTOCOL_VERSION,
            kind: "snapshot",
            revision: self.snapshot.revision.saturating_add(1),
            at: now_millis(),
            inventory_valid: true,
            stale: false,
            controls_allowed: settings.controls,
            summary: summarise(&agents),
            agents,
            wake,
        };
        self.previous = next;
    }
}

pub fn settings_path() -> PathBuf {
    crate::session::data_dir().join("glasses.toml")
}

fn credential_path() -> PathBuf {
    crate::session::data_dir().join("glasses-credential.json")
}

fn status_path() -> PathBuf {
    crate::session::data_dir().join("glasses-status.json")
}

pub fn load_settings() -> io::Result<Option<Settings>> {
    match fs::read_to_string(settings_path()) {
        Ok(value) => toml::from_str(&value)
            .map(Some)
            .map_err(|err| io::Error::new(io::ErrorKind::InvalidData, err)),
        Err(err) if err.kind() == io::ErrorKind::NotFound => Ok(None),
        Err(err) => Err(err),
    }
}

fn load_credential() -> io::Result<Credential> {
    serde_json::from_str(&fs::read_to_string(credential_path())?)
        .map_err(|err| io::Error::new(io::ErrorKind::InvalidData, err))
}

fn write_private(path: &Path, content: &[u8]) -> io::Result<()> {
    let parent = path
        .parent()
        .ok_or_else(|| io::Error::other("missing state directory"))?;
    fs::create_dir_all(parent)?;
    let temporary = parent.join(format!(
        ".{}.{}.tmp",
        path.file_name().and_then(|n| n.to_str()).unwrap_or("state"),
        std::process::id()
    ));
    let mut options = OpenOptions::new();
    options.write(true).create(true).truncate(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    let mut file = options.open(&temporary)?;
    file.write_all(content)?;
    file.sync_all()?;
    fs::rename(temporary, path)?;
    Ok(())
}

pub(crate) fn save_settings(settings: &Settings) -> io::Result<()> {
    let content = toml::to_string(settings).map_err(io::Error::other)?;
    write_private(&settings_path(), content.as_bytes())
}

fn save_status(status: &RuntimeStatus) {
    if let Ok(content) = serde_json::to_vec(status) {
        let _ = write_private(&status_path(), &content);
    }
}

fn random_token() -> io::Result<String> {
    let mut bytes = [0_u8; 32];
    getrandom(&mut bytes).map_err(|err| io::Error::other(err.to_string()))?;
    Ok(base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(bytes))
}

pub(crate) fn save_new_credential() -> io::Result<String> {
    let credential = Credential {
        token: random_token()?,
    };
    let content = serde_json::to_vec(&credential).map_err(io::Error::other)?;
    write_private(&credential_path(), &content)?;
    Ok(credential.token)
}

pub(crate) fn credential_token() -> io::Result<String> {
    load_credential().map(|credential| credential.token)
}

fn local_addresses() -> io::Result<Vec<IpAddr>> {
    let mut addresses = if_addrs::get_if_addrs()?
        .into_iter()
        .map(|interface| interface.ip())
        .filter(is_safe_private_bind)
        .collect::<Vec<_>>();
    addresses.sort();
    addresses.dedup();
    Ok(addresses)
}

fn is_safe_private_bind(address: &IpAddr) -> bool {
    match address {
        IpAddr::V4(ip) => {
            ip.is_private() || (ip.octets()[0] == 100 && (64..=127).contains(&ip.octets()[1]))
        }
        IpAddr::V6(ip) => ip.is_unique_local(),
    }
}

fn tailscale_candidates() -> io::Result<Vec<IpAddr>> {
    let mut candidates = if_addrs::get_if_addrs()?
        .into_iter()
        .filter(|interface| {
            interface.name.starts_with("tailscale") || interface.name.starts_with("ts")
        })
        .map(|interface| interface.ip())
        .filter(is_safe_private_bind)
        .collect::<Vec<_>>();
    candidates.sort();
    candidates.dedup();
    Ok(candidates)
}

pub(crate) fn choose_tailnet_address() -> Result<IpAddr, String> {
    let candidates = tailscale_candidates().map_err(|err| err.to_string())?;
    choose_tailnet_candidate(&candidates)
}

fn choose_tailnet_candidate(candidates: &[IpAddr]) -> Result<IpAddr, String> {
    let ipv4 = candidates
        .iter()
        .copied()
        .filter(IpAddr::is_ipv4)
        .collect::<Vec<_>>();
    match ipv4.as_slice() {
        [address] => return Ok(*address),
        [] => {}
        _ => {
            return Err(format!(
                "several Tailscale IPv4 addresses are available; choose one explicitly with --bind: {}",
                ipv4.iter().map(ToString::to_string).collect::<Vec<_>>().join(", ")
            ));
        }
    }
    match candidates {
        [address] => Ok(*address),
        [] => Err("no suitable local Tailscale address found; use --bind with one of this Host's private LAN addresses".into()),
        _ => Err(format!("several Tailscale addresses are available; choose one explicitly with --bind: {}", candidates.iter().map(ToString::to_string).collect::<Vec<_>>().join(", "))),
    }
}

pub(crate) fn validate_bind(raw: &str) -> Result<IpAddr, String> {
    let address: IpAddr = raw
        .parse()
        .map_err(|_| format!("{raw} is not an IP address"))?;
    if !is_safe_private_bind(&address) {
        return Err("the HUD may bind only a private LAN, Tailnet, or ULA address; public, loopback, and wildcard addresses are rejected".into());
    }
    let addresses = local_addresses().map_err(|err| err.to_string())?;
    if !addresses.contains(&address) {
        return Err(format!(
            "{address} does not belong to this Host; available private addresses: {}",
            addresses
                .iter()
                .map(ToString::to_string)
                .collect::<Vec<_>>()
                .join(", ")
        ));
    }
    Ok(address)
}

/// Starts the managed endpoint supervisor. It is called only by the existing
/// headless Host process and exits with it; it never starts another daemon.
pub fn spawn(should_quit: Arc<AtomicBool>) {
    if let Err(err) = thread::Builder::new()
        .name("herden-glasses-hud".into())
        .spawn(move || supervisor(should_quit))
    {
        tracing::warn!(%err, "failed to start glasses HUD supervisor");
    }
}

fn supervisor(should_quit: Arc<AtomicBool>) {
    let mut active: Option<Settings> = None;
    while !should_quit.load(Ordering::Acquire) {
        let settings = load_settings().ok().flatten();
        if settings.as_ref().is_none_or(|settings| !settings.enabled) {
            if active.take().is_some() {
                save_status(&RuntimeStatus {
                    enabled: false,
                    listener: String::new(),
                    state: "disabled".into(),
                    controls: false,
                    clients: 0,
                    detail: None,
                });
            }
            thread::sleep(Duration::from_millis(250));
            continue;
        }
        let settings = settings.expect("checked enabled settings");
        if let Err(reason) = validate_bind(&settings.bind) {
            save_status(&RuntimeStatus {
                enabled: true,
                listener: format!("{}:{}", settings.bind, settings.port),
                state: "error".into(),
                controls: settings.controls,
                clients: 0,
                detail: Some(reason),
            });
            thread::sleep(Duration::from_secs(1));
            continue;
        }
        active = Some(settings.clone());
        run_listener(&settings, &should_quit);
    }
}

fn run_listener(settings: &Settings, should_quit: &Arc<AtomicBool>) {
    let address = match validate_bind(&settings.bind) {
        Ok(address) => SocketAddr::new(address, settings.port),
        Err(_) => return,
    };
    let listener = match TcpListener::bind(address) {
        Ok(listener) => listener,
        Err(err) => {
            save_status(&RuntimeStatus {
                enabled: true,
                listener: address.to_string(),
                state: "error".into(),
                controls: settings.controls,
                clients: 0,
                detail: Some(format!("cannot bind HUD listener: {err}")),
            });
            thread::sleep(Duration::from_secs(1));
            return;
        }
    };
    if let Err(err) = listener.set_nonblocking(true) {
        save_status(&RuntimeStatus {
            enabled: true,
            listener: address.to_string(),
            state: "error".into(),
            controls: settings.controls,
            clients: 0,
            detail: Some(err.to_string()),
        });
        return;
    }
    let state = Arc::new(Mutex::new(Projection::offline(settings.controls)));
    let clients = Arc::new(AtomicUsize::new(0));
    let credential = match load_credential() {
        Ok(credential) => credential,
        Err(err) => {
            save_status(&RuntimeStatus {
                enabled: true,
                listener: address.to_string(),
                state: "error".into(),
                controls: settings.controls,
                clients: 0,
                detail: Some(format!("credential unavailable: {err}")),
            });
            return;
        }
    };
    let mut last_refresh = Instant::now() - SNAPSHOT_INTERVAL;
    while !should_quit.load(Ordering::Acquire) {
        let changed = load_settings().ok().flatten().as_ref() != Some(settings)
            || load_credential()
                .map(|value| value.token != credential.token)
                .unwrap_or(true);
        if changed {
            return;
        }
        if last_refresh.elapsed() >= SNAPSHOT_INTERVAL {
            if let Ok(mut projection) = state.lock() {
                projection.refresh(settings);
            }
            last_refresh = Instant::now();
        }
        save_status(&RuntimeStatus {
            enabled: true,
            listener: address.to_string(),
            state: "listening".into(),
            controls: settings.controls,
            clients: clients.load(Ordering::Relaxed),
            detail: None,
        });
        match listener.accept() {
            Ok((stream, _)) => {
                if clients.fetch_add(1, Ordering::AcqRel) >= MAX_CLIENTS {
                    clients.fetch_sub(1, Ordering::AcqRel);
                    let _ = write_response(stream, 503, "text/plain", b"busy\n", &[]);
                } else {
                    let state = Arc::clone(&state);
                    let clients = Arc::clone(&clients);
                    let settings = settings.clone();
                    let token = credential.token.clone();
                    thread::spawn(move || {
                        handle_connection(stream, &settings, &token, state);
                        clients.fetch_sub(1, Ordering::AcqRel);
                    });
                }
            }
            Err(err) if err.kind() == io::ErrorKind::WouldBlock => {
                thread::sleep(Duration::from_millis(30))
            }
            Err(err) => {
                tracing::warn!(%err, "glasses HUD accept failed");
                thread::sleep(Duration::from_millis(200));
            }
        }
    }
}

fn handle_connection(
    mut stream: TcpStream,
    settings: &Settings,
    token: &str,
    state: Arc<Mutex<Projection>>,
) {
    let _ = stream.set_read_timeout(Some(Duration::from_secs(5)));
    let _ = stream.set_write_timeout(Some(Duration::from_secs(5)));
    let request = match read_request(&mut stream) {
        Ok(request) => request,
        Err(_) => {
            let _ = write_response(stream, 400, "text/plain", b"bad request\n", &[]);
            return;
        }
    };
    let (method, target, headers, body) = request;
    if method == "GET" && target == "/health" {
        let _ = write_response(
            stream,
            200,
            "application/json",
            br#"{"ready":true,"protocol_version":1}"#,
            &[],
        );
        return;
    }
    let path = target.split('?').next().unwrap_or("");
    let query_token = query_parameter(&target, "token");
    let bearer = headers
        .get("authorization")
        .and_then(|value| value.strip_prefix("Bearer "));
    let supplied = bearer.or(query_token.as_deref()).unwrap_or("");
    if !timing_safe_eq(token.as_bytes(), supplied.as_bytes()) {
        let _ = write_response(stream, 401, "text/plain", b"unauthorized\n", &[]);
        return;
    }
    if method == "GET" && path == "/events" {
        stream_events(stream, token, state);
        return;
    }
    if method == "GET" && path == "/agent-output" {
        let _ = agent_output_response(stream, query_parameter(&target, "agent").as_deref());
        return;
    }
    if method == "POST" && path == "/command" {
        let _ = command_response(stream, settings, &state, &body);
        return;
    }
    let _ = write_response(stream, 404, "text/plain", b"not found\n", &[]);
}

fn agent_output_response(stream: TcpStream, agent_id: Option<&str>) -> io::Result<()> {
    let Some(agent_id) = agent_id.filter(|value| !value.is_empty()) else {
        return write_response(
            stream,
            400,
            "application/json",
            br#"{"error":"agent is required"}"#,
            &[],
        );
    };
    let exists = list_agents()
        .ok()
        .is_some_and(|agents| agents.iter().any(|agent| agent.id == agent_id));
    if !exists {
        return write_response(
            stream,
            404,
            "application/json",
            br#"{"error":"agent no longer exists"}"#,
            &[],
        );
    }
    match read_agent_output(agent_id) {
        Ok(output) => serde_json::to_vec(&output)
            .map_err(io::Error::other)
            .and_then(|body| write_response(stream, 200, "application/json", &body, &[])),
        Err(_) => write_response(
            stream,
            503,
            "application/json",
            br#"{"error":"output is temporarily unavailable"}"#,
            &[],
        ),
    }
}

fn stream_events(mut stream: TcpStream, token: &str, state: Arc<Mutex<Projection>>) {
    let cors = [
        ("Cache-Control", "no-cache"),
        ("Connection", "keep-alive"),
        ("X-Accel-Buffering", "no"),
    ];
    if write_headers(&mut stream, 200, "text/event-stream", &cors).is_err() {
        return;
    }
    let mut revision = u64::MAX;
    let mut last_keepalive = Instant::now();
    loop {
        if load_credential()
            .map(|value| timing_safe_eq(value.token.as_bytes(), token.as_bytes()))
            .unwrap_or(false)
            == false
        {
            return;
        }
        let snapshot = state
            .lock()
            .ok()
            .map(|projection| projection.snapshot.clone());
        let Some(snapshot) = snapshot else {
            return;
        };
        if snapshot.revision != revision {
            let mut initial = snapshot;
            if revision == u64::MAX {
                initial.wake.clear();
            }
            let Ok(json) = serde_json::to_string(&initial) else {
                return;
            };
            if write!(stream, "data: {json}\n\n")
                .and_then(|_| stream.flush())
                .is_err()
            {
                return;
            }
            revision = initial.revision;
        } else if last_keepalive.elapsed() >= KEEPALIVE_INTERVAL {
            if write!(stream, ": keepalive\n\n")
                .and_then(|_| stream.flush())
                .is_err()
            {
                return;
            }
            last_keepalive = Instant::now();
        }
        thread::sleep(Duration::from_millis(250));
    }
}

#[derive(Deserialize)]
struct Command {
    action: String,
    #[serde(rename = "agentId")]
    agent_id: String,
    #[serde(default)]
    text: Option<String>,
    #[serde(default)]
    submit: Option<bool>,
}

/// One validated `pane.send_input` parameter object, plus the key that
/// suppresses an immediate resend of the same intent.
struct PlannedCommand {
    agent_id: String,
    params: serde_json::Value,
    rate_key: String,
}

/// A refusal carries the HTTP status and the exact JSON body written back, so
/// every rejection path stays one shape regardless of which check tripped.
type Refusal = (u16, &'static str);

/// A dictated phrase, not a script. Long enough for a spoken sentence or a
/// short command line, short enough that a mis-transcribed stream cannot fill
/// an Agent's prompt. Counted in characters, not bytes, so non-Latin
/// dictation is not silently penalised.
const MAX_COMMAND_TEXT_CHARS: usize = 512;

/// Dictation must reach the PTY as literal characters and nothing else.
///
/// `\n` and `\r` are the dangerous case and are **rejected, not converted**:
/// the PTY reads either as Enter, so a single embedded newline would submit a
/// line even though `submit` defaults to false, and everything after it would
/// run as a further command. Rewriting them to spaces would silently change
/// what the speaker said, which is worse than refusing. Every other control
/// character is rejected for the same reason — ESC opens an escape sequence,
/// and TUIs read tab as completion rather than as text. Ordinary spaces are
/// the only whitespace that survives.
fn validate_command_text(raw: &str) -> Result<String, Refusal> {
    let text = raw.trim();
    if text.is_empty() {
        return Err((400, r#"{"error":"text is required"}"#));
    }
    if text.chars().count() > MAX_COMMAND_TEXT_CHARS {
        return Err((400, r#"{"error":"text is too long"}"#));
    }
    if text.chars().any(char::is_control) {
        return Err((400, r#"{"error":"text contains control characters"}"#));
    }
    Ok(text.to_string())
}

fn plan_command(body: &[u8]) -> Result<PlannedCommand, Refusal> {
    let command: Command =
        serde_json::from_slice(body).map_err(|_| (400, r#"{"error":"invalid command"}"#))?;
    match command.action.as_str() {
        "send_enter" | "interrupt" => {
            let keys = if command.action == "send_enter" {
                "enter"
            } else {
                "ctrl+c"
            };
            Ok(PlannedCommand {
                rate_key: format!("{}:{}", command.action, command.agent_id),
                params: serde_json::json!({"pane_id": command.agent_id, "keys": [keys]}),
                agent_id: command.agent_id,
            })
        }
        "send_text" => {
            let text = validate_command_text(command.text.as_deref().unwrap_or(""))?;
            // `submit` defaults to false so dictation inserts without firing a
            // command. When it is true the text and Enter travel in one
            // `pane.send_input` call, which the Host applies atomically; two
            // calls could interleave with another writer's input.
            let submit = command.submit.unwrap_or(false);
            let params = if submit {
                serde_json::json!({"pane_id": command.agent_id, "text": text, "keys": ["enter"]})
            } else {
                serde_json::json!({"pane_id": command.agent_id, "text": text})
            };
            Ok(PlannedCommand {
                // Distinct phrases are distinct intents; only a repeat of the
                // same phrase with the same submit choice is a duplicate.
                rate_key: format!("send_text:{}:{submit}:{text}", command.agent_id),
                params,
                agent_id: command.agent_id,
            })
        }
        _ => Err((400, r#"{"error":"unsupported command"}"#)),
    }
}

/// Every decision the command endpoint makes before it touches the network.
fn command_outcome(
    settings: &Settings,
    state: &Arc<Mutex<Projection>>,
    body: &[u8],
    agent_exists: impl FnOnce(&str) -> bool,
) -> Result<serde_json::Value, Refusal> {
    if !settings.controls {
        return Err((403, r#"{"error":"controls are disabled"}"#));
    }
    let command = plan_command(body)?;
    if let Ok(mut projection) = state.lock() {
        projection
            .recent_commands
            .retain(|_, sent| sent.elapsed() < Duration::from_secs(5));
        if projection
            .recent_commands
            .get(&command.rate_key)
            .is_some_and(|sent| sent.elapsed() < Duration::from_millis(750))
        {
            return Err((409, r#"{"error":"duplicate command ignored"}"#));
        }
        projection
            .recent_commands
            .insert(command.rate_key, Instant::now());
    }
    if !agent_exists(&command.agent_id) {
        return Err((404, r#"{"error":"agent no longer exists"}"#));
    }
    Ok(command.params)
}

fn command_response(
    stream: TcpStream,
    settings: &Settings,
    state: &Arc<Mutex<Projection>>,
    body: &[u8],
) -> io::Result<()> {
    let params = match command_outcome(settings, state, body, |agent_id| {
        list_agents()
            .ok()
            .is_some_and(|agents| agents.iter().any(|agent| agent.id == agent_id))
    }) {
        Ok(params) => params,
        Err((status, body)) => {
            return write_response(stream, status, "application/json", body.as_bytes(), &[])
        }
    };
    let request: Request = serde_json::from_value(
        serde_json::json!({"id":"glasses:command","method":"pane.send_input","params":params}),
    )
    .map_err(io::Error::other)?;
    match ApiClient::local().request_value_with_timeout(&request, Duration::from_secs(2)) {
        Ok(value) if value.get("error").is_none() => write_response(
            stream,
            200,
            "application/json",
            br#"{"delivered":true}"#,
            &[],
        ),
        Ok(_) => write_response(
            stream,
            409,
            "application/json",
            br#"{"error":"command was not delivered"}"#,
            &[],
        ),
        Err(_) => write_response(
            stream,
            503,
            "application/json",
            br#"{"error":"delivery uncertain; do not automatically retry"}"#,
            &[],
        ),
    }
}

/// Reads the deepest usable output without exposing the Host's general RPC.
/// An idle Agent has recoverable recent history. A working TUI does not, so
/// fall back to the currently visible screen rather than claiming otherwise.
fn read_agent_output(agent_id: &str) -> Result<AgentOutput, String> {
    let recent = read_output(
        "agent.read",
        serde_json::json!({
            "target": agent_id,
            "source": "recent",
            "lines": OUTPUT_LINES,
            "format": "text",
            "strip_ansi": true,
        }),
    );
    match recent {
        Ok(text) => Ok(AgentOutput {
            agent_id: agent_id.to_string(),
            text: normalise_output(&text),
            source: "recent",
        }),
        Err(_) => read_output(
            "pane.read",
            serde_json::json!({
                "pane_id": agent_id,
                "source": "visible",
                "lines": OUTPUT_LINES,
                "format": "text",
                "strip_ansi": true,
            }),
        )
        .map(|text| AgentOutput {
            agent_id: agent_id.to_string(),
            text: normalise_output(&text),
            source: "visible",
        }),
    }
}

fn read_output(method: &str, params: serde_json::Value) -> Result<String, String> {
    let request: Request = serde_json::from_value(serde_json::json!({
        "id": "glasses:agent-output",
        "method": method,
        "params": params,
    }))
    .map_err(|err| err.to_string())?;
    let response = ApiClient::local()
        .request_value_with_timeout(&request, Duration::from_secs(2))
        .map_err(|err| err.to_string())?;
    response
        .pointer("/result/read/text")
        .and_then(serde_json::Value::as_str)
        .map(ToString::to_string)
        .ok_or_else(|| "output unavailable".to_string())
}

fn normalise_output(text: &str) -> String {
    let terminal_text = strip_terminal_sequences(text);
    let mut lines = Vec::new();
    for raw_line in terminal_text.lines() {
        // A carriage return redraws the current terminal row. The last segment
        // is the only version a wearer could actually have read.
        let line = raw_line.rsplit('\r').next().unwrap_or_default().trim();
        if line.is_empty() {
            continue;
        }
        if is_terminal_chrome(line) || lines.last().is_some_and(|previous| previous == line) {
            continue;
        }
        lines.push(line.to_string());
    }

    let mut clean = String::with_capacity(terminal_text.len().min(MAX_OUTPUT_CHARS));
    for line in lines {
        if !clean.is_empty() {
            clean.push('\n');
        }
        if clean.len().saturating_add(line.len()) > MAX_OUTPUT_CHARS {
            break;
        }
        clean.push_str(&line);
    }
    let clean = clean.trim();
    if clean.is_empty() {
        "No readable output yet.".to_string()
    } else {
        clean.to_string()
    }
}

/// Remove terminal control sequences before a terminal buffer becomes HUD text.
/// `pane.read(strip_ansi)` is advisory across compatible Host versions, so the
/// boundary has to be strict here. CSI includes SGR colours and cursor movement;
/// OSC/DCS/APC/PM carry titles and other out-of-band terminal data.
fn strip_terminal_sequences(text: &str) -> String {
    let bytes = text.as_bytes();
    let mut output = Vec::with_capacity(bytes.len());
    let mut index = 0;
    while index < bytes.len() {
        if bytes[index] != 0x1b {
            let byte = bytes[index];
            if byte == b'\n' || byte == b'\r' || byte == b'\t' || byte >= 0x20 {
                output.push(byte);
            }
            index += 1;
            continue;
        }

        index += 1;
        let Some(kind) = bytes.get(index).copied() else {
            break;
        };
        index += 1;
        match kind {
            b'[' => {
                // CSI ends at its final byte (0x40 through 0x7e).
                while let Some(byte) = bytes.get(index).copied() {
                    index += 1;
                    if (0x40..=0x7e).contains(&byte) {
                        break;
                    }
                }
            }
            b']' | b'P' | b'^' | b'_' => {
                // OSC accepts BEL; all string controls accept ST (ESC \\).
                while index < bytes.len() {
                    if bytes[index] == 0x07 {
                        index += 1;
                        break;
                    }
                    if bytes[index] == 0x1b && bytes.get(index + 1) == Some(&b'\\') {
                        index += 2;
                        break;
                    }
                    index += 1;
                }
            }
            _ => {
                // Two-byte escape sequences (charset selection, save cursor,
                // and similar) have no readable text payload.
            }
        }
    }
    String::from_utf8_lossy(&output).into_owned()
}

/// Full-screen coding tools redraw borders, prompts, spinners and ASCII art on
/// every frame. They are not Agent output, and on a ten-line display they can
/// crowd out the useful reply. Preserve ordinary punctuation-heavy logs/code.
fn is_terminal_chrome(line: &str) -> bool {
    let lower = line.to_ascii_lowercase();
    if matches!(line.chars().next(), Some('│' | '└' | '├' | '╰' | '╭'))
        || line
            .chars()
            .all(|character| matches!(character, '.' | '…' | ' '))
        || line.contains(" · ~/")
        || line.starts_with("$ ")
        || lower.starts_with("working (")
        || lower.starts_with("• working")
        || lower.starts_with("● working")
    {
        return true;
    }
    if lower.contains("ask codex to")
        || lower.contains("ask claude")
        || lower.contains("esc to interrupt")
        || lower.contains("jump to bottom")
    {
        return true;
    }

    let mut decoration = 0usize;
    let mut semantic = 0usize;
    for character in line.chars() {
        if character.is_alphanumeric() {
            semantic += 1;
        } else if matches!(
            character,
            '|' | '-'
                | '_'
                | '='
                | '+'
                | '*'
                | '#'
                | '/'
                | '\\'
                | '.'
                | ':'
                | '┌'
                | '┐'
                | '└'
                | '┘'
                | '├'
                | '┤'
                | '┬'
                | '┴'
                | '┼'
                | '─'
                | '│'
                | '╭'
                | '╮'
                | '╰'
                | '╯'
                | '╱'
                | '╲'
                | '━'
                | '┃'
        ) {
            decoration += 1;
        }
    }
    line.chars().count() >= 12 && decoration >= 6 && decoration > semantic.saturating_mul(2)
}

fn list_agents() -> Result<Vec<Agent>, String> {
    // The HUD is Space-first. `agent.list` exposes the workspace id but its
    // terminal title and cwd are implementation details (and often a branch
    // or repository name), so resolve the visible Space label separately.
    // A transient workspace-list failure must not erase the HUD inventory.
    let workspace_labels = list_workspace_labels().unwrap_or_default();
    let request: Request = serde_json::from_value(
        serde_json::json!({"id":"glasses:agent-list","method":"agent.list","params":{}}),
    )
    .map_err(|err| err.to_string())?;
    let response = ApiClient::local()
        .request_value_with_timeout(&request, Duration::from_secs(1))
        .map_err(|err| err.to_string())?;
    let agents = response
        .pointer("/result/agents")
        .and_then(serde_json::Value::as_array)
        .ok_or_else(|| "agent inventory unavailable".to_string())?;
    Ok(agents
        .iter()
        .filter_map(|agent| project_agent(agent, &workspace_labels))
        .collect())
}

fn list_workspace_labels() -> Result<HashMap<String, String>, String> {
    let request: Request = serde_json::from_value(
        serde_json::json!({"id":"glasses:workspace-list","method":"workspace.list","params":{}}),
    )
    .map_err(|err| err.to_string())?;
    let response = ApiClient::local()
        .request_value_with_timeout(&request, Duration::from_secs(1))
        .map_err(|err| err.to_string())?;
    let workspaces = response
        .pointer("/result/workspaces")
        .and_then(serde_json::Value::as_array)
        .ok_or_else(|| "workspace inventory unavailable".to_string())?;
    Ok(workspaces
        .iter()
        .filter_map(|workspace| {
            let id = workspace.get("workspace_id")?.as_str()?;
            let label = workspace.get("label")?.as_str()?.trim();
            (!label.is_empty()).then(|| (id.to_string(), label.to_string()))
        })
        .collect())
}

fn project_agent(
    value: &serde_json::Value,
    workspace_labels: &HashMap<String, String>,
) -> Option<Agent> {
    let id = value.get("pane_id")?.as_str()?.to_string();
    let name = ["name", "terminal_title_stripped", "terminal_title", "agent"]
        .iter()
        .find_map(|key| value.get(*key).and_then(serde_json::Value::as_str))
        .unwrap_or(&id)
        .to_string();
    let kind = value
        .get("agent")
        .and_then(serde_json::Value::as_str)
        .map(str::to_ascii_lowercase)
        .filter(|kind| matches!(kind.as_str(), "claude" | "codex" | "pi"))
        .unwrap_or_else(|| "agent".to_string());
    let space = value
        .get("workspace_id")
        .and_then(serde_json::Value::as_str)
        .and_then(|workspace_id| workspace_labels.get(workspace_id))
        .cloned()
        .unwrap_or_else(|| "Unnamed Space".to_string());
    let status = match value
        .get("agent_status")
        .and_then(serde_json::Value::as_str)
        .unwrap_or("unknown")
        .to_ascii_lowercase()
        .as_str()
    {
        "blocked" => "blocked",
        "failed" => "failed",
        "done" => "done",
        "working" => "working",
        "idle" => "idle",
        _ => "unknown",
    }
    .to_string();
    Some(Agent {
        id,
        name,
        kind,
        space,
        status,
        pinned: false,
    })
}

fn order_agents(mut agents: Vec<Agent>) -> Vec<Agent> {
    agents.sort_by(|a, b| {
        status_rank(&a.status)
            .cmp(&status_rank(&b.status))
            .then_with(|| a.space.cmp(&b.space))
    });
    agents
}
fn status_rank(status: &str) -> u8 {
    match status {
        "blocked" => 0,
        "failed" => 1,
        "done" => 2,
        "working" => 3,
        "idle" => 4,
        _ => 5,
    }
}
fn summarise(agents: &[Agent]) -> String {
    if agents.is_empty() {
        return "no agents".into();
    }
    let mut counts = HashMap::new();
    for agent in agents {
        *counts.entry(agent.status.as_str()).or_insert(0_usize) += 1;
    }
    ["blocked", "failed", "done", "working", "idle", "unknown"]
        .iter()
        .filter_map(|status| counts.get(status).map(|count| format!("{count} {status}")))
        .collect::<Vec<_>>()
        .join("  ")
}
fn now_millis() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64
}

fn read_request(
    stream: &mut TcpStream,
) -> io::Result<(String, String, HashMap<String, String>, Vec<u8>)> {
    let mut reader = BufReader::new(stream.try_clone()?);
    let mut first = String::new();
    reader.read_line(&mut first)?;
    let mut first_parts = first.split_whitespace();
    let method = first_parts
        .next()
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidData, "missing method"))?
        .to_string();
    let target = first_parts
        .next()
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidData, "missing target"))?
        .to_string();
    if target.len() > 2048 {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "target too long",
        ));
    }
    let mut headers = HashMap::new();
    loop {
        let mut line = String::new();
        reader.read_line(&mut line)?;
        if line == "\r\n" || line == "\n" {
            break;
        }
        let Some((key, value)) = line.split_once(':') else {
            return Err(io::Error::new(io::ErrorKind::InvalidData, "bad header"));
        };
        headers.insert(key.trim().to_ascii_lowercase(), value.trim().to_string());
    }
    let content_length = headers
        .get("content-length")
        .map(|raw| raw.parse::<usize>())
        .transpose()
        .map_err(|_| io::Error::new(io::ErrorKind::InvalidData, "invalid content length"))?
        .unwrap_or(0);
    if content_length > MAX_REQUEST_BYTES {
        return Err(io::Error::new(io::ErrorKind::InvalidData, "body too large"));
    }
    let mut body = vec![0; content_length];
    reader.read_exact(&mut body)?;
    Ok((method, target, headers, body))
}
fn write_headers(
    stream: &mut TcpStream,
    status: u16,
    content_type: &str,
    extra: &[(&str, &str)],
) -> io::Result<()> {
    let phrase = match status {
        200 => "OK",
        400 => "Bad Request",
        401 => "Unauthorized",
        403 => "Forbidden",
        404 => "Not Found",
        409 => "Conflict",
        503 => "Service Unavailable",
        _ => "Error",
    };
    write!(
        stream,
        "HTTP/1.1 {status} {phrase}\r\nContent-Type: {content_type}\r\n"
    )?;
    for (key, value) in extra {
        write!(stream, "{key}: {value}\r\n")?;
    }
    write!(stream, "\r\n")?;
    stream.flush()
}
fn write_response(
    mut stream: TcpStream,
    status: u16,
    content_type: &str,
    body: &[u8],
    extra: &[(&str, &str)],
) -> io::Result<()> {
    write_headers(&mut stream, status, content_type, extra)?;
    stream.write_all(body)?;
    stream.flush()
}
fn timing_safe_eq(left: &[u8], right: &[u8]) -> bool {
    let length = left.len() ^ right.len();
    let mut different = 0_u8;
    for index in 0..left.len().max(right.len()) {
        different |= left.get(index).copied().unwrap_or(0) ^ right.get(index).copied().unwrap_or(0);
    }
    length == 0 && different == 0
}
fn percent_decode(value: &str) -> String {
    let mut output = String::with_capacity(value.len());
    let mut bytes = value.as_bytes().iter().copied();
    while let Some(byte) = bytes.next() {
        if byte == b'%' {
            let high = bytes.next();
            let low = bytes.next();
            if let (Some(high), Some(low)) = (high, low) {
                if let Ok(hex) = std::str::from_utf8(&[high, low]) {
                    if let Ok(decoded) = u8::from_str_radix(hex, 16) {
                        output.push(decoded as char);
                        continue;
                    }
                }
            }
            output.push('%');
        } else if byte == b'+' {
            output.push(' ');
        } else {
            output.push(byte as char);
        }
    }
    output
}

fn query_parameter(target: &str, wanted: &str) -> Option<String> {
    target.split_once('?').and_then(|(_, query)| {
        query.split('&').find_map(|part| {
            part.split_once('=')
                .filter(|(key, _)| *key == wanted)
                .map(|(_, value)| percent_decode(value))
        })
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn timing_comparison_requires_identical_values() {
        assert!(timing_safe_eq(b"same", b"same"));
        assert!(!timing_safe_eq(b"same", b"different"));
    }
    #[test]
    fn public_and_wildcard_binds_are_rejected() {
        assert!(!is_safe_private_bind(&"0.0.0.0".parse().unwrap()));
        assert!(!is_safe_private_bind(&"8.8.8.8".parse().unwrap()));
        assert!(is_safe_private_bind(&"100.100.1.1".parse().unwrap()));
        assert!(is_safe_private_bind(&"192.168.1.5".parse().unwrap()));
    }
    #[test]
    fn prefers_the_tailnet_ipv4_address_over_its_ipv6_peer() {
        assert_eq!(
            choose_tailnet_candidate(&[
                "fd7a:115c:a1e0::2".parse().unwrap(),
                "100.64.0.2".parse().unwrap(),
            ])
            .unwrap(),
            "100.64.0.2".parse::<IpAddr>().unwrap()
        );
    }
    #[test]
    fn multiple_tailnet_ipv4_addresses_still_require_a_choice() {
        let error = choose_tailnet_candidate(&[
            "100.64.0.2".parse().unwrap(),
            "100.64.0.3".parse().unwrap(),
        ])
        .unwrap_err();
        assert!(error.contains("several Tailscale IPv4 addresses"));
    }
    #[test]
    fn status_order_is_attention_first() {
        assert!(status_rank("blocked") < status_rank("working"));
        assert!(status_rank("working") < status_rank("idle"));
    }
    #[test]
    fn summary_never_needs_agent_names() {
        assert_eq!(summarise(&[]), "no agents");
        assert_eq!(
            summarise(&[Agent {
                id: "p".into(),
                name: "secret".into(),
                kind: "agent".into(),
                space: "s".into(),
                status: "blocked".into(),
                pinned: false
            }]),
            "1 blocked"
        );
    }

    #[test]
    fn projection_uses_the_workspace_label_not_cwd_or_terminal_title() {
        let labels = HashMap::from([("w3X".to_string(), "glasses support".to_string())]);
        let agent = project_agent(
            &serde_json::json!({
                "pane_id": "w3X:p1",
                "workspace_id": "w3X",
                "cwd": "/home/ted/src/github.com/3loc/herden",
                "terminal_title_stripped": "herden",
                "agent": "codex",
                "agent_status": "working"
            }),
            &labels,
        )
        .unwrap();
        assert_eq!(agent.space, "glasses support");
        assert_eq!(agent.name, "herden");
        assert_eq!(agent.kind, "codex");
    }

    #[test]
    fn projection_never_uses_a_branch_or_cwd_as_a_space_name() {
        let agent = project_agent(
            &serde_json::json!({
                "pane_id": "w3X:p1",
                "workspace_id": "w3X",
                "cwd": "/project/feature/glasses-hud",
                "agent_status": "working"
            }),
            &HashMap::new(),
        )
        .unwrap();
        assert_eq!(agent.space, "Unnamed Space");
    }

    #[test]
    fn shared_v1_fixture_declares_the_current_protocol() {
        let fixture: serde_json::Value =
            serde_json::from_str(include_str!("../../glasses/protocol/hud-v1.json")).unwrap();
        assert_eq!(fixture["protocol_version"], HUD_PROTOCOL_VERSION);
        assert_eq!(fixture["type"], "snapshot");
        assert_eq!(fixture["controls_allowed"], false);
    }

    #[test]
    fn output_reader_removes_terminal_controls_without_leaking_escape_parameters() {
        assert_eq!(
            normalise_output("first\u{1b}[31m\u{1b}]0;title\u{7}\nsecond\u{7}"),
            "first\nsecond"
        );
        assert_eq!(normalise_output("\n\n"), "No readable output yet.");
    }

    #[test]
    fn output_reader_keeps_latest_carriage_return_redraw() {
        assert_eq!(
            normalise_output("loading 10%\rcompleted 100%\n"),
            "completed 100%"
        );
    }

    #[test]
    fn output_reader_removes_blank_rows_for_the_compact_lens() {
        assert_eq!(normalise_output("first\n\n  \nsecond\n"), "first\nsecond");
    }

    #[test]
    fn output_reader_removes_tui_chrome_and_ascii_decoration() {
        let output = normalise_output(
            "╭──────────────────────────╮\n\
             │ Ask Codex to do anything │\n\
             ╰──────────────────────────╯\n\
             \\  curl completed successfully\n\
             │ npm test -- --runInBand\n\
             └ finished in 2s\n\
             · Working (2m · esc to interrupt)\n\
             ● Working (2m · 1 background task)\n\
             deployed to fansvine\n",
        );
        assert_eq!(
            output,
            "\\  curl completed successfully\ndeployed to fansvine"
        );
    }

    #[test]
    fn output_reader_preserves_punctuation_heavy_logs_and_code() {
        assert_eq!(
            normalise_output("GET /health -> 200 (12ms)\nif (ready) { deploy(); }\n"),
            "GET /health -> 200 (12ms)\nif (ready) { deploy(); }"
        );
    }

    fn controls_settings(controls: bool) -> Settings {
        Settings {
            enabled: true,
            bind: "100.64.0.2".into(),
            port: DEFAULT_PORT,
            controls,
        }
    }

    fn controls_state(controls: bool) -> Arc<Mutex<Projection>> {
        Arc::new(Mutex::new(Projection::offline(controls)))
    }

    fn post_command(
        settings: &Settings,
        state: &Arc<Mutex<Projection>>,
        body: &str,
    ) -> Result<serde_json::Value, Refusal> {
        command_outcome(settings, state, body.as_bytes(), |_| true)
    }

    #[test]
    fn dictated_text_is_inserted_without_submitting_by_default() {
        let params = post_command(
            &controls_settings(true),
            &controls_state(true),
            r#"{"action":"send_text","agentId":"w1:pT","text":"run the tests"}"#,
        )
        .unwrap();
        assert_eq!(params["pane_id"], "w1:pT");
        assert_eq!(params["text"], "run the tests");
        assert!(params.get("keys").is_none());
    }

    #[test]
    fn submitted_text_types_and_presses_enter_in_one_request() {
        let params = post_command(
            &controls_settings(true),
            &controls_state(true),
            r#"{"action":"send_text","agentId":"w1:pT","text":"  run the tests  ","submit":true}"#,
        )
        .unwrap();
        assert_eq!(params["text"], "run the tests");
        assert_eq!(params["keys"], serde_json::json!(["enter"]));
    }

    #[test]
    fn empty_or_whitespace_dictation_is_refused() {
        for body in [
            r#"{"action":"send_text","agentId":"w1:pT","text":""}"#,
            r#"{"action":"send_text","agentId":"w1:pT","text":"   "}"#,
            r#"{"action":"send_text","agentId":"w1:pT"}"#,
        ] {
            let (status, message) =
                post_command(&controls_settings(true), &controls_state(true), body).unwrap_err();
            assert_eq!(status, 400);
            assert!(message.contains("text is required"));
        }
    }

    #[test]
    fn dictated_text_is_bounded_at_the_documented_limit() {
        let settings = controls_settings(true);
        let longest = "a".repeat(MAX_COMMAND_TEXT_CHARS);
        assert!(post_command(
            &settings,
            &controls_state(true),
            &format!(r#"{{"action":"send_text","agentId":"w1:pT","text":"{longest}"}}"#),
        )
        .is_ok());
        let overlong = "a".repeat(MAX_COMMAND_TEXT_CHARS + 1);
        let (status, message) = post_command(
            &settings,
            &controls_state(true),
            &format!(r#"{{"action":"send_text","agentId":"w1:pT","text":"{overlong}"}}"#),
        )
        .unwrap_err();
        assert_eq!(status, 400);
        assert!(message.contains("too long"));
    }

    #[test]
    fn dictation_never_carries_newlines_or_escapes_into_the_pty() {
        for text in [
            r"deploy\nrm -rf /",
            r"deploy\rrm -rf /",
            r"deploy\u001b[31m",
            r"deploy\tnow",
        ] {
            let (status, message) = post_command(
                &controls_settings(true),
                &controls_state(true),
                &format!(r#"{{"action":"send_text","agentId":"w1:pT","text":"{text}"}}"#),
            )
            .unwrap_err();
            assert_eq!(status, 400);
            assert!(message.contains("control characters"), "accepted {text}");
        }
    }

    #[test]
    fn dictation_is_refused_while_controls_are_disabled() {
        let (status, message) = post_command(
            &controls_settings(false),
            &controls_state(false),
            r#"{"action":"send_text","agentId":"w1:pT","text":"run the tests"}"#,
        )
        .unwrap_err();
        assert_eq!(status, 403);
        assert!(message.contains("controls are disabled"));
    }

    #[test]
    fn dictation_to_a_vanished_agent_is_refused() {
        let (status, message) = command_outcome(
            &controls_settings(true),
            &controls_state(true),
            br#"{"action":"send_text","agentId":"w1:gone","text":"run the tests"}"#,
            |_| false,
        )
        .unwrap_err();
        assert_eq!(status, 404);
        assert!(message.contains("no longer exists"));
    }

    #[test]
    fn the_same_phrase_twice_is_a_duplicate_but_a_new_phrase_is_not() {
        let settings = controls_settings(true);
        let state = controls_state(true);
        let first = r#"{"action":"send_text","agentId":"w1:pT","text":"run the tests"}"#;
        assert!(post_command(&settings, &state, first).is_ok());
        let (status, message) = post_command(&settings, &state, first).unwrap_err();
        assert_eq!(status, 409);
        assert!(message.contains("duplicate"));
        assert!(post_command(
            &settings,
            &state,
            r#"{"action":"send_text","agentId":"w1:pT","text":"stop the tests"}"#,
        )
        .is_ok());
        assert!(post_command(
            &settings,
            &state,
            r#"{"action":"send_text","agentId":"w1:pT","text":"run the tests","submit":true}"#,
        )
        .is_ok());
    }

    #[test]
    fn the_existing_key_actions_keep_their_payloads() {
        let settings = controls_settings(true);
        let state = controls_state(true);
        assert_eq!(
            post_command(
                &settings,
                &state,
                r#"{"action":"send_enter","agentId":"w1:pT"}"#
            )
            .unwrap(),
            serde_json::json!({"pane_id":"w1:pT","keys":["enter"]})
        );
        assert_eq!(
            post_command(
                &settings,
                &state,
                r#"{"action":"interrupt","agentId":"w1:pT"}"#
            )
            .unwrap(),
            serde_json::json!({"pane_id":"w1:pT","keys":["ctrl+c"]})
        );
        let (status, _) = post_command(
            &settings,
            &state,
            r#"{"action":"reboot","agentId":"w1:pT"}"#,
        )
        .unwrap_err();
        assert_eq!(status, 400);
    }

    #[test]
    fn output_route_decodes_the_selected_agent_id() {
        assert_eq!(
            query_parameter("/agent-output?agent=w1%3ApT&token=x", "agent"),
            Some("w1:pT".to_string())
        );
    }
}

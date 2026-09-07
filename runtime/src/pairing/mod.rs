mod addresses;
#[cfg(unix)]
mod authorized_keys;
mod code;
mod identity;
mod qr;
#[cfg(unix)]
mod session;

use std::io;

#[cfg(unix)]
use std::io::Read;
#[cfg(unix)]
use std::path::{Path, PathBuf};
#[cfg(unix)]
use std::sync::atomic::{AtomicBool, Ordering};
#[cfg(unix)]
use std::sync::{mpsc, Arc};
#[cfg(unix)]
use std::time::Duration;

#[cfg(unix)]
use authorized_keys::{AuthorizedKeys, EnrollResult};
#[cfg(unix)]
use code::PairingPayload;
#[cfg(unix)]
use session::{Enrollment, PairingState, PendingPairing};

const PAIRING_TTL_SECONDS: u64 = 120;
#[cfg(unix)]
const ENROLLMENT_INPUT_TIMEOUT: Duration = Duration::from_secs(30);

pub(crate) fn run(args: &[String]) -> io::Result<i32> {
    #[cfg(unix)]
    {
        if args.first().map(String::as_str) == Some("accept") {
            return accept(&args[1..]);
        }
        display(args)
    }
    #[cfg(not(unix))]
    {
        let _ = args;
        eprintln!("Pairing currently requires a macOS or Linux Host with OpenSSH Server.");
        Ok(1)
    }
}

#[cfg(unix)]
fn display(args: &[String]) -> io::Result<i32> {
    let options = match PairOptions::parse(args) {
        Ok(options) => options,
        Err(message) => {
            eprintln!("{message}");
            print_help();
            return Ok(2);
        }
    };
    let home = home_directory()?;
    let state = PairingState::new(pairing_state_directory(&home));
    let authorized_keys = AuthorizedKeys::new(&home);
    let now = unix_seconds();
    authorized_keys.sweep_expired(now)?;
    state.sweep_expired(now)?;

    let addresses = if options.addresses.is_empty() {
        addresses::candidates()?
    } else {
        options.addresses
    };
    if addresses.is_empty() {
        eprintln!(
            "No routable Host address was found. Connect this Host to a LAN or VPN and retry."
        );
        return Ok(1);
    }
    let host_key = match identity::read_host_key(Path::new("/etc/ssh")) {
        Ok(host_key) => host_key,
        Err(message) => {
            eprintln!("{message}");
            return Ok(1);
        }
    };
    let username = std::env::var("USER")
        .ok()
        .filter(|value| !value.trim().is_empty())
        .ok_or_else(|| io::Error::other("USER is not set"))?;
    let host_name = short_host_name();
    let (seed, public_line) = identity::bootstrap_key().map_err(io::Error::other)?;
    let pairing_id = random_id().map_err(io::Error::other)?;
    let expires_at = now.saturating_add(PAIRING_TTL_SECONDS);
    let executable = std::env::current_exe()?;
    let command = forced_accept_command(&executable, &pairing_id).map_err(io::Error::other)?;
    let authorized_line =
        authorized_keys::bootstrap_line(&public_line, &pairing_id, expires_at, &command)
            .map_err(io::Error::other)?;
    let pending = PendingPairing {
        pairing_id: pairing_id.clone(),
        expires_at,
        public_line,
    };
    state.write_pending(&pending)?;
    if let Err(error) = authorized_keys.append_bootstrap(authorized_line) {
        state.clear(&pairing_id);
        return Err(error);
    }
    let cleanup = PairingCleanup::new(&authorized_keys, &state, &pairing_id);

    let payload = PairingPayload {
        addresses,
        port: options.port,
        username,
        host_name,
        host_key_fingerprint: host_key.fingerprint,
        bootstrap_seed: seed,
        expires_at,
    };
    let pairing_code = code::encode(&payload).map_err(io::Error::other)?;
    let rendered = qr::render(&pairing_code).map_err(io::Error::other)?;
    println!("Pair this Host with Herden\n");
    print!("{rendered}");
    println!("Scan in Herden → Add Host. This code expires in two minutes.");
    println!("\nPairing Code (for copy/paste):\n{pairing_code}\n");

    let cancelled = Arc::new(AtomicBool::new(false));
    let signal = Arc::clone(&cancelled);
    ctrlc::set_handler(move || signal.store(true, Ordering::SeqCst))
        .map_err(|error| io::Error::other(format!("could not install signal handler: {error}")))?;

    let result = loop {
        if let Some(enrollment) = state.read_enrollment(&pairing_id) {
            println!("Paired successfully: {}", enrollment.fingerprint);
            break 0;
        }
        if cancelled.load(Ordering::SeqCst) {
            println!("Pairing cancelled.");
            break 130;
        }
        if unix_seconds() > expires_at {
            if let Some(enrollment) = state.read_enrollment(&pairing_id) {
                println!("Paired successfully: {}", enrollment.fingerprint);
                break 0;
            }
            println!("Pairing Code expired. Run `herden pair` to generate another.");
            break 1;
        }
        std::thread::sleep(Duration::from_millis(100));
    };
    cleanup.finish()?;
    Ok(result)
}

#[cfg(unix)]
struct PairingCleanup<'a> {
    authorized_keys: &'a AuthorizedKeys,
    state: &'a PairingState,
    pairing_id: &'a str,
    armed: bool,
}

#[cfg(unix)]
impl<'a> PairingCleanup<'a> {
    fn new(
        authorized_keys: &'a AuthorizedKeys,
        state: &'a PairingState,
        pairing_id: &'a str,
    ) -> Self {
        Self {
            authorized_keys,
            state,
            pairing_id,
            armed: true,
        }
    }

    fn finish(mut self) -> io::Result<()> {
        let result = self.authorized_keys.remove_bootstrap(self.pairing_id);
        self.state.clear(self.pairing_id);
        self.armed = false;
        result.map(|_| ())
    }
}

#[cfg(unix)]
impl Drop for PairingCleanup<'_> {
    fn drop(&mut self) {
        if self.armed {
            let _ = self.authorized_keys.remove_bootstrap(self.pairing_id);
            self.state.clear(self.pairing_id);
        }
    }
}

#[cfg(unix)]
fn accept(args: &[String]) -> io::Result<i32> {
    let pairing_id = match parse_pairing_id(args) {
        Some(pairing_id) => pairing_id,
        None => return enrollment_error("unknown_pairing", "missing --pairing-id"),
    };
    let home = home_directory()?;
    let state = PairingState::new(pairing_state_directory(&home));
    let authorized_keys = AuthorizedKeys::new(&home);
    let pending = match state.read_pending(pairing_id) {
        Ok(pending) => pending,
        Err(_) => {
            authorized_keys.remove_bootstrap(pairing_id)?;
            state.clear(pairing_id);
            return enrollment_error("unknown_pairing", "no pending Pairing ceremony");
        }
    };
    if unix_seconds() > pending.expires_at {
        authorized_keys.remove_bootstrap(pairing_id)?;
        state.clear(pairing_id);
        return enrollment_error("expired", "Pairing Code expired");
    }

    let submission = match read_submission() {
        Ok(submission) if !submission.trim().is_empty() => submission,
        Ok(_) => return enrollment_error("no_input", "expected a Device Key public line"),
        Err(error) if error.kind() == io::ErrorKind::TimedOut => {
            return enrollment_error("no_input", "timed out waiting for a Device Key")
        }
        Err(error) => return Err(error),
    };
    let device_key = match identity::parse_device_key(&submission) {
        Ok(device_key) => device_key,
        Err(message) => return enrollment_error("invalid_key", message),
    };
    let enrollment = Enrollment {
        pairing_id: pairing_id.to_string(),
        expires_at: pending.expires_at,
        fingerprint: device_key.fingerprint.clone(),
        line: device_key.line.clone(),
    };
    let result = authorized_keys.enroll(
        pairing_id,
        &device_key.line,
        || state.pending_path(pairing_id).exists(),
        || state.consume_pending(pairing_id),
        || unix_seconds() > pending.expires_at,
        || state.write_enrollment(&enrollment),
    )?;
    match result {
        EnrollResult::Enrolled => {
            println!("HERDR-ENROLL:OK:{}", device_key.fingerprint);
            Ok(0)
        }
        EnrollResult::AlreadyUsed => {
            enrollment_error("unknown_pairing", "Pairing ceremony was already used")
        }
        EnrollResult::Expired => enrollment_error("expired", "Pairing Code expired"),
    }
}

#[cfg(unix)]
fn read_submission() -> io::Result<String> {
    let (sender, receiver) = mpsc::sync_channel(1);
    std::thread::spawn(move || {
        let mut bytes = Vec::new();
        let result = io::stdin()
            .take(4096)
            .read_to_end(&mut bytes)
            .and_then(|_| {
                String::from_utf8(bytes)
                    .map_err(|_| io::Error::new(io::ErrorKind::InvalidData, "input is not UTF-8"))
            });
        let _ = sender.send(result);
    });
    receiver
        .recv_timeout(ENROLLMENT_INPUT_TIMEOUT)
        .map_err(|_| io::Error::new(io::ErrorKind::TimedOut, "Device Key input timed out"))?
        .map(|text| text.lines().next().unwrap_or_default().to_string())
}

#[cfg(unix)]
fn enrollment_error(code: &str, detail: &str) -> io::Result<i32> {
    println!("HERDR-ENROLL:ERR:{code}");
    eprintln!("{detail}");
    Ok(1)
}

#[cfg(unix)]
struct PairOptions {
    addresses: Vec<String>,
    port: u16,
}

#[cfg(unix)]
impl PairOptions {
    fn parse(args: &[String]) -> Result<Self, &'static str> {
        let mut addresses = Vec::new();
        let mut port = 22;
        let mut index = 0;
        while index < args.len() {
            match args[index].as_str() {
                "--address" => {
                    let address = args.get(index + 1).ok_or("--address requires a value")?;
                    if address.is_empty() || address.chars().any(char::is_whitespace) {
                        return Err("--address must contain no whitespace");
                    }
                    addresses.push(address.clone());
                    index += 2;
                }
                "--port" => {
                    port = args
                        .get(index + 1)
                        .ok_or("--port requires a value")?
                        .parse()
                        .map_err(|_| "--port must be an integer from 1 through 65535")?;
                    if port == 0 {
                        return Err("--port must be an integer from 1 through 65535");
                    }
                    index += 2;
                }
                "--help" | "-h" => return Err(""),
                _ => return Err("unrecognized `herden pair` argument"),
            }
        }
        Ok(Self { addresses, port })
    }
}

#[cfg(unix)]
fn parse_pairing_id(args: &[String]) -> Option<&str> {
    if args.len() == 2 && args[0] == "--pairing-id" {
        let value = args[1].as_str();
        (!value.is_empty()
            && value
                .bytes()
                .all(|byte| byte.is_ascii_alphanumeric() || byte == b'-'))
        .then_some(value)
    } else {
        None
    }
}

#[cfg(unix)]
fn home_directory() -> io::Result<PathBuf> {
    std::env::var_os("HOME")
        .map(PathBuf::from)
        .ok_or_else(|| io::Error::other("HOME is not set"))
}

#[cfg(unix)]
fn pairing_state_directory(home: &Path) -> PathBuf {
    std::env::var_os("HERDEN_PAIRING_STATE_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| home.join(".config").join("herden").join("pairing"))
}

#[cfg(unix)]
fn forced_accept_command(executable: &Path, pairing_id: &str) -> Result<String, &'static str> {
    let path = executable
        .to_str()
        .ok_or("Herden executable path is not valid UTF-8")?;
    if path.contains(['\'', '"', '\n', '\r']) {
        return Err("Herden executable path contains unsupported shell characters");
    }
    Ok(format!("'{path}' pair accept --pairing-id {pairing_id}"))
}

#[cfg(unix)]
fn random_id() -> Result<String, String> {
    let mut bytes = [0_u8; 6];
    getrandom::getrandom(&mut bytes)
        .map_err(|error| format!("could not generate Pairing identifier: {error}"))?;
    Ok(bytes.iter().map(|byte| format!("{byte:02x}")).collect())
}

#[cfg(unix)]
fn short_host_name() -> Option<String> {
    std::process::Command::new("hostname")
        .arg("-s")
        .output()
        .ok()
        .filter(|output| output.status.success())
        .and_then(|output| String::from_utf8(output.stdout).ok())
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
}

#[cfg(unix)]
fn print_help() {
    eprintln!("usage: herden pair [--address HOST]... [--port PORT]");
}

pub(crate) fn unix_seconds() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |duration| duration.as_secs())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[cfg(unix)]
    #[test]
    fn pair_options_accept_repeated_addresses_and_custom_port() {
        let args = [
            "--address",
            "100.64.1.2",
            "--address",
            "host.example",
            "--port",
            "2222",
        ]
        .map(str::to_string);
        let parsed = PairOptions::parse(&args).expect("options");
        assert_eq!(parsed.addresses, ["100.64.1.2", "host.example"]);
        assert_eq!(parsed.port, 2222);
    }

    #[cfg(unix)]
    #[test]
    fn pair_options_reject_port_zero() {
        let args = ["--port", "0"].map(str::to_string);
        assert_eq!(
            PairOptions::parse(&args).err(),
            Some("--port must be an integer from 1 through 65535")
        );
    }

    #[cfg(unix)]
    #[test]
    fn forced_command_quotes_the_executable_and_rejects_quotes() {
        assert_eq!(
            forced_accept_command(Path::new("/opt/Herden Host/herden"), "abc").expect("command"),
            "'/opt/Herden Host/herden' pair accept --pairing-id abc"
        );
        assert!(forced_accept_command(Path::new("/tmp/a'b/herden"), "abc").is_err());
    }
}

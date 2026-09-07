use std::fs::{self, OpenOptions};
use std::io::{self, Write};
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::thread;
use std::time::{Duration, SystemTime};

const LOCK_RETRY: Duration = Duration::from_millis(25);
const LOCK_TIMEOUT: Duration = Duration::from_secs(5);
const LOCK_STALE: Duration = Duration::from_secs(10);
const MARKER_PREFIX: &str = "herden-pairing:";

pub(crate) struct AuthorizedKeys {
    path: PathBuf,
}

impl AuthorizedKeys {
    pub(crate) fn new(home: &Path) -> Self {
        Self {
            path: home.join(".ssh").join("authorized_keys"),
        }
    }

    pub(crate) fn append_bootstrap(&self, line: String) -> io::Result<()> {
        self.edit(|mut lines| {
            lines.push(line);
            Ok(Some(lines))
        })?;
        Ok(())
    }

    pub(crate) fn remove_bootstrap(&self, pairing_id: &str) -> io::Result<bool> {
        self.edit(|lines| {
            let original_len = lines.len();
            let kept = lines
                .into_iter()
                .filter(|line| marker(line).is_none_or(|marker| marker.id != pairing_id))
                .collect::<Vec<_>>();
            Ok((kept.len() != original_len).then_some(kept))
        })
    }

    pub(crate) fn sweep_expired(&self, now: u64) -> io::Result<usize> {
        let mut removed = 0;
        self.edit(|lines| {
            let original_len = lines.len();
            let kept = lines
                .into_iter()
                .filter(|line| marker(line).is_none_or(|marker| marker.expires_at > now))
                .collect::<Vec<_>>();
            removed = original_len - kept.len();
            Ok((removed > 0).then_some(kept))
        })?;
        Ok(removed)
    }

    pub(crate) fn enroll(
        &self,
        pairing_id: &str,
        device_line: &str,
        pending_exists: impl FnOnce() -> bool,
        consume_pending: impl FnOnce(),
        expired: impl FnOnce() -> bool,
        record_enrollment: impl FnOnce() -> io::Result<()>,
    ) -> io::Result<EnrollResult> {
        let mut result = EnrollResult::Enrolled;
        let mut pending_exists = Some(pending_exists);
        let mut consume_pending = Some(consume_pending);
        let mut expired = Some(expired);
        let mut record_enrollment = Some(record_enrollment);
        self.edit(|lines| {
            if !pending_exists.take().is_some_and(|check| check()) {
                result = EnrollResult::AlreadyUsed;
                return Ok(None);
            }
            let mut kept = lines
                .into_iter()
                .filter(|line| marker(line).is_none_or(|marker| marker.id != pairing_id))
                .collect::<Vec<_>>();
            if let Some(consume) = consume_pending.take() {
                consume();
            }
            if expired.take().is_some_and(|check| check()) {
                result = EnrollResult::Expired;
                return Ok(Some(kept));
            }
            let identity = super::identity::key_identity(device_line);
            if !kept
                .iter()
                .any(|line| super::identity::key_identity(line) == identity)
            {
                kept.push(device_line.to_string());
            }
            if let Some(record) = record_enrollment.take() {
                record()?;
            }
            Ok(Some(kept))
        })?;
        Ok(result)
    }

    fn edit(
        &self,
        edit: impl FnOnce(Vec<String>) -> io::Result<Option<Vec<String>>>,
    ) -> io::Result<bool> {
        let ssh_dir = self
            .path
            .parent()
            .ok_or_else(|| io::Error::other("authorized_keys has no parent directory"))?;
        fs::create_dir_all(ssh_dir)?;
        fs::set_permissions(ssh_dir, fs::Permissions::from_mode(0o700))?;
        let lock_path = self.path.with_extension("herden-pairing.lock");
        let _lock = LockFile::acquire(lock_path)?;

        let existing = match fs::read_to_string(&self.path) {
            Ok(content) => Some(content),
            Err(error) if error.kind() == io::ErrorKind::NotFound => None,
            Err(error) => return Err(error),
        };
        let lines = existing
            .as_deref()
            .map(|content| content.lines().map(str::to_string).collect())
            .unwrap_or_default();
        let Some(edited) = edit(lines)? else {
            return Ok(false);
        };

        let mode = existing
            .as_ref()
            .and_then(|_| fs::metadata(&self.path).ok())
            .map_or(0o600, |metadata| metadata.permissions().mode() & 0o777);
        let temp = self
            .path
            .with_extension(format!("herden-pairing.{}.tmp", std::process::id()));
        let write_result = (|| {
            let mut file = OpenOptions::new()
                .create(true)
                .truncate(true)
                .write(true)
                .mode(mode)
                .open(&temp)?;
            for line in edited {
                writeln!(file, "{line}")?;
            }
            file.sync_all()?;
            fs::rename(&temp, &self.path)
        })();
        if write_result.is_err() {
            let _ = fs::remove_file(&temp);
        }
        write_result.map(|()| true)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum EnrollResult {
    Enrolled,
    AlreadyUsed,
    Expired,
}

pub(crate) fn bootstrap_line(
    public_line: &str,
    pairing_id: &str,
    expires_at: u64,
    command: &str,
) -> Result<String, &'static str> {
    if pairing_id.is_empty()
        || !pairing_id
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || byte == b'-')
    {
        return Err("pairing id must be alphanumeric or hyphenated");
    }
    if command.contains(['"', '\n', '\r']) {
        return Err("forced command must not contain quotes or newlines");
    }
    Ok(format!(
        "restrict,command=\"{command}\" {public_line} {MARKER_PREFIX}{pairing_id}:exp:{expires_at}"
    ))
}

struct Marker<'a> {
    id: &'a str,
    expires_at: u64,
}

fn marker(line: &str) -> Option<Marker<'_>> {
    let value = line
        .split_whitespace()
        .last()?
        .strip_prefix(MARKER_PREFIX)?;
    let (id, expiry) = value.rsplit_once(":exp:")?;
    if id.is_empty()
        || !id
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || byte == b'-')
    {
        return None;
    }
    Some(Marker {
        id,
        expires_at: expiry.parse().ok()?,
    })
}

struct LockFile {
    path: PathBuf,
}

impl LockFile {
    fn acquire(path: PathBuf) -> io::Result<Self> {
        let started = SystemTime::now();
        loop {
            match OpenOptions::new()
                .create_new(true)
                .write(true)
                .mode(0o600)
                .open(&path)
            {
                Ok(mut file) => {
                    writeln!(file, "{}", std::process::id())?;
                    return Ok(Self { path });
                }
                Err(error) if error.kind() == io::ErrorKind::AlreadyExists => {
                    if is_stale(&path) {
                        let _ = fs::remove_file(&path);
                        continue;
                    }
                    if started.elapsed().unwrap_or_default() > LOCK_TIMEOUT {
                        return Err(io::Error::new(
                            io::ErrorKind::TimedOut,
                            format!("timed out waiting for {}", path.display()),
                        ));
                    }
                    thread::sleep(LOCK_RETRY);
                }
                Err(error) => return Err(error),
            }
        }
    }
}

impl Drop for LockFile {
    fn drop(&mut self) {
        let _ = fs::remove_file(&self.path);
    }
}

fn is_stale(path: &Path) -> bool {
    fs::metadata(path)
        .and_then(|metadata| metadata.modified())
        .and_then(|modified| modified.elapsed().map_err(io::Error::other))
        .is_ok_and(|age| age > LOCK_STALE)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn marker_only_recognizes_herden_pairing_comments() {
        let parsed =
            marker("restrict ssh-ed25519 AAAA herden-pairing:abc-1:exp:42").expect("marker");
        assert_eq!(parsed.id, "abc-1");
        assert_eq!(parsed.expires_at, 42);
        assert!(marker("ssh-ed25519 AAAA ordinary-key").is_none());
        assert!(marker("ssh-ed25519 AAAA herdr-pairing:abc:exp:42").is_none());
    }

    #[test]
    fn bootstrap_lines_restrict_the_key_to_the_accept_command() {
        let line = bootstrap_line(
            "ssh-ed25519 AAAA",
            "abc123",
            42,
            "'/usr/bin/herden' pair accept --pairing-id abc123",
        )
        .expect("bootstrap line");
        assert_eq!(
            line,
            "restrict,command=\"'/usr/bin/herden' pair accept --pairing-id abc123\" ssh-ed25519 AAAA herden-pairing:abc123:exp:42"
        );
    }
}

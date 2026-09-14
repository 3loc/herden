use std::fs::{self, OpenOptions};
use std::io::{self, Write};
use std::os::unix::fs::OpenOptionsExt;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct PendingPairing {
    #[serde(rename = "pairingId")]
    pub(crate) pairing_id: String,
    #[serde(rename = "expiresAt")]
    pub(crate) expires_at: u64,
    #[serde(rename = "publicLine")]
    pub(crate) public_line: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct Enrollment {
    #[serde(rename = "pairingId")]
    pub(crate) pairing_id: String,
    #[serde(rename = "expiresAt")]
    pub(crate) expires_at: u64,
    pub(crate) fingerprint: String,
    pub(crate) line: String,
}

pub(crate) struct PairingState {
    root: PathBuf,
}

impl PairingState {
    pub(crate) fn new(root: PathBuf) -> Self {
        Self { root }
    }

    pub(crate) fn pending_path(&self, pairing_id: &str) -> PathBuf {
        self.root.join("pending").join(format!("{pairing_id}.json"))
    }

    pub(crate) fn enrolled_path(&self, pairing_id: &str) -> PathBuf {
        self.root
            .join("enrolled")
            .join(format!("{pairing_id}.json"))
    }

    pub(crate) fn write_pending(&self, pending: &PendingPairing) -> io::Result<()> {
        write_json(&self.pending_path(&pending.pairing_id), pending)
    }

    pub(crate) fn read_pending(&self, pairing_id: &str) -> io::Result<PendingPairing> {
        read_json(&self.pending_path(pairing_id))
    }

    pub(crate) fn consume_pending(&self, pairing_id: &str) {
        let _ = fs::remove_file(self.pending_path(pairing_id));
    }

    pub(crate) fn write_enrollment(&self, enrollment: &Enrollment) -> io::Result<()> {
        write_json(&self.enrolled_path(&enrollment.pairing_id), enrollment)
    }

    pub(crate) fn read_enrollment(&self, pairing_id: &str) -> Option<Enrollment> {
        read_json(&self.enrolled_path(pairing_id)).ok()
    }

    pub(crate) fn clear(&self, pairing_id: &str) {
        let _ = fs::remove_file(self.pending_path(pairing_id));
        let _ = fs::remove_file(self.enrolled_path(pairing_id));
    }

    pub(crate) fn sweep_expired(&self, now: u64) -> io::Result<usize> {
        sweep_directory(&self.root.join("pending"), now, 0)?
            .checked_add(sweep_directory(&self.root.join("enrolled"), now, 120)?)
            .ok_or_else(|| io::Error::other("pairing state sweep count overflow"))
    }
}

fn write_json(path: &Path, value: &impl Serialize) -> io::Result<()> {
    let parent = path
        .parent()
        .ok_or_else(|| io::Error::other("pairing state path has no parent"))?;
    fs::create_dir_all(parent)?;
    let temp = path.with_extension(format!("{}.tmp", std::process::id()));
    let write_result = (|| {
        let mut file = OpenOptions::new()
            .create(true)
            .truncate(true)
            .write(true)
            .mode(0o600)
            .open(&temp)?;
        serde_json::to_writer(&mut file, value).map_err(io::Error::other)?;
        file.write_all(b"\n")?;
        file.sync_all()?;
        fs::rename(&temp, path)
    })();
    if write_result.is_err() {
        let _ = fs::remove_file(temp);
    }
    write_result
}

fn read_json<T: for<'de> Deserialize<'de>>(path: &Path) -> io::Result<T> {
    let bytes = fs::read(path)?;
    serde_json::from_slice(&bytes).map_err(io::Error::other)
}

fn sweep_directory(path: &Path, now: u64, grace: u64) -> io::Result<usize> {
    let entries = match fs::read_dir(path) {
        Ok(entries) => entries,
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(0),
        Err(error) => return Err(error),
    };
    let mut removed = 0;
    for entry in entries {
        let entry = entry?;
        let value: serde_json::Value = match read_json(&entry.path()) {
            Ok(value) => value,
            Err(_) => continue,
        };
        let expires_at = value.get("expiresAt").and_then(serde_json::Value::as_u64);
        if expires_at.is_some_and(|expiry| expiry.saturating_add(grace) <= now)
            && fs::remove_file(entry.path()).is_ok()
        {
            removed += 1;
        }
    }
    Ok(removed)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::PermissionsExt;

    fn unique_temp_dir() -> PathBuf {
        std::env::temp_dir().join(format!(
            "herden-pairing-state-test-{}-{}",
            std::process::id(),
            crate::pairing::unix_seconds()
        ))
    }

    #[test]
    fn pending_state_round_trips_and_is_private() {
        let root = unique_temp_dir();
        let state = PairingState::new(root.clone());
        let pending = PendingPairing {
            pairing_id: "abc".into(),
            expires_at: 42,
            public_line: "ssh-ed25519 AAAA".into(),
        };
        state.write_pending(&pending).expect("write pending");
        assert_eq!(
            state.read_pending("abc").expect("read pending").pairing_id,
            "abc"
        );
        let mode = fs::metadata(state.pending_path("abc"))
            .expect("metadata")
            .permissions()
            .mode()
            & 0o777;
        assert_eq!(mode, 0o600);
        let _ = fs::remove_dir_all(root);
    }
}

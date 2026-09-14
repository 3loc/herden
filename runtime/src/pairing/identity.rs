use std::fs;
use std::path::{Path, PathBuf};

use base64::engine::general_purpose::STANDARD;
use base64::Engine;
use ed25519_dalek::SigningKey;
use sha2::{Digest, Sha256};

const KEY_TYPE: &str = "ssh-ed25519";
const HOST_KEY_FILES: [&str; 3] = [
    "ssh_host_ed25519_key.pub",
    "ssh_host_ecdsa_key.pub",
    "ssh_host_rsa_key.pub",
];

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct HostKey {
    pub(crate) fingerprint: String,
    pub(crate) path: PathBuf,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct DeviceKey {
    pub(crate) line: String,
    pub(crate) fingerprint: String,
}

pub(crate) fn bootstrap_key() -> Result<([u8; 32], String), String> {
    let mut seed = [0_u8; 32];
    getrandom::getrandom(&mut seed).map_err(|error| format!("could not generate key: {error}"))?;
    let signing_key = SigningKey::from_bytes(&seed);
    let public = signing_key.verifying_key().to_bytes();
    Ok((seed, public_line_from_raw(&public)))
}

pub(crate) fn read_host_key(ssh_dir: &Path) -> Result<HostKey, String> {
    HOST_KEY_FILES
        .iter()
        .find_map(|name| {
            let path = ssh_dir.join(name);
            fs::read_to_string(&path).ok().map(|line| (path, line))
        })
        .ok_or_else(|| {
            format!(
                "no SSH Host public key found under {}; enable OpenSSH Server first",
                ssh_dir.display()
            )
        })
        .and_then(|(path, line)| {
            fingerprint_public_line(&line).map(|fingerprint| HostKey { fingerprint, path })
        })
}

pub(crate) fn parse_device_key(input: &str) -> Result<DeviceKey, &'static str> {
    if input.len() > 1024 {
        return Err("submission exceeds 1024 characters");
    }
    let line = input.trim();
    if line.is_empty() {
        return Err("submission is empty");
    }
    if line.contains(['\n', '\r']) {
        return Err("submission must be a single line");
    }

    let mut words = line.split(' ');
    if words.next() != Some(KEY_TYPE) {
        return Err("key type must be ssh-ed25519");
    }
    let blob_text = words.next().ok_or("key blob is missing")?;
    let blob = STANDARD
        .decode(blob_text)
        .map_err(|_| "key blob is not base64")?;
    let (wire_type, rest) = read_ssh_string(&blob).ok_or("truncated key blob")?;
    if wire_type != KEY_TYPE.as_bytes() {
        return Err("key blob type disagrees with the line type");
    }
    let (public_key, trailing) = read_ssh_string(rest).ok_or("truncated key blob")?;
    if public_key.len() != 32 {
        return Err("Ed25519 public key must be 32 bytes");
    }
    if !trailing.is_empty() {
        return Err("key blob has trailing bytes");
    }

    let comment = words.collect::<Vec<_>>().join(" ");
    if !comment.bytes().all(|byte| (b' '..=b'~').contains(&byte)) {
        return Err("comment must be printable ASCII");
    }
    let canonical_blob = STANDARD.encode(blob);
    let canonical_line = if comment.is_empty() {
        format!("{KEY_TYPE} {canonical_blob}")
    } else {
        format!("{KEY_TYPE} {canonical_blob} {comment}")
    };
    let fingerprint =
        fingerprint_public_line(&canonical_line).map_err(|_| "could not fingerprint Device Key")?;
    Ok(DeviceKey {
        line: canonical_line,
        fingerprint,
    })
}

pub(crate) fn key_identity(line: &str) -> Option<String> {
    let mut words = line.split_whitespace();
    let first = words.next()?;
    let key_type = if first.starts_with("ssh-") || first.starts_with("ecdsa-") {
        first
    } else {
        words.next()?
    };
    let blob = words.next()?;
    Some(format!("{key_type} {blob}"))
}

fn public_line_from_raw(public: &[u8; 32]) -> String {
    let mut blob = Vec::with_capacity(4 + KEY_TYPE.len() + 4 + public.len());
    write_ssh_string(&mut blob, KEY_TYPE.as_bytes());
    write_ssh_string(&mut blob, public);
    format!("{KEY_TYPE} {}", STANDARD.encode(blob))
}

fn fingerprint_public_line(line: &str) -> Result<String, String> {
    let blob_text = line
        .split_whitespace()
        .nth(1)
        .ok_or_else(|| "SSH public key has no key blob".to_string())?;
    let blob = STANDARD
        .decode(blob_text)
        .map_err(|_| "SSH public key blob is not base64".to_string())?;
    let digest = Sha256::digest(blob);
    Ok(format!(
        "SHA256:{}",
        STANDARD.encode(digest).trim_end_matches('=')
    ))
}

fn write_ssh_string(output: &mut Vec<u8>, value: &[u8]) {
    output.extend_from_slice(&(value.len() as u32).to_be_bytes());
    output.extend_from_slice(value);
}

fn read_ssh_string(input: &[u8]) -> Option<(&[u8], &[u8])> {
    let size = u32::from_be_bytes(input.get(..4)?.try_into().ok()?) as usize;
    let end = 4_usize.checked_add(size)?;
    Some((input.get(4..end)?, input.get(end..)?))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn generated_bootstrap_key_is_an_openssh_ed25519_line() {
        let (seed, line) = bootstrap_key().expect("bootstrap key");
        assert_eq!(seed.len(), 32);
        assert!(line.starts_with("ssh-ed25519 AAAA"));
        assert!(parse_device_key(&line).is_ok());
    }

    #[test]
    fn device_key_parser_rejects_options_and_trailing_blob_data() {
        let (_, line) = bootstrap_key().expect("bootstrap key");
        assert_eq!(
            parse_device_key(&format!("restrict {line}")),
            Err("key type must be ssh-ed25519")
        );
        let mut words = line.split_whitespace();
        let key_type = words.next().expect("type");
        let mut blob = STANDARD
            .decode(words.next().expect("blob"))
            .expect("base64");
        blob.push(0);
        assert_eq!(
            parse_device_key(&format!("{key_type} {}", STANDARD.encode(blob))),
            Err("key blob has trailing bytes")
        );
    }

    #[test]
    fn key_identity_ignores_options_and_comments() {
        assert_eq!(
            key_identity("restrict ssh-ed25519 AAAA device one"),
            Some("ssh-ed25519 AAAA".into())
        );
        assert_eq!(
            key_identity("ssh-ed25519 AAAA device one"),
            Some("ssh-ed25519 AAAA".into())
        );
    }
}

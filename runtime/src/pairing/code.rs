use std::fmt;
use std::net::IpAddr;

use base64::engine::general_purpose::STANDARD_NO_PAD;
use base64::Engine;

pub(crate) const PAIRING_CODE_PREFIX: &str = "HERDR-PAIR";
pub(crate) const PAIRING_CODE_VERSION: u8 = 2;

const FLAG_HOST_NAME: u8 = 1;
const ADDRESS_IPV4: u8 = 0;
const ADDRESS_IPV6: u8 = 1;
const ADDRESS_NAME: u8 = 2;

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct PairingPayload {
    pub(crate) addresses: Vec<String>,
    pub(crate) port: u16,
    pub(crate) username: String,
    pub(crate) host_name: Option<String>,
    pub(crate) host_key_fingerprint: String,
    pub(crate) bootstrap_seed: [u8; 32],
    pub(crate) expires_at: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct PairingCodeError(&'static str);

impl fmt::Display for PairingCodeError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(self.0)
    }
}

impl std::error::Error for PairingCodeError {}

/// Encode the compact Pairing Code v2 binary envelope.
///
/// Base45 keeps the complete printable envelope in QR alphanumeric mode. It is
/// not cryptography; the Bootstrap Key remains the same 256-bit credential as
/// v1, while the QR needs substantially fewer modules.
pub(crate) fn encode(payload: &PairingPayload) -> Result<String, PairingCodeError> {
    validate(payload)?;

    let host_name = payload.host_name.as_deref().map(str::trim);
    let mut wire = Vec::new();
    wire.push(u8::from(host_name.is_some()) * FLAG_HOST_NAME);
    wire.extend_from_slice(&payload.port.to_be_bytes());
    wire.extend_from_slice(
        &u32::try_from(payload.expires_at)
            .map_err(|_| PairingCodeError("Pairing Code expiry is out of range"))?
            .to_be_bytes(),
    );
    wire.extend_from_slice(&fingerprint_digest(&payload.host_key_fingerprint)?);
    wire.extend_from_slice(&payload.bootstrap_seed);
    push_string(&mut wire, &payload.username, "SSH username is too long")?;
    if let Some(name) = host_name {
        push_string(&mut wire, name, "Host name is too long")?;
    }
    wire.push(
        u8::try_from(payload.addresses.len())
            .map_err(|_| PairingCodeError("too many Host addresses"))?,
    );
    for address in &payload.addresses {
        match address.parse::<IpAddr>() {
            Ok(IpAddr::V4(address)) => {
                wire.push(ADDRESS_IPV4);
                wire.extend_from_slice(&address.octets());
            }
            Ok(IpAddr::V6(address)) => {
                wire.push(ADDRESS_IPV6);
                wire.extend_from_slice(&address.octets());
            }
            Err(_) => {
                wire.push(ADDRESS_NAME);
                push_string(&mut wire, address, "Host address is too long")?;
            }
        }
    }

    Ok(format!(
        "{PAIRING_CODE_PREFIX}:{PAIRING_CODE_VERSION}:{}",
        base45_encode(&wire)
    ))
}

fn push_string(
    output: &mut Vec<u8>,
    value: &str,
    too_long: &'static str,
) -> Result<(), PairingCodeError> {
    output.push(u8::try_from(value.len()).map_err(|_| PairingCodeError(too_long))?);
    output.extend_from_slice(value.as_bytes());
    Ok(())
}

fn fingerprint_digest(value: &str) -> Result<[u8; 32], PairingCodeError> {
    let digest = value.strip_prefix("SHA256:").ok_or(PairingCodeError(
        "SSH Host fingerprint must use OpenSSH SHA256 form",
    ))?;
    STANDARD_NO_PAD
        .decode(digest)
        .map_err(|_| PairingCodeError("SSH Host fingerprint must use OpenSSH SHA256 form"))?
        .try_into()
        .map_err(|_| PairingCodeError("SSH Host fingerprint must use OpenSSH SHA256 form"))
}

fn base45_encode(bytes: &[u8]) -> String {
    const ALPHABET: &[u8; 45] = b"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:";
    let mut encoded = String::with_capacity(bytes.len().div_ceil(2) * 3);
    let mut chunks = bytes.chunks_exact(2);
    for chunk in &mut chunks {
        let value = u16::from_be_bytes([chunk[0], chunk[1]]) as usize;
        encoded.push(ALPHABET[value % 45] as char);
        encoded.push(ALPHABET[(value / 45) % 45] as char);
        encoded.push(ALPHABET[value / (45 * 45)] as char);
    }
    if let [last] = chunks.remainder() {
        let value = *last as usize;
        encoded.push(ALPHABET[value % 45] as char);
        encoded.push(ALPHABET[value / 45] as char);
    }
    encoded
}

fn validate(payload: &PairingPayload) -> Result<(), PairingCodeError> {
    if payload.addresses.is_empty() {
        return Err(PairingCodeError("at least one Host address is required"));
    }
    if payload
        .addresses
        .iter()
        .any(|address| address.is_empty() || address.chars().any(char::is_whitespace))
    {
        return Err(PairingCodeError(
            "Host addresses must be non-empty and contain no whitespace",
        ));
    }
    if payload.username.is_empty() || payload.username.chars().any(char::is_whitespace) {
        return Err(PairingCodeError(
            "SSH username must be non-empty and contain no whitespace",
        ));
    }
    if payload
        .host_name
        .as_ref()
        .is_some_and(|name| name.trim().is_empty())
    {
        return Err(PairingCodeError("Host name must not be empty"));
    }
    fingerprint_digest(&payload.host_key_fingerprint)?;
    if payload.expires_at == 0 {
        return Err(PairingCodeError("Pairing Code expiry must be positive"));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fixture() -> PairingPayload {
        PairingPayload {
            addresses: vec!["100.64.1.2".into(), "192.168.1.20".into()],
            port: 22,
            username: "developer".into(),
            host_name: Some("buildbox".into()),
            host_key_fingerprint: format!("SHA256:{}", "A".repeat(43)),
            bootstrap_seed: [0; 32],
            expires_at: 1_800_000_000,
        }
    }

    #[test]
    fn encoding_is_compact_and_uses_the_v2_wire_prefix() {
        let encoded = encode(&fixture()).expect("valid fixture");
        assert!(encoded.starts_with("HERDR-PAIR:2:"));
        assert!(encoded.len() < 180, "{} bytes: {encoded}", encoded.len());
        assert!(encoded.bytes().all(|byte| matches!(
            byte,
            b'0'..=b'9'
                | b'A'..=b'Z'
                | b' '
                | b'$'
                | b'%'
                | b'*'
                | b'+'
                | b'-'
                | b'.'
                | b'/'
                | b':'
        )));
    }

    #[test]
    fn encoding_matches_the_shared_ios_pairing_vector() {
        let vectors: serde_json::Value = serde_json::from_str(include_str!(
            "../../../plugin/test-vectors/pairing-code-v2.json"
        ))
        .expect("valid shared pairing vectors");
        let vector = &vectors["valid"][0];
        let payload = &vector["payload"];
        let seed = base64::engine::general_purpose::URL_SAFE_NO_PAD
            .decode(
                payload["bootstrapSeed"]
                    .as_str()
                    .expect("bootstrap seed string"),
            )
            .expect("base64url bootstrap seed")
            .try_into()
            .expect("32-byte bootstrap seed");

        let pairing_payload = PairingPayload {
            addresses: payload["addresses"]
                .as_array()
                .expect("addresses array")
                .iter()
                .map(|address| address.as_str().expect("address string").to_owned())
                .collect(),
            port: payload["port"].as_u64().expect("port") as u16,
            username: payload["username"].as_str().expect("username").to_owned(),
            host_name: payload["hostName"].as_str().map(str::to_owned),
            host_key_fingerprint: payload["hostKeyFingerprint"]
                .as_str()
                .expect("fingerprint")
                .to_owned(),
            bootstrap_seed: seed,
            expires_at: payload["expiresAt"].as_u64().expect("expiry"),
        };

        assert_eq!(
            encode(&pairing_payload).expect("valid shared vector"),
            vector["code"].as_str().expect("encoded pairing code")
        );
    }

    #[test]
    fn encoding_rejects_whitespace_in_an_address() {
        let mut payload = fixture();
        payload.addresses = vec!["host name".into()];
        assert_eq!(
            encode(&payload).expect_err("address must fail").to_string(),
            "Host addresses must be non-empty and contain no whitespace"
        );
    }

    #[test]
    fn encoding_trims_the_optional_host_name() {
        let mut payload = fixture();
        payload.host_name = Some("  buildbox  ".into());
        assert_eq!(encode(&payload), encode(&fixture()));
    }

    #[test]
    fn base45_matches_rfc_9285_examples() {
        assert_eq!(base45_encode(b"AB"), "BB8");
        assert_eq!(base45_encode(b"Hello!!"), "%69 VD92EX0");
        assert_eq!(base45_encode(b"base-45"), "UJCLQE7W581");
    }
}

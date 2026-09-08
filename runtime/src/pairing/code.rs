use std::fmt;

use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;
use serde::Serialize;

pub(crate) const PAIRING_CODE_PREFIX: &str = "HERDR-PAIR";
pub(crate) const PAIRING_CODE_VERSION: u8 = 1;

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

#[derive(Serialize)]
struct WirePayload<'a> {
    addrs: &'a [String],
    port: u16,
    user: &'a str,
    fp: &'a str,
    #[serde(skip_serializing_if = "Option::is_none")]
    name: Option<&'a str>,
    seed: String,
    exp: u64,
}

pub(crate) fn encode(payload: &PairingPayload) -> Result<String, PairingCodeError> {
    validate(payload)?;
    let wire = WirePayload {
        addrs: &payload.addresses,
        port: payload.port,
        user: &payload.username,
        fp: &payload.host_key_fingerprint,
        name: payload.host_name.as_deref().map(str::trim),
        seed: URL_SAFE_NO_PAD.encode(payload.bootstrap_seed),
        exp: payload.expires_at,
    };
    let json = serde_json::to_vec(&wire)
        .map_err(|_| PairingCodeError("could not serialize Pairing Code"))?;
    Ok(format!(
        "{PAIRING_CODE_PREFIX}:{PAIRING_CODE_VERSION}:{}",
        URL_SAFE_NO_PAD.encode(json)
    ))
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
    if !is_sha256_fingerprint(&payload.host_key_fingerprint) {
        return Err(PairingCodeError(
            "SSH Host fingerprint must use OpenSSH SHA256 form",
        ));
    }
    if payload.expires_at == 0 {
        return Err(PairingCodeError("Pairing Code expiry must be positive"));
    }
    Ok(())
}

fn is_sha256_fingerprint(value: &str) -> bool {
    let Some(digest) = value.strip_prefix("SHA256:") else {
        return false;
    };
    digest.len() == 43
        && digest
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'+' | b'/'))
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
    fn encoding_is_canonical_and_keeps_legacy_wire_prefix_for_ios_compatibility() {
        let encoded = encode(&fixture()).expect("valid fixture");
        let expected_json = concat!(
            r#"{"addrs":["100.64.1.2","192.168.1.20"],"port":22,"user":"developer","fp":"SHA256:"#,
            "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
            r#"","name":"buildbox","seed":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA","exp":1800000000}"#,
        );
        assert_eq!(
            encoded,
            format!("HERDR-PAIR:1:{}", URL_SAFE_NO_PAD.encode(expected_json))
        );
    }

    #[test]
    fn encoding_matches_the_shared_ios_pairing_vector() {
        let vectors: serde_json::Value = serde_json::from_str(include_str!(
            "../../../plugin/test-vectors/pairing-code-v1.json"
        ))
        .expect("valid shared pairing vectors");
        let vector = vectors["valid"]
            .as_array()
            .expect("valid vectors array")
            .iter()
            .find(|entry| entry["name"] == "with bootstrap seed and expiry")
            .expect("Host bootstrap vector");
        let payload = &vector["payload"];
        let seed = URL_SAFE_NO_PAD
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
        let encoded = encode(&payload).expect("valid fixture");
        let body = encoded.rsplit(':').next().expect("encoded body");
        let json = URL_SAFE_NO_PAD.decode(body).expect("base64url body");
        let value: serde_json::Value = serde_json::from_slice(&json).expect("JSON body");
        assert_eq!(value["name"], "buildbox");
    }
}

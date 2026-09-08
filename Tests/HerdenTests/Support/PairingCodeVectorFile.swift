import Foundation

/// Shared Pairing Code vectors from `plugin/test-vectors/`. Both versions are
/// bundled into the test target so the Swift decoder and Rust Host encoder
/// exercise the same compatibility contract.
struct PairingCodeVectorFile: Decodable, Sendable {
    let valid: [Valid]
    let invalid: [Invalid]

    struct Valid: Decodable, Sendable, CustomStringConvertible {
        let name: String
        let code: String
        let payload: Payload
        var description: String { name }
    }

    struct Payload: Decodable, Sendable {
        let addresses: [String]
        let port: Int
        let username: String
        let hostName: String?
        let hostKeyFingerprint: String
        /// Raw 32-byte Bootstrap Key seed as unpadded base64url (wire encoding).
        let bootstrapSeed: String?
        let expiresAt: Int?
    }

    struct Invalid: Decodable, Sendable, CustomStringConvertible {
        let name: String
        let code: String
        /// The expected error identifier, e.g. "bad_prefix".
        let error: String
        var description: String { name }
    }

    static let shared = load(named: "pairing-code-v1")
    static let compact = load(named: "pairing-code-v2")

    private static func load(named name: String) -> PairingCodeVectorFile {
        guard
            let url = Bundle(for: BundleLocator.self)
                .url(forResource: name, withExtension: "json")
        else {
            fatalError("\(name).json is missing from the test bundle")
        }
        do {
            return try JSONDecoder().decode(PairingCodeVectorFile.self, from: Data(contentsOf: url))
        } catch {
            fatalError("shared pairing vectors failed to load: \(error)")
        }
    }

    private final class BundleLocator {}
}

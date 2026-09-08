import Foundation

/// A parsed Pairing Code: the versioned payload the pairing plugin renders as
/// a QR image (ADR 0007). Wire format:
///
///     HERDR-PAIR:1:<base64url(JSON, no padding)>
///     HERDR-PAIR:2:<Base45(compact binary)>
///
/// v1 remains decode-only compatibility. The Host emits v2, whose compact
/// body keeps the same complete credential and identity material while fitting
/// a materially smaller terminal QR.
struct PairingCode: Sendable, Equatable {
    static let prefix = "HERDR-PAIR"
    static let version = 2

    /// Candidate addresses in the order the app should try them.
    /// IPv6 literals carry no brackets and no zone id.
    let addresses: [String]
    /// SSH port, 1...65535.
    let port: Int
    /// SSH username.
    let username: String
    /// Short machine name supplied by the pairing plugin. Optional for
    /// Pairing Codes created by older plugin versions.
    let hostName: String?
    /// The Host's SSH host key fingerprint, pinned instead of a TOFU prompt.
    let hostKeyFingerprint: HostKeyFingerprint
    /// The Bootstrap Key material, absent on a config-only Pairing Code.
    let bootstrap: Bootstrap?

    /// The single-use Enrollment credential carried inside a Pairing Code.
    /// Lives in memory only; never enters the Keychain (ADR 0007).
    struct Bootstrap: Sendable, Equatable {
        /// Raw 32-byte Ed25519 seed of the Bootstrap Key.
        let seed: Data
        /// When the Host deletes the Bootstrap Key's authorized_keys line.
        let expiresAt: Date
    }

    init(
        addresses: [String], port: Int, username: String,
        hostName: String? = nil,
        hostKeyFingerprint: HostKeyFingerprint, bootstrap: Bootstrap?
    ) {
        self.addresses = addresses
        self.port = port
        self.username = username
        self.hostName = hostName
        self.hostKeyFingerprint = hostKeyFingerprint
        self.bootstrap = bootstrap
    }

    /// Decodes and validates a scanned Pairing Code string.
    static func decode(_ scanned: String) throws(PairingCodeError) -> PairingCode {
        guard scanned.hasPrefix("\(prefix):") else {
            throw .badPrefix
        }
        let rest = scanned.dropFirst(prefix.count + 1)
        guard let separator = rest.firstIndex(of: ":") else {
            throw .badPrefix
        }
        let foundVersion = String(rest[..<separator])
        let encodedBody = String(rest[rest.index(after: separator)...])
        switch foundVersion {
        case "1": return try decodeV1(encodedBody)
        case "2": return try decodeV2(encodedBody)
        default: throw .unsupportedVersion(found: foundVersion)
        }
    }

    private static func decodeV1(_ encodedBody: String) throws(PairingCodeError) -> PairingCode {
        guard let body = Data(base64URLEncoded: encodedBody) else { throw .badEncoding }
        let wire: WirePayload
        do {
            wire = try JSONDecoder().decode(WirePayload.self, from: body)
        } catch DecodingError.dataCorrupted {
            // Only unparseable JSON reaches here: every wire field is decoded
            // as an optional lenient type, so shape problems surface as
            // typeMismatch/valueNotFound and are classified below.
            throw .badEncoding
        } catch {
            throw .badPayload(reason: "payload shape mismatch")
        }
        return try validated(wire)
    }

    private static func decodeV2(_ encodedBody: String) throws(PairingCodeError) -> PairingCode {
        guard let body = decodeBase45(encodedBody) else { throw .badEncoding }
        var reader = BinaryReader(data: body)

        let flags = try reader.readByte()
        guard flags & ~hostNameFlag == 0 else {
            throw .badPayload(reason: "unsupported compact payload flags")
        }
        let port = Int(try reader.readUInt16())
        guard (1...65535).contains(port) else {
            throw .badPayload(reason: "port must be an integer in 1..65535")
        }
        let expiresAt = try reader.readUInt32()
        guard expiresAt > 0 else {
            throw .badPayload(reason: "exp must be a positive unix-seconds integer")
        }
        let fingerprint = HostKeyFingerprint(digest: try reader.readData(count: fingerprintBytes))
        let seed = try reader.readData(count: bootstrapSeedBytes)
        let username = try reader.readString()
        guard !username.isEmpty, !containsWhitespace(username) else {
            throw .badPayload(reason: "username must be a non-empty string without whitespace")
        }
        let hostName = flags & hostNameFlag != 0 ? try reader.readString() : nil
        if let hostName, hostName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw .badPayload(reason: "Host name must not be empty")
        }

        let addressCount = Int(try reader.readByte())
        guard addressCount > 0 else {
            throw .badPayload(reason: "addresses must be a non-empty array")
        }
        var addresses: [String] = []
        addresses.reserveCapacity(addressCount)
        for _ in 0..<addressCount {
            let address: String
            switch try reader.readByte() {
            case addressIPv4:
                address = try reader.readBytes(count: 4).map(String.init).joined(separator: ".")
            case addressIPv6:
                address = formatIPv6(try reader.readBytes(count: 16))
            case addressName:
                address = try reader.readString()
            default:
                throw .badPayload(reason: "unknown compact address kind")
            }
            guard !address.isEmpty, !containsWhitespace(address) else {
                throw .badPayload(reason: "invalid address: \(address)")
            }
            addresses.append(address)
        }
        guard reader.isAtEnd else {
            throw .badPayload(reason: "unexpected trailing compact payload data")
        }

        return PairingCode(
            addresses: addresses,
            port: port,
            username: username,
            hostName: hostName,
            hostKeyFingerprint: fingerprint,
            bootstrap: Bootstrap(
                seed: seed,
                expiresAt: Date(timeIntervalSince1970: TimeInterval(expiresAt))))
    }

    private static func validated(_ wire: WirePayload) throws(PairingCodeError) -> PairingCode {
        guard let addresses = wire.addrs, !addresses.isEmpty else {
            throw .badPayload(reason: "addresses must be a non-empty array")
        }
        for address in addresses where address.isEmpty || containsWhitespace(address) {
            throw .badPayload(reason: "invalid address: \(address)")
        }
        guard
            let portValue = wire.port, let port = Int(exactly: portValue),
            (1...65535).contains(port)
        else {
            throw .badPayload(reason: "port must be an integer in 1..65535")
        }
        guard let username = wire.user, !username.isEmpty, !containsWhitespace(username) else {
            throw .badPayload(reason: "username must be a non-empty string without whitespace")
        }
        guard let fingerprint = parseFingerprint(wire.fp) else {
            throw .badPayload(reason: "fp must be an OpenSSH SHA256 fingerprint")
        }

        let bootstrap: Bootstrap?
        switch (wire.seed, wire.exp) {
        case (nil, nil):
            bootstrap = nil
        case (let seed?, let exp?):
            guard let seedData = Data(base64URLEncoded: seed), seedData.count == bootstrapSeedBytes
            else {
                throw .badPayload(reason: "seed must be \(bootstrapSeedBytes) bytes of base64url")
            }
            guard let expiry = Int(exactly: exp), expiry > 0 else {
                throw .badPayload(reason: "exp must be a positive unix-seconds integer")
            }
            bootstrap = Bootstrap(
                seed: seedData, expiresAt: Date(timeIntervalSince1970: TimeInterval(expiry)))
        default:
            throw .badPayload(reason: "seed and exp must be present together")
        }

        let hostName = wire.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        return PairingCode(
            addresses: addresses, port: port, username: username,
            hostName: hostName.flatMap { $0.isEmpty ? nil : $0 },
            hostKeyFingerprint: fingerprint, bootstrap: bootstrap)
    }

    private static let bootstrapSeedBytes = 32
    private static let fingerprintBytes = 32
    private static let hostNameFlag: UInt8 = 1
    private static let addressIPv4: UInt8 = 0
    private static let addressIPv6: UInt8 = 1
    private static let addressName: UInt8 = 2

    /// JSON wire shape. Every field is optional and numbers are decoded as
    /// Double so that missing keys and wrong values fail validation with
    /// `badPayload` instead of dying inside JSONDecoder with an error we
    /// cannot tell apart from malformed JSON.
    private struct WirePayload: Decodable {
        var addrs: [String]?
        var port: Double?
        var user: String?
        var name: String?
        var fp: String?
        var seed: String?
        var exp: Double?
    }

    /// OpenSSH presentation: "SHA256:" + 43 chars of unpadded standard base64
    /// (a 32-byte digest). Returns the digest-backed fingerprint, or nil.
    private static func parseFingerprint(_ text: String?) -> HostKeyFingerprint? {
        guard let text, text.wholeMatch(of: /SHA256:[A-Za-z0-9+\/]{43}/) != nil else {
            return nil
        }
        guard let digest = Data(base64Encoded: String(text.dropFirst("SHA256:".count)) + "=")
        else { return nil }
        return HostKeyFingerprint(digest: digest)
    }

    private static func containsWhitespace(_ text: String) -> Bool {
        text.unicodeScalars.contains { CharacterSet.whitespacesAndNewlines.contains($0) }
    }

    private static func decodeBase45(_ text: String) -> Data? {
        let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:".utf8)
        var values: [UInt16] = []
        values.reserveCapacity(text.utf8.count)
        for byte in text.utf8 {
            guard let value = alphabet.firstIndex(of: byte) else { return nil }
            values.append(UInt16(value))
        }
        guard values.count % 3 != 1 else { return nil }

        var decoded: [UInt8] = []
        decoded.reserveCapacity(values.count * 2 / 3)
        var index = 0
        while index + 2 < values.count {
            let value = UInt32(values[index])
                + UInt32(values[index + 1]) * 45
                + UInt32(values[index + 2]) * 2_025
            guard value <= UInt32(UInt16.max) else { return nil }
            decoded.append(UInt8(value >> 8))
            decoded.append(UInt8(value & 0xff))
            index += 3
        }
        if index < values.count {
            let value = values[index] + values[index + 1] * 45
            guard value <= UInt8.max else { return nil }
            decoded.append(UInt8(value))
        }
        return Data(decoded)
    }

    private static func formatIPv6(_ bytes: [UInt8]) -> String {
        let groups = stride(from: 0, to: bytes.count, by: 2).map {
            UInt16(bytes[$0]) << 8 | UInt16(bytes[$0 + 1])
        }
        var longestStart: Int?
        var longestCount = 0
        var index = 0
        while index < groups.count {
            guard groups[index] == 0 else {
                index += 1
                continue
            }
            let start = index
            while index < groups.count, groups[index] == 0 { index += 1 }
            if index - start > longestCount, index - start >= 2 {
                longestStart = start
                longestCount = index - start
            }
        }
        guard let longestStart else {
            return groups.map { String($0, radix: 16) }.joined(separator: ":")
        }
        let before = groups[..<longestStart].map { String($0, radix: 16) }.joined(separator: ":")
        let after = groups[(longestStart + longestCount)...]
            .map { String($0, radix: 16) }.joined(separator: ":")
        return before + "::" + after
    }

    private struct BinaryReader {
        private let bytes: [UInt8]
        private var offset = 0

        init(data: Data) {
            bytes = Array(data)
        }

        var isAtEnd: Bool { offset == bytes.count }

        mutating func readByte() throws(PairingCodeError) -> UInt8 {
            guard offset < bytes.count else { throw truncated }
            defer { offset += 1 }
            return bytes[offset]
        }

        mutating func readBytes(count: Int) throws(PairingCodeError) -> [UInt8] {
            guard count >= 0, offset <= bytes.count - count else { throw truncated }
            defer { offset += count }
            return Array(bytes[offset..<(offset + count)])
        }

        mutating func readData(count: Int) throws(PairingCodeError) -> Data {
            Data(try readBytes(count: count))
        }

        mutating func readUInt16() throws(PairingCodeError) -> UInt16 {
            let value = try readBytes(count: 2)
            return UInt16(value[0]) << 8 | UInt16(value[1])
        }

        mutating func readUInt32() throws(PairingCodeError) -> UInt32 {
            try readBytes(count: 4).reduce(UInt32.zero) { ($0 << 8) | UInt32($1) }
        }

        mutating func readString() throws(PairingCodeError) -> String {
            let value = try readData(count: Int(readByte()))
            guard let string = String(data: value, encoding: .utf8) else {
                throw .badPayload(reason: "compact string is not UTF-8")
            }
            return string
        }

        private var truncated: PairingCodeError {
            .badPayload(reason: "compact payload is truncated")
        }
    }
}

/// Why a scanned string is not a Pairing Code. These map 1:1 to the error
/// identifiers in the shared test vectors and belong to the "parse" step of
/// the pairing failure taxonomy (ADR 0007).
enum PairingCodeError: Error, Sendable, Equatable {
    /// Not a Pairing Code at all — likely someone else's QR.
    case badPrefix
    /// A Pairing Code from a plugin speaking another envelope version.
    case unsupportedVersion(found: String)
    /// The framing is right but the body is not base64url-encoded JSON.
    case badEncoding
    /// Well-formed JSON that violates the payload schema.
    case badPayload(reason: String)

    /// The cross-implementation identifier used by the shared test vectors.
    var wireCode: String {
        switch self {
        case .badPrefix: "bad_prefix"
        case .unsupportedVersion: "unsupported_version"
        case .badEncoding: "bad_encoding"
        case .badPayload: "bad_payload"
        }
    }
}

import Foundation
import Network

/// Addresses learned through pairing or an authenticated SSH connection.
/// They are routing hints, never a replacement for the Host's pinned SSH key.
enum HostAddresses {
    static let marker = "__HERDEN_ADDRESS__="

    // Both tools are part of the normal Host OS; discovery needs no new daemon,
    // root privileges, Python, or a matching Host runtime release.
    static let discoveryCommand = #"""
        /bin/sh -c 'PATH="$PATH:/usr/sbin:/sbin";
        if command -v ip >/dev/null 2>&1; then
          ip -o address show up scope global | awk '\''
            $2 !~ /^(lo|docker|br-|veth|virbr|cni|flannel)/ && ($3 == "inet" || $3 == "inet6") {
              split($4, a, "/"); print "__HERDEN_ADDRESS__=" a[1]
            }'\''
        elif command -v ifconfig >/dev/null 2>&1; then
          ifconfig | awk '\''
            /^[^ \t]/ { usable = $1 !~ /^(lo|bridge|docker|veth|virbr|awdl|llw)/ }
            usable && ($1 == "inet" || $1 == "inet6") { print "__HERDEN_ADDRESS__=" $2 }
          '\''
        fi'
        """#

    static func parse(_ output: String) -> [String] {
        usable(output.split(whereSeparator: \.isNewline).compactMap { line in
            line.hasPrefix(marker) ? String(line.dropFirst(marker.count)) : nil
        })
    }

    static func usable(_ addresses: [String]) -> [String] {
        var seen = Set<String>()
        return Array(addresses.compactMap { raw -> String? in
            let address = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if let ip = IPv4Address(address) {
                let b = Array(ip.rawValue)
                guard b[0] != 0, b[0] != 127, b[0] < 224,
                    !(b[0] == 169 && b[1] == 254) else { return nil }
            } else if let ip = IPv6Address(address) {
                let b = Array(ip.rawValue)
                guard !address.contains("%"), b[0] != 0xff,
                    !(b[0] == 0xfe && b[1] & 0xc0 == 0x80),
                    b.dropLast().contains(where: { $0 != 0 }),
                    // Exclude IPv4-mapped addresses as well as :: and ::1.
                    !(b.prefix(10).allSatisfy { $0 == 0 } && b[10] == 255 && b[11] == 255)
                else { return nil }
            } else { return nil }
            return seen.insert(address).inserted ? address : nil
        }.prefix(16))
    }

    static func rank(_ address: String) -> Int {
        guard let ip = IPv4Address(address) else {
            return IPv6Address(address) == nil ? 0 : 3
        }
        let b = Array(ip.rawValue)
        return b[0] == 100 && (64...127).contains(b[1]) ? 2 : 1
    }
}

/// Kept outside the editable Host catalog: learning a new interface must not
/// tear down the Console projection that just established the connection.
actor HostAddressStore {
    static let shared = HostAddressStore(defaults: SharedAppStorage.defaults)
    private let defaults: UserDefaults?
    private var memory: [String: [String]] = [:]

    init(defaults: UserDefaults? = nil) { self.defaults = defaults }

    init?(suiteName: String) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return nil }
        self.defaults = defaults
    }

    private func key(_ host: Host) -> String {
        "host-addresses-v1|\(host.id)|\(host.address)|\(host.port)|\(host.username)"
    }

    func addresses(for host: Host) -> [String] {
        guard !host.usesJumpHost else { return [] }
        return HostAddresses.usable(defaults?.stringArray(forKey: key(host)) ?? memory[key(host)] ?? [])
    }

    func remember(_ addresses: [String], for host: Host) {
        guard !host.usesJumpHost else { return }
        let usable = HostAddresses.usable(addresses)
        guard !usable.isEmpty else { return } // An unsupported probe preserves pairing hints.
        memory[key(host)] = usable
        defaults?.set(usable, forKey: key(host))
    }

    func forget(_ host: Host) {
        memory[key(host)] = nil
        defaults?.removeObject(forKey: key(host))
    }
}

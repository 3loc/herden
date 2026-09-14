import Foundation

enum SharedAppStorage {
    static let appGroup = "group.ltd.3loc.herden.shared"
    static let sshKeychainService = "ltd.3loc.herden.ssh"
    static let notificationKeychainService = "ltd.3loc.herden.notifications"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    static var sharedSecrets: KeychainSecretStore {
        KeychainSecretStore(service: sshKeychainService, accessGroup: appGroup)
    }

    static var legacySecrets: KeychainSecretStore {
        KeychainSecretStore(service: sshKeychainService)
    }

    /// Copies app-private state into the App Group once so the Share Extension
    /// can read the same Host catalog, fingerprints, passwords, and SSH key.
    static func migrateSharedStateIfNeeded() {
        let shared = defaults
        migrateState(
            from: [UserDefaults.standard],
            sourceSecrets: [legacySecrets],
            to: shared,
            destinationSecrets: sharedSecrets)
    }

    /// Testable migration seam. Existing destination values always win, so a
    /// stale legacy install can never replace newer Herden state.
    static func migrateState(
        from previousDefaults: [UserDefaults],
        sourceSecrets: [any SecretStore],
        to shared: UserDefaults,
        destinationSecrets: any SecretStore
    ) {
        for key in ["hosts", "knownHostFingerprints"] where shared.object(forKey: key) == nil {
            if let value = previousDefaults.lazy.compactMap({ $0.object(forKey: key) }).first {
                shared.set(value, forKey: key)
            }
        }

        copyMissingSecrets(from: sourceSecrets, to: destinationSecrets)
    }

    private static func copyMissingSecrets(
        from sources: [any SecretStore], to destination: any SecretStore
    ) {
        for source in sources {
            guard let secrets = try? source.readAll() else { continue }
            for (account, secret) in secrets {
                guard (try? destination.read(account: account)) == nil else { continue }
                try? destination.write(secret, account: account)
            }
        }
    }
}

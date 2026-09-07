import Foundation

enum SharedAppStorage {
    static let appGroup = "group.com.3loc.herden"
    static let sshKeychainService = "com.3loc.herden.ssh"
    static let notificationKeychainService = "com.3loc.herden.notifications"

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
        let previousDefaults = [UserDefaults.standard]
        for key in ["hosts", "knownHostFingerprints"] where shared.object(forKey: key) == nil {
            if let value = previousDefaults.lazy.compactMap({ $0.object(forKey: key) }).first {
                shared.set(value, forKey: key)
            }
        }

        copyMissingSecrets(from: [legacySecrets], to: sharedSecrets)
    }

    private static func copyMissingSecrets(
        from sources: [KeychainSecretStore], to destination: KeychainSecretStore
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

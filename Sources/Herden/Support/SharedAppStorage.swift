import Foundation

enum SharedAppStorage {
    static let appGroup = "group.com.3loc.herden"
    /// The development build that immediately preceded the public Herden
    /// identity stored Ted's Hosts and device key here. Keep read access so a
    /// correctly identified install can migrate that state once.
    static let legacyFounderTerminalAppGroup = "group.com.fansvine.founderterminal"
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

    static var founderTerminalSecrets: KeychainSecretStore {
        KeychainSecretStore(
            service: sshKeychainService,
            accessGroup: legacyFounderTerminalAppGroup)
    }

    /// Copies app-private state into the App Group once so the Share Extension
    /// can read the same Host catalog, fingerprints, passwords, and SSH key.
    static func migrateSharedStateIfNeeded() {
        let shared = defaults
        let previousDefaults = [
            UserDefaults.standard,
            UserDefaults(suiteName: legacyFounderTerminalAppGroup),
        ].compactMap { $0 }
        migrateState(
            from: previousDefaults,
            sourceSecrets: [legacySecrets, founderTerminalSecrets],
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

import Foundation

/// The choices the user last made in the new-agent flow.
///
/// The new-agent sheet pre-selects the last Host, Workspace, and Agent kind:
/// launching several agents into the same project with the same tool is the
/// common case, and re-picking them every time is pure tax. Workspace and kind
/// are keyed by Host because availability belongs to one herden installation.
struct RecentWorkspaceStore {
    private static let workspaceDefaultsKey = "recent-workspace-by-host"
    private static let agentKindDefaultsKey = "recent-agent-kind-by-host"
    private static let hostDefaultsKey = "recent-agent-host"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func workspaceID(for hostID: Host.ID) -> String? {
        workspaceByHost[hostID.uuidString]
    }

    func remember(_ workspaceID: String, for hostID: Host.ID) {
        var updated = workspaceByHost
        updated[hostID.uuidString] = workspaceID
        defaults.set(updated, forKey: Self.workspaceDefaultsKey)
    }

    var hostID: Host.ID? {
        defaults.string(forKey: Self.hostDefaultsKey).flatMap(UUID.init(uuidString:))
    }

    func rememberHost(_ hostID: Host.ID) {
        defaults.set(hostID.uuidString, forKey: Self.hostDefaultsKey)
    }

    func agentKind(for hostID: Host.ID) -> SupportedAgentKind? {
        agentKindByHost[hostID.uuidString].flatMap(SupportedAgentKind.init(rawValue:))
    }

    func rememberAgentKind(_ kind: SupportedAgentKind, for hostID: Host.ID) {
        var updated = agentKindByHost
        updated[hostID.uuidString] = kind.rawValue
        defaults.set(updated, forKey: Self.agentKindDefaultsKey)
    }

    /// Entries for Hosts that no longer exist are harmless (a few bytes each,
    /// never read), so nothing prunes them.
    private var workspaceByHost: [String: String] {
        defaults.dictionary(forKey: Self.workspaceDefaultsKey) as? [String: String] ?? [:]
    }

    private var agentKindByHost: [String: String] {
        defaults.dictionary(forKey: Self.agentKindDefaultsKey) as? [String: String] ?? [:]
    }
}

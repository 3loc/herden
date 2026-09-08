import Foundation

struct ShareDestination: Identifiable, Sendable {
    let host: Host
    let agent: Agent
    var workspaceName: String? = nil

    var id: String { "\(host.id.uuidString):\(agent.paneID)" }

    var title: String {
        if let name = meaningful(agent.name), name.lowercased() != agent.kind.lowercased() {
            return name
        }
        if let workspace = meaningful(workspaceName) { return workspace }
        if let title = meaningful(agent.title), title.lowercased() != agent.kind.lowercased() { return title }
        if !agent.cwd.isEmpty { return URL(fileURLWithPath: agent.cwd).lastPathComponent }
        return agent.displayName
    }

    private func meaningful(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}

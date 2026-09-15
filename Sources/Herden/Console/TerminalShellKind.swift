import Foundation

/// Exact shell identities supported by the small Space mark. Process names
/// outside this list stay generic; a project title is never treated as proof.
enum TerminalShellKind: String, Hashable, Sendable {
    case zsh
    case bash
    case fish

    var displayName: String { rawValue }

    static func detected(in info: PaneProcessInfo) -> Self? {
        let processes = info.foregroundProcesses ?? []
        let shell: PaneProcessInfoProcess?
        if let shellPid = info.shellPid {
            if let foregroundGroup = info.foregroundProcessGroupID,
                foregroundGroup != shellPid {
                return nil
            }
            shell = processes.first { $0.pid == shellPid }
        } else {
            shell = processes.count == 1 ? processes.first : nil
        }
        guard let shell else { return nil }
        let name = URL(fileURLWithPath: shell.name).lastPathComponent
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            .lowercased()
        return Self(rawValue: name)
    }
}

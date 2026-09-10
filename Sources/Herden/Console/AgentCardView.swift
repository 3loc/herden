import SwiftUI
import UIKit

/// One Console card (#8): the same workspace label and Agent kind herden uses,
/// plus launch directory, Host, and status. Terminal titles, trailing TUI
/// output, and opaque pane ids are deliberately absent: none identifies the
/// Agent in herden's own Agents pane.
struct AgentCardView: View {
    let agent: ConsoleAgent
    var isPinned: Bool = false

    private var presentation: AgentCardPresentation {
        AgentCardPresentation(agent: agent)
    }

    var body: some View {
        HStack(spacing: 12) {
            HerdenAgentMark(size: 42)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(presentation.headline)
                        .font(Brand.sans(.headline, weight: .semibold))
                        .foregroundStyle(Brand.ink)
                        .lineLimit(1)
                    if isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .layoutPriority(1)
                            .accessibilityLabel("Pinned")
                    }
                    Spacer(minLength: 8)
                    AgentStatusBadge(status: agent.agent.status)
                }
                HStack {
                    if let agentType = presentation.agentType {
                        Text(agentType)
                            .font(Brand.sans(.caption, weight: .semibold))
                            .foregroundStyle(Brand.muted)
                    }
                    Spacer(minLength: 8)
                    Text(agent.hostName)
                        .font(Brand.sans(.caption))
                        .foregroundStyle(Brand.subtle)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                if let context = presentation.context {
                    Text(context)
                        .font(Brand.mono(.caption2))
                        .foregroundStyle(Brand.subtle)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct AgentCardPresentation: Equatable {
    let headline: String
    let context: String?
    let agentType: String?

    init(agent: ConsoleAgent) {
        let title = agent.switcherLabel
        headline = title
        let directory = Self.nonEmpty(agent.agent.cwd).map {
            Self.abbreviatingStandardHome(in: $0, username: agent.hostUsername)
        }
        let details = [Self.nonEmpty(agent.workspaceLabel).flatMap { $0 == title ? nil : $0 }, directory]
            .compactMap { $0 }.joined(separator: " · ")
        context = details.isEmpty ? nil : details

        let kind = switch SupportedAgentKind(rawValue: agent.agent.kind) {
        case .some(.claude): "Claude"
        case let supported?: supported.displayName
        case nil: agent.agent.kind
        }
        agentType = headline.caseInsensitiveCompare(kind) == .orderedSame
            ? nil
            : kind
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    /// The snapshot carries an expanded remote path but not `$HOME`. Standard
    /// macOS/Linux SSH-account homes can still be shortened without guessing
    /// that an arbitrary path prefix is a home directory.
    private static func abbreviatingStandardHome(
        in path: String, username: String?
    ) -> String {
        guard let username, !username.isEmpty else { return path }
        let homes = username == "root"
            ? ["/root"]
            : ["/Users/\(username)", "/home/\(username)"]
        guard let home = homes.first(where: { path == $0 || path.hasPrefix("\($0)/") })
        else { return path }
        return path == home ? "~" : "~\(path.dropFirst(home.count))"
    }
}

/// The Console's one durable destination. A Space leads; its current Agent or
/// shell is state carried by the row rather than a second navigation object.
struct SpaceCardView: View {
    let space: ConsoleSpace
    var isOpening = false

    private var occupantLabel: String {
        switch space.occupant {
        case .terminal:
            "Terminal"
        case .agent(let kind, _, _):
            SupportedAgentKind(rawValue: kind)?.displayName ?? kind.capitalized
        case .agents(let count, _):
            "\(count) Agents"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            HerdenSpaceMark(size: 42)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(space.workspace.label)
                        .font(Brand.sans(.headline, weight: .semibold))
                        .foregroundStyle(Brand.ink)
                        .lineLimit(1)
                    if space.pinRank != nil {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .layoutPriority(1)
                            .accessibilityLabel("Pinned")
                    }
                    Spacer(minLength: 8)
                    if let status = space.occupant.status {
                        AgentStatusBadge(status: status)
                    } else {
                        Image(systemName: "apple.terminal")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Brand.muted)
                            .accessibilityHidden(true)
                    }
                }
                HStack(spacing: 6) {
                    Text(occupantLabel)
                        .font(Brand.sans(.caption, weight: .semibold))
                        .foregroundStyle(space.occupant.status == nil ? Brand.muted : Brand.vine)
                    Spacer(minLength: 8)
                    Text(space.hostName)
                        .font(Brand.mono(.caption2))
                        .foregroundStyle(Brand.subtle)
                        .lineLimit(1)
                }
            }
            if isOpening {
                ProgressView()
                    .controlSize(.small)
                    .tint(Brand.vine)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Status rendered as a tinted capsule; Blocked gets the loudest color
/// because it is the one asking for the user. Working keeps a live solving
/// orb inside the capsule — a still badge cannot tell a busy Agent from a
/// finished one at a glance.
struct AgentStatusBadge: View {
    let status: AgentStatus

    var body: some View {
        HStack(spacing: 4) {
            if status == .working {
                SolvingOrbView(size: 12)
                    .accessibilityHidden(true)
            }
            Text(status.rawValue.capitalized)
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color(status.tintUIColor).opacity(0.15), in: Capsule())
        .foregroundStyle(Color(status.inkUIColor))
    }
}

#Preview {
    List {
        AgentCardView(
            agent: ConsoleAgent(
                hostID: UUID(),
                hostName: "devbox",
                agent: Agent(
                    terminalID: "term_a", kind: "claude", title: "Fix the flaky test",
                    status: .blocked, workspaceID: "w1", tabID: "w1:t1", paneID: "w1:p1",
                    cwd: "/work/proj", revision: 3),
                workspaceLabel: "proj",
                repositoryCheckout: RepositoryCheckout(
                    repoKey: "/work/proj/.git",
                    repoName: "proj",
                    repoRoot: "/work/proj",
                    checkoutPath: "/work/proj-wt",
                    isLinkedWorktree: true),
                lastOutputSnippet: "Allow Claude to run rm -rf? 1. Yes 2. No"))
        // No workspace in the snapshot: the Agent's own name takes the lead.
        AgentCardView(
            agent: ConsoleAgent(
                hostID: UUID(),
                hostName: "devbox",
                agent: Agent(
                    terminalID: "term_b", kind: "claude", title: "Draft the release notes",
                    status: .working, workspaceID: "w2", tabID: "w2:t1", paneID: "w2:p1",
                    cwd: "/tmp", revision: 1),
                workspaceLabel: nil,
                repositoryCheckout: nil,
                lastOutputSnippet: nil))
    }
}

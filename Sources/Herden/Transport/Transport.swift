import Foundation

/// The app-side abstraction that executes herden API requests over SSH.
/// UI code talks to Transport, never to SSH primitives (ADR 0011).
protocol Transport: Sendable {
    /// Verifies the server speaks a protocol version we support and returns
    /// its identity. Must be the first herden API call on every new connection
    /// path; Host-local session discovery may run before it.
    func ping() async throws -> ServerInfo

    /// Lists the local herden sessions visible to this SSH account. This is a
    /// Host-level capability and does not depend on the currently selected
    /// API socket, so onboarding can recover from a stale manual selection.
    func listSessions() async throws -> [HerdrSession]

    /// Lists the Agents herden has detected across all workspaces.
    func listAgents() async throws -> [Agent]

    /// Lists the supported Agent kinds whose canonical executables are
    /// currently available on this Host. SSH transports probe the Host's
    /// effective PATH; alternative transports without a Host process
    /// environment report no detected kinds by default.
    func availableAgentKinds() async throws -> [SupportedAgentKind]

    /// The full session tree in one call: agents plus the workspace context
    /// (labels, worktrees) that `listAgents()` lacks. The Console's snapshot
    /// source (#8) — re-fetched on every events-session `.connected`.
    func sessionSnapshot() async throws -> SessionSnapshot

    /// Reads a Pane's recent terminal output for the Console card snippet.
    func readPane(_ params: PaneReadParams) async throws -> PaneReadResult

    /// Reads an Agent's terminal output. Unlike `pane.read`, this preserves
    /// history semantics for alternate-screen Agents: history-capable sources
    /// fail honestly while the Agent is working instead of silently degrading
    /// to the visible screen.
    func readAgent(_ params: AgentReadParams) async throws -> PaneReadResult

    /// Delivers one complete local draft through `agent.prompt`. The request
    /// deliberately omits `wait`: the response acknowledges delivery into
    /// the Agent's pane, while Agent Status events report subsequent work.
    func promptAgent(_ params: AgentPromptParams) async throws -> Agent

    /// Sends control keys to an Agent (`agent.send_keys`). Key names are
    /// herden's own spellings, shared with `pane.send_keys` / `pane.send_input`.
    func sendAgentKeys(_ params: AgentSendKeysParams) async throws

    /// Inserts text and/or keys into any Pane without implicitly submitting
    /// it. Share Extension delivery uses this after SFTP staging so sharing a
    /// file behaves like dropping it into the Agent's terminal composer.
    func sendPaneInput(_ params: PaneSendInputParams) async throws

    /// Starts a new Agent: the new-agent flow (#12, User Story 8 — dispatch
    /// work from the road). Creates a fresh herden tab in the chosen workspace,
    /// starts the requested agent in its root pane, and returns the Agent once
    /// the server acknowledges. The new pane also surfaces in the
    /// Console through the normal snapshot/delta machinery (a membership
    /// event triggers a re-snapshot), so callers do not thread the return
    /// value into the list themselves.
    func startAgent(_ request: AgentLaunchRequest) async throws -> Agent

    /// Creates one ordinary shell tab in an existing Workspace. The concrete
    /// directory is mandatory so herden cannot inherit an unrelated focused
    /// Pane's cwd. The returned identity is sufficient to attach the shell;
    /// no Agent is started and the Pane is not projected into the Console.
    func createShellTerminal(
        _ request: ShellTerminalCreationRequest
    ) async throws -> ShellTerminalIdentity

    /// Creates a new Workspace whose root Pane remains an ordinary shell.
    /// This is the Space-first counterpart to `startAgentInNewWorkspace`:
    /// no Agent is launched, and the returned terminal can be attached
    /// immediately.
    func createSpace(_ request: SpaceCreationRequest) async throws -> CreatedSpace

    /// Starts a new Agent in a fresh git worktree (#97): `worktree.create`
    /// resolves the repository from the source workspace's cwd (a non-git cwd
    /// fails with `not_git_worktree`) and returns a new workspace whose root
    /// pane already runs a shell, so this variant skips `tab.create` and
    /// starts the agent in that pane directly (the `agent_pane_busy`
    /// readiness retry still applies). `request.workspaceID` is the *source*
    /// workspace; the started agent lives in the returned worktree workspace
    /// and surfaces through the normal snapshot/delta machinery.
    func startAgentInNewWorktree(
        _ request: AgentLaunchRequest, worktree: WorktreeSpec
    ) async throws -> Agent

    /// Starts a new Agent in a freshly created Workspace (#230):
    /// `workspace.create` opens the remote directory as its own Workspace
    /// (no existing Workspace required) and returns a root pane already
    /// running a shell, so this variant skips `tab.create` and starts the
    /// agent in that pane directly (the `agent_pane_busy` readiness retry
    /// still applies). `request.workspaceID` is unused; the started agent
    /// lives in the returned Workspace and surfaces through the normal
    /// snapshot/delta machinery.
    func startAgentInNewWorkspace(
        _ request: AgentLaunchRequest, workspace: NewWorkspaceSpec
    ) async throws -> Agent

    /// Closes a Pane (`pane.close`): the Agent detail screen's destructive
    /// close action (#13, User Story 9 — a Done agent must not be destroyed
    /// by a stray swipe, so the UI gates this behind an explicit
    /// confirmation). herden removes the pane and its agent everywhere; the
    /// removal surfaces in the Console through the normal snapshot/delta
    /// machinery (a `pane.closed` membership event triggers a re-snapshot),
    /// so callers do not prune the list themselves. Targeted by the Pane's
    /// id; returns once the server acknowledges.
    func closePane(_ params: PaneTarget) async throws

    /// Closes an entire Workspace (`workspace.close`). This is the destructive
    /// close for a standalone Space and for an Agent that is the Workspace's
    /// only Pane; using `pane.close` for that last Pane leaves herden's
    /// replacement shell behind as an apparently lingering Space.
    func closeWorkspace(_ params: WorkspaceCloseParams) async throws

    /// Lists git worktrees for the repository containing `workspaceID`.
    /// Console detail uses this only to obtain branch presentation because
    /// `session.snapshot` already carries repository and checkout identity.
    func listWorktrees(forWorkspaceID workspaceID: String) async throws -> WorktreeListResponse

    /// Removes one exact confirmed linked Worktree. `authorize` is invoked
    /// after the stream-local channel opens but before its first request byte;
    /// `onDispatched` runs only after the complete request line is written.
    /// Both receive the immutable request that crosses this Transport seam.
    func removeWorktree(
        _ request: WorktreeRemovalRequest,
        authorize: @escaping @Sendable (WorktreeRemovalRequest) async throws -> Void,
        onDispatched: @escaping @Sendable (WorktreeRemovalRequest) async -> Void
    ) async throws -> WorktreeRemovedResponse

    /// Renames an Agent (`agent.rename`): the Console management action
    /// (#98). A nil name clears the custom name back to the detected kind
    /// (verified live against herden 0.7.5: omitting the key clears). The
    /// server enforces `^[a-z][a-z0-9_-]{0,31}$` on non-nil names and
    /// rejects violations with `invalid_agent_name`; non-agent targets fail
    /// with `agent_not_found`. The new name does NOT travel on events — the
    /// `pane.updated` this fires omits the agent name (verified live) — so
    /// consumers re-snapshot after the call instead of mutating local state
    /// or waiting on a delta.
    func renameAgent(_ params: AgentRenameParams) async throws

    /// Renames a workspace (`workspace.rename`): the Console management
    /// action (#98). The server accepts any label — empty, whitespace, and
    /// very long labels all pass (verified live against herden 0.7.5); the
    /// only rejection is `workspace_not_found`. The new label surfaces
    /// through `workspace.renamed`, so callers do not mutate local state
    /// themselves.
    func renameWorkspace(_ params: WorkspaceRenameParams) async throws

    /// Opens this Host's dedicated long-lived events channel and subscribes.
    /// Returns once the server acknowledges the subscription; the stream then
    /// carries events in canonical naming until `end()` closes the channel
    /// explicitly. One events channel per Host: a second call while one is
    /// live throws `.eventsChannelAlreadyOpen`.
    ///
    /// Subscribing does not replay existing *state*, but herden 0.7.5
    /// replays recently buffered *events* on subscribe (verified live;
    /// 0.7.4 replayed nothing). Neither replaces initial sync: fetch a
    /// snapshot alongside subscribing, and treat replayed events as
    /// ordinary change signals.
    func subscribeToEvents(_ subscriptions: [EventSubscription]) async throws -> HerdrEventStream

    /// Opens this Host's dedicated terminal channel as a full interactive
    /// Attach: a PTY running `herden agent attach`, raw bytes both ways until
    /// `end()` closes the channel explicitly. One terminal channel is allowed
    /// per Host, so a second call while one is live throws
    /// `.terminalChannelAlreadyOpen`.
    func attachTerminal(_ request: TerminalAttachRequest) async throws -> TerminalAttachSession

    /// Stages one normalized app-owned image in private Host temporary
    /// storage. Concrete transports own destination selection, restrictive
    /// permissions, partial-file handling, and atomic completion (ADR 0006).
    func stageImage(
        _ image: PreparedImage,
        progress: @escaping @Sendable (AttachmentStageProgress) async -> Void
    ) async throws -> StagedImage

    /// Stages one app-owned file in private Host temporary storage. The file
    /// follows the same SFTP, permission, and atomic-completion policy as images.
    func stageFile(
        _ file: PreparedFile,
        progress: @escaping @Sendable (AttachmentStageProgress) async -> Void
    ) async throws -> StagedFile

    /// Reads the Notification Registration file (v1, `plugin/README.md`)
    /// from the Herden plugin's config dir on this Host; nil when no
    /// device has registered yet. Throws
    /// `NotificationRegistrationError.pluginNotInstalled` when the plugin is
    /// absent, so the ceremony can tell "install the plugin" apart from a
    /// broken read (#72).
    func readNotificationRegistration() async throws -> Data?

    /// Atomically replaces the Notification Registration file with
    /// `contents` (temp file + rename per the v1 contract), creating it when
    /// absent. Same plugin gate as the read.
    func replaceNotificationRegistration(_ contents: Data) async throws

    /// Reads the plugin's `notify.json` config from this Host's Herden
    /// plugin config dir (the registration file's sibling; `plugin/README.md`);
    /// nil when the plugin has no config file yet. Same plugin gate as the
    /// registration read. Carries the custom Push Relay base URL (#76).
    func readNotificationConfig() async throws -> Data?

    /// Atomically replaces the plugin's `notify.json` config with `contents`
    /// (temp file + rename), creating it when absent. Same plugin gate as the
    /// registration write.
    func replaceNotificationConfig(_ contents: Data) async throws

    /// Lists the skills / custom slash commands installed for a kind on this
    /// Host: global sources under the remote home plus project sources under
    /// the query's project root, per `SkillSourceCatalog`. Kinds without a
    /// catalog entry return empty. Reads the filesystem over exec, so
    /// alternative transports without a Host process environment report
    /// nothing by default.
    func listSkills(_ query: SkillListQuery) async throws -> [AgentSkill]

    /// Reads one skill document in full (capped) for the on-demand content
    /// view; `path` is what the skills probe reported. Same transport caveat
    /// as `listSkills`.
    func readSkillFile(atPath path: String) async throws -> String

    /// Whether the underlying connection to the Host is still alive. The
    /// reconnect machinery (#18) decides "re-subscribe on this connection or
    /// re-establish it" from this flag.
    var isConnected: Bool { get async }

    /// Tears the connection down explicitly, ending every channel it
    /// carries. Terminal: a closed Transport is not reusable.
    func close() async throws
}

extension Transport {
    /// Test doubles and alternative transports that do not expose Host-level
    /// session discovery can opt out without inventing sessions.
    func listSessions() async throws -> [HerdrSession] { [] }

    func availableAgentKinds() async throws -> [SupportedAgentKind] {
        []
    }

    func sendPaneInput(_ params: PaneSendInputParams) async throws {
        throw TransportError.channelFailed(
            detail: "This transport cannot send Pane input.")
    }

    func createShellTerminal(
        _ request: ShellTerminalCreationRequest
    ) async throws -> ShellTerminalIdentity {
        throw TransportError.channelFailed(
            detail: "This transport cannot create shell terminals.")
    }

    func createSpace(_ request: SpaceCreationRequest) async throws -> CreatedSpace {
        throw TransportError.channelFailed(
            detail: "This transport cannot create Spaces.")
    }

    func closeWorkspace(_ params: WorkspaceCloseParams) async throws {
        throw TransportError.channelFailed(
            detail: "This transport cannot close Spaces.")
    }

    func listSkills(_ query: SkillListQuery) async throws -> [AgentSkill] {
        []
    }

    func readSkillFile(atPath path: String) async throws -> String {
        throw TransportError.channelFailed(
            detail: "This transport cannot read skill files.")
    }

    /// Non-SSH test doubles and alternative transports can state that SFTP is
    /// unavailable without importing or emulating an SSH library.
    func stageImage(
        _ image: PreparedImage,
        progress: @escaping @Sendable (AttachmentStageProgress) async -> Void
    ) async throws -> StagedImage {
        throw AttachmentStagingError.sftpUnavailable
    }

    func stageFile(
        _ file: PreparedFile,
        progress: @escaping @Sendable (AttachmentStageProgress) async -> Void
    ) async throws -> StagedFile {
        throw AttachmentStagingError.sftpUnavailable
    }

    /// Test doubles and alternative transports without a Host-side plugin
    /// can report its absence without emulating the plugin CLI.
    func readNotificationRegistration() async throws -> Data? {
        throw NotificationRegistrationError.pluginNotInstalled
    }

    func replaceNotificationRegistration(_ contents: Data) async throws {
        throw NotificationRegistrationError.pluginNotInstalled
    }

    func readNotificationConfig() async throws -> Data? {
        throw NotificationRegistrationError.pluginNotInstalled
    }

    func replaceNotificationConfig(_ contents: Data) async throws {
        throw NotificationRegistrationError.pluginNotInstalled
    }

    func listWorktrees(forWorkspaceID workspaceID: String) async throws -> WorktreeListResponse {
        throw TransportError.channelFailed(
            detail: "This transport cannot list worktrees.")
    }

    func removeWorktree(
        _ request: WorktreeRemovalRequest,
        authorize: @escaping @Sendable (WorktreeRemovalRequest) async throws -> Void,
        onDispatched: @escaping @Sendable (WorktreeRemovalRequest) async -> Void
    ) async throws -> WorktreeRemovedResponse {
        throw TransportError.channelFailed(
            detail: "This transport cannot remove worktrees.")
    }
}

/// Herden's catalog of interactive Agent kinds.
///
/// The raw value is the canonical `agent.start.kind`; `executable` mirrors
/// the command herden launches for that kind. Keeping both explicit matters
/// for kinds such as Cursor and Kiro whose executable is not their canonical
/// protocol label.
enum SupportedAgentKind: String, CaseIterable, Identifiable, Sendable, Equatable {
    case pi
    case claude
    case codex
    case gemini
    case cursor
    case devin
    case antigravity = "agy"
    case cline
    case omp
    case mastracode
    case opencode
    case copilot
    case kimi
    case kiro
    case droid
    case amp
    case grok
    case hermes
    case kilo
    case qodercli
    case maki
    case qwen

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pi: "Pi"
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .gemini: "Gemini CLI"
        case .cursor: "Cursor Agent"
        case .devin: "Devin CLI"
        case .antigravity: "Antigravity"
        case .cline: "Cline"
        case .omp: "OMP"
        case .mastracode: "Mastra Code"
        case .opencode: "OpenCode"
        case .copilot: "GitHub Copilot CLI"
        case .kimi: "Kimi CLI"
        case .kiro: "Kiro CLI"
        case .droid: "Droid"
        case .amp: "Amp"
        case .grok: "Grok Build"
        case .hermes: "Hermes Agent"
        case .kilo: "Kilo Code"
        case .qodercli: "Qoder CLI"
        case .maki: "Maki"
        case .qwen: "Qwen Code"
        }
    }

    var executable: String {
        switch self {
        case .cursor: "cursor-agent"
        case .kiro: "kiro-cli"
        default: rawValue
        }
    }
}

/// App-domain request for launching a fresh coding agent.
///
/// herden protocol 17 split the old topology-changing `agent.start` into
/// `tab.create` followed by a pane-targeted `agent.start`. Keeping that wire
/// choreography behind `Transport` prevents UI code from depending on the
/// server's transport-level request shapes.
struct AgentLaunchRequest: Sendable, Equatable {
    let kind: String
    let name: String
    let nameIsUserSet: Bool
    let arguments: [String]
    let workspaceID: String?
    /// Working directory for the fresh tab, carried when the launch starts
    /// from another agent's screen and should land in the same place. Nil
    /// lets herden fall back to the workspace's own directory.
    let cwd: String?

    init(
        kind: String, name: String, arguments: [String] = [], workspaceID: String? = nil,
        cwd: String? = nil, nameIsUserSet: Bool = false
    ) {
        self.kind = kind
        self.name = name
        self.nameIsUserSet = nameIsUserSet
        self.arguments = arguments
        self.workspaceID = workspaceID
        self.cwd = cwd
    }
}

/// The one-shot API request behind Agent Detail's Open Terminal action.
/// `cwd` is concrete by construction; callers disable the action when they
/// cannot resolve one honestly.
struct ShellTerminalCreationRequest: Sendable, Equatable {
    let workspaceID: String
    let cwd: String

    init(workspaceID: String, cwd: String) {
        self.workspaceID = workspaceID
        self.cwd = cwd
    }
}

/// Stable remote identity retained after `tab.create` succeeds. Attach retry
/// and Host-generation replacement use `terminalID`; Pane and Tab ids remain
/// available without inventing a `ConsoleAgent` for the shell.
struct ShellTerminalIdentity: Sendable, Equatable, Hashable {
    let paneID: String
    let tabID: String
    let terminalID: String

    init(paneID: String, tabID: String, terminalID: String) {
        self.paneID = paneID
        self.tabID = tabID
        self.terminalID = terminalID
    }
}

/// The Workspace and root shell created by one explicit New Space action.
/// Keeping both identities prevents the UI from inventing a temporary Agent
/// just to reach the terminal.
struct CreatedSpace: Sendable, Equatable {
    let workspaceID: String
    let label: String
    let terminal: ShellTerminalIdentity

    init(workspaceID: String, label: String, terminal: ShellTerminalIdentity) {
        self.workspaceID = workspaceID
        self.label = label
        self.terminal = terminal
    }
}

/// The user-facing Space creation request. Unlike an Agent launch, creating
/// an ordinary Space does not require a project directory: nil asks herden to
/// use the Host's default directory (normally the user's home).
struct SpaceCreationRequest: Sendable, Equatable {
    let directory: String?
    let label: String?

    init(directory: String? = nil, label: String? = nil) {
        self.directory = directory
        self.label = label
    }
}

/// What the skills probe needs to know: whose sources to walk and where the
/// agent's project lives. The project root is the *launch* directory context
/// (worktree checkout or agent cwd), deliberately not the live foreground
/// cwd — agents load project skills from where they started, and a `cd`
/// inside the session does not change that set.
struct SkillListQuery: Sendable, Equatable {
    let kind: SupportedAgentKind
    /// Absolute project root, or nil when the agent's project is unknown;
    /// nil skips project sources rather than failing the probe.
    let projectRoot: String?

    init(kind: SupportedAgentKind, projectRoot: String? = nil) {
        self.kind = kind
        self.projectRoot = projectRoot
    }
}

/// App-domain refinements for the fresh-worktree launch variant (#97). Nil
/// fields use herden's defaults, verified live against 0.7.5: branch
/// `worktree/<generated-name>` off HEAD, checkout under herden's worktree
/// root. An existing branch is checked out, not rejected; it only fails when
/// another worktree already has it checked out.
struct WorktreeSpec: Sendable, Equatable {
    let branch: String?
    let base: String?

    init(branch: String? = nil, base: String? = nil) {
        self.branch = branch
        self.base = base
    }
}

/// App-domain refinements for the new-Workspace launch variant (#230).
/// `directory` is the remote path `workspace.create` opens; `label` is
/// optional and omitted on the wire when nil so herden applies its default.
struct NewWorkspaceSpec: Sendable, Equatable {
    /// Nil explicitly means the SSH account's home, never the focused pane's cwd.
    let directory: String?
    let label: String?

    init(directory: String? = nil, label: String? = nil) {
        self.directory = directory
        self.label = label
    }
}

/// herden server identity as reported by `ping`.
struct ServerInfo: Sendable, Equatable {
    let version: String
    let protocolVersion: Int
    /// The Host speaks a protocol newer than the schema snapshot this build
    /// was generated against. Purely advisory: the connection is usable, and
    /// herden's additions have been additive, but features introduced after
    /// this build cannot be driven. Consumers surface it, never refuse on it.
    let exceedsGeneratedProtocol: Bool

    init(version: String, protocolVersion: Int, exceedsGeneratedProtocol: Bool = false) {
        self.version = version
        self.protocolVersion = protocolVersion
        self.exceedsGeneratedProtocol = exceedsGeneratedProtocol
    }
}

/// One entry from `herden session list --json` on a Host.
struct HerdrSession: Sendable, Equatable, Decodable {
    let name: String
    let isDefault: Bool
    let isRunning: Bool

    init(name: String, isDefault: Bool, isRunning: Bool) {
        self.name = name
        self.isDefault = isDefault
        self.isRunning = isRunning
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case isDefault = "default"
        case isRunning = "running"
    }
}

/// The grammar enforced by herden 0.7.4 for named sessions. Keeping it at the
/// transport boundary prevents malformed discovery output from becoming part
/// of a remote socket path; forms reuse it for immediate feedback.
enum HerdrSessionName {
    static let maximumUTF8Length = 64

    static func isValid(_ name: String) -> Bool {
        guard !name.isEmpty, name != ".", name != ".." else { return false }
        guard name.utf8.count <= maximumUTF8Length else { return false }
        return name.utf8.allSatisfy { byte in
            (0x30...0x39).contains(byte) || (0x41...0x5A).contains(byte)
                || (0x61...0x7A).contains(byte)
                || byte == 0x2E || byte == 0x5F || byte == 0x2D
        }
    }
}

/// Paths passed through the Host's login shell use the conservative quoting
/// subset shared by POSIX shells and fish. Spaces are safe inside single
/// quotes; quote, backslash, and control characters are refused because their
/// single-quote behavior differs across those shells.
enum RemoteShellPath {
    static func quotedAbsolute(_ path: String) -> String? {
        guard path.hasPrefix("/") else { return nil }
        guard path.unicodeScalars.allSatisfy(isQuotable) else { return nil }
        return "'\(path)'"
    }

    static func isQuotableAbsolute(_ path: String) -> Bool {
        quotedAbsolute(path) != nil
    }

    private static func isQuotable(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value >= 0x20 && scalar.value != 0x7F
            && scalar.value != 0x27 && scalar.value != 0x5C
    }
}

/// A coding agent process running inside a herden Pane.
///
/// The domain view of the generated wire type `AgentInfo`: only the fields
/// the app consumes, with wire-level optionality resolved. `AgentStatus` is
/// the generated raw-string wrapper; Blocked drives sort order and (later)
/// notifications.
struct Agent: Sendable, Equatable {
    let terminalID: String
    /// The agent program herden detected: "claude", "codex", ... Behavior
    /// stays keyed off this; labels prefer `displayName`.
    let kind: String
    /// The server-reported agent name the herden TUI shows (`display_agent`,
    /// falling back to `name`); nil when the server reports neither.
    let name: String?
    /// Whether `agent.rename` supplied the operational name. Managed launch
    /// names such as `codex-2` remain targets, not presentation overrides.
    let nameIsUserSet: Bool
    /// Agent-native session name, when the Host can distinguish one from a
    /// generic cwd/terminal title.
    var automaticName: String?
    /// Terminal title with spinner/status glyphs stripped.
    var title: String
    /// Mutable: the Console applies `pane.agent_status_changed` deltas in
    /// place between snapshots.
    var status: AgentStatus
    let workspaceID: String
    let tabID: String
    /// The Pane address used for per-pane subscriptions and attach.
    let paneID: String
    let cwd: String
    let revision: Int

    /// The card's primary label (#41): the server-reported name when present,
    /// otherwise the detected kind.
    var displayName: String { name ?? kind }

    init(
        terminalID: String, kind: String, title: String, status: AgentStatus,
        workspaceID: String, tabID: String, paneID: String, cwd: String, revision: Int,
        name: String? = nil, nameIsUserSet: Bool? = nil, automaticName: String? = nil
    ) {
        self.terminalID = terminalID
        self.kind = kind
        self.name = name
        self.nameIsUserSet = nameIsUserSet ?? (name != nil)
        self.automaticName = automaticName
        self.title = title
        self.status = status
        self.workspaceID = workspaceID
        self.tabID = tabID
        self.paneID = paneID
        self.cwd = cwd
        self.revision = revision
    }

    /// Maps the generated wire type onto the domain view. Wire-optional
    /// fields degrade instead of failing: herden's API has no stability
    /// guarantee, and a missing title must not drop the Agent from the list.
    init(_ info: AgentInfo) {
        let kind = info.agent ?? "unknown"
        let serverName = Self.nonEmpty(info.name)
        let displayAgent = Self.nonEmpty(info.displayAgent)
        let nameIsUserSet = info.nameIsUserSet
            ?? (displayAgent == nil && Self.inferLegacyUserSetName(serverName, kind: kind))
        let terminalTitle = TerminalTitleGlyphs.strip(
            info.terminalTitleStripped ?? info.terminalTitle ?? "")
        let metadataTitle = Self.nonEmpty(info.title)
        self.init(
            terminalID: info.terminalID,
            kind: kind,
            title: metadataTitle ?? terminalTitle,
            status: info.agentStatus,
            workspaceID: info.workspaceID,
            tabID: info.tabID,
            paneID: info.paneID,
            cwd: info.cwd ?? "",
            revision: info.revision,
            name: nameIsUserSet
                ? serverName
                : displayAgent ?? serverName,
            nameIsUserSet: nameIsUserSet,
            automaticName: metadataTitle
                ?? Self.meaningfulTerminalTitle(terminalTitle, cwd: info.cwd, kind: kind)
        )
    }

    /// An empty wire string carries no name; treating it as missing keeps the
    /// fallback chain from rendering a blank card label.
    private static func nonEmpty(_ value: String?) -> String? {
        value.flatMap {
            let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    private static func meaningfulTerminalTitle(
        _ title: String, cwd: String?, kind: String
    ) -> String? {
        guard let title = nonEmpty(title) else { return nil }
        let cwdName = cwd.map { URL(fileURLWithPath: $0).lastPathComponent }
        if title.caseInsensitiveCompare(kind) == .orderedSame
            || cwdName?.caseInsensitiveCompare(title) == .orderedSame
        {
            return nil
        }
        return title
    }

    private static func inferLegacyUserSetName(_ name: String?, kind: String) -> Bool {
        guard let name else { return false }
        if name == kind { return false }
        guard name.hasPrefix("\(kind)-") else { return true }
        return Int(name.dropFirst(kind.count + 1)) == nil
    }
}

/// Where the herden API socket lives on a Host. Home-relative locations are
/// resolved against the remote home directory, which the Transport resolves
/// over exec once per Host and caches.
enum HerdenSocketLocation: Sendable, Equatable {
    /// The default herden session: `~/.config/herden/herden.sock`.
    case defaultSession
    /// A named session: `~/.config/herden/sessions/<name>/herden.sock`.
    case namedSession(String)
    /// An absolute path known in advance; needs no remote resolution.
    case absolutePath(String)

    /// The absolute socket path, given the Host's home directory.
    func path(homeDirectory: String) -> String {
        let home =
            homeDirectory.hasSuffix("/") ? String(homeDirectory.dropLast()) : homeDirectory
        switch self {
        case .defaultSession:
            return "\(home)/.config/herden/herden.sock"
        case .namedSession(let name):
            return "\(home)/.config/herden/sessions/\(name)/herden.sock"
        case .absolutePath(let path):
            return path
        }
    }

    /// Ordered compatibility candidates. Herden's path always wins; the
    /// retired herdr path keeps already-running sessions attachable during
    /// the product-name migration without moving or restarting their sockets.
    func candidatePaths(homeDirectory: String) -> [String] {
        let preferred = path(homeDirectory: homeDirectory)
        let home =
            homeDirectory.hasSuffix("/") ? String(homeDirectory.dropLast()) : homeDirectory
        switch self {
        case .defaultSession:
            return [preferred, "\(home)/.config/herdr/herdr.sock"]
        case .namedSession(let name):
            return [preferred, "\(home)/.config/herdr/sessions/\(name)/herdr.sock"]
        case .absolutePath:
            return [preferred]
        }
    }
}

/// Transport-level failures: a closed taxonomy so every screen maps errors to
/// user guidance consistently instead of string-matching.
indirect enum TransportError: Error, Sendable, Equatable {
    /// The SSH server could not be reached: connection refused, no route,
    /// or the connection died before authentication.
    case sshUnreachable(detail: String)
    /// The first hop failed: the Host may be perfectly healthy, but the
    /// Jump Host in front of it is unreachable, rejected our key, or presented
    /// an unexpected host key. Carries the underlying failure so screens can
    /// reuse the existing guidance while naming the Jump Host as the culprit.
    case jumpHostFailed(TransportError)
    /// The Jump Host accepted SSH authentication but its server or key policy
    /// prohibits the direct-tcpip channel required to reach the Host.
    case tcpForwardingUnavailable
    /// The Host rejected our credentials (key not authorized, wrong
    /// password, or the offered auth method is unavailable).
    case authenticationFailed
    /// The device's stored Ed25519 private key cannot be decoded. Reconnecting
    /// cannot repair it; the user must explicitly replace the Device Key.
    case deviceKeyCorrupt
    /// First connect to an unknown Host and the user declined its key
    /// fingerprint; nothing was stored.
    case hostKeyRejected(presented: HostKeyFingerprint)
    /// The Host presented a key that differs from the trusted fingerprint —
    /// possibly a man-in-the-middle. Hard failure; the stored fingerprint is
    /// left untouched.
    case hostKeyMismatch(known: HostKeyFingerprint, presented: HostKeyFingerprint)
    /// The herden API socket path does not exist on the Host: herden is not
    /// installed there, or the socket path is wrong.
    case socketNotFound(path: String)
    /// The herden CLI is not on the SSH session's PATH and was not found in
    /// the well-known install prefixes. The API socket can still work — that
    /// is why the Console may list Agents while Attach fails (#206).
    case herdenBinaryNotFound
    /// libssh2 cannot distinguish a listening Unix socket rejected by SSH
    /// policy from a stale socket file. The Host needs either herden started or
    /// stream-local forwarding enabled; presenting a narrower cause would be
    /// fabricated precision.
    case streamLocalOpenFailed(path: String)
    /// The server speaks a herden protocol version this build does not support.
    case protocolVersionMismatch(server: Int, supported: Int)
    /// The remote home directory could not be resolved, so a home-relative
    /// socket location has no path.
    case homeDirectoryUnresolvable(detail: String)
    /// A second events channel was requested while one is live; each Host
    /// keeps exactly one dedicated events channel (ADR 0011 headroom).
    case eventsChannelAlreadyOpen
    /// A second terminal channel was requested while one is live, or a
    /// second reader tried to consume a terminal session that already has
    /// one; each Host keeps exactly one interactive terminal surface at a
    /// time, and each session serves exactly one of them.
    case terminalChannelAlreadyOpen
    /// The request exceeded its per-request deadline; the channel it held was
    /// closed.
    case timedOut
    /// The request's task was cancelled before completing; any channel it
    /// held was closed.
    case cancelled
    /// The channel produced bytes that do not decode as a herden response.
    case malformedResponse(String)
    /// herden answered with an error envelope: the request arrived intact and
    /// the server rejected it on its own terms.
    case apiRejected(code: String, message: String)
    /// The channel failed outside the known failure shapes; carries the
    /// underlying description for diagnostics.
    case channelFailed(detail: String)

    /// Whether reconnecting without user intervention can plausibly recover.
    /// Configuration, trust, authentication, and protocol failures instead
    /// stop so the UI can explain the required action.
    /// `.streamLocalOpenFailed` is configuration-class: neither of the two
    /// causes it cannot tell apart — a stopped herden, disabled stream-local
    /// forwarding — resolves without the user acting on the Host (ADR 0011).
    var isRetryable: Bool {
        switch self {
        // A rejection is retryable because herden's error codes are open-ended
        // and most of them describe a target that moved, not a broken setup.
        case .sshUnreachable, .timedOut, .cancelled, .channelFailed,
            .apiRejected:
            true
        case .authenticationFailed, .tcpForwardingUnavailable,
            .deviceKeyCorrupt, .hostKeyRejected, .hostKeyMismatch,
            .socketNotFound, .herdenBinaryNotFound, .protocolVersionMismatch,
            .streamLocalOpenFailed,
            .homeDirectoryUnresolvable, .eventsChannelAlreadyOpen,
            .terminalChannelAlreadyOpen, .malformedResponse:
            false
        // A Jump Host is retryable exactly when the failure behind it is: a
        // rebooting VPS should reconnect on its own, a rejected key should not.
        case .jumpHostFailed(let underlying):
            underlying.isRetryable
        }
    }
}

/// An error returned by the herden server inside a response envelope.
struct HerdrAPIError: Error, Sendable, Equatable {
    /// Normalized to a string; the wire schema promises `{"code","message"}`
    /// without pinning the code's JSON type.
    let code: String
    let message: String
}

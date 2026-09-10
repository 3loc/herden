import SwiftUI

/// The new-agent sheet (#12, User Story 8): pick a Host and a launch target
/// (an existing Workspace or a new one at a remote directory), type an
/// installed Agent and its native arguments, and dispatch it through the
/// Transport launch flow. On success the sheet dismisses and hands the
/// started Agent's identity to `onStarted`; the owner opens it, so a fresh
/// launch lands in its terminal instead of back on the list.
struct StartAgentView: View {
    @State private var store: StartAgentStore
    private let onStarted: (ConsoleAgent.ID) -> Void
    @State private var showsLocationOptions = false
    @Environment(\.dismiss) private var dismiss

    init(
        hosts: [Host], console: ConsoleStore,
        terminalColors: AgentLaunchTerminalColors? = nil,
        origin: StartAgentStore.LaunchOrigin? = nil,
        initialHostID: Host.ID? = nil,
        onStarted: @escaping (ConsoleAgent.ID) -> Void
    ) {
        self.onStarted = onStarted
        let store = StartAgentStore(
                hosts: hosts,
                workspaces: { console.workspaces(for: $0) },
                existingAgentNames: { hostID in
                    Set(
                        console.agents
                            .filter { $0.hostID == hostID }
                            .compactMap { $0.agent.name })
                },
                discoverAgentKinds: { try await console.availableAgentKinds(on: $0) },
                start: { params, destination, hostID in
                    switch destination {
                    case .existingWorkspace:
                        try await console.startAgent(params, on: hostID)
                    case .newWorktree(let worktree):
                        try await console.startAgentInNewWorktree(
                            params, worktree: worktree, on: hostID)
                    case .newWorkspace(let workspace):
                        try await console.startAgentInNewWorkspace(
                            params, workspace: workspace, on: hostID)
                    }
                },
                awaitAgentVisible: { await console.waitForAgent($0) },
                origin: origin,
                dedicatedWorkspaceByDefault: true,
                terminalColors: terminalColors)
        if origin == nil, let initialHostID, hosts.contains(where: { $0.id == initialHostID }) {
            store.selectedHostID = initialHostID
        }
        _store = State(initialValue: store)
    }

    var body: some View {
        NavigationStack {
            Form {
                if store.origin == nil {
                    Section("Host") {
                        Picker("Host", selection: $store.selectedHostID) {
                            if store.selectedHostID == nil {
                                Text("Select a Host").tag(Host.ID?.none)
                            }
                            ForEach(store.hosts) { host in
                                Text(host.pickerIdentity).tag(Host.ID?.some(host.id))
                            }
                        }
                    }
                }
                if store.launchTarget == .newWorkspace {
                    Section {
                        TextField(store.origin?.cwd ?? "Host home directory", text: $store.newWorkspaceDirectory)
                            .font(.callout.monospaced())
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    } header: {
                        Text("Directory")
                    } footer: {
                        Text("A Space is created automatically for this Agent. This does not create an isolated checkout.")
                    }
                }
                if store.origin == nil {
                    Section {
                        DisclosureGroup("Location options", isExpanded: $showsLocationOptions) {
                            Picker("Location", selection: $store.launchTarget) {
                                Text("New Space automatically").tag(StartAgentStore.LaunchTarget.newWorkspace)
                                Text("Reuse an existing Space").tag(StartAgentStore.LaunchTarget.existingWorkspace)
                            }
                            if store.launchTarget == .existingWorkspace {
                                Picker("Space", selection: $store.selectedWorkspaceID) {
                                    if store.workspaces.isEmpty {
                                        Text("None reported").tag(String?.none)
                                    }
                                    ForEach(store.workspaces) { workspace in
                                        Text(workspace.label).tag(String?.some(workspace.id))
                                    }
                                }
                                .disabled(store.selectedHostID == nil || store.workspaces.isEmpty)
                            }
                        }
                    }
                }

                if store.offersWorktree {
                    Section {
                        Toggle("Start in a new worktree", isOn: $store.startsInNewWorktree)
                            .disabled(store.selectedWorkspaceID == nil)
                        if store.startsInNewWorktree {
                            TextField("Branch (optional)", text: $store.worktreeBranch)
                                .font(.callout.monospaced())
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                            TextField("Base (optional)", text: $store.worktreeBase)
                                .font(.callout.monospaced())
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }
                    } header: {
                        Text("Worktree")
                    } footer: {
                        if let message = store.worktreeBranchErrorMessage {
                            Text(message)
                                .foregroundStyle(.red)
                        } else if store.startsInNewWorktree {
                            Text(
                                "A fresh checkout of the workspace's repository. Empty fields use a generated worktree/ branch off HEAD."
                            )
                        } else {
                            Text(
                                "Run the agent in a clean checkout instead of the workspace itself."
                            )
                        }
                    }
                }

                Section {
                    switch store.agentDiscoveryState {
                    case .idle:
                        Text("Select a Host to detect installed Agents.")
                            .foregroundStyle(.secondary)
                    case .loading:
                        HStack {
                            ProgressView()
                            Text("Detecting installed Agents…")
                        }
                    case .loaded where store.availableAgentKinds.isEmpty:
                        ContentUnavailableView(
                            "No Agents Found",
                            systemImage: "magnifyingglass",
                            description: Text(
                                "Install a supported Agent CLI on this Host, then try again."))
                        Button("Detect Again", systemImage: "arrow.clockwise") {
                            Task { await store.discoverAgents() }
                        }
                    case .loaded:
                        Picker("Agent", selection: $store.selectedAgentKind) {
                            ForEach(store.availableAgentKinds) { kind in
                                Text("\(kind.displayName) (\(kind.executable))")
                                    .tag(SupportedAgentKind?.some(kind))
                            }
                        }
                        Button("Detect Again", systemImage: "arrow.clockwise") {
                            Task { await store.discoverAgents() }
                        }
                    case .failed(let message):
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                        Button("Retry", systemImage: "arrow.clockwise") {
                            Task { await store.discoverAgents() }
                        }
                    }
                } header: {
                    Text("Agent")
                } footer: {
                    Text("Agents installed and launchable from this Host's PATH.")
                }

                Section {
                    TextField(store.defaultAgentName ?? "e.g. reviewer", text: $store.name)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("Agent Name")
                } footer: {
                    if let message = store.nameErrorMessage {
                        Text(message)
                            .foregroundStyle(.red)
                    } else if let defaultName = store.defaultAgentName {
                        Text("Optional. Empty names the agent \(Text(defaultName).monospaced()).")
                    } else {
                        Text("Optional. Empty names the agent after its kind.")
                    }
                }

                Section {
                    AgentArgumentsField(
                        text: $store.arguments,
                        placeholder: #"e.g. --model "gpt 5" --continue"#)
                } header: {
                    Text("Arguments")
                } footer: {
                    if let message = store.argumentErrorMessage {
                        Text(message)
                            .foregroundStyle(.red)
                    } else {
                        Text("Optional. Quotes and backslash escapes are supported.")
                    }
                }

                if case .failed(let message) = store.state {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("New Agent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(!store.canDismiss)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if store.state == .starting {
                        ProgressView()
                    } else {
                        Button("Start") {
                            Task { await store.submit() }
                        }
                        .disabled(!store.canSubmit)
                    }
                }
            }
            .onChange(of: store.state) {
                if case .started(let id) = store.state {
                    StartAgentPresentationTransition.finish(
                        id: id,
                        onStarted: onStarted,
                        dismiss: { dismiss() })
                }
            }
            .task(id: store.selectedHostID) {
                await store.discoverAgents()
            }
            .interactiveDismissDisabled(!store.canDismiss)
        }
    }
}

/// Keeps the successful-launch handoff outside SwiftUI's sheet teardown.
///
/// The owner must receive the Agent ID before dismissal begins: `onDismiss`
/// may run synchronously enough to otherwise observe no pending destination.
/// Opening the terminal is then deferred one main-actor turn so its UIKit
/// surface is not created while the modal presentation is still unwinding.
@MainActor
enum StartAgentPresentationTransition {
    static func finish(
        id: ConsoleAgent.ID,
        onStarted: (ConsoleAgent.ID) -> Void,
        dismiss: () -> Void
    ) {
        onStarted(id)
        dismiss()
    }

    static func openAfterDismissal(
        id: ConsoleAgent.ID,
        open: @escaping @MainActor (ConsoleAgent.ID) -> Void
    ) {
        Task { @MainActor in
            await Task.yield()
            open(id)
        }
    }
}

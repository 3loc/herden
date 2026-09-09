import SwiftUI

/// The picker for Spaces and Agents. One stable list, with creation and Host
/// management in the toolbar; sessions remain a horizontal gesture away.
struct ConsoleView: View {
    let hosts: HostStore
    let console: ConsoleStore
    let terminal: TerminalSettings
    let inputMode: AgentInputModeSettings
    let appearance: AppAppearanceSettings
    let pushRegistration: PushRegistrationStore
    let notificationPreferences: NotificationPreferencesStore
    let relaySettings: NotificationRelaySettings
    /// Owns the navigation path (#74): user taps and notification deep links
    /// drive the same stack.
    @Bindable var notificationRouter: AgentNotificationRouter
    /// Announces foreground Blocked/Done transitions in-app (#77).
    let bannerStore: AgentNotificationBannerStore
    /// Per-Host Live Activity start/update/end and the Settings toggle.
    let liveActivities: HostLiveActivityCoordinator
    /// Scene phase widened by the background grace period; an Attach screen
    /// pauses its work on real suspensions only.
    let activity: AppActivityCoordinator
    @State private var hostSheet: HostSheet?
    @State private var isCreatingSpace = false
    @State private var newSpaceHostID: Host.ID?
    @State private var createsSpaceAfterHostSheetCloses = false
    @State private var isStartingAgent = false
    @State private var isShowingSettings = false
    @State private var isBrowsingSpaces = false
    @State private var spaceAfterBrowserDismissal: ConsoleSpace?
    @State private var createsTerminalAfterBrowserDismissal = false
    @State private var startedAgentAfterDismissal: ConsoleAgent.ID?
    @State private var selectedSpace: ConsoleSpace?
    @State private var openedSpace: OpenedSpace?
    @State private var openingSpaceID: ConsoleSpace.ID?
    @State private var spaceOpenFailureMessage: String?
    @State private var isClosingOpenedSpace = false
    @State private var spaceCloseFailureMessage: String?
    /// Hosts whose Host-detail Reconnect request is in flight, including the
    /// 1.2 s visual-feedback hold after `retryHost` returns. Distinct from
    /// `EventsSessionStatus.reconnecting`.
    @State private var manualReconnectInFlightHostIDs: Set<Host.ID> = []
    /// Outlives the detail column's rebuilds, which is the whole point: it
    /// carries the raised keyboard from one Attach screen to the next.
    @State private var keyboardHandoff = TerminalKeyboardHandoff()
    /// Outlives those rebuilds for the same reason. A per-screen inset starts
    /// every switch at zero and only learns the keyboard's height once UIKit
    /// posts the next frame notification, so the terminal that inherits a
    /// raised keyboard would lay out full height first and shrink a moment
    /// later — an extra reflow, and a Connecting dialog that visibly jumps
    /// from the middle of the screen to the middle of the terminal.
    @State private var keyboardInset = TerminalKeyboardInset()
    /// Remember the most recent session so a left swipe anywhere in the picker
    /// can return to it. Only one of the two IDs is set at a time.
    @State private var lastOpenedAgentID: ConsoleAgent.ID?
    @State private var lastOpenedSpaceID: ConsoleSpace.ID?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        // A split view instead of a plain stack for the iPad's sake: regular
        // width shows the Agent list beside the Attach terminal; compact
        // width collapses into the familiar push navigation. The router's
        // path stays the single source of truth — the sidebar selection is a
        // projection of it, so notification deep links keep working.
        NavigationSplitView {
            content
                .modifier(ConsoleSwipeNavigationModifier(
                    direction: .session, isEnabled: horizontalSizeClass == .compact,
                    navigate: reopenLastSession))
                .accessibilityAction(named: "Return to session", reopenLastSession)
                .navigationTitle("Herden")
                .navigationBarTitleDisplayMode(.inline)
                .navigationSplitViewColumnWidth(min: 320, ideal: 380)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        HStack(spacing: 8) {
                            HerdenMark(size: 30)
                            Text("Herden.")
                                .font(Brand.display(.title3))
                                .foregroundStyle(Brand.ink)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Menu("Settings", systemImage: "ellipsis.circle") {
                            Button("Spaces & Terminals", systemImage: "apple.terminal") { isBrowsingSpaces = true }
                            Button("Hosts", systemImage: "server.rack") { presentHosts() }
                            Button("Settings", systemImage: "gearshape") { isShowingSettings = true }
                        }
                    }
                    if !hosts.hosts.isEmpty {
                        ToolbarItem(placement: .primaryAction) {
                            Button("New Agent", systemImage: "plus") {
                                newSpaceHostID = nil
                                isStartingAgent = true
                            }
                        }
                    }
                }
                .sheet(item: $hostSheet, onDismiss: {
                    guard createsSpaceAfterHostSheetCloses else { return }
                    createsSpaceAfterHostSheetCloses = false
                    isStartingAgent = true
                }) { destination in
                    // HostListView brings its own NavigationStack.
                    HostListView(
                        store: hosts,
                        initialHostID: destination.hostID,
                        connectionStatuses: console.hostStatuses,
                        standingFailures: console.hostStandingFailures,
                        latencies: console.hostLatencies,
                        manualReconnectInFlightHostIDs: manualReconnectInFlightHostIDs,
                        retryConnection: { await reconnectHost($0) },
                        onHostAdded: { hostID in
                            newSpaceHostID = hostID
                            createsSpaceAfterHostSheetCloses = true
                            hostSheet = nil
                        })
                }
                .sheet(isPresented: $isStartingAgent, onDismiss: {
                    guard let id = startedAgentAfterDismissal else { return }
                    startedAgentAfterDismissal = nil
                    notificationRouter.path = [id]
                }) {
                    // StartAgentView brings its own NavigationStack.
                    StartAgentView(hosts: hosts.hosts, console: console, initialHostID: newSpaceHostID) { id in
                        // A fresh launch lands in its own terminal, exactly
                        // as tapping the new row would.
                        startedAgentAfterDismissal = id
                    }
                }
                .sheet(isPresented: $isCreatingSpace, onDismiss: {
                    newSpaceHostID = nil
                }) {
                    NewSpaceView(
                        hosts: hosts.hosts,
                        selectedHostID: newSpaceHostID,
                        console: console
                    ) { hostID, created in
                        console.rememberShellTerminal(
                            created.terminal,
                            forWorkspaceID: created.workspaceID,
                            on: hostID)
                        Task { @MainActor in
                            await Task.yield()
                            openedSpace = makeOpenedSpace(
                                hostID: hostID,
                                workspaceID: created.workspaceID,
                                label: created.label,
                                terminalIdentity: created.terminal)
                            lastOpenedSpaceID = ConsoleSpace.ID(
                                hostID: hostID, workspaceID: created.workspaceID)
                            lastOpenedAgentID = nil
                        }
                    }
                }
                .sheet(isPresented: $isShowingSettings) {
                    SettingsView(
                        terminal: terminal,
                        appearance: appearance,
                        pushRegistration: pushRegistration,
                        notificationPreferences: notificationPreferences,
                        relaySettings: relaySettings,
                        liveActivities: liveActivities)
                }
                .sheet(item: $selectedSpace) { space in
                    spaceDetail(space)
                }
                .sheet(isPresented: $isBrowsingSpaces, onDismiss: {
                    if let space = spaceAfterBrowserDismissal {
                        spaceAfterBrowserDismissal = nil
                        openSpace(space)
                    } else if createsTerminalAfterBrowserDismissal {
                        createsTerminalAfterBrowserDismissal = false
                        isCreatingSpace = true
                    }
                }) {
                    NavigationStack {
                        List {
                            ForEach(filteredSpaces) { space in
                                spaceRow(space)
                            }
                            Button("New Terminal", systemImage: "plus") {
                                createsTerminalAfterBrowserDismissal = true
                                isBrowsingSpaces = false
                                newSpaceHostID = nil
                            }
                        }
                        .scrollContentBackground(.hidden)
                        .background(Brand.background)
                        .navigationTitle("Spaces & Terminals")
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { isBrowsingSpaces = false }
                            }
                        }
                    }
                    .preferredColorScheme(.dark)
                }
                .fullScreenCover(item: $openedSpace) { opened in
                    NavigationStack {
                        ShellTerminalView(
                            store: opened.terminal,
                            terminal: terminal,
                            activity: activity,
                            isReturning: false,
                            title: opened.label,
                            backLabel: "Back to Agents",
                            isClosingTerminal: isClosingOpenedSpace,
                            onCloseTerminal: { closeOpenedSpace(opened) },
                            closeActionTitle: "Close Space",
                            closeConfirmationTitle: "Close \(opened.label)?",
                            closeConfirmationMessage:
                                "This closes the Space on the Host, ending every Agent and "
                                + "terminal inside it. This can't be undone.",
                            stageImage: console.imageStager(for: opened.hostID),
                            stageFile: console.fileStager(for: opened.hostID)
                        ) {
                            openedSpace = nil
                        }
                    }
                }
                .alert(
                    "Could Not Open Space",
                    isPresented: Binding(
                        get: { spaceOpenFailureMessage != nil },
                        set: { if !$0 { spaceOpenFailureMessage = nil } })
                ) {
                    Button("OK", role: .cancel) { spaceOpenFailureMessage = nil }
                } message: {
                    Text(spaceOpenFailureMessage ?? "")
                }
                .alert(
                    "Could Not Close Space",
                    isPresented: Binding(
                        get: { spaceCloseFailureMessage != nil },
                        set: { if !$0 { spaceCloseFailureMessage = nil } })
                ) {
                    Button("OK", role: .cancel) { spaceCloseFailureMessage = nil }
                } message: {
                    Text(spaceCloseFailureMessage ?? "")
                }
        } detail: {
            detail
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            SharedTransfersView { record in
                notificationRouter.open(AgentNotificationTarget(
                    hostID: record.host.id, paneID: record.paneID))
            }
        }
        .background(Brand.background.ignoresSafeArea())
        .modifier(
            ConsoleStatusBarModifier(
                scheme: terminalStatusBarColorScheme
            )
        )
        // Above the NavigationStack so a banner also shows over a pushed
        // Agent detail; a tap deep-links exactly like a push tap would.
        .overlay(alignment: .top) {
            if let banner = bannerStore.banner {
                AgentNotificationBannerView(banner: banner) {
                    bannerStore.dismiss()
                    notificationRouter.open(banner.target)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: bannerStore.banner)
        // A notification deep link must land on Agent detail even when one of
        // the Console's sheets covers it. The only other push a sheet can
        // cause is the new-agent flow's, which dismisses itself first, so
        // clearing here is a no-op for it.
        .onChange(of: notificationRouter.path) { _, path in
            if let opened = path.last {
                lastOpenedAgentID = opened
                lastOpenedSpaceID = nil
                openedSpace = nil
            }
            guard !path.isEmpty else { return }
            hostSheet = nil
            isStartingAgent = false
            isCreatingSpace = false
            isShowingSettings = false
            selectedSpace = nil
        }
    }

    /// The sidebar selection as a projection of the router's path. Setting
    /// it (a row tap, or the collapsed stack popping) writes the path back,
    /// so user navigation and deep links keep one source of truth.
    private var selectedAgent: Binding<ConsoleAgent.ID?> {
        Binding(
            get: { notificationRouter.path.last },
            set: { notificationRouter.path = $0.map { [$0] } ?? [] })
    }

    /// The split view owns the window's status-bar appearance on iPhone. A
    /// pushed terminal cannot reliably override it from the detail subtree.
    private var terminalStatusBarColorScheme: ColorScheme? {
        guard let id = notificationRouter.path.last else { return nil }
        let showsTerminalSurface = console.agents.contains(where: { $0.id == id })
        let showsTerminalSyncSurface = !showsTerminalSurface
            && MissingAgentPresentation(agentID: id, console: console, hosts: hosts)
                .renderingMode == .progress
        guard showsTerminalSurface || showsTerminalSyncSurface else { return nil }
        return terminal.themes.selection(for: colorScheme)
            .chromeColorScheme(for: colorScheme)
    }

    /// The detail column. Not keyed off the live Agent list alone: the
    /// selection must survive the list emptying while an Agent is shown
    /// (a reconnect empties it briefly), so a vanished Agent shows a
    /// placeholder instead of clearing the selection.
    @ViewBuilder
    private var detail: some View {
        if let id = notificationRouter.path.last {
            if let receipt = matchingRemovedWorktreeReceipt(for: id) {
                removedWorktreeSurface(receipt)
            } else if let agent = console.agents.first(where: { $0.id == id }) {
                AgentDetailView(
                    agent: agent,
                    console: console,
                    terminal: terminal,
                    inputMode: inputMode,
                    hosts: hosts.hosts,
                    activity: activity,
                    keyboardHandoff: keyboardHandoff,
                    keyboardInset: keyboardInset,
                    // The router's truth, not SwiftUI's appear/disappear:
                    // only the screen still selected may rebuild its
                    // terminal on a spurious reappearance.
                    isOnStage: { [notificationRouter] in
                        notificationRouter.path.last == id
                            && console.agents.contains(where: { $0.id == id })
                    },
                    onSwitch: { notificationRouter.path = [$0] },
                    onClosed: { notificationRouter.path = [] }
                )
                // Selecting another Agent must tear down the previous terminal
                // pipeline; without the explicit identity the detail column
                // would reuse the old view's state.
                .id(id)
            } else {
                // The Agent is gone from the list, but not necessarily
                // because its pane went: a failed Host empties the list the
                // same way, and blaming the Agent for that hides the only
                // text that says what to do about it (#146).
                // The stores, not their contents: which collections this reads
                // is the part a test can then assert, and the part #146 got
                // wrong.
                let presentation = MissingAgentPresentation(
                    agentID: id, console: console, hosts: hosts)
                missingAgentSurface(presentation)
            }
        } else {
            ContentUnavailableView(
                "Nothing Open", systemImage: "rectangle.on.rectangle",
                description: Text("Choose an Agent to open its terminal."))
        }
    }

    /// A receipt is keyed by the Agent set captured at the authorized write.
    /// If the same pane id has already returned, require the live row to match
    /// the exact removed workspace/worktree identity before showing it.
    private func matchingRemovedWorktreeReceipt(
        for id: ConsoleAgent.ID
    ) -> WorktreeRemovalReceipt? {
        RemovedWorktreeSelection.receipt(
            for: id,
            agents: console.agents,
            receipts: console.removedWorktreesByAgent)
    }

    private func removedWorktreeSurface(
        _ receipt: WorktreeRemovalReceipt
    ) -> some View {
        ContentUnavailableView {
            Label("Worktree Removed", systemImage: "checkmark.circle")
        } description: {
            Text(
                "The checkout at \(receipt.request.identity.checkoutPath) was removed and its workspace was closed. No branch was deleted."
            )
        } actions: {
            Button("Back to Console") { notificationRouter.path = [] }
                .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private func missingAgentSurface(_ presentation: MissingAgentPresentation) -> some View {
        if presentation.renderingMode == .progress {
            let theme = terminal.themes.selection(for: colorScheme)
            ZStack {
                theme.surfaceBackground(for: colorScheme)
                    .ignoresSafeArea()
                TerminalStatusDialog(
                    glyph: .progress,
                    title: presentation.title,
                    message: presentation.message,
                    palette: theme.palette(for: colorScheme),
                    dimsBackground: false)
            }
        } else {
            ContentUnavailableView(
                presentation.title, systemImage: presentation.systemImage,
                description: Text(presentation.message))
        }
    }

    @ViewBuilder
    private var content: some View {
        switch agentsSurface {
        case .noHosts:
            ContentUnavailableView {
                Label("No Hosts", systemImage: "server.rack")
            } description: {
                Text("Add a machine that runs herden to create a Space.")
            } actions: {
                Button("Add Host") { presentHosts() }
                    .buttonStyle(.borderedProminent)
            }
        case .noAgents:
            ContentUnavailableView {
                VStack(spacing: 12) {
                    Image("HerdenFieldsAndSheep")
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(maxWidth: 260, maxHeight: 260)
                        .clipShape(.rect(cornerRadius: 22))
                        .accessibilityHidden(true)
                    Label("No Agents", systemImage: "plus.bubble")
                }
            } description: {
                Text("Start an Agent. Its Space is created automatically.")
            } actions: {
                Button("New Agent", systemImage: "plus") {
                    newSpaceHostID = nil
                    isStartingAgent = true
                }
                .buttonStyle(.borderedProminent)
                .tint(Brand.vine)
            }
        case .rows:
            List(selection: selectedAgent) {
                Section {
                    flatAgentListRows
                } header: {
                    consoleSectionLabel("Agents")
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Brand.background)
        }
    }

    @ViewBuilder
    private var flatAgentListRows: some View {
        ForEach(hostIssues) { issue in
            if issue.navigates {
                Button { presentHosts(issue.hostID) } label: {
                    hostIssueRow(issue, showsChevron: true)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens this Host's settings.")
            } else {
                hostIssueRow(issue, showsChevron: false)
            }
        }
        ForEach(console.agents) { agent in
            agentRow(agent)
        }
        if console.agents.isEmpty && hostIssues.isEmpty {
            Text("No Agents")
                .font(Brand.sans(.subheadline))
                .foregroundStyle(Brand.muted)
                .listRowBackground(Brand.elevated)
        }
    }

    private func agentRow(_ agent: ConsoleAgent) -> some View {
        NavigationLink(value: agent.id) {
            AgentCardView(
                agent: agent,
                isPinned: console.pins.isPinned(
                    hostID: agent.hostID, paneID: agent.agent.paneID))
        }
        .contextMenu {
            let pinned = console.pins.isPinned(
                hostID: agent.hostID, paneID: agent.agent.paneID)
            Button(
                pinned ? "Unpin" : "Pin",
                systemImage: pinned ? "pin.slash" : "pin"
            ) {
                console.togglePin(
                    hostID: agent.hostID, paneID: agent.agent.paneID)
            }
        }
        .listRowBackground(Brand.elevated)
    }

    private func spaceRow(_ space: ConsoleSpace) -> some View {
        Button {
            if isBrowsingSpaces {
                spaceAfterBrowserDismissal = space
                isBrowsingSpaces = false
            } else {
                openSpace(space)
            }
        } label: {
            HStack(spacing: 12) {
                HerdenSpaceMark(size: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text(space.workspace.label)
                        .font(Brand.sans(.headline, weight: .semibold))
                        .foregroundStyle(Brand.ink)
                        .lineLimit(1)
                    Text(space.hostName)
                        .font(Brand.mono(.caption2))
                        .foregroundStyle(Brand.subtle)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if space.agentCount > 0 {
                    Text("\(space.agentCount) \(space.agentCount == 1 ? "Agent" : "Agents")")
                        .font(Brand.mono(.caption2, weight: .semibold))
                        .foregroundStyle(Brand.vine)
                }
                if openingSpaceID == space.id {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Brand.vine)
                } else {
                    Image(systemName: "apple.terminal")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Brand.subtle)
                }
            }
            .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .listRowBackground(Brand.card)
        .accessibilityElement(children: .combine)
        .disabled(openingSpaceID != nil)
        .accessibilityHint("Opens the first Agent, or the first terminal in this Space")
    }

    private func openSpace(_ space: ConsoleSpace) {
        guard openingSpaceID == nil else { return }
        isBrowsingSpaces = false
        openingSpaceID = space.id
        Task { @MainActor in
            defer { openingSpaceID = nil }
            do {
                let identity: ShellTerminalIdentity
                switch try await console.existingSpaceDestination(
                    workspaceID: space.workspace.id, on: space.hostID)
                {
                case .agent(let paneID):
                    let id = ConsoleAgent.ID(hostID: space.hostID, paneID: paneID)
                    lastOpenedAgentID = id
                    lastOpenedSpaceID = space.id
                    notificationRouter.path = [id]
                    return
                case .terminal(let existing):
                    identity = existing
                case nil:
                    guard let cwd = space.workspace.cwd else {
                        selectedSpace = space
                        return
                    }
                    identity = try await console.createShellTerminal(
                        ShellTerminalCreationRequest(
                            workspaceID: space.workspace.id,
                            cwd: cwd),
                        on: space.hostID)
                }
                console.rememberShellTerminal(
                    identity, forWorkspaceID: space.workspace.id, on: space.hostID)
                openedSpace = makeOpenedSpace(
                    hostID: space.hostID,
                    workspaceID: space.workspace.id,
                    label: space.workspace.label,
                    terminalIdentity: identity)
                lastOpenedSpaceID = space.id
                lastOpenedAgentID = nil
                notificationRouter.path = []
            } catch {
                spaceOpenFailureMessage = Self.spaceOpenMessage(for: error)
            }
        }
    }

    private func makeOpenedSpace(
        hostID: Host.ID,
        workspaceID: String,
        label: String,
        terminalIdentity: ShellTerminalIdentity
    ) -> OpenedSpace {
        OpenedSpace(
            hostID: hostID,
            workspaceID: workspaceID,
            label: label,
            terminal: ShellTerminalStore(
                identity: terminalIdentity,
                transportGeneration: console.hostConnectionGenerations[hostID],
                isOnStage: { true },
                runTerminal: console.terminalRunner(for: hostID)))
    }

    private func closeOpenedSpace(_ opened: OpenedSpace) {
        guard !isClosingOpenedSpace else { return }
        isClosingOpenedSpace = true
        spaceCloseFailureMessage = nil
        Task { @MainActor in
            defer { isClosingOpenedSpace = false }
            do {
                try await console.closeWorkspace(
                    opened.workspaceID, on: opened.hostID)
            } catch {
                spaceCloseFailureMessage = Self.spaceCloseMessage(for: error)
                return
            }
            await opened.terminal.leave().value
            console.forgetShellTerminal(
                forWorkspaceID: opened.workspaceID, on: opened.hostID)
            if openedSpace?.id == opened.id {
                openedSpace = nil
            }
        }
    }

    private func reopenLastSession() {
        if let id = lastOpenedAgentID, console.agents.contains(where: { $0.id == id }) {
            notificationRouter.path = [id]
        } else if let id = lastOpenedSpaceID,
                  let space = ConsoleSpace.project(
                    hosts: hosts.hosts, workspacesByHost: console.workspacesByHost,
                    agents: console.agents, filteredHostID: nil).first(where: { $0.id == id }) {
            openSpace(space)
        }
    }

    private static func spaceOpenMessage(for error: any Error) -> String {
        switch error {
        case TransportError.sshUnreachable:
            "The Host is not connected."
        case TransportError.timedOut:
            "The Host did not answer in time."
        case let api as HerdrAPIError:
            "herden could not open the Space: \(api.message)"
        case TransportError.apiRejected(_, let message):
            "herden could not open the Space: \(message)"
        default:
            "Opening the Space failed: \(error)"
        }
    }

    private static func spaceCloseMessage(for error: any Error) -> String {
        switch error {
        case TransportError.sshUnreachable:
            "The Host is not connected. The Space is still open there."
        case TransportError.timedOut:
            "The Host did not answer in time. The Space may still be open there."
        case let api as HerdrAPIError:
            "herden could not close the Space: \(api.message)"
        case TransportError.apiRejected(_, let message):
            "herden could not close the Space: \(message)"
        default:
            "Closing the Space failed: \(error)"
        }
    }

    private func spaceDetail(_ space: ConsoleSpace) -> some View {
        let agents = console.agents.filter {
            $0.hostID == space.hostID && $0.agent.workspaceID == space.workspace.id
        }
        return NavigationStack {
            Group {
                if agents.isEmpty {
                    ContentUnavailableView {
                        Label("No Agents", systemImage: "rectangle.on.rectangle.slash")
                    } description: {
                        Text("Start an Agent in \(space.workspace.label).")
                    } actions: {
                        Button("New Agent", systemImage: "plus") {
                            selectedSpace = nil
                            Task { @MainActor in
                                await Task.yield()
                                isStartingAgent = true
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Brand.vine)
                    }
                } else {
                    List(agents) { agent in
                        Button {
                            selectedSpace = nil
                            notificationRouter.path = [agent.id]
                        } label: {
                            AgentCardView(
                                agent: agent,
                                isPinned: console.pins.isPinned(
                                    hostID: agent.hostID, paneID: agent.agent.paneID))
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Brand.elevated)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Brand.background.ignoresSafeArea())
            .navigationTitle(space.workspace.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { selectedSpace = nil }
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(Brand.vine)
    }

    private func consoleSectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(Brand.mono(.caption2, weight: .semibold))
            .tracking(1.8)
            .foregroundStyle(Brand.vine)
    }

    private var agentsSurface: ConsoleAgentsSurface {
        ConsoleAgentsSurface(
            hostCount: hosts.hosts.count,
            agentCount: console.agents.count,
            filteredSpaceCount: 0,
            visibleIssueCount: hostIssues.count,
            presentationMode: .flat,
            projectedSectionCount: 0)
    }

    private var filteredSpaces: [ConsoleSpace] {
        ConsoleSpace.project(
            hosts: hosts.hosts,
            workspacesByHost: console.workspacesByHost,
            agents: console.agents)
    }

    private struct HostSheet: Identifiable {
        let id = UUID()
        let hostID: Host.ID?
    }

    /// One actionable status per Host. A disconnected session takes priority;
    /// otherwise a connected Host can still have a failing snapshot RPC.
    private var hostIssues: [ConsoleHostStatusPresentation] {
        hosts.hosts.compactMap { host in
            ConsoleHostStatusPresentation(
                host: host,
                status: console.hostStatuses[host.id],
                standingFailure: console.hostStandingFailures[host.id],
                isAwaitingSnapshot: console.hostsAwaitingSnapshot.contains(host.id),
                syncError: console.hostSyncErrors[host.id])
        }
    }

    private func hostIssueRow(
        _ issue: ConsoleHostStatusPresentation, showsChevron: Bool
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: issue.systemImage)
                .foregroundStyle(hostIssueTint(issue))
            Text(issue.message)
                .font(.footnote)
                .foregroundStyle(issue.isCritical ? Color.red : Color.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func hostIssueTint(_ issue: ConsoleHostStatusPresentation) -> Color {
        switch issue.severity {
        case .critical: .red
        case .warning: .orange
        case .informational: .secondary
        }
    }

    private func presentHosts(_ id: Host.ID? = nil) {
        hostSheet = HostSheet(hostID: id)
    }

    private func reconnectHost(_ id: Host.ID) async {
        guard manualReconnectInFlightHostIDs.insert(id).inserted else { return }
        await console.retryHost(id)
        try? await Task.sleep(for: .milliseconds(1_200))
        manualReconnectInFlightHostIDs.remove(id)
    }
}

enum ConsoleHorizontalNavigation {
    private static let requiredHorizontalDistance: CGFloat = 70
    private static let maximumVerticalDistance: CGFloat = 60

    static func returnsToPicker(translation: CGSize) -> Bool {
        translation.width > requiredHorizontalDistance
            && abs(translation.height) < maximumVerticalDistance
    }

    static func opensLastAgent(translation: CGSize) -> Bool {
        translation.width < -requiredHorizontalDistance
            && abs(translation.height) < maximumVerticalDistance
    }
}

/// The picker listens across its full content width. Terminals arbitrate their
/// own native gestures so prompt editing cannot trigger screen navigation.
struct ConsoleSwipeNavigationModifier: ViewModifier {
    enum Direction { case picker, session }
    let direction: Direction
    var isEnabled = true
    let navigate: () -> Void

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    guard isEnabled else { return }
                    let shouldNavigate = switch direction {
                    case .picker:
                        ConsoleHorizontalNavigation.returnsToPicker(translation: value.translation)
                    case .session:
                        ConsoleHorizontalNavigation.opensLastAgent(translation: value.translation)
                    }
                    if shouldNavigate { navigate() }
                })
    }
}

private struct ConsoleStatusBarModifier: ViewModifier {
    let scheme: ColorScheme?

    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) {
            content
                .toolbarVisibility(.visible, for: .statusBar)
                .toolbarColorScheme(scheme, for: .statusBar)
        } else {
            content
                .toolbarColorScheme(scheme, for: .navigationBar)
        }
        #else
        content
            .toolbarColorScheme(scheme, for: .navigationBar)
        #endif
    }
}

/// What the detail column shows when the selected Agent is no longer in the
/// Console list. Six conditions empty that list and they need six answers
/// (#141, #146, #154, #155).
///
/// Read Host Connection Status first, then Standing Failure, then the Agent
/// Inventory. A Standing Failure changes only what `.connecting` looks like.
/// The inventory is consulted only under `.connected`.
struct MissingAgentPresentation: Equatable {
    /// Which situation emptied the list. Explicit so that collapsing them
    /// into a single message cannot happen by accident.
    enum Cause: Hashable {
        case hostSuspended
        case hostConnecting
        case hostReconnecting
        /// A stopped Host, or a `.connecting` Host that still carries a
        /// Standing Failure.
        case hostFailed
        /// The Host is Connected, but its first snapshot for this connection
        /// has not landed yet.
        case hostLoadingAgents
        case paneGone
    }

    enum RenderingMode: Equatable {
        case progress
        case staticUnavailable
    }

    let cause: Cause
    let title: String
    let systemImage: String
    let message: String

    var renderingMode: RenderingMode {
        switch cause {
        case .hostConnecting, .hostReconnecting, .hostLoadingAgents:
            .progress
        case .hostSuspended, .hostFailed, .paneGone:
            .staticUnavailable
        }
    }

    /// Resolves the Host from the selection rather than taking a status the
    /// caller looked up: the pane address alone is not unique across Hosts,
    /// so `ConsoleAgent.ID` carries the `hostID`, and keeping the resolution
    /// here means no call site can apply a *different* rule to it.
    ///
    /// This initializer takes the *contents* and so cannot police where they
    /// came from — passing an empty `hostStatuses` restores #146's defect
    /// outright, since every failed Host then falls back to the placeholder.
    /// The detail column therefore does not call it; it calls the store-taking
    /// initializer below, which is the one under test (#152).
    init(
        agentID: ConsoleAgent.ID,
        hostStatuses: [Host.ID: EventsSessionStatus],
        hosts: [Host],
        hostsAwaitingSnapshot: Set<Host.ID> = [],
        hostStandingFailures: [Host.ID: TransportError] = [:]
    ) {
        let hostName = hosts.first { $0.id == agentID.hostID }?.displayName
        func named(_ text: String) -> String {
            hostName.map { "\($0): \(text)" } ?? text
        }
        func applyFailed(_ failure: TransportError) -> (
            Cause, String, String, String
        ) {
            (
                .hostFailed,
                "Host Unavailable",
                failure.isHostKeySecurityFailure
                    ? "exclamationmark.shield.fill" : "exclamationmark.triangle.fill",
                named(failure.presentation.message)
            )
        }
        let hostStatus = hostStatuses[agentID.hostID]
        let standingFailure = hostStandingFailures[agentID.hostID]
        switch hostStatus {
        case .suspended:
            cause = .hostSuspended
            title = "Connection Paused"
            systemImage = "pause.circle"
            message = named("The connection is paused until Herden becomes active.")
        case .connecting:
            if let standingFailure {
                (cause, title, systemImage, message) = applyFailed(standingFailure)
            } else {
                cause = .hostConnecting
                title = "Connecting…"
                systemImage = "dot.radiowaves.left.and.right"
                message = named("Opening the connection.")
            }
        case .reconnecting(_, _, let failure):
            cause = .hostReconnecting
            title = "Reconnecting…"
            systemImage = "arrow.trianglehead.2.clockwise"
            message = named(failure.presentation.summary)
        case .failed(let failure):
            (cause, title, systemImage, message) = applyFailed(failure)
        case .connected:
            if hostsAwaitingSnapshot.contains(agentID.hostID) {
                cause = .hostLoadingAgents
                title = "Loading Agents…"
                systemImage = "hourglass"
                message = named("Fetching the latest Agents.")
            } else {
                cause = .paneGone
                title = "Agent Gone"
                systemImage = "rectangle.on.rectangle.slash"
                message = "This Agent's pane is no longer reported."
            }
        case .ended, nil:
            cause = .paneGone
            title = "Agent Gone"
            systemImage = "rectangle.on.rectangle.slash"
            message = "This Agent's pane is no longer reported."
        }
    }

    /// What the Console's detail column shows when the selected Agent is not
    /// in the list.
    ///
    /// This exists to be called from a test, and deleting it would cost real
    /// coverage rather than tidy up an unused overload. The defect it guards
    /// (#146) is *which collections the view reads*, not what the rule does
    /// with them, and that could not be reached: a hosted `NavigationSplitView`
    /// builds its columns and navigation bar but never the SwiftUI content
    /// inside them, so the detail column cannot be rendered in a test and
    /// asserted against (measured under #152).
    ///
    /// Taking the stores instead of their contents is what makes the seam
    /// worth having. The reader is now written once, here, where a test calls
    /// exactly what the view calls — rather than at a call site that no test
    /// can reach.
    @MainActor
    init(agentID: ConsoleAgent.ID, console: ConsoleStore, hosts: HostStore) {
        self.init(
            agentID: agentID,
            hostStatuses: console.hostStatuses,
            hosts: hosts.hosts,
            hostsAwaitingSnapshot: console.hostsAwaitingSnapshot,
            hostStandingFailures: console.hostStandingFailures)
    }
}

/// Collapsible Host-section header for the grouped Console list (#245).
private struct ConsoleHostSectionHeaderView: View {
    let presentation: ConsoleHostSectionHeaderPresentation
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 8) {
                Image(systemName: presentation.disclosureSystemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12, alignment: .center)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(presentation.hostDisplayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(presentation.readinessText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if presentation.showsStatusPills {
                    ConsoleHostStatusCountPills(items: presentation.statusItems)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
        .accessibilityValue(presentation.accessibilityValue)
        .accessibilityHint(presentation.accessibilityHint)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Mirrors the Live Activity count chips so a collapsed Host communicates
/// the same status distribution at a glance.
private struct ConsoleHostStatusCountPills: View {
    let items: [ConsoleHostAgentStatusCount]

    var body: some View {
        HStack(spacing: 5) {
            ForEach(items) { item in
                Text("\(item.count) \(item.status.rawValue)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color(item.status.inkUIColor))
                    .fixedSize()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Color(item.status.tintUIColor).opacity(0.15),
                        in: Capsule())
            }
        }
    }
}

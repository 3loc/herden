import Foundation
import Observation
import SwiftUI

struct OpenedSpace: Identifiable {
    let id = UUID()
    let hostID: Host.ID
    let workspaceID: String
    let label: String
    let terminal: ShellTerminalStore
}

@MainActor
@Observable
final class NewSpaceStore {
    enum State: Equatable {
        case editing
        case creating
        case failed(String)
        case created
    }

    let hosts: [Host]
    var selectedHostID: Host.ID?
    var directory = ""
    var label = ""
    private(set) var state: State = .editing

    @ObservationIgnored
    private let create: (SpaceCreationRequest, Host.ID) async throws -> CreatedSpace

    init(
        hosts: [Host],
        selectedHostID: Host.ID? = nil,
        create: @escaping (SpaceCreationRequest, Host.ID) async throws -> CreatedSpace
    ) {
        self.hosts = hosts
        self.selectedHostID = selectedHostID ?? (hosts.count == 1 ? hosts.first?.id : nil)
        self.create = create
    }

    var directoryErrorMessage: String? {
        let path = directory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        return path.hasPrefix("/") ? nil : "Enter an absolute path on the Host."
    }

    var canSubmit: Bool {
        guard state != .creating, selectedHostID != nil else { return false }
        let path = directory.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty || (path.hasPrefix("/") && directoryErrorMessage == nil)
    }

    var canDismiss: Bool { state != .creating }

    func submit() async -> (Host.ID, CreatedSpace)? {
        guard canSubmit, let selectedHostID else { return nil }
        state = .creating
        do {
            let created = try await create(
                SpaceCreationRequest(
                    directory: Self.nonEmptyTrimmed(directory),
                    label: Self.nonEmptyTrimmed(label)),
                selectedHostID)
            state = .created
            return (selectedHostID, created)
        } catch {
            state = .failed(Self.message(for: error))
            return nil
        }
    }

    private static func nonEmptyTrimmed(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func message(for error: any Error) -> String {
        switch error {
        case TransportError.sshUnreachable:
            "The Host is not connected."
        case TransportError.timedOut:
            "The Host did not answer in time."
        case let api as HerdrAPIError:
            "herden could not create the Space: \(api.message)"
        case TransportError.apiRejected(_, let message):
            "herden could not create the Space: \(message)"
        default:
            "Creating the Space failed: \(error)"
        }
    }
}

struct NewSpaceView: View {
    @State private var store: NewSpaceStore
    private let onCreated: (Host.ID, CreatedSpace) -> Void
    @Environment(\.dismiss) private var dismiss

    init(
        hosts: [Host],
        selectedHostID: Host.ID? = nil,
        console: ConsoleStore,
        onCreated: @escaping (Host.ID, CreatedSpace) -> Void
    ) {
        self.onCreated = onCreated
        _store = State(
            initialValue: NewSpaceStore(
                hosts: hosts,
                selectedHostID: selectedHostID
            ) { spec, hostID in
                try await console.createSpace(spec, on: hostID)
            })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Host") {
                    Picker("Host", selection: $store.selectedHostID) {
                        if store.selectedHostID == nil {
                            Text("Select a Host").tag(Host.ID?.none)
                        }
                        ForEach(store.hosts) { host in
                            Text(host.pickerIdentity).tag(Host.ID?.some(host.id))
                        }
                    }
                    if let host = store.hosts.first(where: { $0.id == store.selectedHostID }) {
                        LabeledContent("Machine") {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(host.displayName)
                                    .fontWeight(.semibold)
                                Text(host.connectionIdentity)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section {
                    TextField("Optional — defaults to Host home", text: $store.directory)
                        .font(.callout.monospaced())
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("Directory")
                } footer: {
                    if let message = store.directoryErrorMessage {
                        Text(message).foregroundStyle(.red)
                    } else {
                        Text("Leave blank to open the Host’s home directory.")
                    }
                }

                Section {
                    TextField("Optional", text: $store.label)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("Space Name")
                } footer: {
                    Text("Empty uses herden’s name for the directory.")
                }

                if case .failed(let message) = store.state {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("New Space")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(!store.canDismiss)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if store.state == .creating {
                        ProgressView()
                    } else {
                        Button("Create") {
                            Task {
                                guard let (hostID, created) = await store.submit() else { return }
                                dismiss()
                                onCreated(hostID, created)
                            }
                        }
                        .disabled(!store.canSubmit)
                    }
                }
            }
            .interactiveDismissDisabled(!store.canDismiss)
        }
    }
}

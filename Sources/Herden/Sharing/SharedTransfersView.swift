import SwiftUI

/// Reads the same durable records as the Share Extension. Opening a record is
/// navigation only: it never replays an insertion, even after a cold launch.
struct SharedTransfersView: View {
    @Binding var showingTransfers: Bool
    let openAgent: (SharedTransfer) -> Void
    @State private var records: [SharedTransfer] = []
    @State private var activeID: UUID?
    @State private var operation: Task<Void, Never>?
    @State private var errorMessage: String?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            if let latest = Self.bannerRecord(in: records) {
                Button { showingTransfers = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "doc.badge.arrow.up")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(latest.filename) · \(latest.agentName)").lineLimit(1)
                            Text(latest.message).font(.caption).lineLimit(2)
                            if latest.status == .uploading {
                                ProgressView(value: fraction(latest))
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                    }.padding(10)
                }
                .buttonStyle(.plain)
                .background(.regularMaterial)
                .accessibilityIdentifier("shared-transfer-banner")
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { operation?.cancel(); return }
            repeat {
                refresh()
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            } while !Task.isCancelled
        }
        .sheet(isPresented: $showingTransfers) {
            NavigationStack {
                List {
                    if let errorMessage { Text(errorMessage).foregroundStyle(.secondary) }
                    if records.isEmpty {
                        Text("No shared files").foregroundStyle(.secondary)
                    }
                    ForEach(records) { record in
                        Section {
                            Text(record.filename).font(.headline)
                            Text("\(record.agentName) · \(record.host.displayName)")
                                .font(.subheadline)
                            Text(record.message)
                            if record.status == .uploading {
                                ProgressView(value: fraction(record))
                                Text(fraction(record), format: .percent.precision(.fractionLength(0)))
                            }
                            Button("Open Agent") {
                                showingTransfers = false
                                openAgent(record)
                            }
                            if record.canRetry {
                                Button(record.remotePath == nil ? "Retry Upload" : "Insert File Path") {
                                    retry(record)
                                }.disabled(activeID != nil)
                            }
                            if activeID == record.id {
                                Button("Cancel Transfer", role: .cancel) { operation?.cancel() }
                            }
                            if record.status == .uncertain, let path = record.remotePath {
                                Text("The path may already be in the prompt. Open the Agent and check. If it is missing, copy it here and paste it yourself.")
                                    .font(.caption)
                                Button("Copy Path") {
                                    UIPasteboard.general.setItems([["public.utf8-plain-text": path + " "]],
                                        options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(86400)])
                                }
                            }
                            if ![.uploading, .inserting].contains(record.status), activeID != record.id {
                                Button("Dismiss", role: .destructive) {
                                    do { try SharedTransferStore().dismiss(record.id); refresh() }
                                    catch { errorMessage = "The transfer could not be dismissed." }
                                }
                            }
                        }
                    }
                }
                .navigationTitle("Shared Files")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showingTransfers = false }
                    }
                }
            }
        }
    }

    /// Completed receipts remain in history to prevent replay after reopening,
    /// but must not occupy terminal space or hide an older pending transfer.
    static func bannerRecord(in records: [SharedTransfer]) -> SharedTransfer? {
        records.first { $0.status != .added }
    }

    private func fraction(_ record: SharedTransfer) -> Double {
        min(1, max(0, Double(record.transferredBytes) / Double(max(1, record.byteCount))))
    }

    private func refresh() {
        do {
            let store = try SharedTransferStore()
            try store.recover()
            records = try store.records()
        } catch { errorMessage = "Shared files are temporarily unavailable." }
    }

    private func retry(_ record: SharedTransfer) {
        guard activeID == nil else { return }
        activeID = record.id
        errorMessage = nil
        operation = Task {
            defer { activeID = nil; operation = nil; refresh() }
            var connection: (any Transport)?
            do {
                // A Host edit must not silently redirect a pending file.
                guard HostStore().hosts.contains(record.host) else {
                    errorMessage = "This Host changed or was removed. Share the document again."
                    return
                }
                let transport = try await SharedTransferDelivery.connect(record.host)
                connection = transport
                guard try await transport.listAgents().contains(where: { $0.paneID == record.paneID }) else {
                    errorMessage = "That Agent is no longer available. Share the document again."
                    try? await transport.close()
                    return
                }
                try await SharedTransferDelivery.run(id: record.id, store: SharedTransferStore(),
                    stage: { file, progress in try await transport.stageFile(file, progress: progress) },
                    insert: { params in try await transport.sendPaneInput(params) },
                    changed: { _ in refresh() })
            } catch {
                errorMessage = "The transfer stopped. Check its status before retrying."
            }
            if let connection { try? await connection.close() }
        }
    }
}

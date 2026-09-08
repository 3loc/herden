import SwiftUI

struct ShareRootView: View {
    @State var model: ShareViewModel

    var body: some View {
        NavigationStack {
            Group {
                switch model.phase {
                case .loading:
                    progressView("Finding your Agents…")
                case .choosing:
                    destinationList
                case .sending(let progress):
                    progressView(model.transfer?.message ?? "Uploading…", progress: progress)
                case .sent:
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle").font(.largeTitle)
                        Text("File added — open the Agent to add text.").font(.headline)
                        if let transfer = model.transfer {
                            Text("\(transfer.agentName) · \(transfer.host.displayName)")
                        }
                        Text("Return has not been pressed.").foregroundStyle(.secondary)
                        Button("Done") { model.done() }.buttonStyle(.borderedProminent)
                    }.padding()
                case .failed(let message):
                    ContentUnavailableView {
                        Label("Couldn’t Share", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    } actions: {
                        if model.transfer?.canRetry == true {
                            Button("Retry") { model.retry() }.buttonStyle(.borderedProminent)
                        } else if model.transfer == nil, !model.destinations.isEmpty {
                            Button("Choose Another Agent") { model.chooseAnotherAgent() }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Brand.background)
            .navigationTitle("Send to Agent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Brand.elevated, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if model.phase != .sent {
                        Button("Cancel") { model.cancel() }
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(Brand.vine)
        .foregroundStyle(Brand.ink)
        .font(Brand.sans(.body))
        .task { await model.load() }
        .onReceive(NotificationCenter.default.publisher(for: .NSExtensionHostDidEnterBackground)) { _ in
            model.pause()
        }
        .onDisappear { if model.phase != .sent { model.cancel() } }
    }

    private var destinationList: some View {
        List {
            Section {
                Label(model.filename, systemImage: "doc.fill")
                    .lineLimit(1)
                    .listRowBackground(Brand.card)
            } header: {
                Text("Sharing")
            }

            Section {
                ForEach(model.destinations) { destination in
                    Button {
                        model.send(to: destination)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "terminal.fill")
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(destination.title)
                                    .font(Brand.sans(.headline, weight: .semibold))
                                    .foregroundStyle(Brand.ink)
                                Text("\(destination.agent.kind) · \(destination.host.displayName)")
                                    .font(Brand.sans(.subheadline))
                                    .foregroundStyle(Brand.muted)
                                Text(destination.host.connectionIdentity)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.circle.fill")
                                .foregroundStyle(.tint)
                        }
                    }
                    .disabled(model.isBusy)
                    .listRowBackground(Brand.card)
                }
            } header: {
                Text("Choose an Agent")
            } footer: {
                Text("The file path is inserted into the Agent without pressing Return.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Brand.background)
    }

    private func progressView(_ title: String, progress: Double? = nil) -> some View {
        VStack(spacing: 18) {
            if let progress {
                ProgressView(value: progress)
                    .frame(maxWidth: 220)
                Text(progress, format: .percent.precision(.fractionLength(0)))
            } else {
                ProgressView()
            }
            Text(title).font(.headline)
            Text(model.filename)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let transfer = model.transfer {
                Text("\(transfer.agentName) · \(transfer.host.displayName)")
                    .font(.subheadline)
            }
        }
        .padding(32)
    }
}

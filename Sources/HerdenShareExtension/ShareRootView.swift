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
                    progressView("Sending…", progress: progress)
                case .sent:
                    progressView("Delivered")
                case .failed(let message):
                    ContentUnavailableView {
                        Label("Couldn’t Share", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    } actions: {
                        if !model.destinations.isEmpty {
                            Button("Choose Another Agent") { model.chooseAnotherAgent() }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
            .navigationTitle("Send to Agent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { model.cancel() }
                }
            }
        }
        .tint(Color(red: 0.16, green: 0.58, blue: 0.49))
        .task { await model.load() }
    }

    private var destinationList: some View {
        List {
            Section {
                Label(model.filename, systemImage: "doc.fill")
                    .lineLimit(1)
            } header: {
                Text("Sharing")
            }

            Section {
                ForEach(model.destinations) { destination in
                    Button {
                        Task { await model.send(to: destination) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "terminal.fill")
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(destination.agent.displayName)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(destination.host.displayName)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text(destination.host.connectionIdentity)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.circle.fill")
                                .foregroundStyle(.tint)
                        }
                    }
                }
            } header: {
                Text("Choose an Agent")
            } footer: {
                Text("The file path is inserted into the Agent without pressing Return.")
            }
        }
    }

    private func progressView(_ title: String, progress: Double? = nil) -> some View {
        VStack(spacing: 18) {
            if let progress {
                ProgressView(value: progress)
                    .frame(maxWidth: 220)
            } else {
                ProgressView()
            }
            Text(title).font(.headline)
            Text(model.filename)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(32)
    }
}

import AVFAudio
import SwiftUI

struct AudioRecordingSheet: View {
    let attach: (PreparedFile) -> Bool
    @StateObject private var recorder = HerdenAudioRecorder()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: recorder.state == .recording ? "waveform" : "waveform.circle")
                    .font(.system(size: 40))
                    .foregroundStyle(recorder.state == .recording ? Brand.fault : Brand.vine)
                    .accessibilityHidden(true)
                Text(Duration.seconds(recorder.duration), format: .time(pattern: .minuteSecond))
                    .font(.system(size: 36, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .accessibilityLabel("Duration")
                    .accessibilityValue("\(Int(recorder.duration)) seconds")
                Text(recorder.state == .recording ? "Recording · up to 10 minutes" : "Audio recording")
                    .font(.headline)
                if let message = recorder.message {
                    Text(message).font(.callout).foregroundStyle(Brand.fault)
                    if recorder.settingsRequired {
                        Button("Open Settings") {
                            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                            UIApplication.shared.open(url)
                        }
                    }
                }
                controls
                Text("Attach the recording to your prompt, then press Return when you’re ready. Your Agent needs audio support to listen to it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Brand.elevated)
            .navigationTitle("Record audio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { recorder.discard(); dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(recorder.state == .recording || recorder.state == .preparing)
        .task {
            await recorder.start()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(200)) }
                catch { break }
                recorder.tick()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background || (phase == .inactive && recorder.state == .recording) {
                recorder.suspend()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in
            recorder.suspend()
        }
        .onDisappear { recorder.discard() }
    }

    @ViewBuilder private var controls: some View {
        switch recorder.state {
        case .idle:
            Button("Record", systemImage: "record.circle") { Task { await recorder.start() } }
                .buttonStyle(.borderedProminent)
        case .preparing:
            ProgressView("Preparing microphone…")
        case .recording:
            Button("Stop recording", systemImage: "stop.fill") { recorder.finish() }
                .buttonStyle(.borderedProminent)
                .tint(Brand.fault)
                .accessibilityIdentifier("audio-stop")
        case .review:
            HStack(spacing: 16) {
                Button(recorder.isPlaying ? "Stop playback" : "Play", systemImage: recorder.isPlaying ? "stop.fill" : "play.fill") {
                    recorder.togglePlayback()
                }
                .buttonStyle(.bordered)
                Button("Discard", role: .destructive) { recorder.discard() }
                    .buttonStyle(.bordered)
            }
            Button("Attach audio", systemImage: "paperclip") {
                if recorder.attach(using: attach) { dismiss() }
            }
            .buttonStyle(.borderedProminent)
            .tint(Brand.vine)
            .accessibilityIdentifier("audio-attach")
        }
    }
}

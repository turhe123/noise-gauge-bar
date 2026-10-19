import SwiftUI

/// The MenuBarExtra window: first-run intro, permission-denied guidance, or the live meter.
struct MenuContentView: View {
    @ObservedObject var meter: AudioMeter
    @AppStorage(Prefs.introSeen) private var introSeen = false
    @AppStorage(Prefs.alertEnabled) private var alertEnabled = false
    @AppStorage(Prefs.alertLevel) private var alertLevel = 85.0
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch (meter.permission, introSeen) {
            case (.denied, _): deniedView
            case (.notDetermined, _), (_, false): introView
            default: meterView
            }
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 320)
        .onAppear { meter.refreshPermission() }
    }

    private var introView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Welcome to NoiseGaugeBar", systemImage: "waveform.badge.mic").font(.headline)
            Text("NoiseGaugeBar listens through your microphone to estimate how loud the room is. "
                 + "Audio is analysed in memory only — it is never recorded, saved or transmitted.")
            Text("macOS shows the orange microphone indicator while measuring. Use Pause to stop at any time.")
                .foregroundStyle(.secondary)
            Button("Allow Microphone & Start") {
                introSeen = true
                meter.requestAccessAndStart()
            }
            .buttonStyle(.borderedProminent)
        }
        .font(.callout)
    }

    private var deniedView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Microphone access is off", systemImage: "mic.slash").font(.headline)
            Text("To measure sound, open System Settings › Privacy & Security › Microphone and turn on "
                 + "NoiseGaugeBar. Audio is never recorded or sent anywhere.")
                .font(.callout)
            HStack {
                Button("Open Privacy Settings") { AudioMeter.openPrivacySettings() }
                    .buttonStyle(.borderedProminent)
                Button("Check Again") { meter.bootstrap() }
            }
        }
    }

    private var meterView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(meter.isRunning ? "\(Int(meter.level.rounded()))" : "--")
                    .font(.system(size: 48, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("dB").font(.title3).foregroundStyle(.secondary)
                Spacer()
                Text(meter.isRunning ? LoudnessCategory.word(for: meter.level) : (meter.isPaused ? "Paused" : "Idle"))
                    .font(.title3.weight(.medium))
                    .foregroundStyle(meter.isRunning ? levelColor(meter.level) : .secondary)
            }
            if let error = meter.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(levelColor(meter.level))
                        .frame(width: geo.size.width * (meter.isRunning ? meter.fraction : 0))
                        .animation(.easeOut(duration: 0.2), value: meter.level)
                }
            }
            .frame(height: 8)

            HistoryGraph(values: meter.history.values, alertLevel: alertEnabled ? alertLevel : nil)
                .frame(height: 90)

            HStack {
                stat("Min", meter.minLevel)
                stat("Avg", meter.avgLevel)
                stat("Max", meter.maxLevel)
                Spacer()
                Button("Reset") { meter.resetStats() }
            }
            Toggle("Pause measuring", isOn: Binding(get: { meter.isPaused }, set: { meter.setPaused($0) }))
                .toggleStyle(.switch)
        }
    }

    private var footer: some View {
        HStack {
            Button {
                openSettings()
                NSApp.activate()
            } label: { Label("Settings…", systemImage: "gearshape") }
            SupportButton()
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
        }
        .controlSize(.small)
    }

    private func stat(_ title: String, _ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value.map { "\(Int($0.rounded()))" } ?? "--").font(.callout.monospacedDigit())
        }
        .frame(width: 44, alignment: .leading)
    }
}

/// Colour scale used for bars and the category word.
func levelColor(_ db: Double) -> Color {
    switch db {
    case ..<60: return .green
    case ..<75: return .yellow
    case ..<85: return .orange
    default: return .red
    }
}

/// Opens the project's donation page.
struct SupportButton: View {
    var body: some View {
        Button("Support / Donate ❤️") {
            NSWorkspace.shared.open(URL(string: "https://ko-fi.com/leodavidai")!)
        }
    }
}

import ServiceManagement
import SwiftUI

/// Settings window: input device, weighting, calibration, alerts, smoothing and launch at login.
struct SettingsView: View {
    @ObservedObject var meter: AudioMeter
    @AppStorage(Prefs.deviceUID) private var deviceUID = ""
    @AppStorage(Prefs.aWeighting) private var aWeighting = true
    @AppStorage(Prefs.calibrationOffset) private var offset = Prefs.defaultOffset
    @AppStorage(Prefs.alertEnabled) private var alertEnabled = false
    @AppStorage(Prefs.alertLevel) private var alertLevel = 85.0
    @AppStorage(Prefs.alertDuration) private var alertDuration = 10.0
    @AppStorage(Prefs.smoothing) private var smoothing = Smoothing.fast.rawValue
    @State private var devices: [InputDevice] = []
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Input") {
                Picker("Input device", selection: $deviceUID) {
                    Text("System Default").tag("")
                    ForEach(devices) { Text($0.name).tag($0.id) }
                }
                Picker("Weighting", selection: $aWeighting) {
                    Text("A-weighted (dBA)").tag(true)
                    Text("Unweighted (Z)").tag(false)
                }
                Picker("Smoothing", selection: $smoothing) {
                    ForEach(Smoothing.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Stepper(value: $offset, in: 0...160, step: 0.5) {
                    LabeledContent("Calibration offset", value: String(format: "%+.1f dB", offset))
                }
                Button("Reset Calibration") { offset = Prefs.defaultOffset }
            }
            Section("Too-loud alert") {
                Toggle("Notify when it gets too loud", isOn: $alertEnabled)
                Stepper(value: $alertLevel, in: 40...130, step: 1) {
                    LabeledContent("Alert level", value: "\(Int(alertLevel)) dB")
                }
                .disabled(!alertEnabled)
                Stepper(value: $alertDuration, in: 1...600, step: 1) {
                    LabeledContent("For longer than", value: "\(Int(alertDuration)) s")
                }
                .disabled(!alertEnabled)
            }
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
                HStack {
                    SupportButton()
                    Spacer()
                    Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Text("Readings are estimates. Mac microphones apply automatic gain and differ by model, so "
                     + "use the calibration offset to match a reference sound level meter. No audio is ever "
                     + "recorded, saved or transmitted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            devices = AudioMeter.availableDevices()
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
        .onChange(of: deviceUID) { meter.restartIfRunning() }
        .onChange(of: aWeighting) { meter.restartIfRunning() }
        .onChange(of: smoothing) { meter.setSmoothing(Smoothing(rawValue: smoothing) ?? .fast) }
        .onChange(of: alertEnabled) { if alertEnabled { AlertMonitor.requestAuthorization() } }
        .onChange(of: launchAtLogin) { updateLoginItem(launchAtLogin) }
    }

    private func updateLoginItem(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Could not update login item: \(error.localizedDescription)"
        }
    }
}

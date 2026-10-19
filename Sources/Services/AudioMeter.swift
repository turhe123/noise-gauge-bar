import AppKit
import AVFoundation
import CoreAudio

/// A selectable audio input device.
struct InputDevice: Identifiable, Hashable {
    let id: String   // Core Audio UID
    let name: String
}

/// Owns the AVAudioEngine capture pipeline and publishes the calibrated level, statistics and history.
/// Restarts on device/configuration changes and pauses automatically while the Mac sleeps.
final class AudioMeter: ObservableObject {
    static let shared = AudioMeter()

    enum Permission { case notDetermined, denied, authorized }

    @Published private(set) var permission: Permission = .notDetermined
    @Published private(set) var level: Double = 0
    @Published private(set) var minLevel: Double?
    @Published private(set) var maxLevel: Double?
    @Published private(set) var avgLevel: Double?
    @Published private(set) var history = HistoryBuffer()
    @Published private(set) var isRunning = false
    @Published private(set) var isPaused = false
    @Published private(set) var errorMessage: String?

    private var engine: AVAudioEngine?
    private var processor: LevelProcessor?
    private var configObserver: NSObjectProtocol?
    private var sum: Double = 0
    private var samples = 0
    private var pausedBySleep = false
    private let alerts = AlertMonitor()

    /// Level mapped onto 0…1 for bars (30 dB … 110 dB).
    var fraction: Double { min(max((level - 30) / 80, 0), 1) }

    private init() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.isRunning else { return }
            self.pausedBySleep = true
            self.stop()
        }
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.pausedBySleep else { return }
            self.pausedBySleep = false
            if !self.isPaused { self.start() }
        }
    }

    // MARK: Permission

    func bootstrap() {
        refreshPermission()
        if UserDefaults.standard.bool(forKey: Prefs.alertEnabled) { AlertMonitor.requestAuthorization() }
        if permission == .authorized && UserDefaults.standard.bool(forKey: Prefs.introSeen) { start() }
    }

    func refreshPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: permission = .authorized
        case .notDetermined: permission = .notDetermined
        default: permission = .denied
        }
    }

    /// Called from the first-run screen: asks for microphone access and starts measuring if granted.
    func requestAccessAndStart() {
        UserDefaults.standard.set(true, forKey: Prefs.introSeen)
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.refreshPermission()
                if self.permission == .authorized { self.start() }
            }
        }
    }

    static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Engine

    func start() {
        stop()
        refreshPermission()
        guard permission == .authorized, !isPaused else { return }
        let defaults = UserDefaults.standard
        let engine = AVAudioEngine()
        let input = engine.inputNode
        selectDevice(uid: defaults.string(forKey: Prefs.deviceUID) ?? "", on: input)

        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            errorMessage = "No microphone found. Connect an input device or pick another one in Settings."
            return
        }
        let smoothing = Smoothing(rawValue: defaults.string(forKey: Prefs.smoothing) ?? "") ?? .fast
        let processor = LevelProcessor(sampleRate: format.sampleRate,
                                       aWeighted: defaults.bool(forKey: Prefs.aWeighting),
                                       smoothing: smoothing) { [weak self] dbfs in
            DispatchQueue.main.async { self?.ingest(dbfs: dbfs) }
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            processor.process(buffer)
        }
        do {
            engine.prepare()
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            errorMessage = "The microphone is unavailable. Another app may be using it exclusively."
            return
        }
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            // Device added/removed or format changed: rebuild the pipeline shortly after.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self?.restartIfRunning() }
        }
        self.engine = engine
        self.processor = processor
        errorMessage = nil
        isRunning = true
    }

    func stop() {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil
        processor = nil
        isRunning = false
        alerts.reset()
    }

    func restartIfRunning() {
        if isRunning || errorMessage != nil { start() }
    }

    func setPaused(_ paused: Bool) {
        isPaused = paused
        if paused { stop(); errorMessage = nil } else { start() }
    }

    func setSmoothing(_ smoothing: Smoothing) {
        processor?.setSmoothing(smoothing)
    }

    func resetStats() {
        minLevel = nil; maxLevel = nil; avgLevel = nil
        sum = 0; samples = 0
        history.removeAll()
    }

    private func ingest(dbfs: Double) {
        guard isRunning else { return }
        let offset = UserDefaults.standard.double(forKey: Prefs.calibrationOffset)
        let value = max(dbfs + offset, 0)
        level = value
        minLevel = min(minLevel ?? value, value)
        maxLevel = max(maxLevel ?? value, value)
        sum += value; samples += 1
        avgLevel = sum / Double(samples)
        history.append(value)
        alerts.evaluate(level: value)
    }

    // MARK: Devices

    static func availableDevices() -> [InputDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified)
            .devices.map { InputDevice(id: $0.uniqueID, name: $0.localizedName) }
    }

    private func selectDevice(uid: String, on input: AVAudioInputNode) {
        guard !uid.isEmpty, let unit = input.audioUnit else { return }
        var cfUID = uid as CFString
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = withUnsafePointer(to: &cfUID) { ptr in
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                       UInt32(MemoryLayout<CFString>.size), ptr, &size, &deviceID)
        }
        guard status == noErr, deviceID != kAudioObjectUnknown else { return }  // fall back to system default
        AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                             &deviceID, UInt32(MemoryLayout<AudioDeviceID>.size))
    }
}

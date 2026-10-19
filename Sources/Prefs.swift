import Foundation

/// Central list of UserDefaults keys and their default values, shared by `@AppStorage` and services.
enum Prefs {
    static let deviceUID = "deviceUID"
    static let aWeighting = "aWeighting"
    static let calibrationOffset = "calibrationOffset"
    static let alertEnabled = "alertEnabled"
    static let alertLevel = "alertLevel"
    static let alertDuration = "alertDuration"
    static let smoothing = "smoothing"
    static let introSeen = "introSeen"

    static let defaultOffset = 100.0

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            deviceUID: "",
            aWeighting: true,
            calibrationOffset: defaultOffset,
            alertEnabled: false,
            alertLevel: 85.0,
            alertDuration: 10.0,
            smoothing: Smoothing.fast.rawValue,
            introSeen: false,
        ])
    }
}

/// Exponential averaging speed, mirroring the classic sound level meter "Fast" and "Slow" settings.
enum Smoothing: String, CaseIterable, Identifiable {
    case fast, slow
    var id: String { rawValue }
    var title: String { self == .fast ? "Fast (125 ms)" : "Slow (1 s)" }
    var timeConstant: Double { self == .fast ? 0.125 : 1.0 }
}

/// Human-friendly description of a sound level.
enum LoudnessCategory {
    static func word(for db: Double) -> String {
        switch db {
        case ..<40: return "Quiet"
        case ..<60: return "Conversation"
        case ..<75: return "Busy"
        default: return "Loud"
        }
    }
}

/// Fixed-capacity ring buffer holding the most recent level samples (1200 × 0.25 s = 5 minutes).
struct HistoryBuffer {
    let capacity: Int
    private var storage: [Double]
    private var head = 0
    private(set) var count = 0

    init(capacity: Int = 1200) {
        self.capacity = capacity
        storage = Array(repeating: 0, count: capacity)
    }

    mutating func append(_ value: Double) {
        storage[head] = value
        head = (head + 1) % capacity
        count = min(count + 1, capacity)
    }

    mutating func removeAll() {
        head = 0
        count = 0
    }

    /// Samples in chronological order, oldest first.
    var values: [Double] {
        guard count > 0 else { return [] }
        let start = (head - count + capacity) % capacity
        return (0..<count).map { storage[(start + $0) % capacity] }
    }
}

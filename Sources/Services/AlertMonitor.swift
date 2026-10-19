import Foundation
import UserNotifications

/// Fires a local notification when the level stays above the user's threshold for long enough,
/// with a cooldown so it never nags.
final class AlertMonitor {
    private var aboveSince: Date?
    private var lastAlert = Date.distantPast
    private let cooldown: TimeInterval = 180

    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func reset() { aboveSince = nil }

    func evaluate(level: Double, now: Date = Date()) {
        let defaults = UserDefaults.standard
        let threshold = defaults.double(forKey: Prefs.alertLevel)
        let duration = defaults.double(forKey: Prefs.alertDuration)
        guard defaults.bool(forKey: Prefs.alertEnabled), level >= threshold else {
            aboveSince = nil
            return
        }
        let start = aboveSince ?? now
        aboveSince = start
        guard now.timeIntervalSince(start) >= duration, now.timeIntervalSince(lastAlert) >= cooldown else { return }
        lastAlert = now
        aboveSince = nil
        send(level: level, threshold: threshold, duration: duration)
    }

    private func send(level: Double, threshold: Double, duration: Double) {
        let content = UNMutableNotificationContent()
        content.title = "It's too loud"
        content.body = "The room has been above \(Int(threshold)) dB for over \(Int(duration)) s "
            + "(now about \(Int(level.rounded())) dB)."
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }
}

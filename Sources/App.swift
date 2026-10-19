import SwiftUI
import AppKit

/// Application entry point: owns the menu bar extra and the Settings window.
@main
struct NoiseGaugeBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var meter = AudioMeter.shared

    init() {
        Prefs.registerDefaults()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(meter: meter)
        } label: {
            MenuBarLabel(meter: meter)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(meter: meter)
        }
    }
}

/// Starts metering once the app has finished launching.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AudioMeter.shared.bootstrap()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AudioMeter.shared.stop()
    }
}

/// The compact status item content: a tiny template level bar plus the current reading.
struct MenuBarLabel: View {
    @ObservedObject var meter: AudioMeter

    var body: some View {
        HStack(spacing: 3) {
            Image(nsImage: LevelBarImage.make(fraction: meter.isRunning ? meter.fraction : 0))
            Text(meter.isRunning ? "\(Int(meter.level.rounded())) dB" : "-- dB")
                .monospacedDigit()
        }
    }
}

/// Draws the miniature vertical level bar shown in the menu bar.
enum LevelBarImage {
    static func make(fraction: Double) -> NSImage {
        let size = NSSize(width: 6, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            let outline = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 1.5), xRadius: 1.5, yRadius: 1.5)
            NSColor.black.setStroke()
            outline.lineWidth = 1
            outline.stroke()
            let inner = rect.insetBy(dx: 1.5, dy: 2.5)
            let fill = NSRect(x: inner.minX, y: inner.minY,
                              width: inner.width, height: inner.height * min(max(fraction, 0), 1))
            NSColor.black.setFill()
            NSBezierPath(rect: fill).fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}

# NoiseGaugeBar — specification

**Tagline:** A menu bar decibel readout of the room around your Mac with a history graph and a too-loud alert.

**Category:** System Monitoring

**Inspired by (paid):** Decibel Meter Analyzer ($4.99 one-time)

**Frameworks:** SwiftUI, AppKit, AVFoundation, Accelerate, UserNotifications, ServiceManagement

**Donation URL (Support button):** https://ko-fi.com/leodavidai

## Spec

What the paid app does: Decibel Meter Analyzer is a Mac App Store app priced at 4.99 dollars one-time that shows sound level in decibels with an equalizer style view and a timeline, with calibration for the microphone. A free GitHub project named DeciBar shows people want a menu bar version. Evidence of demand comes from many decibel meter apps on both phone and desktop, used by parents, remote workers, musicians and people checking noisy offices. This is a different idea from loudness metering in LUFS, because ours measures the room with the microphone and is aimed at everyday users.

Our clean-room feature set: a menu bar item that displays the current ambient sound level as a number in decibels, updated about four times a second, with A weighting as an option. The dropdown shows a live bar, the minimum, average and maximum since start, a graph of the last five minutes, and a Reset button. Users can set an alert level, for example 85 decibels, and receive a notification when the level stays above it for more than a chosen number of seconds. A calibration offset field lets the user match a reference meter. Scope is about 350 lines.

UI spec: a MenuBarExtra in window style. The label shows a number and a tiny level bar. The popover has a large current value with a descriptive word such as Quiet, Conversation, Busy or Loud, a Canvas graph of recent history, statistics, a Pause switch and a Settings button. The Settings window has input device picker, weighting picker, calibration offset stepper, alert level and duration, smoothing choice of fast or slow, and launch at login. Empty state when the microphone permission is denied explains how to enable it and has a button to open the Privacy pane.

Technical approach: request microphone access with AVCaptureDevice requestAccess for audio and include the microphone usage description in the Info plist. Capture with AVAudioEngine by installing a tap on the input node with a small buffer size. For each buffer compute root mean square with Accelerate vDSP, convert to decibels relative to full scale, and add the calibration offset so the displayed number sits in a positive range that approximates sound pressure. For A weighting apply a biquad filter chain using AVAudioUnitEQ or a manual filter before measuring. Smooth with an exponential average. Store history in a ring buffer of about 1200 samples. Alerts use UNUserNotificationCenter with a cooldown of a few minutes. Settings persist in UserDefaults through AppStorage. Launch at login uses SMAppService.mainApp.

Edge cases: be honest that values are estimates, with a note in the settings footer, since laptop microphones apply automatic gain and vary by model. If the input device changes or disappears, restart the engine on the configuration change notification. If another app holds the microphone exclusively, show a short message. Pause automatically on sleep. Never write or transmit any audio, and say so in the first-run text, because the orange microphone indicator will be visible while measuring.

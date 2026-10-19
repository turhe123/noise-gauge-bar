import Accelerate
import AVFoundation

/// Runs on the audio render thread: optional A-weighting, RMS via vDSP, exponential smoothing,
/// and emits a dBFS reading roughly four times a second. Audio is never stored or written anywhere.
final class LevelProcessor {
    private let lock = NSLock()
    private let sampleRate: Double
    private var filter: AWeightingFilter?
    private var timeConstant: Double
    private var scratch: [Float] = []
    private var smoothedMeanSquare: Double = 0
    private var primed = false
    private var sinceEmit: Double = 0
    private let emitInterval = 0.25
    private let onLevel: (Double) -> Void

    init(sampleRate: Double, aWeighted: Bool, smoothing: Smoothing, onLevel: @escaping (Double) -> Void) {
        self.sampleRate = sampleRate
        self.filter = aWeighted ? AWeightingFilter(sampleRate: sampleRate) : nil
        self.timeConstant = smoothing.timeConstant
        self.onLevel = onLevel
    }

    func setSmoothing(_ smoothing: Smoothing) {
        lock.lock(); timeConstant = smoothing.timeConstant; lock.unlock()
    }

    func process(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0, sampleRate > 0 else { return }
        let n = Int(buffer.frameLength)
        lock.lock()
        defer { lock.unlock() }

        var meanSquare: Float = 0
        if let filter {
            if scratch.count < n { scratch = Array(repeating: 0, count: n) }
            scratch.withUnsafeMutableBufferPointer { out in
                guard let base = out.baseAddress else { return }
                filter.process(channel, into: base, count: n)
                vDSP_measqv(base, 1, &meanSquare, vDSP_Length(n))
            }
        } else {
            vDSP_measqv(channel, 1, &meanSquare, vDSP_Length(n))
        }

        let dt = Double(n) / sampleRate
        if primed {
            let alpha = 1 - exp(-dt / timeConstant)
            smoothedMeanSquare += alpha * (Double(meanSquare) - smoothedMeanSquare)
        } else {
            smoothedMeanSquare = Double(meanSquare)
            primed = true
        }

        sinceEmit += dt
        if sinceEmit >= emitInterval {
            sinceEmit = 0
            onLevel(10 * log10(max(smoothedMeanSquare, 1e-12)))
        }
    }
}

import Accelerate
import Foundation

/// IEC 61672 A-weighting implemented as three cascaded biquads (bilinear transform, pre-warped poles)
/// running through Accelerate's `vDSP_biquad`. Normalised to 0 dB gain at 1 kHz.
final class AWeightingFilter {
    private let setup: vDSP_biquad_Setup
    private var delay: [Float]
    private var gain: Float

    init?(sampleRate fs: Double) {
        guard fs > 1000 else { return nil }
        let k = 2 * fs
        func warp(_ f: Double) -> Double { k * tan(Double.pi * min(f, 0.45 * fs) / fs) }
        let w1 = warp(20.598997), w2 = warp(107.65265), w3 = warp(737.86223), w4 = warp(12194.217)

        // Analog sections as (b0 s² + b1 s + b2) / (s² + a1 s + a2).
        let analog: [(b: [Double], a: [Double])] = [
            ([1, 0, 0], [1, 2 * w1, w1 * w1]),
            ([1, 0, 0], [1, w2 + w3, w2 * w3]),
            ([0, 0, w4 * w4], [1, 2 * w4, w4 * w4]),
        ]
        var coefficients: [Double] = []
        let omega = 2 * Double.pi * 1000 / fs
        var magnitudeAt1k = 1.0
        for section in analog {
            let d = Self.bilinear(section.b, section.a, k: k)
            coefficients += d
            magnitudeAt1k *= Self.magnitude(d, omega: omega)
        }
        guard let created = vDSP_biquad_CreateSetup(coefficients, vDSP_Length(analog.count)) else { return nil }
        setup = created
        delay = Array(repeating: 0, count: 2 * analog.count + 2)
        gain = magnitudeAt1k > 0 ? Float(1 / magnitudeAt1k) : 1
    }

    deinit { vDSP_biquad_DestroySetup(setup) }

    /// Filters `count` samples from `input` into `output`.
    func process(_ input: UnsafePointer<Float>, into output: UnsafeMutablePointer<Float>, count: Int) {
        vDSP_biquad(setup, &delay, input, 1, output, 1, vDSP_Length(count))
        vDSP_vsmul(output, 1, &gain, output, 1, vDSP_Length(count))
    }

    /// Returns digital coefficients [b0, b1, b2, a1, a2] normalised by a0.
    private static func bilinear(_ b: [Double], _ a: [Double], k: Double) -> [Double] {
        let k2 = k * k
        let nb0 = b[0] * k2 + b[1] * k + b[2], nb1 = 2 * (b[2] - b[0] * k2), nb2 = b[0] * k2 - b[1] * k + b[2]
        let na0 = a[0] * k2 + a[1] * k + a[2], na1 = 2 * (a[2] - a[0] * k2), na2 = a[0] * k2 - a[1] * k + a[2]
        return [nb0 / na0, nb1 / na0, nb2 / na0, na1 / na0, na2 / na0]
    }

    private static func magnitude(_ c: [Double], omega w: Double) -> Double {
        let numRe = c[0] + c[1] * cos(w) + c[2] * cos(2 * w), numIm = -(c[1] * sin(w) + c[2] * sin(2 * w))
        let denRe = 1 + c[3] * cos(w) + c[4] * cos(2 * w), denIm = -(c[3] * sin(w) + c[4] * sin(2 * w))
        let den = (denRe * denRe + denIm * denIm).squareRoot()
        return den > 0 ? (numRe * numRe + numIm * numIm).squareRoot() / den : 0
    }
}

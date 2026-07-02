//  PitchDetector.swift
//  AudioSpectrumPro

import Accelerate
import Foundation

/// YIN pitch detector (de Cheveigné & Kawahara, 2002).
///
/// Time-domain autocorrelation method — unlike an FFT peak pick it locks onto
/// the fundamental even when harmonics carry more energy, which is the normal
/// case for low guitar/bass strings (E2 at 82 Hz has most energy in overtones).
/// FFT bin resolution at 82 Hz (~10.7 Hz per bin at 44.1 kHz / 4096) is also
/// far too coarse for cent-accurate tuning; YIN's lag-domain resolution plus
/// parabolic interpolation is not.
final class PitchDetector {
    let sampleRate: Float

    /// Detection range — covers 5-string bass low B (31 Hz is unrealistic from
    /// a phone mic; 60 Hz still catches its strong 2nd harmonic) up to violin E5+.
    private let minFrequency: Float = 60
    private let maxFrequency: Float = 1500
    /// CMND acceptance threshold — lower is stricter (fewer octave errors).
    private let threshold: Float = 0.15

    private let tauMin: Int
    private let tauMax: Int
    private let windowSize: Int

    // Pre-allocated work buffers (hot path — no per-frame heap allocations).
    private var diff:  [Float]
    private var cmnd:  [Float]

    init(sampleRate: Float) {
        self.sampleRate = sampleRate
        self.tauMax     = Int(sampleRate / minFrequency)
        self.tauMin     = max(2, Int(sampleRate / maxFrequency))
        // Window + max lag must fit in one 4096-sample capture buffer.
        self.windowSize = min(3072, 4096 - tauMax)
        self.diff       = [Float](repeating: 0, count: tauMax + 1)
        self.cmnd       = [Float](repeating: 1, count: tauMax + 1)
    }

    /// Returns the fundamental frequency in Hz, or nil when no confident
    /// pitch is present (silence, noise, or signal below the gate).
    func detectPitch(_ samples: [Float], noiseGateDB: Float) -> Float? {
        guard samples.count >= windowSize + tauMax else { return nil }

        // Noise gate on RMS of the analysis window.
        var sumSq: Float = 0
        vDSP_svesq(samples, 1, &sumSq, vDSP_Length(windowSize))
        let rmsDB = 20.0 * log10f(max(sqrtf(sumSq / Float(windowSize)), 1e-10))
        guard rmsDB > noiseGateDB else { return nil }

        // Difference function d(tau) = Σ (x[j] − x[j+tau])²
        //                            = E0 + E(tau) − 2·corr(tau)
        // E(tau) is updated incrementally; corr(tau) via vDSP dot product.
        let w = windowSize
        samples.withUnsafeBufferPointer { buf in
            let x = buf.baseAddress!
            var energyShifted = sumSq            // E(0) == E0
            diff[0] = 0
            for tau in 1...tauMax {
                energyShifted += x[tau + w - 1] * x[tau + w - 1]
                              - x[tau - 1]     * x[tau - 1]
                var corr: Float = 0
                vDSP_dotpr(x, 1, x + tau, 1, &corr, vDSP_Length(w))
                diff[tau] = max(sumSq + energyShifted - 2 * corr, 0)
            }
        }

        // Cumulative-mean-normalized difference (CMND).
        cmnd[0] = 1
        var runningSum: Float = 0
        for tau in 1...tauMax {
            runningSum += diff[tau]
            cmnd[tau] = runningSum > 0 ? diff[tau] * Float(tau) / runningSum : 1
        }

        // First dip below threshold, then walk down to its local minimum.
        var tauEstimate = -1
        var tau = tauMin
        while tau <= tauMax {
            if cmnd[tau] < threshold {
                while tau + 1 <= tauMax && cmnd[tau + 1] < cmnd[tau] { tau += 1 }
                tauEstimate = tau
                break
            }
            tau += 1
        }
        guard tauEstimate > 0 else { return nil }

        // Parabolic interpolation around the minimum for sub-sample precision.
        var betterTau = Float(tauEstimate)
        if tauEstimate > 1 && tauEstimate < tauMax {
            let y0 = cmnd[tauEstimate - 1]
            let y1 = cmnd[tauEstimate]
            let y2 = cmnd[tauEstimate + 1]
            let denom = y0 - 2 * y1 + y2
            if denom != 0 {
                betterTau += 0.5 * (y0 - y2) / denom
            }
        }

        let frequency = sampleRate / betterTau
        guard frequency >= minFrequency, frequency <= maxFrequency else { return nil }
        return frequency
    }
}

//  LoudnessProcessor.swift
//  AudioSpectrumPro

import Accelerate
import Foundation

/// ITU-R BS.1770-4 loudness meter for a mono stream, plus 4× oversampled
/// true-peak detection.
///
/// Produces momentary (400 ms), short-term (3 s) and gated integrated
/// loudness in LUFS. K-weighting filter coefficients are derived for the
/// actual hardware sample rate from the BS.1770 analog prototypes (same
/// derivation as libebur128).
final class LoudnessProcessor {
    let sampleRate: Float

    static let silenceFloor: Float = -80   // display floor, matches FFTProcessor.minDB

    // MARK: - K-weighting biquads

    private struct Biquad {
        let b0, b1, b2, a1, a2: Float
        var z1: Float = 0
        var z2: Float = 0

        // Direct form II transposed.
        mutating func process(_ buffer: inout [Float]) {
            for i in 0..<buffer.count {
                let x = buffer[i]
                let y = b0 * x + z1
                z1 = b1 * x - a1 * y + z2
                z2 = b2 * x - a2 * y
                buffer[i] = y
            }
        }
    }

    private var shelf: Biquad
    private var highpass: Biquad

    // MARK: - Windows / gating state

    private let blockSamples: Int      // 400 ms
    private let hopSamples: Int        // 100 ms
    private let shortTermSamples: Int  // 3 s

    /// Ring buffer of K-weighted samples covering the short-term window (3 s).
    private var ring: [Float]
    private var ringWrite = 0
    private var ringFilled = 0
    private var hopCounter = 0

    /// Mean-square energies of 400 ms gating blocks that passed the −70 LUFS
    /// absolute gate (the relative gate is applied at query time, per spec).
    private var blockEnergies: [Float] = []

    // MARK: - True peak (4× polyphase windowed-sinc interpolator)

    private let tapsPerPhase = 12
    private var firPhases: [[Float]] = []
    private var padded: [Float]
    private var phaseOut: [Float]
    private var prevTail: [Float]
    private(set) var maxTruePeakDB: Float = LoudnessProcessor.silenceFloor

    private var kBuffer: [Float]

    // MARK: - Init

    init(sampleRate: Float) {
        // Clamp against degenerate rates (a dead audio stack reports 0 Hz);
        // a zero-size ring buffer would trap on the modulo below.
        let sampleRate = max(sampleRate, 8000)
        self.sampleRate       = sampleRate
        self.blockSamples     = Int(sampleRate * 0.4)
        self.hopSamples       = Int(sampleRate * 0.1)
        self.shortTermSamples = Int(sampleRate * 3.0)
        self.ring             = [Float](repeating: 0, count: shortTermSamples)
        self.kBuffer          = []
        self.padded           = []
        self.phaseOut         = []
        self.prevTail         = [Float](repeating: 0, count: tapsPerPhase - 1)

        // Stage 1 — high shelf (+~4 dB above ~1.7 kHz), BS.1770 prototype.
        do {
            let f0: Float = 1681.9744509555319
            let gainDB: Float = 3.999843853973347
            let q: Float = 0.7071752369554196
            let k  = tanf(.pi * f0 / sampleRate)
            let vh = powf(10, gainDB / 20)
            let vb = powf(vh, 0.4996667741545416)
            let a0 = 1 + k / q + k * k
            shelf = Biquad(
                b0: (vh + vb * k / q + k * k) / a0,
                b1: 2 * (k * k - vh) / a0,
                b2: (vh - vb * k / q + k * k) / a0,
                a1: 2 * (k * k - 1) / a0,
                a2: (1 - k / q + k * k) / a0
            )
        }

        // Stage 2 — high pass (~38 Hz), BS.1770 prototype.
        do {
            let f0: Float = 38.13547087602444
            let q: Float = 0.5003270373238773
            let k  = tanf(.pi * f0 / sampleRate)
            let a0 = 1 + k / q + k * k
            highpass = Biquad(
                b0: 1, b1: -2, b2: 1,
                a1: 2 * (k * k - 1) / a0,
                a2: (1 - k / q + k * k) / a0
            )
        }

        // 4× interpolation FIR: Hann-windowed sinc, cut at the original Nyquist,
        // decomposed into 4 polyphase branches of `tapsPerPhase` taps.
        let phases = 4
        let totalTaps = phases * tapsPerPhase
        let center = Float(totalTaps - 1) / 2
        var proto = [Float](repeating: 0, count: totalTaps)
        for n in 0..<totalTaps {
            let t = (Float(n) - center) / Float(phases)
            let sinc: Float = t == 0 ? 1 : sinf(.pi * t) / (.pi * t)
            let window = 0.5 * (1 - cosf(2 * .pi * Float(n) / Float(totalTaps - 1)))
            proto[n] = sinc * window
        }
        for p in 0..<phases {
            // vDSP_conv computes correlation; reverse taps to get convolution.
            var taps = stride(from: p, to: totalTaps, by: phases).map { proto[$0] }
            taps.reverse()
            firPhases.append(taps)
        }
    }

    // MARK: - Reset (new measurement session)

    func reset() {
        shelf.z1 = 0; shelf.z2 = 0
        highpass.z1 = 0; highpass.z2 = 0
        ring = [Float](repeating: 0, count: shortTermSamples)
        ringWrite = 0
        ringFilled = 0
        hopCounter = 0
        blockEnergies.removeAll()
        prevTail = [Float](repeating: 0, count: tapsPerPhase - 1)
        maxTruePeakDB = Self.silenceFloor
    }

    // MARK: - Processing

    /// Feed one capture buffer. Must be called for EVERY buffer so the
    /// 100 ms gating hop stays aligned with real time.
    func process(_ samples: [Float]) {
        updateTruePeak(samples)

        // K-weighting.
        if kBuffer.count != samples.count {
            kBuffer = [Float](repeating: 0, count: samples.count)
        }
        kBuffer.replaceSubrange(0..<samples.count, with: samples)
        shelf.process(&kBuffer)
        highpass.process(&kBuffer)

        // Append to ring buffer.
        for v in kBuffer {
            ring[ringWrite] = v
            ringWrite = (ringWrite + 1) % ring.count
        }
        ringFilled = min(ringFilled + kBuffer.count, ring.count)

        // Emit a 400 ms gating block every 100 ms hop. Block edges land on
        // capture-buffer boundaries (≤ ~85 ms jitter) — irrelevant once the
        // integrated value averages tens of blocks.
        hopCounter += kBuffer.count
        while hopCounter >= hopSamples {
            hopCounter -= hopSamples
            guard ringFilled >= blockSamples else { continue }
            let energy = meanSquare(last: blockSamples)
            let loudness = lufs(fromMeanSquare: energy)
            if loudness > -70 {                    // absolute gate
                blockEnergies.append(energy)
            }
        }
    }

    // MARK: - Meter readouts

    /// Momentary loudness — trailing 400 ms.
    var momentary: Float {
        guard ringFilled >= blockSamples else { return Self.silenceFloor }
        return max(lufs(fromMeanSquare: meanSquare(last: blockSamples)), Self.silenceFloor)
    }

    /// Short-term loudness — trailing 3 s.
    var shortTerm: Float {
        guard ringFilled >= shortTermSamples else { return Self.silenceFloor }
        return max(lufs(fromMeanSquare: meanSquare(last: shortTermSamples)), Self.silenceFloor)
    }

    /// Gated integrated loudness over the whole session (BS.1770 two-stage gate).
    var integrated: Float {
        guard !blockEnergies.isEmpty else { return Self.silenceFloor }
        var sum: Float = 0
        vDSP_sve(blockEnergies, 1, &sum, vDSP_Length(blockEnergies.count))
        let meanAll = sum / Float(blockEnergies.count)

        // Relative gate: −10 LU below the mean of absolute-gated blocks.
        let relThresholdEnergy = meanAll * powf(10, -1.0)   // −10 dB in energy
        var gatedSum: Float = 0
        var gatedCount = 0
        for e in blockEnergies where e > relThresholdEnergy {
            gatedSum += e
            gatedCount += 1
        }
        guard gatedCount > 0 else { return Self.silenceFloor }
        return max(lufs(fromMeanSquare: gatedSum / Float(gatedCount)), Self.silenceFloor)
    }

    // MARK: - Helpers

    private func lufs(fromMeanSquare ms: Float) -> Float {
        -0.691 + 10 * log10f(max(ms, 1e-12))
    }

    /// Mean square of the last `n` samples in the ring buffer (two segments).
    private func meanSquare(last n: Int) -> Float {
        let count = ring.count
        var sum: Float = 0
        let start = (ringWrite - n + count * 2) % count
        if start + n <= count {
            ring.withUnsafeBufferPointer { p in
                vDSP_svesq(p.baseAddress! + start, 1, &sum, vDSP_Length(n))
            }
        } else {
            let firstLen = count - start
            var s1: Float = 0, s2: Float = 0
            ring.withUnsafeBufferPointer { p in
                vDSP_svesq(p.baseAddress! + start, 1, &s1, vDSP_Length(firstLen))
                vDSP_svesq(p.baseAddress!, 1, &s2, vDSP_Length(n - firstLen))
            }
            sum = s1 + s2
        }
        return sum / Float(n)
    }

    /// 4× oversampled peak (dBTP), held at the session maximum.
    private func updateTruePeak(_ samples: [Float]) {
        var peak: Float = 0
        vDSP_maxmgv(samples, 1, &peak, vDSP_Length(samples.count))

        // Interpolated phases need `tapsPerPhase − 1` samples of history.
        let histLen = tapsPerPhase - 1
        let needed = histLen + samples.count
        if padded.count != needed {
            padded = [Float](repeating: 0, count: needed)
            phaseOut = [Float](repeating: 0, count: samples.count)
        }
        padded.replaceSubrange(0..<histLen, with: prevTail)
        padded.replaceSubrange(histLen..<needed, with: samples)

        for taps in firPhases {
            padded.withUnsafeBufferPointer { input in
                taps.withUnsafeBufferPointer { kernel in
                    phaseOut.withUnsafeMutableBufferPointer { out in
                        vDSP_conv(input.baseAddress!, 1,
                                  kernel.baseAddress!, 1,
                                  out.baseAddress!, 1,
                                  vDSP_Length(samples.count),
                                  vDSP_Length(tapsPerPhase))
                    }
                }
            }
            var phasePeak: Float = 0
            vDSP_maxmgv(phaseOut, 1, &phasePeak, vDSP_Length(samples.count))
            peak = max(peak, phasePeak)
        }

        if samples.count >= histLen {
            prevTail = Array(samples.suffix(histLen))
        }

        let db = 20 * log10f(max(peak, 1e-10))
        maxTruePeakDB = max(maxTruePeakDB, max(db, Self.silenceFloor))
    }
}

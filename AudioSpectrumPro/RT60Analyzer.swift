//  RT60Analyzer.swift
//  AudioSpectrumPro

import Accelerate
import Foundation

// MARK: - Result

/// Per-octave-band RT60 estimate (how acousticians actually report decay).
struct RT60Band: Sendable, Identifiable {
    let centerHz: Float
    let rt60: Float
    let isValid: Bool
    var id: Float { centerHz }

    var label: String {
        centerHz >= 1000 ? "\(Int(centerHz / 1000))k" : "\(Int(centerHz))"
    }
}

struct RT60Result: Sendable {
    /// Estimated RT60 in seconds (extrapolated from T20).
    let rt60: Float
    /// T20 duration in seconds (decay from –5 dB to –25 dB below peak).
    let t20:  Float
    /// RMS envelope in dBFS, one value per 20 ms analysis window.
    let envelope: [Float]
    /// Index into `envelope` where the –5 dB threshold was crossed.
    let idx5: Int
    /// Index into `envelope` where the –25 dB threshold was crossed.
    let idx25: Int
    /// False when decay was too short or too flat to yield a reliable estimate.
    let isValid: Bool
    /// Octave-band breakdown (250 Hz … 4 kHz); empty when broadband failed.
    var bands: [RT60Band] = []
}

// MARK: - State

enum RT60State {
    case idle
    case waitingForImpulse
    case recording(elapsed: Double)
    case analyzing
    case done(RT60Result)
    case failed(String)
}

// MARK: - Analyzer

@MainActor
final class RT60Analyzer: ObservableObject {
    @Published var state: RT60State = .idle

    var sampleRate: Float = 48000

    private let recordDuration: Double = 5.0   // seconds to capture after impulse
    private let impulseThresholdDB: Float = -25 // level that triggers recording

    private var buffer: [Float] = []

    // MARK: - Control

    func startMeasurement() {
        buffer = []
        state  = .waitingForImpulse
    }

    func cancelMeasurement() {
        buffer = []
        state  = .idle
    }

    func reset() {
        buffer = []
        state  = .idle
    }

    // MARK: - Sample feed (called from SpectrumViewModel every audio frame)

    func process(samples: [Float]) {
        switch state {
        case .waitingForImpulse:
            var peak: Float = 0
            samples.withUnsafeBufferPointer { ptr in
                vDSP_maxmgv(ptr.baseAddress!, 1, &peak, vDSP_Length(samples.count))
            }
            let peakDB = 20.0 * log10f(max(peak, 1e-10))
            if peakDB >= impulseThresholdDB {
                buffer = samples
                state  = .recording(elapsed: Double(samples.count) / Double(sampleRate))
            }

        case .recording:
            buffer.append(contentsOf: samples)
            let elapsed = Double(buffer.count) / Double(sampleRate)
            state = .recording(elapsed: elapsed)
            if elapsed >= recordDuration {
                beginAnalysis()
            }

        default:
            break
        }
    }

    // MARK: - Analysis

    private func beginAnalysis() {
        state = .analyzing
        let captured  = buffer
        let sr        = sampleRate
        buffer = []

        Task.detached(priority: .userInitiated) { [weak self] in
            let result = Self.compute(samples: captured, sampleRate: sr)
            await MainActor.run { [weak self] in
                guard let self else { return }
                if result.isValid {
                    self.state = .done(result)
                } else {
                    self.state = .failed("Decay too short — make a louder impulse or check room conditions.")
                }
            }
        }
    }

    // MARK: - Computation (nonisolated — pure math, no actor state)

    /// Octave-band centers for the per-band breakdown.
    nonisolated private static let bandCenters: [Float] = [250, 500, 1000, 2000, 4000]

    nonisolated static func compute(samples: [Float], sampleRate: Float) -> RT60Result {
        let envelope = makeEnvelope(samples, sampleRate: sampleRate)

        guard !envelope.isEmpty else {
            return RT60Result(rt60: 0, t20: 0, envelope: [], idx5: 0, idx25: 0, isValid: false)
        }

        guard let decay = analyzeDecay(envelope: envelope) else {
            return RT60Result(rt60: 0, t20: 0, envelope: envelope,
                              idx5: 0, idx25: 0, isValid: false)
        }

        // Octave-band breakdown: bandpass the capture, re-run the same T20 walk.
        let bands: [RT60Band] = bandCenters.map { center in
            let filtered = bandpass(samples, center: center, sampleRate: sampleRate)
            let bandEnv  = makeEnvelope(filtered, sampleRate: sampleRate)
            if let bandDecay = analyzeDecay(envelope: bandEnv), bandDecay.rt60 > 0.05 {
                return RT60Band(centerHz: center, rt60: bandDecay.rt60, isValid: true)
            }
            return RT60Band(centerHz: center, rt60: 0, isValid: false)
        }

        return RT60Result(rt60: decay.rt60, t20: decay.t20, envelope: envelope,
                          idx5: decay.idx5, idx25: decay.idx25,
                          isValid: decay.rt60 > 0.05, bands: bands)
    }

    /// RMS envelope in dBFS, one value per 20 ms window.
    nonisolated private static func makeEnvelope(_ samples: [Float],
                                                 sampleRate: Float) -> [Float] {
        let windowSize = max(1, Int(sampleRate * 0.020))
        var envelope: [Float] = []
        envelope.reserveCapacity(samples.count / windowSize + 1)

        var i = 0
        while i + windowSize <= samples.count {
            var sumSq: Float = 0
            samples.withUnsafeBufferPointer { ptr in
                vDSP_svesq(ptr.baseAddress! + i, 1, &sumSq, vDSP_Length(windowSize))
            }
            let rms  = sqrtf(sumSq / Float(windowSize))
            envelope.append(20.0 * log10f(max(rms, 1e-10)))
            i += windowSize
        }
        return envelope
    }

    /// Walk the envelope from its peak to the –5 dB and –25 dB crossings (T20 method).
    nonisolated private static func analyzeDecay(
        envelope: [Float]
    ) -> (rt60: Float, t20: Float, idx5: Int, idx25: Int)? {
        guard let peakDB = envelope.max() else { return nil }

        let threshold5  = peakDB - 5.0
        let threshold25 = peakDB - 25.0

        var idx5: Int?  = nil
        var idx25: Int? = nil

        let peakIdx = envelope.firstIndex(of: peakDB) ?? 0
        for idx in peakIdx..<envelope.count {
            let v = envelope[idx]
            if idx5  == nil && v <= threshold5  { idx5  = idx }
            if idx5  != nil && idx25 == nil && v <= threshold25 { idx25 = idx; break }
        }

        guard let i5 = idx5, let i25 = idx25, i25 > i5 else { return nil }

        let windowDuration: Float = 0.020
        let t20  = Float(i25 - i5) * windowDuration
        return (rt60: t20 * 3.0, t20: t20, idx5: i5, idx25: i25)
    }

    /// One-octave bandpass (RBJ biquad, Q ≈ √2, applied twice for steeper skirts).
    nonisolated private static func bandpass(_ samples: [Float],
                                             center: Float,
                                             sampleRate: Float) -> [Float] {
        let omega = 2 * Float.pi * center / sampleRate
        let q: Float = 1.414   // one octave: f0 / (f0·√2 − f0/√2)
        let alpha = sinf(omega) / (2 * q)
        let a0 = 1 + alpha
        let b0 = alpha / a0
        let b2 = -alpha / a0
        let a1 = -2 * cosf(omega) / a0
        let a2 = (1 - alpha) / a0

        var out = samples
        for _ in 0..<2 {
            var x1: Float = 0, x2: Float = 0, y1: Float = 0, y2: Float = 0
            for i in 0..<out.count {
                let x = out[i]
                let y = b0 * x + b2 * x2 - a1 * y1 - a2 * y2
                x2 = x1; x1 = x
                y2 = y1; y1 = y
                out[i] = y
            }
        }
        return out
    }
}

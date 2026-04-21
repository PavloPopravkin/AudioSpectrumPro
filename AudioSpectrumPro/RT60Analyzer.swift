//  RT60Analyzer.swift
//  AudioSpectrumPro

import Accelerate
import Foundation

// MARK: - Result

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

    nonisolated static func compute(samples: [Float], sampleRate: Float) -> RT60Result {
        let windowSize = max(1, Int(sampleRate * 0.020))  // 20 ms window
        var envelope: [Float] = []
        envelope.reserveCapacity(samples.count / windowSize + 1)

        var i = 0
        while i + windowSize <= samples.count {
            var sumSq: Float = 0
            samples.withUnsafeBufferPointer { ptr in
                vDSP_svesq(ptr.baseAddress! + i, 1, &sumSq, vDSP_Length(windowSize))
            }
            let rms  = sqrtf(sumSq / Float(windowSize))
            let db   = 20.0 * log10f(max(rms, 1e-10))
            envelope.append(db)
            i += windowSize
        }

        guard !envelope.isEmpty else {
            return RT60Result(rt60: 0, t20: 0, envelope: [], idx5: 0, idx25: 0, isValid: false)
        }

        // Find peak
        guard let peakDB = envelope.max() else {
            return RT60Result(rt60: 0, t20: 0, envelope: envelope, idx5: 0, idx25: 0, isValid: false)
        }

        let threshold5  = peakDB - 5.0
        let threshold25 = peakDB - 25.0

        var idx5: Int?  = nil
        var idx25: Int? = nil

        // Walk forward from peak to find –5 dB and –25 dB crossings
        let peakIdx = envelope.firstIndex(of: peakDB) ?? 0
        for idx in peakIdx..<envelope.count {
            let v = envelope[idx]
            if idx5  == nil && v <= threshold5  { idx5  = idx }
            if idx5  != nil && idx25 == nil && v <= threshold25 { idx25 = idx; break }
        }

        guard let i5 = idx5, let i25 = idx25, i25 > i5 else {
            return RT60Result(rt60: 0, t20: 0, envelope: envelope,
                              idx5: idx5 ?? 0, idx25: idx25 ?? 0, isValid: false)
        }

        let windowDuration: Float = 0.020
        let t20  = Float(i25 - i5) * windowDuration
        let rt60 = t20 * 3.0

        return RT60Result(rt60: rt60, t20: t20, envelope: envelope,
                          idx5: i5, idx25: i25, isValid: rt60 > 0.05)
    }
}

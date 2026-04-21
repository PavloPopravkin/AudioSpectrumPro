
//  SpectrumViewModel.swift
//  AudioSpectrumPro

import Combine
import SwiftUI
import AVFoundation

@MainActor
final class SpectrumViewModel: ObservableObject {
    // Spectrum
    @Published var displayData: [Float] = Array(repeating: FFTProcessor.minDB,
                                                count: FFTProcessor.displayBinCount)
    @Published var peaks: [FrequencyPeak] = []
    @Published var recommendations: [EQRecommendation] = []
    // Oscilloscope
    @Published var rawSamples: [Float] = []
    // Tuner
    @Published var tunerReading: TunerReading? = nil
    // Loudness
    @Published var rmsDB: Float = FFTProcessor.minDB
    @Published var truePeakDB: Float = FFTProcessor.minDB
    @Published var loudnessHistory: [Float] = []
    // Sensitivity / gain (1.0 = normal, >1 amplifies, <1 attenuates)
    @Published var sensitivity: Float = 1.0
    // State
    @Published var isRunning = false
    @Published var errorMessage: String?

    private let maxLoudnessHistory = 120

    /// Set by TunerView settings; not @Published to avoid unnecessary redraws.
    var referenceA4: Float = 440.0
    /// Noise gate threshold in dB; set by TunerView settings.
    var noiseGateDB: Float = -50.0

    private var audioEngine   = AudioEngine()
    // Kept in sync with the hardware sample rate; not used for processing
    // (the detached task owns its own FFTProcessor instance).
    private var fftProcessor  = FFTProcessor()
    private var volumeObserver: NSKeyValueObservation?
    /// Reference to the background processing task so we can cancel it on stop().
    private var processingTask: Task<Void, Never>?

    /// RT60 reverberation time analyzer — fed live samples every audio frame.
    let rt60Analyzer = RT60Analyzer()

    // MARK: - Start / Stop

    func start() {
        guard !isRunning else { return }
        audioEngine  = AudioEngine()
        isRunning    = true
        errorMessage = nil

        // Phase 1 — start the engine on MainActor (permission prompt, session setup).
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.audioEngine.start()
                self.startVolumeObservation()

                // Keep the stored processor in sync with the hardware sample rate.
                let actualRate = Float(self.audioEngine.sampleRate)
                if actualRate != self.fftProcessor.sampleRate {
                    self.fftProcessor = FFTProcessor(fftSize: self.fftProcessor.fftSize,
                                                     sampleRate: actualRate)
                }
                self.rt60Analyzer.sampleRate = actualRate
            } catch {
                self.errorMessage = error.localizedDescription
                self.isRunning    = false
                return
            }

            // Phase 2 — hand off the sample stream to a background task.
            // The detached task owns its own FFTProcessor and smoothing buffer,
            // keeping ALL heavy computation off the main thread.
            let stream     = self.audioEngine.sampleStream
            let sampleRate = Float(self.audioEngine.sampleRate)

            self.processingTask = Task.detached(priority: .userInitiated) { [weak self] in
                guard let self else { return }

                let fft      = FFTProcessor(sampleRate: sampleRate)
                let detector = PeakDetector()
                var smoothed = [Float](repeating: FFTProcessor.minDB,
                                       count: FFTProcessor.displayBinCount)
                let alpha: Float = 0.3
                var frame    = 0

                for await samples in stream {
                    guard !Task.isCancelled else { break }
                    frame += 1

                    // Read actor-isolated settings in a single MainActor hop.
                    let snap = await MainActor.run { [weak self] () -> (Float, Float, Float)? in
                        guard let self else { return nil }
                        return (self.sensitivity, self.referenceA4, self.noiseGateDB)
                    }
                    guard let (sens, refA4, gateDB) = snap else { break }

                    // ── All heavy work runs on the background thread ──────────
                    let gained = sens == 1.0 ? samples : samples.map { $0 * sens }
                    let rawFFT = fft.process(gained)
                    let tuner  = fft.detectPitch(rawFFT, referenceA4: refA4,
                                                 noiseGateDB: gateDB)

                    // ── Tuner + RT60: push every frame ───────────────────────
                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        self.tunerReading = tuner
                        self.rt60Analyzer.process(samples: gained)
                    }

                    // ── Spectrum / oscilloscope / loudness: every 2nd frame ───
                    guard frame.isMultiple(of: 2) else { continue }

                    let log = fft.mapToLogScale(rawFFT)
                    for i in 0..<min(log.count, smoothed.count) {
                        smoothed[i] = alpha * log[i] + (1.0 - alpha) * smoothed[i]
                    }
                    let detectedPeaks = detector.detect(fftData: rawFFT,
                                                        sampleRate: fft.sampleRate,
                                                        fftSize: fft.fftSize)
                    let rms        = fft.rmsDB(gained)
                    let peakDB     = fft.truePeakDB(gained)
                    let smoothSnap = smoothed          // value copy for MainActor

                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        self.displayData     = smoothSnap
                        self.peaks           = detectedPeaks
                        self.recommendations = self.makeRecommendations(from: detectedPeaks)
                        self.rawSamples      = gained
                        self.rmsDB           = rms
                        self.truePeakDB      = max(self.truePeakDB * 0.999, peakDB)
                        self.loudnessHistory.append(rms)
                        if self.loudnessHistory.count > self.maxLoudnessHistory {
                            self.loudnessHistory.removeFirst()
                        }
                    }
                }
            }
        }
    }

    func stop() {
        audioEngine.stop()
        processingTask?.cancel()
        processingTask = nil
        stopVolumeObservation()
        isRunning = false
    }

    // MARK: - Volume-button sensitivity

    private func startVolumeObservation() {
        volumeObserver = AVAudioSession.sharedInstance()
            .observe(\.outputVolume, options: [.old, .new]) { [weak self] _, change in
                guard let self = self,
                      let oldVol = change.oldValue,
                      let newVol = change.newValue else { return }
                let delta = newVol - oldVol
                guard abs(delta) > 0.001 else { return }
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    let updated = self.sensitivity + delta * 3.0
                    self.sensitivity = max(0.1, min(8.0, updated))
                }
            }
    }

    private func stopVolumeObservation() {
        volumeObserver?.invalidate()
        volumeObserver = nil
    }

    // MARK: - EQ Recommendations (pure computation — called from background-safe context)

    nonisolated func makeRecommendations(from peaks: [FrequencyPeak]) -> [EQRecommendation] {
        guard !peaks.isEmpty else {
            return [EQRecommendation(frequency: 0, cutDB: 0, urgency: .ok,
                                     bandwidthQ: 0, band: .mid)]
        }
        return peaks.map { peak in
            let cutDB      = min(peak.prominence * 0.75, 12.0)
            let urgency: EQRecommendation.Urgency = peak.prominence >= 18 ? .critical : .warning
            let bandwidthQ: Float = peak.prominence >= 15 ? 2.0 : 1.4
            return EQRecommendation(frequency: peak.frequency, cutDB: cutDB,
                                    urgency: urgency, bandwidthQ: bandwidthQ,
                                    band: FrequencyBand.from(peak.frequency))
        }
        .sorted { $0.urgency.sortPriority > $1.urgency.sortPriority }
    }
}

// MARK: - Preview

#if DEBUG
extension SpectrumViewModel {
    static var preview: SpectrumViewModel {
        let vm    = SpectrumViewModel()
        let count = FFTProcessor.displayBinCount

        vm.displayData = (0..<count).map { i in
            let t      = Float(i) / Float(count - 1)
            let floor: Float = -55 + 10 * (1 - t)
            let peak1  = 30 * expf(-0.5 * powf((Float(i) - 90)  / 6, 2))
            let peak2  = 18 * expf(-0.5 * powf((Float(i) - 160) / 5, 2))
            let noise  = Float.random(in: -2...2)
            return min(floor + peak1 + peak2 + noise, FFTProcessor.maxDB)
        }
        vm.peaks = [
            FrequencyPeak(frequency: 820,  magnitude: -15, prominence: 22),
            FrequencyPeak(frequency: 2400, magnitude: -25, prominence: 13)
        ]
        vm.recommendations = [
            EQRecommendation(frequency: 820,  cutDB: 8, urgency: .critical,
                             bandwidthQ: 2.0, band: .lowMid),
            EQRecommendation(frequency: 2400, cutDB: 4, urgency: .warning,
                             bandwidthQ: 1.4, band: .presence)
        ]
        return vm
    }
}
#endif

extension EQRecommendation.Urgency {
    var sortPriority: Int {
        switch self {
        case .critical: return 2
        case .warning:  return 1
        case .ok:       return 0
        }
    }
}

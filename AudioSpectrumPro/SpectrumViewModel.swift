
//  SpectrumViewModel.swift
//  AudioSpectrumPro

import Combine
import SwiftUI
import AVFoundation

@MainActor
final class SpectrumViewModel: ObservableObject {
    // Spectrum
    @Published var displayData: [Float] = Array(repeating: FFTProcessor.minDB, count: FFTProcessor.displayBinCount)
    @Published var peaks: [FrequencyPeak] = []
    @Published var recommendations: [EQRecommendation] = []
    // Spectrograph
    @Published var waterfallRows: [[Float]] = []
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

    private let maxWaterfallRows = 60
    private let maxLoudnessHistory = 120

    /// Set by TunerView settings; not @Published to avoid unnecessary redraws.
    var referenceA4: Float = 440.0
    /// Noise gate threshold in dB; set by TunerView settings.
    var noiseGateDB: Float = -50.0

    private var audioEngine = AudioEngine()
    private let fftProcessor = FFTProcessor()
    private let peakDetector = PeakDetector()
    private var volumeObserver: NSKeyValueObservation?

    // Exponential moving average smoothing (alpha: 0 = no update, 1 = no smoothing)
    private let smoothingAlpha: Float = 0.3
    private var smoothedData: [Float] = Array(repeating: FFTProcessor.minDB, count: FFTProcessor.displayBinCount)

    func start() {
        guard !isRunning else { return }
        // Recreate engine so the AsyncStream is fresh after a previous stop
        audioEngine = AudioEngine()
        isRunning = true
        errorMessage = nil

        Task {
            do {
                try await audioEngine.start()
                startVolumeObservation()
                for await samples in audioEngine.sampleStream {
                    // Apply software gain for sensitivity control
                    let gainedSamples: [Float] = sensitivity == 1.0
                        ? samples
                        : samples.map { $0 * sensitivity }
                    let rawFFT = fftProcessor.process(gainedSamples)
                    let logScaled = fftProcessor.mapToLogScale(rawFFT)
                    smooth(logScaled)

                    let detectedPeaks = peakDetector.detect(
                        fftData: rawFFT,
                        sampleRate: fftProcessor.sampleRate,
                        fftSize: fftProcessor.fftSize
                    )

                    // Spectrum
                    displayData = smoothedData
                    peaks = detectedPeaks
                    recommendations = makeRecommendations(from: detectedPeaks)

                    // Spectrograph waterfall
                    var newRows = waterfallRows
                    newRows.insert(smoothedData, at: 0)
                    if newRows.count > maxWaterfallRows { newRows = Array(newRows.prefix(maxWaterfallRows)) }
                    waterfallRows = newRows

                    // Oscilloscope
                    rawSamples = gainedSamples

                    // Tuner
                    tunerReading = fftProcessor.detectPitch(rawFFT, referenceA4: referenceA4, noiseGateDB: noiseGateDB)

                    // Loudness
                    let rms = fftProcessor.rmsDB(gainedSamples)
                    let peak = fftProcessor.truePeakDB(gainedSamples)
                    rmsDB = rms
                    truePeakDB = max(truePeakDB * 0.999, peak)   // slow decay for true peak hold
                    var newHistory = loudnessHistory
                    newHistory.append(rms)
                    if newHistory.count > maxLoudnessHistory { newHistory = Array(newHistory.dropFirst()) }
                    loudnessHistory = newHistory
                }
            } catch {
                errorMessage = error.localizedDescription
                isRunning = false
            }
        }
    }

    func stop() {
        audioEngine.stop()
        stopVolumeObservation()
        isRunning = false
    }

    // MARK: - Volume-button sensitivity

    private func startVolumeObservation() {
        // KVO on outputVolume — fires when the hardware volume buttons are pressed.
        // Each press changes volume by ~0.0625; we map that delta to sensitivity instead.
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

    // MARK: - Private

    private func smooth(_ newData: [Float]) {
        let count = min(newData.count, smoothedData.count)
        let alpha = smoothingAlpha
        let oneMinusAlpha = 1.0 - alpha
        for i in 0..<count {
            smoothedData[i] = alpha * newData[i] + oneMinusAlpha * smoothedData[i]
        }
    }

    private func makeRecommendations(from peaks: [FrequencyPeak]) -> [EQRecommendation] {
        guard !peaks.isEmpty else {
            return [EQRecommendation(
                frequency: 0,
                cutDB: 0,
                urgency: .ok,
                bandwidthQ: 0,
                band: .mid
            )]
        }

        return peaks.map { peak in
            let cutDB = min(peak.prominence * 0.75, 12.0)
            let urgency: EQRecommendation.Urgency = peak.prominence >= 18 ? .critical : .warning
            let bandwidthQ: Float = peak.prominence >= 15 ? 2.0 : 1.4

            return EQRecommendation(
                frequency: peak.frequency,
                cutDB: cutDB,
                urgency: urgency,
                bandwidthQ: bandwidthQ,
                band: FrequencyBand.from(peak.frequency)
            )
        }
        .sorted { $0.urgency.sortPriority > $1.urgency.sortPriority }
    }
}

#if DEBUG
extension SpectrumViewModel {
    /// Pre-populated instance for SwiftUI previews — no microphone needed.
    static var preview: SpectrumViewModel {
        let vm = SpectrumViewModel()
        let count = FFTProcessor.displayBinCount

        // Simulate a spectrum: noise floor with two prominent peaks
        vm.displayData = (0..<count).map { i in
            let t = Float(i) / Float(count - 1)
            // Noise floor that rolls off at high frequencies
            let floor: Float = -55 + 10 * (1 - t)
            // Peak at ~820 Hz (bin ≈ 90) and ~2.4 kHz (bin ≈ 160)
            let peak1 = 30 * expf(-0.5 * powf((Float(i) - 90) / 6, 2))
            let peak2 = 18 * expf(-0.5 * powf((Float(i) - 160) / 5, 2))
            let noise = Float.random(in: -2...2)
            return min(floor + peak1 + peak2 + noise, FFTProcessor.maxDB)
        }

        vm.peaks = [
            FrequencyPeak(frequency: 820,  magnitude: -15, prominence: 22),
            FrequencyPeak(frequency: 2400, magnitude: -25, prominence: 13)
        ]

        vm.recommendations = [
            EQRecommendation(
                frequency: 820, cutDB: 8, urgency: .critical, bandwidthQ: 2.0,
                band: .lowMid
            ),
            EQRecommendation(
                frequency: 2400, cutDB: 4, urgency: .warning, bandwidthQ: 1.4,
                band: .presence
            )
        ]

        return vm
    }
}
#endif

extension EQRecommendation.Urgency {
    var sortPriority: Int {
        switch self {
        case .critical: return 2
        case .warning: return 1
        case .ok: return 0
        }
    }
}

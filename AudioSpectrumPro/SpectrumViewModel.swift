
//  SpectrumViewModel.swift
//  AudioSpectrumPro

import Combine
import SwiftUI
import AVFoundation
import UIKit

@MainActor
final class SpectrumViewModel: ObservableObject {
    enum AnalyzerError: Equatable {
        case microphonePermission
        case other(String)
    }

    // Spectrum
    @Published var displayData: [Float] = Array(repeating: FFTProcessor.minDB,
                                                count: FFTProcessor.displayBinCount)
    @Published var peaks: [FrequencyPeak] = []
    @Published var recommendations: [EQRecommendation] = []
    // Peak hold (max envelope; lives here so it survives mode switches
    // and is available to the share snapshot)
    @Published var peakHoldEnabled = false
    @Published var peakHoldTrace: [Float] = []
    // Oscilloscope
    @Published var rawSamples: [Float] = []
    // Tuner
    @Published var tunerReading: TunerReading? = nil
    // Loudness (BS.1770)
    @Published var rmsDB: Float = FFTProcessor.minDB
    @Published var truePeakDB: Float = FFTProcessor.minDB   // dBTP, session max
    @Published var lufsMomentary: Float = FFTProcessor.minDB
    @Published var lufsShortTerm: Float = FFTProcessor.minDB
    @Published var lufsIntegrated: Float = FFTProcessor.minDB
    @Published var loudnessHistory: [Float] = []             // momentary LUFS
    // Sensitivity / gain (1.0 = normal, >1 amplifies, <1 attenuates)
    @Published var sensitivity: Float = 1.0
    // State
    @Published var isRunning = false
    @Published var error: AnalyzerError?

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

    /// True while an audio-session interruption paused a running capture, so we
    /// know to resume once it ends.
    private var resumeAfterInterruption = false

    // MARK: - Lifecycle

    init() {
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(handleInterruption(_:)),
                       name: AVAudioSession.interruptionNotification, object: nil)
        nc.addObserver(self, selector: #selector(handleRouteChange(_:)),
                       name: AVAudioSession.routeChangeNotification, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Audio-session interruptions & route changes

    /// Phone calls, Siri, alarms, backgrounding. Pause a running capture on
    /// `.began` (releases the mic, re-enables the idle timer), auto-resume on
    /// `.ended` when the system allows it and the app is foregrounded.
    @objc private nonisolated func handleInterruption(_ n: Notification) {
        guard let info = n.userInfo,
              let raw  = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            switch type {
            case .began:
                if self.isRunning {
                    self.resumeAfterInterruption = true
                    self.stop()
                }
            case .ended:
                let shouldResume = (info[AVAudioSessionInterruptionOptionKey] as? UInt)
                    .map { AVAudioSession.InterruptionOptions(rawValue: $0).contains(.shouldResume) } ?? false
                let wasPaused = self.resumeAfterInterruption
                self.resumeAfterInterruption = false
                if wasPaused, shouldResume,
                   UIApplication.shared.applicationState == .active {
                    self.start()
                }
            @unknown default:
                break
            }
        }
    }

    /// Restart only when a device we were using is removed (headphones/Bluetooth
    /// unplugged): the hardware sample rate can change and the tap can drop.
    /// `.oldDeviceUnavailable` is never posted by our own session activation, so
    /// this can't loop; a full restart rebuilds capture + DSP at the new rate.
    @objc private nonisolated func handleRouteChange(_ n: Notification) {
        guard let info = n.userInfo,
              let raw  = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw),
              reason == .oldDeviceUnavailable else { return }

        Task { @MainActor [weak self] in
            guard let self, self.isRunning else { return }
            self.stop()
            self.start()
        }
    }

    // MARK: - Start / Stop

    func start() {
        guard !isRunning else { return }
        audioEngine  = AudioEngine()
        isRunning    = true
        error        = nil
        // Fresh measurement session
        truePeakDB      = FFTProcessor.minDB
        lufsMomentary   = FFTProcessor.minDB
        lufsShortTerm   = FFTProcessor.minDB
        lufsIntegrated  = FFTProcessor.minDB
        loudnessHistory = []
        peakHoldTrace   = []

        // Phase 1 — start the engine on MainActor (permission prompt, session setup).
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.audioEngine.start()
                // stop() may have run during the permission/session await — bail
                // before disabling the idle timer or spawning the processing task.
                guard self.isRunning else {
                    self.audioEngine.stop()
                    return
                }
                self.startVolumeObservation()

                // Keep the stored processor in sync with the hardware sample rate.
                let actualRate = Float(self.audioEngine.sampleRate)
                if actualRate != self.fftProcessor.sampleRate {
                    self.fftProcessor = FFTProcessor(fftSize: self.fftProcessor.fftSize,
                                                     sampleRate: actualRate)
                }
                self.rt60Analyzer.sampleRate = actualRate

                // Measurement in progress — don't let the screen sleep.
                UIApplication.shared.isIdleTimerDisabled = true
            } catch {
                if case AudioEngineError.microphonePermissionDenied = error {
                    self.error = .microphonePermission
                } else {
                    self.error = .other(error.localizedDescription)
                }
                self.isRunning = false
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
                let pitch    = PitchDetector(sampleRate: sampleRate)
                let loudness = LoudnessProcessor(sampleRate: sampleRate)
                var smoothed = [Float](repeating: FFTProcessor.minDB,
                                       count: FFTProcessor.displayBinCount)
                var holdTrace = [Float](repeating: FFTProcessor.minDB,
                                        count: FFTProcessor.displayBinCount)
                var holdWasEnabled = false
                let alpha: Float = 0.3
                var frame    = 0

                for await samples in stream {
                    guard !Task.isCancelled else { break }
                    frame += 1

                    // Read actor-isolated settings in a single MainActor hop.
                    let snap = await MainActor.run { [weak self] () -> (Float, Float, Float, Bool)? in
                        guard let self else { return nil }
                        return (self.sensitivity, self.referenceA4, self.noiseGateDB,
                                self.peakHoldEnabled)
                    }
                    guard let (sens, refA4, gateDB, holdEnabled) = snap else { break }

                    // ── All heavy work runs on the background thread ──────────
                    let gained = sens == 1.0 ? samples : samples.map { $0 * sens }
                    let rawFFT = fft.process(gained)
                    // YIN pitch detection (time domain) — accurate on low strings
                    // where the FFT-peak method suffers octave errors.
                    let tunerFreq = pitch.detectPitch(gained, noiseGateDB: gateDB)
                    let tuner = tunerFreq.map { TunerReading(frequency: $0, referenceA4: refA4) }
                    // BS.1770 needs every buffer for its 100 ms gating hop.
                    // Measure the true mic signal, NOT the display-gain-boosted
                    // copy — the sensitivity multiplier must not inflate LUFS/dBTP.
                    loudness.process(samples)

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

                    // Peak hold: elementwise max; reset on re-enable.
                    if holdEnabled {
                        if !holdWasEnabled {
                            holdTrace = smoothed
                        } else {
                            for i in 0..<holdTrace.count {
                                holdTrace[i] = max(holdTrace[i], smoothed[i])
                            }
                        }
                    }
                    holdWasEnabled = holdEnabled

                    let detectedPeaks = detector.detect(fftData: rawFFT,
                                                        sampleRate: fft.sampleRate,
                                                        fftSize: fft.fftSize)
                    let rms        = fft.rmsDB(gained)
                    let smoothSnap = smoothed          // value copies for MainActor
                    let holdSnap   = holdEnabled ? holdTrace : []
                    let lufsM      = loudness.momentary
                    let lufsS      = loudness.shortTerm
                    let lufsI      = loudness.integrated
                    let peakTP     = loudness.maxTruePeakDB

                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        self.displayData     = smoothSnap
                        self.peaks           = detectedPeaks
                        self.recommendations = self.makeRecommendations(from: detectedPeaks)
                        self.peakHoldTrace   = holdSnap
                        self.rawSamples      = gained
                        self.rmsDB           = rms
                        self.truePeakDB      = peakTP
                        self.lufsMomentary   = lufsM
                        self.lufsShortTerm   = lufsS
                        self.lufsIntegrated  = lufsI
                        self.loudnessHistory.append(lufsM)
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
        UIApplication.shared.isIdleTimerDisabled = false
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

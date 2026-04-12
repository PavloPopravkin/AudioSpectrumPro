//  ReferenceAudioPlayer.swift
//  AudioSpectrumPro

import AVFoundation

/// Generates and plays a reference sine-wave tone at any frequency.
final class ReferenceAudioPlayer: ObservableObject {
    @Published private(set) var playingFrequency: Float? = nil

    private var engine     = AVAudioEngine()
    private var playerNode = AVAudioPlayerNode()
    /// Incremented on every new play() call so stale completion handlers
    /// from a previous buffer don't clear the current frequency.
    private var generation: Int = 0

    init() {
        setupEngine()
        // Rebuild the engine if the hardware route or sample rate changes
        // (headphones in/out, Bluetooth connect, AirPlay, etc.).
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleConfigChange(_:)),
            name: .AVAudioEngineConfigurationChange,
            object: nil
        )
        // Handle phone calls, Siri, and other session interruptions.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Engine lifecycle

    /// The current hardware sample rate. Valid after the session is active;
    /// falls back to 44100 when called too early.
    private var hardwareSampleRate: Double {
        let r = AVAudioSession.sharedInstance().sampleRate
        return r > 0 ? r : 44100
    }

    /// Builds (or rebuilds) the AVAudioEngine graph with the correct sample rate.
    private func setupEngine() {
        if engine.isRunning { engine.stop() }

        engine     = AVAudioEngine()
        playerNode = AVAudioPlayerNode()

        let rate   = hardwareSampleRate
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)

        do {
            try engine.start()
        } catch {
            // Will retry automatically on the next play() call.
        }
    }

    @objc private func handleConfigChange(_ notification: Notification) {
        // Route changed (e.g. headphones plugged in) — rebuild with new rate.
        DispatchQueue.main.async { [weak self] in self?.setupEngine() }
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard
            let info = notification.userInfo,
            let raw  = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: raw)
        else { return }

        if type == .ended {
            try? AVAudioSession.sharedInstance().setActive(true)
            DispatchQueue.main.async { [weak self] in self?.setupEngine() }
        } else {
            DispatchQueue.main.async { [weak self] in self?.playingFrequency = nil }
        }
    }

    // MARK: - Playback

    /// Play a tone at `frequency` Hz for `duration` seconds.
    func play(frequency: Float, duration: Double = 2.5) {
        // Re-activate the session — it may have been deactivated when the
        // microphone engine stopped (AudioEngine.stop calls setActive(false)).
        try? AVAudioSession.sharedInstance().setActive(true)

        // Restart the engine if it died (session deactivated, config change, etc.)
        if !engine.isRunning { setupEngine() }
        guard engine.isRunning else { return }

        playerNode.stop()

        let rate       = hardwareSampleRate
        let frameCount = AVAudioFrameCount(rate * duration)
        guard
            let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
            let data   = buffer.floatChannelData?[0]
        else { return }

        buffer.frameLength = frameCount
        let sr       = Float(rate)
        let twoPiF   = 2.0 * Float.pi * frequency
        let totalDur = Float(duration)

        // ADSR envelope
        // attack = 25 ms: long enough to eliminate the onset click on desktop
        // speakers while still feeling instantaneous to the player.
        let attack:      Float = 0.025
        let decay:       Float = 0.06
        let sustain:     Float = 0.65
        let release:     Float = 0.6
        let releaseStart       = totalDur - release

        for i in 0..<Int(frameCount) {
            let t = Float(i) / sr
            let env: Float
            switch t {
            case ..<attack:
                env = t / attack
            case attack..<(attack + decay):
                env = 1.0 - (1.0 - sustain) * (t - attack) / decay
            case (attack + decay)..<releaseStart:
                env = sustain
            case releaseStart..<totalDur:
                env = sustain * (1.0 - (t - releaseStart) / release)
            default:
                env = 0
            }
            data[i] = sinf(twoPiF * t) * env * 0.45
        }

        generation += 1
        let myGeneration = generation
        playingFrequency = frequency

        playerNode.scheduleBuffer(buffer, at: nil, options: [], completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.generation == myGeneration else { return }
                self.playingFrequency = nil
            }
        })
        playerNode.play()
    }

    func stop() {
        playerNode.stop()
        playingFrequency = nil
    }
}

//  SignalGenerator.swift
//  AudioSpectrumPro

import AVFoundation

enum SignalType: String, CaseIterable, Identifiable {
    case pinkNoise  = "pink"
    case whiteNoise = "white"
    case sineSweep  = "sweep"
    case fixedTone  = "tone"
    var id: String { rawValue }
}

@MainActor
final class SignalGenerator: ObservableObject {
    @Published var isPlaying     = false
    @Published var signalType    = SignalType.pinkNoise
    @Published var toneFrequency : Float  = 1000.0
    @Published var sweepDuration : Double = 10.0

    private var engine     = AVAudioEngine()
    private var playerNode = AVAudioPlayerNode()
    private var sweepTask  : Task<Void, Never>?

    init() {
        setupEngine()
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleConfigChange(_:)),
            name: .AVAudioEngineConfigurationChange, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance())
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    // MARK: - Engine

    private var hardwareSampleRate: Double {
        let r = AVAudioSession.sharedInstance().sampleRate
        return r > 0 ? r : 44100
    }

    private func setupEngine() {
        if engine.isRunning { engine.stop() }
        engine     = AVAudioEngine()
        playerNode = AVAudioPlayerNode()
        let rate   = hardwareSampleRate
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1) else { return }
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        try? engine.start()
    }

    @objc private nonisolated func handleConfigChange(_ n: Notification) {
        Task { @MainActor [weak self] in self?.setupEngine() }
    }

    @objc private nonisolated func handleInterruption(_ n: Notification) {
        guard let info = n.userInfo,
              let raw  = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        if type == .ended {
            try? AVAudioSession.sharedInstance().setActive(true)
            Task { @MainActor [weak self] in self?.setupEngine() }
        } else {
            Task { @MainActor [weak self] in
                self?.sweepTask?.cancel()
                self?.isPlaying = false
            }
        }
    }

    // MARK: - Playback

    func togglePlayback() { isPlaying ? stopPlayback() : startPlayback() }

    func startPlayback() {
        try? AVAudioSession.sharedInstance().setActive(true)
        if !engine.isRunning { setupEngine() }
        guard engine.isRunning else { return }
        playerNode.stop()
        isPlaying = true

        let rate = hardwareSampleRate

        switch signalType {
        case .pinkNoise, .whiteNoise:
            if let buf = Self.makeNoiseBuffer(type: signalType, sampleRate: rate) {
                playerNode.scheduleBuffer(buf, at: nil, options: .loops)
                playerNode.play()
            } else { isPlaying = false }

        case .fixedTone:
            if let buf = Self.makeToneBuffer(frequency: toneFrequency, sampleRate: rate) {
                playerNode.scheduleBuffer(buf, at: nil, options: .loops)
                playerNode.play()
            } else { isPlaying = false }

        case .sineSweep:
            let node = playerNode
            let dur  = sweepDuration
            node.play()
            sweepTask = Task.detached(priority: .userInitiated) { [weak self] in
                while !Task.isCancelled {
                    guard let buf = Self.makeSweepBuffer(duration: dur, sampleRate: rate) else { break }
                    await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                        node.scheduleBuffer(buf, at: nil, options: []) { c.resume() }
                    }
                    guard !Task.isCancelled else { break }
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
                await MainActor.run { [weak self] in self?.isPlaying = false }
            }
        }
    }

    func stopPlayback() {
        sweepTask?.cancel()
        sweepTask = nil
        playerNode.stop()
        isPlaying = false
    }

    // MARK: - Buffer factories (nonisolated — pure computation, no actor state)

    nonisolated static func makeNoiseBuffer(type: SignalType, sampleRate: Double) -> AVAudioPCMBuffer? {
        let frameCount = max(Int(sampleRate), 4096)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)),
              let data   = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(frameCount)

        if type == .whiteNoise {
            for i in 0..<frameCount { data[i] = Float.random(in: -0.35...0.35) }
        } else {
            // Paul Kellett's refined pink noise algorithm (7-state IIR)
            var b0: Float=0, b1: Float=0, b2: Float=0
            var b3: Float=0, b4: Float=0, b5: Float=0, b6: Float=0
            for i in 0..<frameCount {
                let w = Float.random(in: -1.0...1.0)
                b0 = 0.99886*b0 + w*0.0555179
                b1 = 0.99332*b1 + w*0.0750759
                b2 = 0.96900*b2 + w*0.1538520
                b3 = 0.86650*b3 + w*0.3104856
                b4 = 0.55000*b4 + w*0.5329522
                b5 = -0.7616*b5 - w*0.0168980
                data[i] = max(-1, min(1, (b0+b1+b2+b3+b4+b5+b6 + w*0.5362) * 0.11))
                b6 = w * 0.115926
            }
        }
        return buffer
    }

    nonisolated static func makeToneBuffer(frequency: Float, sampleRate: Double) -> AVAudioPCMBuffer? {
        guard frequency > 0 else { return nil }
        // Buffer length = integer multiple of the period → seamless looping
        let periodSamples = sampleRate / Double(frequency)
        let periods       = max(1, Int((sampleRate * 2.0) / periodSamples))
        let frameCount    = Int(periodSamples.rounded()) * periods
        guard frameCount > 0,
              let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)),
              let data   = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let phaseInc = 2.0 * Float.pi * frequency / Float(sampleRate)
        var phase: Float = 0
        for i in 0..<frameCount {
            data[i] = sinf(phase) * 0.40
            phase  += phaseInc
            if phase > 2.0 * .pi { phase -= 2.0 * .pi }
        }
        return buffer
    }

    nonisolated static func makeSweepBuffer(duration: Double, sampleRate: Double) -> AVAudioPCMBuffer? {
        let frameCount = Int(sampleRate * duration)
        guard frameCount > 0,
              let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)),
              let data   = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(frameCount)

        let f1: Float = 20, f2: Float = 20000
        let T         = Float(duration)
        let R         = logf(f2 / f1)
        let aFrames   = min(Int(sampleRate * 0.1), frameCount / 10)
        let rFrames   = min(Int(sampleRate * 0.3), frameCount / 4)
        let rStart    = frameCount - rFrames

        for i in 0..<frameCount {
            let t   = Float(i) / Float(sampleRate)
            let phi = 2.0 * Float.pi * f1 * T / R * (expf(R * t / T) - 1.0)
            let env: Float = i < aFrames   ? Float(i) / Float(aFrames)
                           : i >= rStart   ? Float(frameCount - i) / Float(rFrames)
                           : 1.0
            data[i] = sinf(phi) * env * 0.45
        }
        return buffer
    }
}

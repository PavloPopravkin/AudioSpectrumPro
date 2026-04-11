
//  AudioEngine.swift
//  AudioSpectrumPro

import AVFoundation

final class AudioEngine {
    private let engine = AVAudioEngine()
    private var continuation: AsyncStream<[Float]>.Continuation?

    /// Stream of PCM sample buffers from the microphone.
    let sampleStream: AsyncStream<[Float]>

    init() {
        var capturedContinuation: AsyncStream<[Float]>.Continuation?
        sampleStream = AsyncStream { continuation in
            capturedContinuation = continuation
        }
        self.continuation = capturedContinuation
    }

    /// Request microphone permission, configure the audio session, and start the engine.
    func start() async throws {
        let granted = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        guard granted else {
            throw AudioEngineError.microphonePermissionDenied
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        let bufferSize: AVAudioFrameCount = 4096

        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak self] buffer, _ in
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let count = Int(buffer.frameLength)
            let samples = Array(UnsafeBufferPointer(start: channelData, count: count))
            self?.continuation?.yield(samples)
        }

        try engine.start()
    }

    /// The actual hardware sample rate — available after `start()` returns.
    var sampleRate: Double {
        engine.inputNode.outputFormat(forBus: 0).sampleRate
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        continuation?.finish()
        try? AVAudioSession.sharedInstance().setActive(false)
    }
}

enum AudioEngineError: LocalizedError {
    case microphonePermissionDenied

    var errorDescription: String? {
        "Нет доступа к микрофону. Разрешите доступ в Настройках → Конфиденциальность."
    }
}

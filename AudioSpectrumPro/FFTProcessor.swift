
//  FFTProcessor.swift
//  AudioSpectrumPro

import Accelerate
import Foundation

final class FFTProcessor {
    let fftSize: Int
    let sampleRate: Float

    // Display range
    static let minFrequency: Float = 50
    static let maxFrequency: Float = 16000
    static let displayBinCount = 256

    // dB display range
    static let minDB: Float = -80
    static let maxDB: Float = 0

    private let halfSize: Int
    private let log2n: vDSP_Length
    private let fftSetup: FFTSetup
    private var hannWindow: [Float]

    // Pre-allocated work buffers — reused on every call to eliminate per-frame
    // heap allocations that were causing memory pressure and eventual OOM kills.
    private var windowed:   [Float]
    private var realPart:   [Float]
    private var imagPart:   [Float]
    private var magnitudes: [Float]
    private var resultBuf:  [Float]
    private var logBuf:     [Float]

    init(fftSize: Int = 4096, sampleRate: Float = 44100) {
        self.fftSize  = fftSize
        self.sampleRate = sampleRate
        self.halfSize = fftSize / 2
        self.log2n    = vDSP_Length(log2(Double(fftSize)))
        self.fftSetup = vDSP_create_fftsetup(vDSP_Length(log2(Double(fftSize))),
                                              FFTRadix(kFFTRadix2))!
        self.hannWindow  = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&hannWindow, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))

        self.windowed   = [Float](repeating: 0,              count: fftSize)
        self.realPart   = [Float](repeating: 0,              count: fftSize / 2)
        self.imagPart   = [Float](repeating: 0,              count: fftSize / 2)
        self.magnitudes = [Float](repeating: 0,              count: fftSize / 2)
        self.resultBuf  = [Float](repeating: FFTProcessor.minDB, count: fftSize / 2)
        self.logBuf     = [Float](repeating: FFTProcessor.minDB, count: FFTProcessor.displayBinCount)
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    /// Returns raw FFT magnitude bins in dB (halfSize values, linear frequency spacing).
    /// Uses pre-allocated internal buffers — no heap allocation on the hot path.
    func process(_ samples: [Float]) -> [Float] {
        // Fill windowed buffer; zero-pad if input is shorter than fftSize.
        let copyCount = min(samples.count, fftSize)
        windowed.replaceSubrange(0..<copyCount, with: samples[0..<copyCount])
        if copyCount < fftSize {
            for i in copyCount..<fftSize { windowed[i] = 0 }
        }

        // Apply Hann window to reduce spectral leakage.
        vDSP_vmul(windowed, 1, hannWindow, 1, &windowed, 1, vDSP_Length(fftSize))

        // Forward FFT using split-complex representation.
        realPart.withUnsafeMutableBufferPointer { realPtr in
            imagPart.withUnsafeMutableBufferPointer { imagPtr in
                var sc = DSPSplitComplex(realp: realPtr.baseAddress!,
                                         imagp: imagPtr.baseAddress!)
                windowed.withUnsafeBytes { rawPtr in
                    let complexPtr = rawPtr.baseAddress!
                        .assumingMemoryBound(to: DSPComplex.self)
                    vDSP_ctoz(complexPtr, 2, &sc, 1, vDSP_Length(halfSize))
                }
                vDSP_fft_zrip(fftSetup, &sc, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&sc, 1, &magnitudes, 1, vDSP_Length(halfSize))
            }
        }

        // Scale and convert power to dB, write into pre-allocated result buffer.
        let scale = Float(1.0) / Float(fftSize * fftSize)
        for i in 0..<halfSize {
            let power = magnitudes[i] * scale
            resultBuf[i] = max(10.0 * log10f(max(power, 1e-20)), FFTProcessor.minDB)
        }
        return resultBuf
    }

    /// Maps raw FFT bins to logarithmic frequency display bins (50 Hz – 16 kHz).
    /// Uses a pre-allocated output buffer — no heap allocation on the hot path.
    func mapToLogScale(_ fftData: [Float]) -> [Float] {
        let count      = FFTProcessor.displayBinCount
        let freqPerBin = sampleRate / Float(fftSize)
        let logMin     = log10(FFTProcessor.minFrequency)
        let logMax     = log10(FFTProcessor.maxFrequency)

        for i in 0..<count {
            let t        = Float(i) / Float(count - 1)
            let logFreq  = logMin + t * (logMax - logMin)
            let freq     = powf(10, logFreq)
            let binIndex = Int(freq / freqPerBin)
            logBuf[i]    = fftData[min(binIndex, fftData.count - 1)]
        }
        return logBuf
    }

    /// Convert a display bin index to frequency in Hz.
    func frequency(forDisplayBin bin: Int) -> Float {
        let t      = Float(bin) / Float(FFTProcessor.displayBinCount - 1)
        let logMin = log10(FFTProcessor.minFrequency)
        let logMax = log10(FFTProcessor.maxFrequency)
        return powf(10, logMin + t * (logMax - logMin))
    }

    /// Convert frequency in Hz to a 0...1 normalised X position (log scale).
    static func normalizedX(for frequency: Float) -> Float {
        let logMin = log10(minFrequency)
        let logMax = log10(maxFrequency)
        let logF   = log10(max(frequency, minFrequency))
        return (logF - logMin) / (logMax - logMin)
    }

    /// RMS level in dB from raw PCM samples.
    func rmsDB(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return FFTProcessor.minDB }
        var sumSquares: Float = 0
        vDSP_svesq(samples, 1, &sumSquares, vDSP_Length(samples.count))
        let rms = sqrtf(sumSquares / Float(samples.count))
        return max(20.0 * log10f(max(rms, 1e-10)), FFTProcessor.minDB)
    }

    /// True peak level in dB (maximum absolute sample value).
    func truePeakDB(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return FFTProcessor.minDB }
        var peak: Float = 0
        vDSP_maxmgv(samples, 1, &peak, vDSP_Length(samples.count))
        return max(20.0 * log10f(max(peak, 1e-10)), FFTProcessor.minDB)
    }

    /// Detect dominant pitch using FFT peak with quadratic interpolation.
    func detectPitch(_ fftData: [Float],
                     referenceA4: Float = 440.0,
                     noiseGateDB: Float = -50.0) -> TunerReading? {
        let halfN      = fftData.count
        let freqPerBin = sampleRate / Float(fftSize)

        let minBin = Int(80.0 / freqPerBin)
        let maxBin = min(Int(2000.0 / freqPerBin), halfN - 2)
        guard minBin < maxBin else { return nil }

        var peakBin = minBin
        for i in (minBin + 1)..<maxBin {
            if fftData[i] > fftData[peakBin] { peakBin = i }
        }
        guard fftData[peakBin] > noiseGateDB else { return nil }

        // Quadratic interpolation for sub-bin accuracy.
        let y0 = fftData[peakBin - 1]
        let y1 = fftData[peakBin]
        let y2 = fftData[peakBin + 1]
        let denom      = y0 - 2 * y1 + y2
        let correction: Float = denom != 0 ? 0.5 * (y0 - y2) / denom : 0
        let freq = (Float(peakBin) + correction) * freqPerBin

        return TunerReading(frequency: freq, referenceA4: referenceA4)
    }

    /// Finds the closest string in the given tuning to the detected frequency.
    func nearestString(
        to frequency: Float,
        in tuning: InstrumentTuning,
        referenceA4: Float,
        capo: Int
    ) -> (string: InstrumentString, centsOff: Int)? {
        guard !tuning.strings.isEmpty else { return nil }

        var bestString  = tuning.strings[0]
        var bestCentsOff = Int.max

        for string in tuning.strings {
            let shiftedMidi = string.midiNote + capo
            let targetFreq  = referenceA4 * pow(2.0, Float(shiftedMidi - 69) / 12.0)
            let semitones   = 12.0 * log2(frequency / targetFreq)
            let cents       = Int((semitones * 100.0).rounded())
            if abs(cents) < abs(bestCentsOff) {
                bestCentsOff = cents
                bestString   = string
            }
        }
        return (string: bestString, centsOff: bestCentsOff)
    }
}

struct TunerReading {
    static let noteNames = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]

    let frequency: Float
    let note:      String
    let octave:    Int
    let cents:     Int      // -50…+50

    init(frequency: Float, referenceA4: Float = 440.0) {
        self.frequency = frequency
        guard frequency > 0, referenceA4 > 0 else {
            self.cents = 0; self.note = "–"; self.octave = 4; return
        }
        let semitones = 12.0 * log2(frequency / referenceA4)
        guard semitones.isFinite else {
            self.cents = 0; self.note = "–"; self.octave = 4; return
        }
        let rounded   = semitones.rounded()
        self.cents    = Int(((semitones - rounded) * 100).rounded())
        let index     = ((Int(rounded) % 12) + 12 + 9) % 12
        self.note     = TunerReading.noteNames[index]
        self.octave   = 4 + (Int(rounded) + 9) / 12
    }

    /// 0 = perfectly in tune, 1 = 50 cents off
    var inTuneRatio: Float { 1.0 - abs(Float(cents)) / 50.0 }
}

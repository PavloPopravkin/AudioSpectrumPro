
//  PeakDetector.swift
//  AudioSpectrumPro

import Foundation

struct PeakDetector {
    /// Minimum dB level to consider a bin as a potential peak.
    var minMagnitude: Float = -40.0
    /// Minimum prominence (dB above surroundings) for a peak to be reported.
    var minProminence: Float = 10.0
    /// Half-width of the local maximum window (in raw FFT bins).
    var localWindowBins: Int = 4
    /// Half-width of the prominence measurement window (in raw FFT bins).
    var prominenceWindowBins: Int = 40
    /// Maximum number of peaks to return (sorted by prominence).
    var maxPeaks: Int = 7

    /// Detects prominent spectral peaks from raw FFT dB data.
    /// - Parameters:
    ///   - fftData: Raw FFT dB values (halfSize bins, linear frequency spacing).
    ///   - sampleRate: Sample rate used to compute frequencies.
    ///   - fftSize: FFT size used to compute bin spacing.
    func detect(fftData: [Float], sampleRate: Float, fftSize: Int) -> [FrequencyPeak] {
        let halfN = fftData.count
        let freqPerBin = sampleRate / Float(fftSize)

        // Only look at bins within our display range (50 Hz – 16 kHz)
        let startBin = max(Int(FFTProcessor.minFrequency / freqPerBin), localWindowBins)
        let endBin = min(Int(FFTProcessor.maxFrequency / freqPerBin), halfN - localWindowBins - 1)
        // Guard the closed range below against a short/degenerate FFT buffer.
        guard startBin <= endBin else { return [] }

        var peaks: [FrequencyPeak] = []

        for i in startBin...endBin {
            let mag = fftData[i]
            guard mag > minMagnitude else { continue }

            // Check local maximum within window
            let localRange = max(0, i - localWindowBins)...min(halfN - 1, i + localWindowBins)
            let isLocalMax = localRange.allSatisfy { j in j == i || fftData[j] < mag }
            guard isLocalMax else { continue }

            // Compute prominence: peak height above the minimum in its vicinity
            let promRange = max(0, i - prominenceWindowBins)...min(halfN - 1, i + prominenceWindowBins)
            let surroundMin = promRange.map { fftData[$0] }.min() ?? mag
            let prominence = mag - surroundMin
            guard prominence >= minProminence else { continue }

            let frequency = Float(i) * freqPerBin
            peaks.append(FrequencyPeak(frequency: frequency, magnitude: mag, prominence: prominence))
        }

        // Sort by prominence descending, deduplicate peaks closer than 1/6 octave
        let sorted = peaks.sorted { $0.prominence > $1.prominence }
        return deduplicate(sorted).prefix(maxPeaks).map { $0 }
    }

    // Removes peaks that are within 1/6 octave of a stronger peak.
    private func deduplicate(_ sortedPeaks: [FrequencyPeak]) -> [FrequencyPeak] {
        var kept: [FrequencyPeak] = []
        for candidate in sortedPeaks {
            let tooClose = kept.contains { existing in
                let ratio = candidate.frequency / existing.frequency
                // 1/6 octave ≈ ratio of 2^(1/6) ≈ 1.122
                return ratio > (1.0 / 1.122) && ratio < 1.122
            }
            if !tooClose {
                kept.append(candidate)
            }
        }
        return kept
    }
}

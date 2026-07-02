
//  FrequencyPeak.swift
//  AudioSpectrumPro

import Foundation

struct FrequencyPeak: Identifiable, Equatable {
    let id = UUID()
    let frequency: Float    // Hz
    let magnitude: Float    // dB
    let prominence: Float   // dB above surroundings

    // Compare by measurement values, not `id` (a fresh UUID per detection
    // would make every array update look like a change).
    static func == (lhs: FrequencyPeak, rhs: FrequencyPeak) -> Bool {
        lhs.frequency == rhs.frequency &&
        lhs.magnitude == rhs.magnitude &&
        lhs.prominence == rhs.prominence
    }

    var frequencyLabel: String {
        if frequency >= 1000 {
            let kHz = Double(frequency / 1000)
            return kHz.formatted(.number.precision(.fractionLength(1))) + " kHz"
        } else {
            return Int(frequency).formatted() + " Hz"
        }
    }
}

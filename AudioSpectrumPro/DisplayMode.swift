//  DisplayMode.swift
//  AudioSpectrumPro

import Foundation

enum DisplayMode: String, CaseIterable, Identifiable {
    case spectrum
    case tuner
    case oscilloscope
    case loudness
    case generator
    case rt60

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .spectrum:     return "waveform.path.ecg"
        case .tuner:        return "music.note"
        case .oscilloscope: return "waveform"
        case .loudness:     return "speaker.wave.3.fill"
        case .generator:    return "waveform.path"
        case .rt60:         return "timer"
        }
    }

    func title(l10n: L10n) -> String {
        switch self {
        case .spectrum:     return l10n.modeSpectrum
        case .tuner:        return l10n.modeTuner
        case .oscilloscope: return l10n.modeOscilloscope
        case .loudness:     return l10n.modeLoudness
        case .generator:    return l10n.modeGenerator
        case .rt60:         return l10n.modeRT60
        }
    }
}

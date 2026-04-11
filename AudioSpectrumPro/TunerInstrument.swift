//  TunerInstrument.swift
//  AudioSpectrumPro

import Foundation

// MARK: - InstrumentString

struct InstrumentString: Identifiable {
    let id: Int
    let name: String
    let midiNote: Int

    func frequency(referenceA4: Float) -> Float {
        referenceA4 * pow(2.0, Float(midiNote - 69) / 12.0)
    }
}

// MARK: - InstrumentTuning

struct InstrumentTuning: Identifiable {
    let id: Int
    let name: String
    let strings: [InstrumentString]
}

// MARK: - TunerInstrument

enum TunerInstrument: String, CaseIterable, Identifiable {
    case chromatic
    case guitar
    case bass
    case violin
    case viola
    case cello
    case ukulele
    case mandolin
    case banjo

    var id: String { rawValue }

    /// English fallback — used only where no `L10n` is available.
    var displayName: String {
        switch self {
        case .chromatic: return "Chromatic"
        case .guitar:    return "Guitar"
        case .bass:      return "Bass"
        case .violin:    return "Violin"
        case .viola:     return "Viola"
        case .cello:     return "Cello"
        case .ukulele:   return "Ukulele"
        case .mandolin:  return "Mandolin"
        case .banjo:     return "Banjo"
        }
    }

    /// Localized display name — use this in views that have `L10n`.
    func displayName(l10n: L10n) -> String {
        switch self {
        case .chromatic: return l10n.instrChromatic
        case .guitar:    return l10n.instrGuitar
        case .bass:      return l10n.instrBass
        case .violin:    return l10n.instrViolin
        case .viola:     return l10n.instrViola
        case .cello:     return l10n.instrCello
        case .ukulele:   return l10n.instrUkulele
        case .mandolin:  return l10n.instrMandolin
        case .banjo:     return l10n.instrBanjo
        }
    }

    var systemImage: String {
        switch self {
        case .chromatic: return "music.note"
        case .guitar:    return "guitars"
        case .bass:      return "guitars"
        case .violin:    return "music.note.list"
        case .viola:     return "music.note.list"
        case .cello:     return "music.note.list"
        case .ukulele:   return "guitars"
        case .mandolin:  return "music.note"
        case .banjo:     return "music.note"
        }
    }

    var tunings: [InstrumentTuning] {
        switch self {
        case .chromatic:
            return []

        case .guitar:
            return [
                InstrumentTuning(id: 0, name: "Standard", strings: [
                    InstrumentString(id: 0, name: "E2", midiNote: 40),
                    InstrumentString(id: 1, name: "A2", midiNote: 45),
                    InstrumentString(id: 2, name: "D3", midiNote: 50),
                    InstrumentString(id: 3, name: "G3", midiNote: 55),
                    InstrumentString(id: 4, name: "B3", midiNote: 59),
                    InstrumentString(id: 5, name: "E4", midiNote: 64)
                ]),
                InstrumentTuning(id: 1, name: "Drop D", strings: [
                    InstrumentString(id: 0, name: "D2", midiNote: 38),
                    InstrumentString(id: 1, name: "A2", midiNote: 45),
                    InstrumentString(id: 2, name: "D3", midiNote: 50),
                    InstrumentString(id: 3, name: "G3", midiNote: 55),
                    InstrumentString(id: 4, name: "B3", midiNote: 59),
                    InstrumentString(id: 5, name: "E4", midiNote: 64)
                ]),
                InstrumentTuning(id: 2, name: "Open G", strings: [
                    InstrumentString(id: 0, name: "D2", midiNote: 38),
                    InstrumentString(id: 1, name: "G2", midiNote: 43),
                    InstrumentString(id: 2, name: "D3", midiNote: 50),
                    InstrumentString(id: 3, name: "G3", midiNote: 55),
                    InstrumentString(id: 4, name: "B3", midiNote: 59),
                    InstrumentString(id: 5, name: "D4", midiNote: 62)
                ]),
                InstrumentTuning(id: 3, name: "DADGAD", strings: [
                    InstrumentString(id: 0, name: "D2", midiNote: 38),
                    InstrumentString(id: 1, name: "A2", midiNote: 45),
                    InstrumentString(id: 2, name: "D3", midiNote: 50),
                    InstrumentString(id: 3, name: "G3", midiNote: 55),
                    InstrumentString(id: 4, name: "A3", midiNote: 57),
                    InstrumentString(id: 5, name: "D4", midiNote: 62)
                ])
            ]

        case .bass:
            return [
                InstrumentTuning(id: 0, name: "4-String", strings: [
                    InstrumentString(id: 0, name: "E1", midiNote: 28),
                    InstrumentString(id: 1, name: "A1", midiNote: 33),
                    InstrumentString(id: 2, name: "D2", midiNote: 38),
                    InstrumentString(id: 3, name: "G2", midiNote: 43)
                ]),
                InstrumentTuning(id: 1, name: "5-String", strings: [
                    InstrumentString(id: 0, name: "B0", midiNote: 23),
                    InstrumentString(id: 1, name: "E1", midiNote: 28),
                    InstrumentString(id: 2, name: "A1", midiNote: 33),
                    InstrumentString(id: 3, name: "D2", midiNote: 38),
                    InstrumentString(id: 4, name: "G2", midiNote: 43)
                ])
            ]

        case .violin:
            return [
                InstrumentTuning(id: 0, name: "Standard", strings: [
                    InstrumentString(id: 0, name: "G3", midiNote: 55),
                    InstrumentString(id: 1, name: "D4", midiNote: 62),
                    InstrumentString(id: 2, name: "A4", midiNote: 69),
                    InstrumentString(id: 3, name: "E5", midiNote: 76)
                ])
            ]

        case .viola:
            return [
                InstrumentTuning(id: 0, name: "Standard", strings: [
                    InstrumentString(id: 0, name: "C3", midiNote: 48),
                    InstrumentString(id: 1, name: "G3", midiNote: 55),
                    InstrumentString(id: 2, name: "D4", midiNote: 62),
                    InstrumentString(id: 3, name: "A4", midiNote: 69)
                ])
            ]

        case .cello:
            return [
                InstrumentTuning(id: 0, name: "Standard", strings: [
                    InstrumentString(id: 0, name: "C2", midiNote: 36),
                    InstrumentString(id: 1, name: "G2", midiNote: 43),
                    InstrumentString(id: 2, name: "D3", midiNote: 50),
                    InstrumentString(id: 3, name: "A3", midiNote: 57)
                ])
            ]

        case .ukulele:
            return [
                InstrumentTuning(id: 0, name: "Standard", strings: [
                    InstrumentString(id: 0, name: "G4", midiNote: 67),
                    InstrumentString(id: 1, name: "C4", midiNote: 60),
                    InstrumentString(id: 2, name: "E4", midiNote: 64),
                    InstrumentString(id: 3, name: "A4", midiNote: 69)
                ])
            ]

        case .mandolin:
            return [
                InstrumentTuning(id: 0, name: "Standard", strings: [
                    InstrumentString(id: 0, name: "G3", midiNote: 55),
                    InstrumentString(id: 1, name: "D4", midiNote: 62),
                    InstrumentString(id: 2, name: "A4", midiNote: 69),
                    InstrumentString(id: 3, name: "E5", midiNote: 76)
                ])
            ]

        case .banjo:
            return [
                InstrumentTuning(id: 0, name: "Standard", strings: [
                    InstrumentString(id: 0, name: "G4", midiNote: 67),
                    InstrumentString(id: 1, name: "D3", midiNote: 50),
                    InstrumentString(id: 2, name: "G3", midiNote: 55),
                    InstrumentString(id: 3, name: "B3", midiNote: 59),
                    InstrumentString(id: 4, name: "D4", midiNote: 62)
                ])
            ]
        }
    }
}

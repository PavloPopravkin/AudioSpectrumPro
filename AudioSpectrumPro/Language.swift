//  Language.swift
//  AudioSpectrumPro

import Foundation

enum Language: String, CaseIterable, Identifiable {
    case english    = "en"
    case russian    = "ru"
    case ukrainian  = "uk"
    case spanish            = "es"
    case chineseSimplified  = "zh-Hans"
    case chineseTraditional = "zh-Hant"
    case japanese           = "ja"
    case korean             = "ko"
    case german             = "de"
    case french             = "fr"
    case portugueseBR       = "pt-BR"
    case italian            = "it"
    case turkish            = "tr"
    case dutch              = "nl"
    case polish             = "pl"
    case swedish            = "sv"
    case danish             = "da"
    case indonesian         = "id"
    case thai               = "th"
    case hindi              = "hi"
    case vietnamese         = "vi"
    case czech              = "cs"
    case greek              = "el"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english:            return "English"
        case .russian:            return "Русский"
        case .ukrainian:          return "Українська"
        case .spanish:            return "Español"
        case .chineseSimplified:  return "简体中文"
        case .chineseTraditional: return "繁體中文"
        case .japanese:           return "日本語"
        case .korean:             return "한국어"
        case .german:             return "Deutsch"
        case .french:             return "Français"
        case .portugueseBR:       return "Português (Brasil)"
        case .italian:            return "Italiano"
        case .turkish:            return "Türkçe"
        case .dutch:              return "Nederlands"
        case .polish:             return "Polski"
        case .swedish:            return "Svenska"
        case .danish:             return "Dansk"
        case .indonesian:         return "Bahasa Indonesia"
        case .thai:               return "ไทย"
        case .hindi:              return "हिन्दी"
        case .vietnamese:         return "Tiếng Việt"
        case .czech:              return "Čeština"
        case .greek:              return "Ελληνικά"
        }
    }
}

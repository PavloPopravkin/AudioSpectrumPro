//  LanguageManager.swift
//  AudioSpectrumPro

import Combine
import SwiftUI

enum AppColorScheme: String, CaseIterable, Identifiable {
    case dark   = "dark"
    case light  = "light"
    case system = "system"

    var id: String { rawValue }

    /// The SwiftUI ColorScheme to apply, or nil to follow the system setting.
    var colorScheme: ColorScheme? {
        switch self {
        case .dark:   return .dark
        case .light:  return .light
        case .system: return nil
        }
    }
}

final class LanguageManager: ObservableObject {
    @AppStorage("app_language") var selectedLanguage: String = Language.english.rawValue {
        willSet { objectWillChange.send() }
    }

    @AppStorage("app_color_scheme") var selectedScheme: String = AppColorScheme.dark.rawValue {
        willSet { objectWillChange.send() }
    }

    var language: Language {
        get { Language(rawValue: selectedLanguage) ?? .english }
        set { selectedLanguage = newValue.rawValue }
    }

    var colorScheme: AppColorScheme {
        get { AppColorScheme(rawValue: selectedScheme) ?? .dark }
        set { selectedScheme = newValue.rawValue }
    }

    var l10n: L10n { L10n.make(for: language) }
}

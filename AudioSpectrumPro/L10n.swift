//  L10n.swift
//  AudioSpectrumPro

import Foundation

struct L10n {
    // MARK: - General UI
    let appTitle:           String
    let start:              String
    let stop:               String
    let startAnalysis:      String  // accessibility label
    let stopAnalysis:       String  // accessibility label
    let errorTitle:         String
    let errorOK:            String
    let language:           String
    let microphoneError:    String

    // MARK: - Display modes
    let modeSpectrum:       String
    let modeSpectrograph:   String
    let modeTuner:          String
    let modeOscilloscope:   String
    let modeLoudness:       String

    // MARK: - Tuner
    let tunerListening:     String
    let tunerCents:         String
    let tunerSettings:      String
    let tunerReferencePitch: String
    let tunerCapo:          String
    let tunerNoiseGate:     String
    let tunerInTune:        String
    let tunerCustom:        String

    // MARK: - Instrument names (tuner selector)
    let instrChromatic:     String
    let instrGuitar:        String
    let instrBass:          String
    let instrViolin:        String
    let instrViola:         String
    let instrCello:         String
    let instrUkulele:       String
    let instrMandolin:      String
    let instrBanjo:         String

    // MARK: - Loudness
    let loudnessRMS:        String
    let loudnessPeak:       String
    let loudnessHistory:    String

    // MARK: - Sensitivity
    let sensitivityLabel:   String   // e.g. "Gain"
    let sensitivityReset:   String   // e.g. "Reset"

    // MARK: - Recommendations panel
    let eqRecommendations:  String
    let spectrumClean:      String

    // MARK: - EQ band descriptions (cut in dB is injected at call site)
    let subBass:            (Int) -> String
    let lowMid:             (Int) -> String
    let mid:                (Int) -> String
    let upperMid:           (Int) -> String
    let presence:           (Int) -> String
    let high:               (Int) -> String

    // MARK: - Factory

    static func make(for language: Language) -> L10n {
        switch language {
        case .english:   return .english
        case .russian:   return .russian
        case .ukrainian: return .ukrainian
        }
    }

    // MARK: - English

    static let english = L10n(
        appTitle:           "Audio Spectrum Pro",
        start:              "Start",
        stop:               "Stop",
        startAnalysis:      "Start analysis",
        stopAnalysis:       "Stop analysis",
        errorTitle:         "Error",
        errorOK:            "OK",
        language:           "Language",
        microphoneError:    "Microphone access denied. Allow access in Settings → Privacy.",
        modeSpectrum:       "Spectrum",
        modeSpectrograph:   "Spectrograph",
        modeTuner:          "Tuner",
        modeOscilloscope:   "Oscilloscope",
        modeLoudness:       "Loudness",
        tunerListening:     "Listening…",
        tunerCents:         "cents",
        tunerSettings:      "Tuner Settings",
        tunerReferencePitch: "Reference Pitch (A4)",
        tunerCapo:          "Capo",
        tunerNoiseGate:     "Min. Signal",
        tunerInTune:        "In Tune ✓",
        tunerCustom:        "Custom",
        instrChromatic:     "Chromatic",
        instrGuitar:        "Guitar",
        instrBass:          "Bass",
        instrViolin:        "Violin",
        instrViola:         "Viola",
        instrCello:         "Cello",
        instrUkulele:       "Ukulele",
        instrMandolin:      "Mandolin",
        instrBanjo:         "Banjo",
        loudnessRMS:        "RMS",
        loudnessPeak:       "Peak",
        loudnessHistory:    "History",
        sensitivityLabel:   "Gain",
        sensitivityReset:   "Reset",
        eqRecommendations:  "EQ Recommendations",
        spectrumClean:      "Spectrum is clean — feedback unlikely.",
        subBass:            { "Sub-bass — room rumble. Cut -\($0) dB removes the hum." },
        lowMid:             { "Low-mid — muddiness. Cut -\($0) dB." },
        mid:                { "Mid — nasal sound. Cut -\($0) dB improves intelligibility." },
        upperMid:           { "Upper-mid — harshness. Cut -\($0) dB reduces tension." },
        presence:           { "Presence — boxiness. Cut -\($0) dB won't hurt clarity." },
        high:               { "High range — sibilance. Cut -\($0) dB." }
    )

    // MARK: - Russian

    static let russian = L10n(
        appTitle:           "Audio Spectrum Pro",
        start:              "Старт",
        stop:               "Стоп",
        startAnalysis:      "Начать анализ",
        stopAnalysis:       "Остановить анализ",
        errorTitle:         "Ошибка",
        errorOK:            "OK",
        language:           "Язык",
        microphoneError:    "Нет доступа к микрофону. Разрешите доступ в Настройках → Конфиденциальность.",
        modeSpectrum:       "Спектр",
        modeSpectrograph:   "Спектрограф",
        modeTuner:          "Тюнер",
        modeOscilloscope:   "Осциллоскоп",
        modeLoudness:       "Громкость",
        tunerListening:     "Слушаю…",
        tunerCents:         "центов",
        tunerSettings:      "Настройки тюнера",
        tunerReferencePitch: "Эталон (A4)",
        tunerCapo:          "Каподастр",
        tunerNoiseGate:     "Мин. сигнал",
        tunerInTune:        "В строе ✓",
        tunerCustom:        "Своё",
        instrChromatic:     "Хроматик",
        instrGuitar:        "Гитара",
        instrBass:          "Бас",
        instrViolin:        "Скрипка",
        instrViola:         "Альт",
        instrCello:         "Виолончель",
        instrUkulele:       "Укулеле",
        instrMandolin:      "Мандолина",
        instrBanjo:         "Банджо",
        loudnessRMS:        "RMS",
        loudnessPeak:       "Пик",
        loudnessHistory:    "История",
        sensitivityLabel:   "Усиление",
        sensitivityReset:   "Сброс",
        eqRecommendations:  "Рекомендации EQ",
        spectrumClean:      "Спектр чистый — обратная связь маловероятна.",
        subBass:            { "Суббас — гул помещения. Срез -\($0) dB уберёт гудение." },
        lowMid:             { "Нижняя середина — гулкость зала. Срез -\($0) dB." },
        mid:                { "Середина — гнусавость. Срез -\($0) dB улучшит разборчивость." },
        upperMid:           { "Верхняя середина — резкость. Срез -\($0) dB снизит напряжённость." },
        presence:           { "Присутствие — картонность. Срез -\($0) dB не повредит разборчивости." },
        high:               { "Верхний диапазон — свистящие призвуки. Срез -\($0) dB." }
    )

    // MARK: - Ukrainian

    static let ukrainian = L10n(
        appTitle:           "Audio Spectrum Pro",
        start:              "Старт",
        stop:               "Стоп",
        startAnalysis:      "Почати аналіз",
        stopAnalysis:       "Зупинити аналіз",
        errorTitle:         "Помилка",
        errorOK:            "OK",
        language:           "Мова",
        microphoneError:    "Немає доступу до мікрофона. Дозвольте доступ у Налаштуваннях → Конфіденційність.",
        modeSpectrum:       "Спектр",
        modeSpectrograph:   "Спектрограф",
        modeTuner:          "Тюнер",
        modeOscilloscope:   "Осцилоскоп",
        modeLoudness:       "Гучність",
        tunerListening:     "Слухаю…",
        tunerCents:         "центів",
        tunerSettings:      "Налаштування тюнера",
        tunerReferencePitch: "Еталон (A4)",
        tunerCapo:          "Капо",
        tunerNoiseGate:     "Мін. сигнал",
        tunerInTune:        "В строї ✓",
        tunerCustom:        "Своє",
        instrChromatic:     "Хроматик",
        instrGuitar:        "Гітара",
        instrBass:          "Бас",
        instrViolin:        "Скрипка",
        instrViola:         "Альт",
        instrCello:         "Віолончель",
        instrUkulele:       "Укулеле",
        instrMandolin:      "Мандоліна",
        instrBanjo:         "Банджо",
        loudnessRMS:        "RMS",
        loudnessPeak:       "Пік",
        loudnessHistory:    "Історія",
        sensitivityLabel:   "Підсилення",
        sensitivityReset:   "Скинути",
        eqRecommendations:  "Рекомендації EQ",
        spectrumClean:      "Спектр чистий — зворотний зв'язок малоймовірний.",
        subBass:            { "Суббас — гул приміщення. Зріз -\($0) dB приберe гудіння." },
        lowMid:             { "Нижня середина — каламутність залу. Зріз -\($0) dB." },
        mid:                { "Середина — гнусавість. Зріз -\($0) dB покращить розбірливість." },
        upperMid:           { "Верхня середина — різкість. Зріз -\($0) dB знизить напругу." },
        presence:           { "Присутність — картонність. Зріз -\($0) dB не зашкодить чіткості." },
        high:               { "Верхній діапазон — свистячі призвуки. Зріз -\($0) dB." }
    )
}

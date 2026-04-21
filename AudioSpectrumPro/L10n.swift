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
    let modeGenerator:      String
    let modeRT60:           String

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

    // MARK: - Signal Generator
    let genPinkNoise:       String
    let genWhiteNoise:      String
    let genSineSweep:       String
    let genFixedTone:       String
    let genFrequency:       String
    let genDuration:        String
    let genPlay:            String
    let genPinkNoiseDesc:   String
    let genWhiteNoiseDesc:  String
    let genSineSweepDesc:   String
    let genFixedToneDesc:   String

    // MARK: - RT60
    let rt60Idle:               String
    let rt60Start:              String
    let rt60WaitingForImpulse:  String
    let rt60ImpulseTip:         String
    let rt60Recording:          String
    let rt60Analyzing:          String
    let rt60Failed:             String
    let rt60NeedsMic:           String
    let rt60QualityDry:         String
    let rt60QualityGood:        String
    let rt60QualityFair:        String
    let rt60QualityHigh:        String

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
        modeGenerator:      "Generator",
        modeRT60:           "RT60",
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
        genPinkNoise:       "Pink Noise",
        genWhiteNoise:      "White Noise",
        genSineSweep:       "Sine Sweep",
        genFixedTone:       "Fixed Tone",
        genFrequency:       "Frequency",
        genDuration:        "Duration",
        genPlay:            "Play",
        genPinkNoiseDesc:   "Pink noise (–3 dB/oct) closely matches real-world programme levels. Use for loudspeaker alignment and acoustic measurements.",
        genWhiteNoiseDesc:  "White noise has equal energy per frequency. Useful for PA system response checks and signal path verification.",
        genSineSweepDesc:   "Logarithmic sweep 20 Hz → 20 kHz. Reveals resonances and non-linearities in speakers, rooms, and signal chains.",
        genFixedToneDesc:   "Constant sine tone at a single frequency. Use for ring-out, feedback elimination, and driver alignment.",
        rt60Idle:           "Tap Start, then make a loud impulse (clap, burst of noise) to measure room reverberation time.",
        rt60Start:          "Start",
        rt60WaitingForImpulse: "Waiting for impulse…",
        rt60ImpulseTip:     "Clap your hands, snap, or use the Generator → Sine Sweep for an automated measurement.",
        rt60Recording:      "Recording decay…",
        rt60Analyzing:      "Analyzing…",
        rt60Failed:         "Measurement failed",
        rt60NeedsMic:       "Start the microphone to measure RT60",
        rt60QualityDry:     "Very dry / close-miked",
        rt60QualityGood:    "Ideal for live sound",
        rt60QualityFair:    "Moderately reverberant",
        rt60QualityHigh:    "Very reverberant — intelligibility risk",
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
        modeGenerator:      "Генератор",
        modeRT60:           "RT60",
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
        genPinkNoise:       "Розовый шум",
        genWhiteNoise:      "Белый шум",
        genSineSweep:       "Синус-свип",
        genFixedTone:       "Тон",
        genFrequency:       "Частота",
        genDuration:        "Длительность",
        genPlay:            "Воспр.",
        genPinkNoiseDesc:   "Розовый шум (–3 дБ/окт) близок к реальным программным уровням. Используется для настройки АС и акустических измерений.",
        genWhiteNoiseDesc:  "Белый шум — равная энергия на всех частотах. Подходит для проверки АЧХ системы и сигнального тракта.",
        genSineSweepDesc:   "Логарифмический свип от 20 Гц до 20 кГц. Выявляет резонансы и нелинейности в АС, помещении и тракте.",
        genFixedToneDesc:   "Постоянный синусоидальный тон. Используется для подавления обратной связи и настройки усилителей.",
        rt60Idle:           "Нажмите Старт, затем создайте громкий импульс (хлопок, шум) для измерения времени реверберации.",
        rt60Start:          "Старт",
        rt60WaitingForImpulse: "Ожидание импульса…",
        rt60ImpulseTip:     "Хлопните в ладоши, щёлкните пальцами или используйте Генератор → Синус-свип для автоматического измерения.",
        rt60Recording:      "Запись затухания…",
        rt60Analyzing:      "Анализ…",
        rt60Failed:         "Измерение не удалось",
        rt60NeedsMic:       "Запустите микрофон для измерения RT60",
        rt60QualityDry:     "Очень сухо / ближнее микрофонирование",
        rt60QualityGood:    "Идеально для живого звука",
        rt60QualityFair:    "Умеренная реверберация",
        rt60QualityHigh:    "Сильная реверберация — риск потери разборчивости",
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
        modeGenerator:      "Генератор",
        modeRT60:           "RT60",
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
        genPinkNoise:       "Рожевий шум",
        genWhiteNoise:      "Білий шум",
        genSineSweep:       "Синус-свіп",
        genFixedTone:       "Тон",
        genFrequency:       "Частота",
        genDuration:        "Тривалість",
        genPlay:            "Відтв.",
        genPinkNoiseDesc:   "Рожевий шум (–3 дБ/окт) близький до реальних програмних рівнів. Використовується для налаштування АС та акустичних вимірювань.",
        genWhiteNoiseDesc:  "Білий шум — рівна енергія на всіх частотах. Підходить для перевірки АЧХ системи та сигнального тракту.",
        genSineSweepDesc:   "Логарифмічний свіп від 20 Гц до 20 кГц. Виявляє резонанси та нелінійності в АС, приміщенні та тракті.",
        genFixedToneDesc:   "Постійний синусоїдальний тон. Використовується для придушення зворотного зв'язку та налаштування підсилювачів.",
        rt60Idle:           "Натисніть Старт, потім створіть гучний імпульс (хлопок, шум) для вимірювання часу реверберації.",
        rt60Start:          "Старт",
        rt60WaitingForImpulse: "Очікування імпульсу…",
        rt60ImpulseTip:     "Клацніть пальцями, хлопніть або скористайтеся Генератором → Синус-свіп для автоматичного вимірювання.",
        rt60Recording:      "Запис загасання…",
        rt60Analyzing:      "Аналіз…",
        rt60Failed:         "Вимірювання не вдалось",
        rt60NeedsMic:       "Запустіть мікрофон для вимірювання RT60",
        rt60QualityDry:     "Дуже сухо / ближнє мікрофонування",
        rt60QualityGood:    "Ідеально для живого звуку",
        rt60QualityFair:    "Помірна реверберація",
        rt60QualityHigh:    "Сильна реверберація — ризик втрати розбірливості",
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

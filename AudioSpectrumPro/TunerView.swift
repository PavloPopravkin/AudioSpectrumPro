//  TunerView.swift
//  AudioSpectrumPro

import SwiftUI

struct TunerView: View {
    let reading: TunerReading?
    @EnvironmentObject private var langManager: LanguageManager
    @EnvironmentObject private var viewModel: SpectrumViewModel

    // MARK: - Persisted state

    @AppStorage("tuner_instrument") private var instrumentRaw: String = TunerInstrument.chromatic.rawValue
    @AppStorage("tuner_tuning_index") private var tuningIndex: Int = 0
    @AppStorage("tuner_reference_a4") private var referenceA4Storage: Double = 440.0
    @AppStorage("tuner_capo") private var capo: Int = 0
    @AppStorage("tuner_noise_gate") private var noiseGateDB: Double = -50.0

    // MARK: - Ephemeral state

    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @StateObject private var audioPlayer = ReferenceAudioPlayer()
    @State private var showingSettings = false
    @State private var strobeOn: Bool = false

    // MARK: - Piano keyboard data (two octaves: C3–B4)

    private let allNotes = TunerReading.noteNames
    // (semitone 0–11, octave): 14 white keys C3→B3→C4→B4
    private let whiteKeyData: [(noteIndex: Int, octave: Int)] = [
        (0,3),(2,3),(4,3),(5,3),(7,3),(9,3),(11,3),
        (0,4),(2,4),(4,4),(5,4),(7,4),(9,4),(11,4)
    ]
    // (semitone, octave, left-edge as multiple of white-key width)
    private let blackKeyData: [(noteIndex: Int, octave: Int, xMult: CGFloat)] = [
        (1,3,0.7),(3,3,1.7),(6,3,3.7),(8,3,4.7),(10,3,5.7),
        (1,4,7.7),(3,4,8.7),(6,4,10.7),(8,4,11.7),(10,4,12.7)
    ]

    // MARK: - Derived helpers

    private var instrument: TunerInstrument {
        TunerInstrument(rawValue: instrumentRaw) ?? .chromatic
    }

    private var referenceA4: Float {
        Float(referenceA4Storage)
    }

    private var currentTuning: InstrumentTuning? {
        let tunings = instrument.tunings
        guard !tunings.isEmpty else { return nil }
        let idx = min(tuningIndex, tunings.count - 1)
        return tunings[idx]
    }

    private var nearestStringResult: (string: InstrumentString, centsOff: Int)? {
        guard instrument != .chromatic,
              let tuning = currentTuning,
              let freq = reading?.frequency else { return nil }
        return nearestString(to: freq, in: tuning, referenceA4: referenceA4, capo: capo)
    }

    private func nearestString(
        to frequency: Float,
        in tuning: InstrumentTuning,
        referenceA4: Float,
        capo: Int
    ) -> (string: InstrumentString, centsOff: Int)? {
        guard !tuning.strings.isEmpty else { return nil }
        var bestString = tuning.strings[0]
        var bestAbsDist = Int.max
        var bestCents = 0
        for string in tuning.strings {
            let shiftedMidi = string.midiNote + capo
            let targetFreq = referenceA4 * pow(2.0, Float(shiftedMidi - 69) / 12.0)
            let semitones = 12.0 * log2(frequency / targetFreq)
            let cents = Int((semitones * 100.0).rounded())
            let dist = abs(cents)
            if dist < bestAbsDist {
                bestAbsDist = dist
                bestCents = cents
                bestString = string
            }
        }
        return (string: bestString, centsOff: bestCents)
    }

    private var displayCents: Int {
        if instrument != .chromatic, let ns = nearestStringResult {
            return ns.centsOff
        }
        return reading?.cents ?? 0
    }

    private var supportsCapo: Bool {
        instrument == .guitar || instrument == .bass
    }

    // MARK: - Body

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                instrumentSelector
                    .padding(.top, 12)

                if instrument != .chromatic && instrument.tunings.count > 1 {
                    tuningSelector
                        .padding(.top, 8)
                }

                if instrument != .chromatic {
                    stringIndicators
                        .padding(.top, 10)
                }

                readoutArea
                    .padding(.top, verticalSizeClass == .compact ? 4 : 10)

                tuningMeter
                    .padding(.vertical, verticalSizeClass == .compact ? 4 : 10)

                if instrument == .chromatic {
                    pianoKeyboard
                        .frame(height: verticalSizeClass == .compact ? 60 : 90)
                        .padding(.horizontal, 16)
                }

                quickSettingsBar
                    .padding(.top, verticalSizeClass == .compact ? 4 : 8)
                    .padding(.bottom, verticalSizeClass == .compact ? 6 : 12)
            }
            .frame(maxWidth: .infinity)
        }
        .background(Color.black)
        .sheet(isPresented: $showingSettings) {
            TunerSettingsView()
                .environmentObject(langManager)
        }
        .onChange(of: referenceA4Storage) { _ in syncViewModel() }
        .onChange(of: noiseGateDB) { _ in syncViewModel() }
        .onAppear { syncViewModel() }
    }

    // MARK: - Sync ViewModel

    private func syncViewModel() {
        viewModel.referenceA4 = Float(referenceA4Storage)
        viewModel.noiseGateDB = Float(noiseGateDB)
    }

    // MARK: - Instrument Selector

    private var instrumentSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TunerInstrument.allCases) { inst in
                    Button(action: {
                        instrumentRaw = inst.rawValue
                        tuningIndex = 0
                    }) {
                        VStack(spacing: 3) {
                            Image(systemName: inst.systemImage)
                                .font(.system(size: 14))
                            Text(inst.displayName(l10n: langManager.l10n))
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(instrument == inst ? Color.black : Color.white.opacity(0.7))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(instrument == inst ? Color.white : Color.white.opacity(0.1))
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Tuning Selector

    private var tuningSelector: some View {
        let tunings = instrument.tunings
        return HStack(spacing: 6) {
            ForEach(Array(tunings.enumerated()), id: \.offset) { idx, tuning in
                Button(action: { tuningIndex = idx }) {
                    Text(tuning.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(tuningIndex == idx ? Color.black : Color.white.opacity(0.7))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(tuningIndex == idx ? Color.white : Color.white.opacity(0.12))
                        )
                }
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - String Indicators

    private var stringIndicators: some View {
        let strings = currentTuning?.strings ?? []
        // Don't highlight the nearest-string pill while a reference tone plays
        let nearest: InstrumentString? = audioPlayer.playingFrequency == nil ? nearestStringResult?.string : nil
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(strings) { str in
                    let isNearest = nearest?.id == str.id
                    let playFreq = stringFrequency(str)
                    let isPlaying = audioPlayer.playingFrequency.map {
                        abs($0 - playFreq) < 2.0
                    } ?? false
                    let color: Color = isPlaying
                        ? .cyan
                        : isNearest ? pillColor(centsOff: nearestStringResult?.centsOff ?? 0) : Color.white.opacity(0.15)
                    Button(action: { audioPlayer.play(frequency: playFreq) }) {
                        HStack(spacing: 4) {
                            Text(str.name)
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            if isPlaying {
                                Image(systemName: "speaker.wave.1.fill")
                                    .font(.system(size: 9))
                            }
                        }
                        .foregroundStyle(isNearest || isPlaying ? Color.black : Color.white.opacity(0.6))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(color))
                    }
                    .buttonStyle(.plain)
                    .animation(.easeInOut(duration: 0.15), value: isPlaying)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func stringFrequency(_ str: InstrumentString) -> Float {
        let shiftedMidi = str.midiNote + capo
        return referenceA4 * pow(2.0, Float(shiftedMidi - 69) / 12.0)
    }

    private func pillColor(centsOff: Int) -> Color {
        let a = abs(centsOff)
        if a <= 10 { return .green }
        if a <= 25 { return .yellow }
        return .red
    }

    // MARK: - Readout

    private var readoutArea: some View {
        // Always render exactly 3 rows with the SAME font weight so row heights
        // never change when a pitch is detected or lost.  The fixed frame is a
        // second guard: even if text metrics wobble, the piano below stays put.
        let cents  = displayCents
        let isLandscape = verticalSizeClass == .compact
        let noteFontSize: CGFloat = isLandscape ? 38 : 52
        let fixedHeight: CGFloat  = isLandscape ? 72  : 108

        return VStack(spacing: 4) {
            // Row 1 — note name  (always .bold so line-height never changes)
            Text(reading.map { "\($0.note)\($0.octave)" } ?? "–")
                .font(.system(size: noteFontSize, weight: .bold, design: .monospaced))
                .foregroundStyle(reading != nil
                    ? noteColor(cents: cents)
                    : Color.white.opacity(0.15))

            // Row 2 — frequency / listening label
            Text(reading.map { String(format: "%.1f Hz", $0.frequency) }
                 ?? langManager.l10n.tunerListening)
                .font(.system(size: 14, weight: .regular, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.6))

            // Row 3 — cents / in-tune badge.
            // When no reading: render an invisible same-font placeholder so this
            // row always occupies exactly the same height as the visible variants.
            Group {
                if reading != nil {
                    if abs(cents) <= 5 {
                        Text(langManager.l10n.tunerInTune)
                            .foregroundStyle(Color.green)
                            .fontWeight(.semibold)
                    } else {
                        Text(centsLabel(cents))
                            .foregroundStyle(noteColor(cents: cents).opacity(0.9))
                            .fontWeight(.medium)
                    }
                } else {
                    Text(verbatim: "+00 \(langManager.l10n.tunerCents)")
                        .foregroundStyle(Color.clear)   // invisible, same width/height
                }
            }
            .font(.system(size: 13, design: .monospaced))
        }
        .frame(maxWidth: .infinity, minHeight: fixedHeight, maxHeight: fixedHeight)
    }

    // MARK: - Tuning Meter

    private var tuningMeter: some View {
        GeometryReader { geo in
            let cents = reading != nil ? displayCents : 0
            let isNearZero = reading != nil && abs(cents) <= 5

            ZStack(alignment: .leading) {
                // Track
                Capsule()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 6)

                // Centre marker
                Rectangle()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 2, height: 14)
                    .offset(x: geo.size.width / 2 - 1)

                // Strobe glow when in-tune
                if isNearZero {
                    Capsule()
                        .fill(Color.green.opacity(strobeOn ? 0.35 : 0.12))
                        .frame(width: geo.size.width * 0.4, height: 10)
                        .offset(x: geo.size.width * 0.3)
                        .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: strobeOn)
                        .onAppear { strobeOn = true }
                        .onDisappear { strobeOn = false }
                }

                // Needle
                if reading != nil {
                    let offset = CGFloat(cents) / 50.0 * (geo.size.width / 2)
                    Capsule()
                        .fill(noteColor(cents: cents))
                        .frame(width: geo.size.width * 0.12, height: 6)
                        .offset(x: geo.size.width / 2 + offset - geo.size.width * 0.06)
                        .animation(.spring(response: 0.15, dampingFraction: 0.7), value: cents)
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: 20)
        .padding(.horizontal, 32)
    }

    // MARK: - Piano Keyboard

    /// Frequency for a note at (semitone 0–11, octave): C4=MIDI60, A4=MIDI69.
    private func pianoKeyFrequency(noteIndex: Int, octave: Int) -> Float {
        let midi = 12 * (octave + 1) + noteIndex
        return referenceA4 * pow(2.0, Float(midi - 69) / 12.0)
    }

    private var pianoKeyboard: some View {
        GeometryReader { geo in
            let totalW  = geo.size.width
            let whiteN  = whiteKeyData.count     // 14
            let ww      = totalW / CGFloat(whiteN)
            let whiteH  = geo.size.height
            let blackW  = ww * 0.58
            let blackH  = whiteH * 0.62
            // Suppress mic highlight while a reference tone plays (avoids two lit keys).
            let activeNote:   String? = audioPlayer.playingFrequency == nil ? reading?.note   : nil
            let activeOctave: Int?    = audioPlayer.playingFrequency == nil ? reading?.octave : nil

            ZStack(alignment: .topLeading) {
                // ── White keys ──────────────────────────────────────────────
                // HStack gives correct layout-based tap targets (ZStack+offset
                // would leave hit-test rects at the original position).
                HStack(spacing: 0) {
                    ForEach(0..<whiteN, id: \.self) { i in
                        let ni     = whiteKeyData[i].noteIndex
                        let oct    = whiteKeyData[i].octave
                        let name   = allNotes[ni]
                        let isActive  = activeNote == name && activeOctave == oct
                        let freq      = pianoKeyFrequency(noteIndex: ni, octave: oct)
                        let isPlaying = audioPlayer.playingFrequency.map { abs($0 - freq) < 2.0 } ?? false
                        let fill: Color = isPlaying ? .cyan
                            : isActive  ? noteColor(cents: displayCents)
                            : .white

                        RoundedRectangle(cornerRadius: 2)
                            .fill(fill)
                            .overlay(RoundedRectangle(cornerRadius: 2)
                                .stroke(Color.black.opacity(0.35), lineWidth: 0.5))
                            .contentShape(Rectangle())
                            .animation(.easeInOut(duration: 0.1), value: isPlaying || isActive)
                            .onTapGesture { audioPlayer.play(frequency: freq) }
                    }
                }
                .frame(width: totalW, height: whiteH)

                // ── Black keys ───────────────────────────────────────────────
                // .position(x:y:) sets the CENTER in parent coords — both visual
                // and hit-test area land in the right place (unlike .offset()).
                ForEach(0..<blackKeyData.count, id: \.self) { i in
                    let ni     = blackKeyData[i].noteIndex
                    let oct    = blackKeyData[i].octave
                    let xMult  = blackKeyData[i].xMult
                    let name   = allNotes[ni]
                    let isActive  = activeNote == name && activeOctave == oct
                    let freq      = pianoKeyFrequency(noteIndex: ni, octave: oct)
                    let isPlaying = audioPlayer.playingFrequency.map { abs($0 - freq) < 2.0 } ?? false
                    let fill: Color = isPlaying ? .cyan
                        : isActive  ? noteColor(cents: displayCents)
                        : .black

                    RoundedRectangle(cornerRadius: 2)
                        .fill(fill)
                        .overlay(RoundedRectangle(cornerRadius: 2)
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.5))
                        .frame(width: blackW, height: blackH)
                        .position(x: xMult * ww + blackW / 2, y: blackH / 2)
                        .animation(.easeInOut(duration: 0.1), value: isPlaying || isActive)
                        .onTapGesture { audioPlayer.play(frequency: freq) }
                }
            }
        }
    }

    // MARK: - Quick Settings Bar

    private var quickSettingsBar: some View {
        HStack(spacing: 10) {
            // A4 reference button
            Button(action: { showingSettings = true }) {
                Text("A4: \(Int(referenceA4)) Hz")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.08))
                    )
            }

            // Capo stepper (only for guitar/bass)
            if supportsCapo {
                HStack(spacing: 6) {
                    Text("\(langManager.l10n.tunerCapo): \(capo)")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.6))

                    Stepper("", value: $capo, in: 0...7)
                        .labelsHidden()
                        .scaleEffect(0.8)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.08))
                )
            }

            // Playing indicator
            if audioPlayer.playingFrequency != nil {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.cyan)
                    .transition(.opacity)
            }

            Spacer()

            // Gear / settings button — moved here so it doesn't overlap the instrument row
            Button(action: { showingSettings = true }) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .padding(8)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .accessibilityLabel(langManager.l10n.tunerSettings)
        }
        .animation(.easeInOut(duration: 0.2), value: audioPlayer.playingFrequency != nil)
        .padding(.horizontal, 16)
    }

    // MARK: - Helpers

    private func noteColor(cents: Int) -> Color {
        let a = abs(cents)
        if a <= 10 { return .green }   // ≤10 cents = in tune (visible green zone)
        if a <= 25 { return .yellow }
        return .red
    }

    private func centsLabel(_ cents: Int) -> String {
        let sign = cents > 0 ? "+" : ""
        return "\(sign)\(cents) \(langManager.l10n.tunerCents)"
    }
}

// MARK: - Tuner Settings Sheet
// Extracted into its own struct so SwiftUI manages its own state independently.
// A computed `var` on the parent view doesn't re-render the already-presented
// sheet when AppStorage changes, causing sliders to appear frozen.

struct TunerSettingsView: View {
    @AppStorage("tuner_reference_a4") private var referenceA4: Double = 440.0
    @AppStorage("tuner_capo")         private var capo: Int = 0
    @AppStorage("tuner_noise_gate")   private var noiseGateDB: Double = -50.0
    @AppStorage("tuner_instrument")   private var instrumentRaw: String = TunerInstrument.chromatic.rawValue

    @EnvironmentObject private var langManager: LanguageManager
    @Environment(\.dismiss) private var dismiss

    private let presets: [Int] = [432, 438, 440, 441, 442, 443, 444]

    private var supportsCapo: Bool {
        let inst = TunerInstrument(rawValue: instrumentRaw) ?? .chromatic
        return inst == .guitar || inst == .bass
    }

    var body: some View {
        NavigationView {
            Form {
                // ── Reference pitch ──────────────────────────────────────
                Section(header: Text(langManager.l10n.tunerReferencePitch)) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(presets, id: \.self) { preset in
                                let isSelected = Int(referenceA4) == preset
                                Button(action: { referenceA4 = Double(preset) }) {
                                    Text("\(preset)")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(isSelected ? Color.black : Color.primary)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.2))
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(langManager.l10n.tunerCustom).font(.callout)
                            Spacer()
                            Text("\(Int(referenceA4)) Hz")
                                .font(.system(.callout, design: .monospaced))
                                .foregroundStyle(Color.secondary)
                        }
                        Slider(value: $referenceA4, in: 430...450, step: 1)
                    }
                }

                // ── Capo (guitar / bass only) ────────────────────────────
                if supportsCapo {
                    Section(header: Text(langManager.l10n.tunerCapo)) {
                        Stepper("\(langManager.l10n.tunerCapo): \(capo)", value: $capo, in: 0...7)
                    }
                }

                // ── Noise gate ───────────────────────────────────────────
                Section(header: Text(langManager.l10n.tunerNoiseGate)) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(langManager.l10n.tunerNoiseGate).font(.callout)
                            Spacer()
                            Text("\(Int(noiseGateDB)) dB")
                                .font(.system(.callout, design: .monospaced))
                                .foregroundStyle(Color.secondary)
                        }
                        Slider(value: $noiseGateDB, in: -60...(-20), step: 1)
                    }
                }
            }
            .navigationTitle(langManager.l10n.tunerSettings)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(langManager.l10n.errorOK) { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

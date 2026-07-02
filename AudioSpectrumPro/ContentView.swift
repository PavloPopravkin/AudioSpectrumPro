//
//  ContentView.swift
//  AudioSpectrumPro
//
//  Created by Dmitry Popravkin on 11.04.2026.
//

import SwiftUI
import MediaPlayer

struct ContentView: View {
    @StateObject private var viewModel: SpectrumViewModel
    @EnvironmentObject private var langManager: LanguageManager
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showingLanguagePicker = false
    @State private var displayMode: DisplayMode = .spectrum
    /// Sensitivity as it was before auto-boosting for the tuner, restored on exit.
    @State private var preTunerSensitivity: Float? = nil
    @State private var shareItem: ShareImage? = nil

    @MainActor
    init(viewModel: SpectrumViewModel? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel ?? SpectrumViewModel())
    }

    var body: some View {
        Group {
            if sizeClass == .regular {
                iPadLayout
            } else {
                iPhoneLayout
            }
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
        .alert(langManager.l10n.errorTitle,
               isPresented: .constant(viewModel.error != nil)) {
            Button(langManager.l10n.errorOK) { viewModel.error = nil }
        } message: {
            Text(errorText)
        }
        .sheet(isPresented: $showingLanguagePicker) {
            LanguagePickerView()
        }
        .sheet(item: $shareItem) { item in
            ActivityView(items: [item.image])
        }
        .onChange(of: displayMode) { mode in
            if mode == .tuner {
                if preTunerSensitivity == nil {
                    preTunerSensitivity = viewModel.sensitivity
                }
                viewModel.sensitivity = 5.0
            } else if let saved = preTunerSensitivity {
                viewModel.sensitivity = saved
                preTunerSensitivity = nil
            }
        }
    }

    private var errorText: String {
        switch viewModel.error {
        case .microphonePermission: return langManager.l10n.microphoneError
        case .other(let message):   return message
        case nil:                   return ""
        }
    }

    // MARK: - Layouts

    private var iPadLayout: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    titleBar
                    modeTabBar
                    mainPanel
                }
                if displayMode == .spectrum {
                    Divider().background(Color.white.opacity(0.15))
                    RecommendationsView(recommendations: viewModel.recommendations)
                        .frame(width: 280)
                }
            }
            bottomBar
        }
    }

    private var iPhoneLayout: some View {
        VStack(spacing: 0) {
            titleBar
            modeTabBar
            mainPanel
            if displayMode == .spectrum {
                Divider().background(Color.white.opacity(0.15))
                RecommendationsView(recommendations: viewModel.recommendations)
                    .frame(maxHeight: 160)
            }
            bottomBar
        }
    }

    // MARK: - Subviews

    private var titleBar: some View {
        HStack(spacing: 10) {
            Text(langManager.l10n.appTitle)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
            Spacer()
            if viewModel.isRunning {
                sensitivityControl
            }
            if displayMode != .generator {
                shareButton
            }
            languageButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(white: 0.06))
        // Hidden MPVolumeView suppresses the system volume HUD so volume-button
        // presses silently adjust microphone sensitivity instead.
        .background(
            HiddenVolumeView()
                .frame(width: 1, height: 1)
                .opacity(0.001)
        )
    }

    private var sensitivityControl: some View {
        HStack(spacing: 6) {
            Button(action: {
                viewModel.sensitivity = max(0.1, viewModel.sensitivity / 1.26)
            }) {
                Image(systemName: "minus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .frame(width: 22, height: 22)
                    .background(Color.white.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)

            Text("\(langManager.l10n.sensitivityLabel) \(viewModel.sensitivity, specifier: "%.1f")×")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(sensitivityColor)
                .onTapGesture { viewModel.sensitivity = 1.0 }

            Button(action: {
                viewModel.sensitivity = min(8.0, viewModel.sensitivity * 1.26)
            }) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .frame(width: 22, height: 22)
                    .background(Color.white.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
        }
    }

    private var sensitivityColor: Color {
        if viewModel.sensitivity > 2.0 { return .orange }
        if viewModel.sensitivity < 0.5 { return Color.white.opacity(0.4) }
        return Color.white.opacity(0.6)
    }

    private var modeTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(DisplayMode.allCases) { mode in
                    ModeTabButton(
                        mode: mode,
                        isSelected: displayMode == mode,
                        l10n: langManager.l10n
                    ) { displayMode = mode }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .background(Color(white: 0.05))
    }

    private var mainPanel: some View {
        Group {
            switch displayMode {
            case .spectrum:
                SpectrumView(displayData: viewModel.displayData,
                             peaks: viewModel.peaks,
                             holdTrace: viewModel.peakHoldTrace,
                             peakHoldEnabled: $viewModel.peakHoldEnabled,
                             peakHoldAccessibilityLabel: langManager.l10n.peakHold)
            case .spectrograph:
                SpectrographView(rows: viewModel.spectrographRows)
            case .tuner:
                TunerView(reading: viewModel.tunerReading)
                    .environmentObject(viewModel)
            case .oscilloscope:
                OscilloscopeView(samples: viewModel.rawSamples)
            case .loudness:
                LoudnessView(
                    lufsMomentary: viewModel.lufsMomentary,
                    lufsShortTerm: viewModel.lufsShortTerm,
                    lufsIntegrated: viewModel.lufsIntegrated,
                    truePeakDB: viewModel.truePeakDB,
                    history: viewModel.loudnessHistory
                )
            case .generator:
                SignalGeneratorView()
            case .rt60:
                RT60View(analyzer: viewModel.rt60Analyzer,
                         isRunning: viewModel.isRunning)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Share snapshot

    private var shareButton: some View {
        Button(action: shareSnapshot) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.5))
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(langManager.l10n.shareSnapshot)
    }

    private func shareSnapshot() {
        guard let image = renderSnapshot() else { return }
        shareItem = ShareImage(image: image)
    }

    /// Renders the current measurement panel into a shareable PNG card.
    private func renderSnapshot() -> UIImage? {
        let timestamp = Date().formatted(date: .abbreviated, time: .shortened)
        let card = VStack(spacing: 0) {
            HStack {
                Text(langManager.l10n.appTitle)
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(displayMode.title(l10n: langManager.l10n)) · \(timestamp)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(white: 0.06))

            snapshotPanel
                .frame(width: 900, height: 560)
        }
        .frame(width: 900)
        .background(Color.black)
        .environment(\.colorScheme, .dark)
        .environmentObject(langManager)
        .environmentObject(viewModel)

        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        renderer.isOpaque = true
        return renderer.uiImage
    }

    @ViewBuilder
    private var snapshotPanel: some View {
        switch displayMode {
        case .spectrum:
            SpectrumView(displayData: viewModel.displayData,
                         peaks: viewModel.peaks,
                         holdTrace: viewModel.peakHoldTrace,
                         isSnapshot: true)
        case .spectrograph:
            SpectrographView(rows: viewModel.spectrographRows)
        case .tuner:
            TunerView(reading: viewModel.tunerReading)
        case .oscilloscope:
            OscilloscopeView(samples: viewModel.rawSamples)
        case .loudness:
            LoudnessView(
                lufsMomentary: viewModel.lufsMomentary,
                lufsShortTerm: viewModel.lufsShortTerm,
                lufsIntegrated: viewModel.lufsIntegrated,
                truePeakDB: viewModel.truePeakDB,
                history: viewModel.loudnessHistory
            )
        case .generator:
            EmptyView()
        case .rt60:
            RT60View(analyzer: viewModel.rt60Analyzer,
                     isRunning: viewModel.isRunning)
        }
    }

    private var bottomBar: some View {
        HStack {
            Spacer()
            StartStopButton(
                isRunning: viewModel.isRunning,
                startLabel: langManager.l10n.start,
                stopLabel: langManager.l10n.stop,
                startAccessibility: langManager.l10n.startAnalysis,
                stopAccessibility: langManager.l10n.stopAnalysis,
                action: toggleAnalysis
            )
            Spacer()
        }
        .padding(.vertical, 16)
        .background(Color(white: 0.06))
    }

    private var languageButton: some View {
        Button(action: { showingLanguagePicker = true }) {
            Text(langManager.language.displayName)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(langManager.l10n.language)
    }

    // MARK: - Actions

    private func toggleAnalysis() {
        if viewModel.isRunning {
            viewModel.stop()
        } else {
            viewModel.start()
        }
    }
}

// MARK: - Start/Stop Button

struct StartStopButton: View {
    let isRunning: Bool
    let startLabel: String
    let stopLabel: String
    let startAccessibility: String
    let stopAccessibility: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(isRunning ? Color.red.opacity(0.15) : Color.green.opacity(0.15))
                        .frame(width: 64, height: 64)
                    Circle()
                        .strokeBorder(isRunning ? Color.red : Color.green, lineWidth: 2)
                        .frame(width: 64, height: 64)
                    Image(systemName: isRunning ? "stop.fill" : "mic.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(isRunning ? Color.red : Color.green)
                }
                Text(isRunning ? stopLabel : startLabel)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(isRunning ? Color.red : Color.green)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRunning ? stopAccessibility : startAccessibility)
        .animation(.easeInOut(duration: 0.2), value: isRunning)
    }
}

// MARK: - Mode Tab Button

struct ModeTabButton: View {
    let mode: DisplayMode
    let isSelected: Bool
    let l10n: L10n
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: mode.systemImage)
                    .font(.system(size: 14))
                Text(mode.title(l10n: l10n))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
            }
            .foregroundStyle(isSelected ? Color.green : Color.white.opacity(0.4))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.green.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - Language Picker Sheet

struct LanguagePickerView: View {
    @EnvironmentObject private var langManager: LanguageManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                ForEach(Language.allCases) { language in
                    Button(action: {
                        langManager.language = language
                        dismiss()
                    }) {
                        HStack {
                            Text(language.displayName)
                                .foregroundStyle(Color.primary)
                            Spacer()
                            if langManager.language == language {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            }
            .navigationTitle(langManager.l10n.language)
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Share sheet plumbing

struct ShareImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController,
                                context: Context) {}
}

// MARK: - Hidden Volume View (suppresses system HUD)

struct HiddenVolumeView: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView()
        view.showsVolumeSlider = true   // must be true to intercept HUD
        view.isUserInteractionEnabled = false
        return view
    }
    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

// MARK: - Previews

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(viewModel: SpectrumViewModel.preview)
            .environmentObject(LanguageManager())
            .previewDisplayName("С данными")
        ContentView()
            .environmentObject(LanguageManager())
            .previewDisplayName("Пустой")
    }
}
#endif

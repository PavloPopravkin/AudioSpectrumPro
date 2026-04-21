//  SignalGeneratorView.swift
//  AudioSpectrumPro

import SwiftUI

struct SignalGeneratorView: View {
    @StateObject private var generator = SignalGenerator()
    @EnvironmentObject private var langManager: LanguageManager

    var body: some View {
        VStack(spacing: 0) {
            typeSelector
            Divider().background(Color.white.opacity(0.1))
            controlArea
            Spacer()
            descriptionText
            Spacer()
            playButton
        }
        .background(Color.black)
    }

    // MARK: - Type selector

    private var typeSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(SignalType.allCases) { type in
                    typeButton(type)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(Color(white: 0.05))
    }

    private func typeButton(_ type: SignalType) -> some View {
        let selected = generator.signalType == type
        return Button {
            if generator.isPlaying { generator.stopPlayback() }
            generator.signalType = type
        } label: {
            VStack(spacing: 3) {
                Image(systemName: type.systemImage)
                    .font(.system(size: 16))
                Text(type.title(l10n: langManager.l10n))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
            }
            .foregroundStyle(selected ? Color.cyan : Color.white.opacity(0.4))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(selected ? Color.cyan.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: selected)
    }

    // MARK: - Type-specific controls

    @ViewBuilder
    private var controlArea: some View {
        switch generator.signalType {
        case .fixedTone:
            toneControls
        case .sineSweep:
            sweepControls
        case .pinkNoise, .whiteNoise:
            noiseInfo
        }
    }

    private var toneControls: some View {
        VStack(spacing: 16) {
            HStack {
                Text(langManager.l10n.genFrequency)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.6))
                Spacer()
                Text(String(format: "%.0f Hz", generator.toneFrequency))
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.cyan)
                    .frame(width: 90, alignment: .trailing)
            }

            // Logarithmic frequency slider 50 – 8000 Hz
            Slider(
                value: Binding(
                    get: { logSliderValue(from: generator.toneFrequency) },
                    set: { generator.toneFrequency = freq(from: $0) }
                )
            )
            .tint(.cyan)

            // Quick-tap frequency presets
            HStack(spacing: 6) {
                ForEach([100, 440, 1000, 2000, 4000, 8000] as [Float], id: \.self) { f in
                    Button {
                        generator.toneFrequency = f
                        if generator.isPlaying {
                            generator.stopPlayback()
                            generator.startPlayback()
                        }
                    } label: {
                        Text(f >= 1000 ? String(format: "%.0fk", f/1000) : String(format: "%.0f", f))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(generator.toneFrequency == f ? .cyan : Color.white.opacity(0.4))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(generator.toneFrequency == f ? Color.cyan.opacity(0.15) : Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
    }

    private var sweepControls: some View {
        VStack(spacing: 16) {
            HStack {
                Text(langManager.l10n.genDuration)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.6))
                Spacer()
                Text(String(format: "%.0f s", generator.sweepDuration))
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.cyan)
                    .frame(width: 50, alignment: .trailing)
            }

            Slider(value: $generator.sweepDuration, in: 5...30, step: 5)
                .tint(.cyan)

            HStack(spacing: 6) {
                Text("20 Hz")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.35))
                Image(systemName: "arrow.right")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.35))
                Text("20 kHz")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.35))
                Spacer()
            }
        }
        .padding(16)
    }

    private var noiseInfo: some View {
        VStack { Spacer().frame(height: 32) }
    }

    // MARK: - Description

    private var descriptionText: some View {
        Text(generator.signalType.description(l10n: langManager.l10n))
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(Color.white.opacity(0.35))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
    }

    // MARK: - Play button

    private var playButton: some View {
        Button(action: { generator.togglePlayback() }) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(generator.isPlaying ? Color.red.opacity(0.15) : Color.cyan.opacity(0.15))
                        .frame(width: 64, height: 64)
                    Circle()
                        .strokeBorder(generator.isPlaying ? Color.red : Color.cyan, lineWidth: 2)
                        .frame(width: 64, height: 64)
                    Image(systemName: generator.isPlaying ? "stop.fill" : "play.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(generator.isPlaying ? Color.red : Color.cyan)
                }
                Text(generator.isPlaying
                     ? langManager.l10n.stop
                     : langManager.l10n.genPlay)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(generator.isPlaying ? Color.red : Color.cyan)
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 20)
        .animation(.easeInOut(duration: 0.2), value: generator.isPlaying)
        .accessibilityLabel(generator.isPlaying ? langManager.l10n.stop : langManager.l10n.genPlay)
    }

    // MARK: - Helpers (log-scale slider)

    private let logMin = log10(50.0 as Float)
    private let logMax = log10(8000.0 as Float)

    private func logSliderValue(from freq: Float) -> Double {
        Double((log10(max(freq, 50)) - logMin) / (logMax - logMin))
    }

    private func freq(from sliderValue: Double) -> Float {
        let clamped = max(0, min(1, Float(sliderValue)))
        return pow(10, logMin + clamped * (logMax - logMin))
    }
}

// MARK: - SignalType helpers

extension SignalType {
    var systemImage: String {
        switch self {
        case .pinkNoise:  return "waveform.path"
        case .whiteNoise: return "waveform"
        case .sineSweep:  return "arrow.up.right"
        case .fixedTone:  return "tuningfork"
        }
    }

    func title(l10n: L10n) -> String {
        switch self {
        case .pinkNoise:  return l10n.genPinkNoise
        case .whiteNoise: return l10n.genWhiteNoise
        case .sineSweep:  return l10n.genSineSweep
        case .fixedTone:  return l10n.genFixedTone
        }
    }

    func description(l10n: L10n) -> String {
        switch self {
        case .pinkNoise:  return l10n.genPinkNoiseDesc
        case .whiteNoise: return l10n.genWhiteNoiseDesc
        case .sineSweep:  return l10n.genSineSweepDesc
        case .fixedTone:  return l10n.genFixedToneDesc
        }
    }
}

// MARK: - Previews

struct SignalGeneratorView_Previews: PreviewProvider {
    static var previews: some View {
        SignalGeneratorView()
            .environmentObject(LanguageManager())
            .background(Color.black)
            .preferredColorScheme(.dark)
    }
}

//  RT60View.swift
//  AudioSpectrumPro

import SwiftUI

struct RT60View: View {
    @ObservedObject var analyzer: RT60Analyzer
    let isRunning: Bool

    @EnvironmentObject private var langManager: LanguageManager

    var body: some View {
        VStack(spacing: 0) {
            if !isRunning {
                microphoneOffBanner
            }
            stateView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            controlBar
        }
        .background(Color.black)
    }

    // MARK: - State views

    @ViewBuilder
    private var stateView: some View {
        switch analyzer.state {
        case .idle:
            idleView
        case .waitingForImpulse:
            waitingView
        case .recording(let elapsed):
            recordingView(elapsed: elapsed)
        case .analyzing:
            analyzingView
        case .done(let result):
            resultView(result)
        case .failed(let msg):
            failedView(message: msg)
        }
    }

    private var idleView: some View {
        VStack(spacing: 14) {
            Image(systemName: "waveform.badge.microphone")
                .font(.system(size: 48))
                .foregroundStyle(Color.white.opacity(0.2))
            Text(langManager.l10n.rt60Idle)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private var waitingView: some View {
        VStack(spacing: 20) {
            Image(systemName: "hand.tap")
                .font(.system(size: 52))
                .foregroundStyle(Color.yellow.opacity(0.7))
            Text(langManager.l10n.rt60WaitingForImpulse)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.yellow.opacity(0.9))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Text(langManager.l10n.rt60ImpulseTip)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.35))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private func recordingView(elapsed: Double) -> some View {
        let progress = min(elapsed / 5.0, 1.0)
        return VStack(spacing: 20) {
            Image(systemName: "record.circle")
                .font(.system(size: 44))
                .foregroundStyle(Color.red.opacity(0.8))
            Text(langManager.l10n.rt60Recording)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.red.opacity(0.9))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.red.opacity(0.7))
                        .frame(width: geo.size.width * progress, height: 8)
                }
            }
            .frame(height: 8)
            .padding(.horizontal, 32)
            Text(String(format: "%.1f / 5.0 s", elapsed))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.5))
        }
        .padding(.horizontal, 20)
    }

    private var analyzingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.cyan)
                .scaleEffect(1.4)
            Text(langManager.l10n.rt60Analyzing)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.5))
        }
    }

    private func resultView(_ result: RT60Result) -> some View {
        VStack(spacing: 0) {
            // RT60 value
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(format: "%.2f", result.rt60))
                    .font(.system(size: 56, weight: .thin, design: .monospaced))
                    .foregroundStyle(rt60Color(result.rt60))
                Text("s")
                    .font(.system(size: 22, weight: .light, design: .monospaced))
                    .foregroundStyle(rt60Color(result.rt60).opacity(0.7))
            }
            .padding(.top, 12)

            Text(rt60Quality(result.rt60, l10n: langManager.l10n))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(rt60Color(result.rt60))
                .padding(.bottom, 16)

            // Decay curve
            if !result.envelope.isEmpty {
                decayCurve(result)
                    .frame(maxWidth: .infinity)
                    .frame(height: 140)
                    .padding(.horizontal, 16)
            }

            // T20 annotation
            HStack(spacing: 0) {
                Spacer()
                Text("T20 = \(String(format: "%.2f", result.t20)) s")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.35))
                    .padding(.trailing, 20)
            }
            .padding(.top, 6)
        }
    }

    private func decayCurve(_ result: RT60Result) -> some View {
        Canvas { ctx, size in
            let env   = result.envelope
            let count = env.count
            guard count > 1 else { return }

            let minDB = env.min()! - 2
            let maxDB = (env.max()! + 2).clamped(to: -3...0)
            let dbRange = maxDB - minDB

            func point(_ i: Int) -> CGPoint {
                let x = CGFloat(i) / CGFloat(count - 1) * size.width
                let y = CGFloat(1.0 - (env[i] - minDB) / dbRange) * size.height
                return CGPoint(x: x, y: y.clamped(to: 0...size.height))
            }

            // Draw decay curve
            var path = Path()
            path.move(to: point(0))
            for i in 1..<count { path.addLine(to: point(i)) }
            ctx.stroke(path, with: .color(.cyan.opacity(0.8)), lineWidth: 1.5)

            // –5 dB marker
            if result.idx5 < count {
                let x = CGFloat(result.idx5) / CGFloat(count - 1) * size.width
                var m5 = Path()
                m5.move(to: CGPoint(x: x, y: 0))
                m5.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(m5, with: .color(.yellow.opacity(0.5)), lineWidth: 1)
            }

            // –25 dB marker
            if result.idx25 < count {
                let x = CGFloat(result.idx25) / CGFloat(count - 1) * size.width
                var m25 = Path()
                m25.move(to: CGPoint(x: x, y: 0))
                m25.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(m25, with: .color(.orange.opacity(0.5)), lineWidth: 1)
            }
        }
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func failedView(message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(Color.orange.opacity(0.7))
            Text(langManager.l10n.rt60Failed)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.orange.opacity(0.8))
            Text(message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.35))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    // MARK: - Control bar

    private var controlBar: some View {
        HStack {
            Spacer()
            switch analyzer.state {
            case .idle, .failed, .done:
                startButton
            case .waitingForImpulse, .recording:
                cancelButton
            case .analyzing:
                EmptyView()
            }
            Spacer()
        }
        .padding(.vertical, 16)
        .background(Color(white: 0.06))
    }

    private var startButton: some View {
        Button {
            analyzer.startMeasurement()
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.15))
                        .frame(width: 64, height: 64)
                    Circle()
                        .strokeBorder(isRunning ? Color.green : Color.white.opacity(0.2), lineWidth: 2)
                        .frame(width: 64, height: 64)
                    Image(systemName: "waveform.badge.microphone")
                        .font(.system(size: 22))
                        .foregroundStyle(isRunning ? Color.green : Color.white.opacity(0.3))
                }
                Text(langManager.l10n.rt60Start)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(isRunning ? Color.green : Color.white.opacity(0.3))
            }
        }
        .buttonStyle(.plain)
        .disabled(!isRunning)
    }

    private var cancelButton: some View {
        Button {
            analyzer.cancelMeasurement()
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.12))
                        .frame(width: 64, height: 64)
                    Circle()
                        .strokeBorder(Color.red, lineWidth: 2)
                        .frame(width: 64, height: 64)
                    Image(systemName: "xmark")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.red)
                }
                Text(langManager.l10n.stop)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.red)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func rt60Color(_ rt60: Float) -> Color {
        switch rt60 {
        case ..<0.5:  return .green
        case 0.5..<0.8: return .cyan
        case 0.8..<1.4: return .yellow
        default:      return .red
        }
    }

    private func rt60Quality(_ rt60: Float, l10n: L10n) -> String {
        switch rt60 {
        case ..<0.5:    return l10n.rt60QualityDry
        case 0.5..<0.8: return l10n.rt60QualityGood
        case 0.8..<1.4: return l10n.rt60QualityFair
        default:        return l10n.rt60QualityHigh
        }
    }

    private var microphoneOffBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "mic.slash")
                .font(.system(size: 12))
            Text(langManager.l10n.rt60NeedsMic)
                .font(.system(size: 11, design: .monospaced))
        }
        .foregroundStyle(Color.orange.opacity(0.8))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.08))
    }
}

// MARK: - CGFloat clamp helper

extension Comparable {
    fileprivate func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - Previews

struct RT60View_Previews: PreviewProvider {
    static var previews: some View {
        let idle = RT60Analyzer()
        RT60View(analyzer: idle, isRunning: false)
            .environmentObject(LanguageManager())
            .preferredColorScheme(.dark)
            .previewDisplayName("Idle")

        let done = RT60Analyzer()
        let env: [Float] = (0..<200).map { i in
            let t = Float(i) * 0.02
            return min(-3.0, -5.0 - 12.0 * t + Float.random(in: -1...1))
        }
        let _ = {
            done.state = .done(RT60Result(rt60: 1.2, t20: 0.4, envelope: env,
                                          idx5: 20, idx25: 40, isValid: true))
        }()
        RT60View(analyzer: done, isRunning: true)
            .environmentObject(LanguageManager())
            .preferredColorScheme(.dark)
            .previewDisplayName("Done")
    }
}

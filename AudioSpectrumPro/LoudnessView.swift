//  LoudnessView.swift
//  AudioSpectrumPro

import SwiftUI

struct LoudnessView: View {
    let lufsMomentary: Float
    let lufsShortTerm: Float
    let lufsIntegrated: Float
    let truePeakDB: Float
    let history: [Float]
    @EnvironmentObject private var langManager: LanguageManager

    var body: some View {
        VStack(spacing: 0) {
            metersRow
            Divider().background(Color.white.opacity(0.1))
            historyGraph
        }
        .background(Color.black)
    }

    // MARK: - Level Meters (ITU-R BS.1770: M = 400 ms, S = 3 s, I = gated session)

    private var metersRow: some View {
        HStack(spacing: 18) {
            LevelMeterView(
                label: "M",
                valueDB: lufsMomentary,
                unit: "LUFS",
                color: .cyan
            )
            LevelMeterView(
                label: "S",
                valueDB: lufsShortTerm,
                unit: "LUFS",
                color: .green
            )
            LevelMeterView(
                label: "I",
                valueDB: lufsIntegrated,
                unit: "LUFS",
                color: .white
            )
            LevelMeterView(
                label: "TP",
                valueDB: truePeakDB,
                unit: "dBTP",
                color: truePeakDB > -1 ? .red : .orange
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
    }

    // MARK: - History graph

    private var historyGraph: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(langManager.l10n.loudnessHistory)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.4))
                .padding(.horizontal, 12)
                .padding(.top, 8)

            Canvas { context, size in
                guard history.count > 1 else { return }

                let count = history.count
                let chartH = size.height - 4

                // Grid lines
                for db in [-60, -40, -20, 0] as [Float] {
                    let y = yPos(db: db, height: chartH)
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(path, with: .color(Color.white.opacity(0.08)), lineWidth: 0.5)
                }

                // Fill + line
                var fill = Path()
                var line = Path()
                for i in 0..<count {
                    let x = CGFloat(i) / CGFloat(count - 1) * size.width
                    let y = yPos(db: history[i], height: chartH)
                    if i == 0 {
                        fill.move(to: CGPoint(x: x, y: chartH))
                        fill.addLine(to: CGPoint(x: x, y: y))
                        line.move(to: CGPoint(x: x, y: y))
                    } else {
                        fill.addLine(to: CGPoint(x: x, y: y))
                        line.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                fill.addLine(to: CGPoint(x: size.width, y: chartH))
                fill.closeSubpath()

                context.fill(fill, with: .color(Color.green.opacity(0.2)))
                context.stroke(line, with: .color(Color.green.opacity(0.8)), lineWidth: 1.2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
    }

    private func yPos(db: Float, height: CGFloat) -> CGFloat {
        let t = CGFloat((db - FFTProcessor.maxDB) / (FFTProcessor.minDB - FFTProcessor.maxDB))
        return t * height
    }
}

// MARK: - Single level meter

struct LevelMeterView: View {
    let label: String
    let valueDB: Float
    var unit: String = "dB"
    let color: Color

    private let minDB = FFTProcessor.minDB
    private let maxDB = FFTProcessor.maxDB

    var body: some View {
        VStack(spacing: 6) {
            // Value readout
            Text(valueDB > minDB
                 ? "\(valueDB, format: .number.precision(.fractionLength(1))) \(unit)"
                 : "–∞")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .frame(minWidth: 74)

            // Vertical bar
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    // Background track
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.07))

                    // Level fill
                    let fraction = CGFloat((valueDB - minDB) / (maxDB - minDB))
                    let clamped  = max(0, min(1, fraction))

                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.6), color],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(height: geo.size.height * clamped)
                        .animation(.easeOut(duration: 0.05), value: clamped)
                }
            }
            .frame(width: 28, height: 120)

            Text(label)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.5))
        }
    }
}


//  SpectrumView.swift
//  AudioSpectrumPro

import SwiftUI

struct SpectrumView: View {
    let displayData: [Float]
    let peaks: [FrequencyPeak]
    /// Max-envelope trace (peak hold); empty when disabled.
    var holdTrace: [Float] = []
    /// Present in the live view; nil hides the HOLD control (e.g. snapshots).
    var peakHoldEnabled: Binding<Bool>? = nil
    var peakHoldAccessibilityLabel: String = "Peak hold"
    /// Snapshot rendering: draw current peak labels directly at full opacity
    /// (the timeline/fade state machine never runs inside ImageRenderer).
    var isSnapshot: Bool = false

    // Grid configuration
    private let gridFrequencies: [Float] = [50, 100, 200, 500, 1000, 2000, 5000, 10000, 16000]
    private let gridDBLevels: [Float] = [0, -20, -40, -60]

    // Peak hold labels: each entry keeps the peak plus the moment it should expire.
    @State private var heldPeaks: [(peak: FrequencyPeak, expiry: Date)] = []
    private let holdDuration: TimeInterval = 2.5
    private let fadeDuration: TimeInterval = 0.5

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.05, paused: isSnapshot)) { timeline in
            Canvas { context, size in
                drawGrid(context: context, size: size)
                drawSpectrum(context: context, size: size)
                drawHoldTrace(context: context, size: size)
                if isSnapshot {
                    let now = timeline.date
                    let entries = peaks.map { (peak: $0, expiry: now.addingTimeInterval(1)) }
                    drawPeakLabels(context: context, size: size, heldPeaks: entries, now: now)
                } else {
                    let now = timeline.date
                    let visible = heldPeaks.filter { $0.expiry > now }
                    drawPeakLabels(context: context, size: size, heldPeaks: visible, now: now)
                }
            }
        }
        .background(Color.black)
        .overlay(alignment: .topTrailing) { holdButton }
        .onChange(of: peaks) { newPeaks in
            guard !isSnapshot else { return }
            let now    = Date()
            let expiry = now.addingTimeInterval(holdDuration)
            // Drop fully expired entries first
            heldPeaks.removeAll { $0.expiry <= now }
            // Upsert: refresh expiry for a nearby existing entry, or add new one
            for p in newPeaks {
                if let idx = heldPeaks.firstIndex(where: { abs($0.peak.frequency - p.frequency) < 80 }) {
                    heldPeaks[idx] = (peak: p, expiry: expiry)
                } else {
                    heldPeaks.append((peak: p, expiry: expiry))
                }
            }
        }
    }

    // MARK: - HOLD control

    @ViewBuilder
    private var holdButton: some View {
        if let binding = peakHoldEnabled, !isSnapshot {
            Button {
                binding.wrappedValue.toggle()
            } label: {
                Text("HOLD")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(binding.wrappedValue ? Color.orange : Color.white.opacity(0.4))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(binding.wrappedValue ? Color.orange.opacity(0.15) : Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(peakHoldAccessibilityLabel)
            .padding(8)
        }
    }

    // MARK: - Grid

    private func drawGrid(context: GraphicsContext, size: CGSize) {
        let gridColor = Color.white.opacity(0.12)
        let labelColor = Color.white.opacity(0.5)
        let font = Font.system(size: 10, weight: .regular, design: .monospaced)

        // Horizontal lines (dB levels)
        for db in gridDBLevels {
            let y = yPos(db: db, height: size.height)
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(path, with: .color(gridColor), lineWidth: 1)

            let label = db == 0 ? "0 dB" : "\(Int(db)) dB"
            context.draw(
                Text(label).font(font).foregroundColor(labelColor),
                at: CGPoint(x: 28, y: y - 6)
            )
        }

        // Vertical lines (frequencies)
        for freq in gridFrequencies {
            let x = xPos(freq: freq, width: size.width)
            var path = Path()
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height - 18))
            context.stroke(path, with: .color(gridColor), lineWidth: 1)

            let label = freq >= 1000 ? "\(Int(freq / 1000))k" : "\(Int(freq))"
            context.draw(
                Text(label).font(font).foregroundColor(labelColor),
                at: CGPoint(x: x, y: size.height - 8)
            )
        }
    }

    // MARK: - Spectrum

    private func drawSpectrum(context: GraphicsContext, size: CGSize) {
        guard displayData.count > 1 else { return }

        let count = displayData.count
        let chartHeight = size.height - 20 // leave room for freq labels

        // Build filled path
        var fillPath = Path()
        var linePath = Path()

        for i in 0..<count {
            let x = CGFloat(i) / CGFloat(count - 1) * size.width
            let y = yPos(db: displayData[i], height: chartHeight)

            if i == 0 {
                fillPath.move(to: CGPoint(x: x, y: chartHeight))
                fillPath.addLine(to: CGPoint(x: x, y: y))
                linePath.move(to: CGPoint(x: x, y: y))
            } else {
                fillPath.addLine(to: CGPoint(x: x, y: y))
                linePath.addLine(to: CGPoint(x: x, y: y))
            }
        }

        // Close fill path at bottom
        fillPath.addLine(to: CGPoint(x: size.width, y: chartHeight))
        fillPath.closeSubpath()

        // Fill with gradient
        context.fill(
            fillPath,
            with: .linearGradient(
                Gradient(colors: [
                    Color(hue: 0.45, saturation: 1, brightness: 0.9).opacity(0.5),
                    Color(hue: 0.45, saturation: 1, brightness: 0.5).opacity(0.15)
                ]),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: 0, y: chartHeight)
            )
        )

        // Stroke the line on top
        context.stroke(linePath, with: .color(Color(hue: 0.45, saturation: 0.8, brightness: 1.0)), lineWidth: 1.5)
    }

    // MARK: - Peak hold trace

    private func drawHoldTrace(context: GraphicsContext, size: CGSize) {
        guard holdTrace.count > 1 else { return }
        let count = holdTrace.count
        let chartHeight = size.height - 20

        var path = Path()
        for i in 0..<count {
            let x = CGFloat(i) / CGFloat(count - 1) * size.width
            let y = yPos(db: holdTrace[i], height: chartHeight)
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else      { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        context.stroke(path, with: .color(Color.orange.opacity(0.85)), lineWidth: 1)
    }

    // MARK: - Peak Labels

    private func drawPeakLabels(context: GraphicsContext,
                                size: CGSize,
                                heldPeaks: [(peak: FrequencyPeak, expiry: Date)],
                                now: Date) {
        let chartHeight = size.height - 20
        let font = Font.system(size: 11, weight: .bold, design: .monospaced)

        for entry in heldPeaks {
            let peak      = entry.peak
            let remaining = entry.expiry.timeIntervalSince(now)
            // Fade out during the last `fadeDuration` seconds
            let opacity   = remaining < fadeDuration
                            ? CGFloat(remaining / fadeDuration)
                            : 1.0

            let x      = CGFloat(FFTProcessor.normalizedX(for: peak.frequency)) * size.width
            let peakY  = yPos(db: peak.magnitude, height: chartHeight)
            let labelY = max(peakY - 20, 8)

            // Urgency-based colour
            let color: Color = peak.prominence >= 18 ? .red : .yellow

            // Tick mark
            var tick = Path()
            tick.move(to: CGPoint(x: x, y: peakY - 4))
            tick.addLine(to: CGPoint(x: x, y: labelY + 12))
            context.stroke(tick, with: .color(color.opacity(0.7 * opacity)), lineWidth: 1)

            // Frequency label
            context.draw(
                Text(peak.frequencyLabel).font(font).foregroundColor(color.opacity(opacity)),
                at: CGPoint(x: x, y: labelY)
            )
        }
    }

    // MARK: - Helpers

    private func xPos(freq: Float, width: CGFloat) -> CGFloat {
        CGFloat(FFTProcessor.normalizedX(for: freq)) * width
    }

    private func yPos(db: Float, height: CGFloat) -> CGFloat {
        let t = CGFloat((db - FFTProcessor.maxDB) / (FFTProcessor.minDB - FFTProcessor.maxDB))
        return t * height
    }
}

#if DEBUG
struct SpectrumView_Previews: PreviewProvider {
    static var previews: some View {
        SpectrumView(
            displayData: Array(repeating: -40, count: FFTProcessor.displayBinCount),
            peaks: []
        )
        .frame(height: 300)
        .background(Color.black)
    }
}
#endif

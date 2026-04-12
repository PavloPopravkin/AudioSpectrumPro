
//  SpectrumView.swift
//  AudioSpectrumPro

import SwiftUI

struct SpectrumView: View {
    let displayData: [Float]
    let peaks: [FrequencyPeak]

    // Grid configuration
    private let gridFrequencies: [Float] = [50, 100, 200, 500, 1000, 2000, 5000, 10000, 16000]
    private let gridDBLevels: [Float] = [0, -20, -40, -60]

    var body: some View {
        Canvas { context, size in
            drawGrid(context: context, size: size)
            drawSpectrum(context: context, size: size)
            drawPeakLabels(context: context, size: size)
        }
        .background(Color.black)
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

    // MARK: - Peak Labels

    private func drawPeakLabels(context: GraphicsContext, size: CGSize) {
        let chartHeight = size.height - 20
        let font = Font.system(size: 11, weight: .bold, design: .monospaced)

        for peak in peaks {
            let x = CGFloat(FFTProcessor.normalizedX(for: peak.frequency)) * size.width
            let peakY = yPos(db: peak.magnitude, height: chartHeight)
            let labelY = max(peakY - 20, 8)

            // Urgency-based colour
            let color: Color = peak.prominence >= 18 ? .red : .yellow

            // Tick mark
            var tick = Path()
            tick.move(to: CGPoint(x: x, y: peakY - 4))
            tick.addLine(to: CGPoint(x: x, y: labelY + 12))
            context.stroke(tick, with: .color(color.opacity(0.7)), lineWidth: 1)

            // Frequency label
            context.draw(
                Text(peak.frequencyLabel).font(font).foregroundColor(color),
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

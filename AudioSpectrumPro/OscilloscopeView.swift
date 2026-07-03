//  OscilloscopeView.swift
//  AudioSpectrumPro

import SwiftUI

struct OscilloscopeView: View {
    let samples: [Float]

    var body: some View {
        Canvas { context, size in
            // Guard against a collapsed/sub-1pt canvas during tab transitions —
            // a zero width would trap the integer division below.
            guard samples.count > 1, size.width >= 1 else { return }

            let midY   = size.height / 2
            let scaleY = size.height * 0.45   // 90% of half-height for signal

            // Zero line
            var zeroLine = Path()
            zeroLine.move(to: CGPoint(x: 0, y: midY))
            zeroLine.addLine(to: CGPoint(x: size.width, y: midY))
            context.stroke(zeroLine, with: .color(Color.white.opacity(0.1)), lineWidth: 0.5)

            // dB grid lines ±0.5 amplitude
            for amp in [-0.5, 0.5] as [Double] {
                let y = midY - CGFloat(amp) * scaleY
                var gridLine = Path()
                gridLine.move(to: CGPoint(x: 0, y: y))
                gridLine.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(gridLine, with: .color(Color.white.opacity(0.07)), lineWidth: 0.5)
            }

            // Waveform path — downsample to fit width
            let step = max(1, samples.count / max(1, Int(size.width)))
            var waveform = Path()
            var first = true

            var i = 0
            while i < samples.count {
                let x = CGFloat(i) / CGFloat(samples.count) * size.width
                let y = midY - CGFloat(samples[i]) * scaleY

                if first {
                    waveform.move(to: CGPoint(x: x, y: y))
                    first = false
                } else {
                    waveform.addLine(to: CGPoint(x: x, y: y))
                }
                i += step
            }

            context.stroke(
                waveform,
                with: .color(Color(hue: 0.45, saturation: 0.8, brightness: 0.9)),
                lineWidth: 1.2
            )
        }
        .background(Color.black)
    }
}

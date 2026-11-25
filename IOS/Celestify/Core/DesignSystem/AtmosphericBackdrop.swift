//
//  AtmosphericBackdrop.swift
//  Celestify
//
//  Kawarp-inspired artwork color mesh & Celestial starlight particle atmosphere.
//  Built on Myspoti (https://github.com/kota-zo/myspoti), GPL-3.0.
//

import SwiftUI

public struct AtmosphericBackdrop: View {
    public let palette: ArtworkPalette
    public let isAnimating: Bool
    public let showParticles: Bool
    public let particleIntensity: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var prefs: PreferencesStore { PreferencesStore.shared }

    public init(
        palette: ArtworkPalette,
        isAnimating: Bool = true,
        showParticles: Bool = true,
        particleIntensity: Int = 1
    ) {
        self.palette = palette
        self.isAnimating = isAnimating
        self.showParticles = showParticles
        self.particleIntensity = particleIntensity
    }

    public init(
        palette: ArtworkPalette,
        isPlaying: Bool,
        intensity: Double
    ) {
        self.palette = palette
        self.isAnimating = isPlaying
        self.showParticles = intensity > 0.35
        self.particleIntensity = intensity >= 0.8 ? 2 : 1
    }

    public var body: some View {
        let animate = isAnimating && !reduceMotion && !prefs.reduceAnimations && !prefs.energySaverEnabled
        ZStack {
            Color.black.ignoresSafeArea()

            if animate {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    meshSurface(phase: t)
                    if showParticles && prefs.ambientParticles && particleIntensity > 0 {
                        starlightCanvas(phase: t)
                    }
                }
            } else {
                meshSurface(phase: 0)
            }

            // Subtle vignette keeping foreground lyrics and controls crisp at WCAG contrast
            RadialGradient(
                colors: [
                    Color.black.opacity(0.10),
                    Color.black.opacity(0.46)
                ],
                center: .center,
                startRadius: 80,
                endRadius: 620
            )
            .ignoresSafeArea()
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func meshSurface(phase: TimeInterval) -> some View {
        let stops = palette.meshColors
        if #available(iOS 18.0, *), stops.count == 9 {
            let dx = Float(sin(phase * 0.31) * 0.14)
            let dy = Float(cos(phase * 0.23) * 0.14)
            MeshGradient(
                width: 3,
                height: 3,
                points: [
                    SIMD2(0.0, 0.0), SIMD2(0.5 + dx * 0.5, 0.0), SIMD2(1.0, 0.0),
                    SIMD2(0.0, 0.5 - dy * 0.5), SIMD2(0.5 + dx, 0.5 + dy), SIMD2(1.0, 0.5 + dy * 0.4),
                    SIMD2(0.0, 1.0), SIMD2(0.5 - dx * 0.5, 1.0), SIMD2(1.0, 1.0)
                ],
                colors: stops,
                smoothsColors: true
            )
            .ignoresSafeArea()
        } else {
            Canvas { context, size in
                let colors = stops.isEmpty ? ArtworkPalette.celestialDefault.meshColors : stops
                for (index, color) in colors.prefix(5).enumerated() {
                    let angle = phase * (0.20 + Double(index) * 0.05) + Double(index) * 1.25
                    let cx = size.width * (0.5 + 0.32 * cos(angle))
                    let cy = size.height * (0.5 + 0.32 * sin(angle * 0.85))
                    let radius = max(size.width, size.height) * 0.72
                    let rect = CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2)
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .radialGradient(
                            Gradient(colors: [color.opacity(0.85), color.opacity(0.0)]),
                            center: CGPoint(x: cx, y: cy),
                            startRadius: 0,
                            endRadius: radius
                        )
                    )
                }
            }
            .ignoresSafeArea()
        }
    }

    private func starlightCanvas(phase: TimeInterval) -> some View {
        let count = particleIntensity == 2 ? 28 : 14
        return Canvas { context, size in
            for idx in 0..<count {
                let seed = Double(idx * 97 + 13)
                let xNorm = fmod(seed * 0.61803398875 + phase * 0.008 * ((idx % 2 == 0) ? 1 : -1), 1.0)
                let yNorm = fmod(seed * 0.38196601125 - phase * (0.012 + Double(idx % 4) * 0.003), 1.0)
                let px = (xNorm < 0 ? xNorm + 1 : xNorm) * size.width
                let py = (yNorm < 0 ? yNorm + 1 : yNorm) * size.height
                let pulse = 0.25 + 0.45 * (0.5 + 0.5 * sin(phase * 1.4 + seed))
                let radius = CGFloat(1.1 + Double(idx % 3) * 0.75)
                let rect = CGRect(x: px - radius, y: py - radius, width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(pulse * 0.42)))
            }
        }
        .ignoresSafeArea()
    }
}

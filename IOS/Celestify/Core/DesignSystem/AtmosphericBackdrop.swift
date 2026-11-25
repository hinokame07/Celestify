//
//  AtmosphericBackdrop.swift
//  Celestify
//
//  Subtle artwork-derived color wash for the player and sign-in screen.
//  Built on Myspoti (https://github.com/kota-zo/myspoti), GPL-3.0.
//

import SwiftUI

public struct AtmosphericBackdrop: View {
    public let palette: ArtworkPalette
    public let isAnimating: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.celestialTheme) private var theme
    private var prefs: PreferencesStore { PreferencesStore.shared }

    public init(palette: ArtworkPalette, isAnimating: Bool = true) {
        self.palette = palette
        self.isAnimating = isAnimating
    }

    public var body: some View {
        let animate = isAnimating && !reduceMotion && !prefs.reduceAnimations && !prefs.energySaverEnabled
        ZStack {
            theme.page.ignoresSafeArea()

            if animate {
                TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    meshSurface(phase: t)
                }
            } else {
                meshSurface(phase: 0)
            }

            RadialGradient(
                colors: [
                    theme.page.opacity(0.08),
                    theme.page.opacity(0.54)
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
        let stops = palette.meshColors.map { $0.opacity(theme.isLight ? 0.16 : 0.24) }
        if #available(iOS 18.0, *), stops.count == 9 {
            let dx = Float(sin(phase * 0.16) * 0.045)
            let dy = Float(cos(phase * 0.12) * 0.045)
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
                let colors = stops.isEmpty
                    ? ArtworkPalette.celestialDefault.meshColors.map { $0.opacity(theme.isLight ? 0.16 : 0.24) }
                    : stops
                for (index, color) in colors.prefix(5).enumerated() {
                    let angle = phase * (0.08 + Double(index) * 0.02) + Double(index) * 1.25
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
}

//
//  LiquidGlass.swift
//  Celestify
//
//  Native Apple Liquid Glass design system with iOS 26 API adoption and
//  tactile refractive material fallback for iOS 17–18.
//  Built on Myspoti (https://github.com/kota-zo/myspoti), GPL-3.0.
//

import SwiftUI

public enum LiquidGlassRenderPath: String, Sendable {
    case nativeIOS26Glass = "NATIVE_IOS26_LIQUID_GLASS"
    case refractiveMaterial = "REFRACTIVE_SYSTEM_MATERIAL"
    case reducedTransparency = "ACCESSIBILITY_OPAQUE_SURFACE"

    public static func current(
        preferenceEnabled: Bool,
        reduceTransparency: Bool
    ) -> LiquidGlassRenderPath {
        if reduceTransparency || !preferenceEnabled {
            return .reducedTransparency
        }
        if #available(iOS 26.0, *) {
            return .nativeIOS26Glass
        }
        return .refractiveMaterial
    }
}

public enum GlassProminence: Sendable {
    /// Floating chrome: tab bar, mini-player, floating top action pills.
    case regular
    /// Thin interactive controls, chips, and badges.
    case thin
    /// Sheets, dialogs, and dense cards where multi-line text legibility dominates.
    case thick
}

/// Applies native iOS 26 `.glassEffect(...)` when running on iOS 26+,
/// falling back cleanly to layered `.ultraThinMaterial` + vibrancy specular rim on iOS 17–18,
/// and respecting `accessibilityReduceTransparency` / `accessibilityReduceMotion`.
public struct CelestialLiquidGlassModifier<S: InsettableShape>: ViewModifier {
    public let shape: S
    public let prominence: GlassProminence
    public let tint: Color?
    public let isInteractive: Bool

    @Environment(\.celestial) private var celestial
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var prefs: PreferencesStore { PreferencesStore.shared }

    public func body(content: Content) -> some View {
        let path = LiquidGlassRenderPath.current(
            preferenceEnabled: prefs.liquidGlassEnabled,
            reduceTransparency: reduceTransparency
        )
        Group {
            switch path {
            case .reducedTransparency:
                content
                    .background(celestial.elevated, in: shape)
                    .overlay {
                        shape.strokeBorder(celestial.separator, lineWidth: 1)
                    }

            case .nativeIOS26Glass, .refractiveMaterial:
                applyGlassBody(to: content)
            }
        }
    }

    @ViewBuilder
    private func applyGlassBody(to content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            if let tint {
                content.glassEffect(.regular.tint(tint).interactive(isInteractive), in: shape)
            } else {
                content.glassEffect(.regular.interactive(isInteractive), in: shape)
            }
        } else {
            materialFallback(content)
        }
        #else
        materialFallback(content)
        #endif
    }

    private func materialFallback(_ content: Content) -> some View {
        let material: Material = {
            switch prominence {
            case .thin: return .ultraThinMaterial
            case .regular: return .thinMaterial
            case .thick: return .regularMaterial
            }
        }()

        return content
            .background {
                ZStack {
                    shape.fill(material)
                    if let tint {
                        shape.fill(tint.opacity(celestial.isLight ? 0.14 : 0.18))
                    } else {
                        shape.fill(celestial.glassFill.opacity(0.32))
                    }
                }
            }
            .overlay {
                shape.strokeBorder(celestial.glassEdge.opacity(0.65), lineWidth: 0.75)
            }
            .shadow(
                color: Color.black.opacity(celestial.isLight ? 0.06 : 0.12),
                radius: prominence == .thin ? 4 : 8,
                x: 0,
                y: prominence == .thin ? 2 : 4
            )
    }
}

/// Interactive press spring style for Liquid Glass controls (subtle bulge + specular lift).
public struct LiquidGlassButtonStyle: ButtonStyle {
    public var scaleOnPress: CGFloat = 0.96
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(scaleOnPress: CGFloat = 0.96) {
        self.scaleOnPress = scaleOnPress
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? scaleOnPress : 1.0)
            .brightness(configuration.isPressed ? 0.04 : 0.0)
            .animation(
                reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.72),
                value: configuration.isPressed
            )
    }
}

public extension View {
    func celestialLiquidGlass<S: InsettableShape>(
        in shape: S,
        prominence: GlassProminence = .regular,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        modifier(
            CelestialLiquidGlassModifier(
                shape: shape,
                prominence: prominence,
                tint: tint,
                isInteractive: interactive
            )
        )
    }

    func celestialGlassCapsule(
        prominence: GlassProminence = .regular,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        celestialLiquidGlass(
            in: Capsule(style: .continuous),
            prominence: prominence,
            tint: tint,
            interactive: interactive
        )
    }

    func celestialGlassCard(
        cornerRadius: CGFloat = 22,
        prominence: GlassProminence = .regular,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        celestialLiquidGlass(
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
            prominence: prominence,
            tint: tint,
            interactive: interactive
        )
    }

    func celestialGlassCircle(
        prominence: GlassProminence = .thin,
        tint: Color? = nil,
        interactive: Bool = true
    ) -> some View {
        celestialLiquidGlass(
            in: Circle(),
            prominence: prominence,
            tint: tint,
            interactive: interactive
        )
    }

    func liquidGlass<S: InsettableShape>(
        shape: S,
        prominence: GlassProminence = .regular,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        celestialLiquidGlass(
            in: shape,
            prominence: prominence,
            tint: tint,
            interactive: interactive
        )
    }
}

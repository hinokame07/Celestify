//
//  CelestialTheme.swift
//  Celestify
//
//  Built on Myspoti (https://github.com/kota-zo/myspoti), GPL-3.0.
//

import Foundation
import SwiftUI

/// Resolved semantic design tokens for built-in palettes, system appearance,
/// and imported Spicetify/Glassify themes.
public struct CelestialTokens: Sendable, Equatable {
    public let page: Color
    public let secondary: Color
    public let elevated: Color
    public let textPrimary: Color
    public let textSecondary: Color
    public let separator: Color
    public let accent: Color
    public let onAccent: Color
    public let glassFill: Color
    public let glassEdge: Color
    public let destructive: Color
    public let isLight: Bool

    public static func resolve(
        palette: CelestialPalette,
        colorScheme: ColorScheme,
        dynamicColorsEnabled: Bool,
        artworkPalette: ArtworkPalette?,
        importedTheme: InstalledTheme?
    ) -> CelestialTokens {
        let isLight = colorScheme == .light && importedTheme == nil
        let artworkHex: UInt32? = dynamicColorsEnabled ? artworkPalette?.accentHex : nil

        if isLight {
            let basePage: UInt32 = palette == .goldenSeraph ? 0xFFFAF6EE : 0xFFF5F6FA
            let baseSec: UInt32 = palette == .goldenSeraph ? 0xFFF0EAE0 : 0xFFFFFFFF
            let baseElev: UInt32 = palette == .goldenSeraph ? 0xFFE6DEC9 : 0xFFEBEDF3
            let accentHex: UInt32 = (palette == .adaptive ? artworkHex : nil) ?? palette.defaultAccentHex
            return CelestialTokens(
                page: Color(argb: blendARGB(basePage, with: artworkHex, amount: palette == .adaptive ? 0.04 : 0)),
                secondary: Color(argb: blendARGB(baseSec, with: artworkHex, amount: palette == .adaptive ? 0.03 : 0)),
                elevated: Color(argb: baseElev),
                textPrimary: Color(argb: 0xFF121317),
                textSecondary: Color(argb: 0xFF5A5D68),
                separator: Color.black.opacity(0.08),
                accent: Color(argb: accentHex),
                onAccent: luminance(of: accentHex) < 0.179 ? .white : .black,
                glassFill: Color.white.opacity(0.72),
                glassEdge: Color(argb: accentHex).opacity(0.22),
                destructive: Color(argb: 0xFFFF3B30),
                isLight: true
            )
        }

        let imported = importedTheme?.colors
        let effects = importedTheme?.effects
        let useArtwork = dynamicColorsEnabled && (palette == .adaptive || effects?.dynamicArtwork == true)
        let activeArt = useArtwork ? artworkHex : nil

        let basePage: UInt32 = imported?.background ?? (palette == .goldenSeraph ? 0xFF050402 : 0xFF000000)
        let baseSec: UInt32 = imported?.surface ?? (palette == .goldenSeraph ? 0xFF1C1A16 : 0xFF1C1C1E)
        let baseElev: UInt32 = imported?.elevated ?? (palette == .goldenSeraph ? 0xFF2C2921 : 0xFF2C2C2E)

        let surfaceTint = effects?.surfaceTint ?? (palette == .adaptive ? 0.05 : 0.0)
        let pageHex = blendARGB(basePage, with: activeArt, amount: surfaceTint * 0.45)
        let secHex = blendARGB(baseSec, with: activeArt, amount: surfaceTint)
        let elevHex = blendARGB(baseElev, with: activeArt, amount: surfaceTint * 1.25)

        let textHex: UInt32 = imported?.text ?? (palette == .goldenSeraph ? 0xFFFFFAED : 0xFFF5F5F7)
        let subHex: UInt32 = imported?.secondary ?? (palette == .goldenSeraph ? 0xFFC7BFAE : 0xFFA1A1A6)

        let accentHex: UInt32 = {
            if effects?.dynamicArtwork == true {
                return activeArt ?? imported?.accent ?? palette.defaultAccentHex
            }
            if let impAccent = imported?.accent {
                return impAccent
            }
            return activeArt ?? palette.defaultAccentHex
        }()

        let glassAlpha = effects?.glassOpacity ?? 0.76
        let edgeHex = blendARGB(textHex, with: accentHex, amount: 0.45)
        let edgeAlpha = effects?.presentation == .glassify ? 0.28 : 0.17

        return CelestialTokens(
            page: Color(argb: pageHex),
            secondary: Color(argb: secHex),
            elevated: Color(argb: elevHex),
            textPrimary: Color(argb: textHex),
            textSecondary: Color(argb: subHex),
            separator: Color(argb: textHex).opacity(0.10),
            accent: Color(argb: accentHex),
            onAccent: luminance(of: accentHex) < 0.179 ? .white : .black,
            glassFill: Color(argb: secHex).opacity(glassAlpha),
            glassEdge: Color(argb: edgeHex).opacity(edgeAlpha),
            destructive: Color(argb: 0xFFFF453A),
            isLight: false
        )
    }

    public static func blendARGB(_ a: UInt32, with b: UInt32?, amount: Double) -> UInt32 {
        guard let b, amount > 0 else { return a }
        let t = min(max(amount, 0.0), 1.0)
        let ar = Double((a >> 16) & 0xFF)
        let ag = Double((a >> 8) & 0xFF)
        let ab = Double(a & 0xFF)
        let br = Double((b >> 16) & 0xFF)
        let bg = Double((b >> 8) & 0xFF)
        let bb = Double(b & 0xFF)
        let r = UInt32(ar + (br - ar) * t)
        let g = UInt32(ag + (bg - ag) * t)
        let bl = UInt32(ab + (bb - ab) * t)
        return 0xFF000000 | (r << 16) | (g << 8) | bl
    }

    public static func luminance(of argb: UInt32) -> Double {
        func linear(_ byte: UInt32) -> Double {
            let v = Double(byte & 0xFF) / 255.0
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(argb >> 16) + 0.7152 * linear(argb >> 8) + 0.0722 * linear(argb)
    }
}

// MARK: - Environment Key

private struct CelestialTokensKey: EnvironmentKey {
    static let defaultValue = CelestialTokens.resolve(
        palette: .adaptive,
        colorScheme: .dark,
        dynamicColorsEnabled: true,
        artworkPalette: .celestialDefault,
        importedTheme: nil
    )
}

public extension EnvironmentValues {
    var celestial: CelestialTokens {
        get { self[CelestialTokensKey.self] }
        set { self[CelestialTokensKey.self] = newValue }
    }

    var celestialTheme: CelestialTokens {
        get { self[CelestialTokensKey.self] }
        set { self[CelestialTokensKey.self] = newValue }
    }
}

public typealias CelestialTheme = CelestialTokens

public extension CelestialTokens {
    var background: Color { page }
    var surface: Color { secondary }
    var primaryText: Color { textPrimary }
    var secondaryText: Color { textSecondary }
}

// MARK: - System Typography Helpers

public enum CelestialFont {
    public static var largeTitle: Font { .system(.largeTitle, design: .default, weight: .bold) }
    public static var title: Font { .system(.title2, design: .default, weight: .bold) }
    public static var headline: Font { .system(.headline, design: .default, weight: .semibold) }
    public static var body: Font { .system(.body, design: .default, weight: .regular) }
    public static var bodyStrong: Font { .system(.body, design: .default, weight: .semibold) }
    public static var subhead: Font { .system(.subheadline, design: .default, weight: .medium) }
    public static var caption: Font { .system(.caption, design: .default, weight: .medium) }

    public static func lyricLine(scale: Double = 1.0, emphasized: Bool = true) -> Font {
        .system(size: CGFloat(28.0 * scale), weight: emphasized ? .bold : .semibold, design: .default)
    }

    public static func lyricSubline(scale: Double = 1.0) -> Font {
        .system(size: CGFloat(15.5 * scale), weight: .medium, design: .default)
    }
}

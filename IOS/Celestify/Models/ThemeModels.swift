//
//  ThemeModels.swift
//  Celestify
//
//  Built on Myspoti (https://github.com/kota-zo/myspoti), GPL-3.0.
//  Glassify compatibility profile adapted under AGPL-3.0 (see THIRD_PARTY_NOTICES.md).
//

import Foundation
import SwiftUI

public enum CelestialPalette: String, Codable, Sendable, CaseIterable, Identifiable {
    case midnight = "BLUE"
    case goldenSeraph = "GOLD"
    case adaptive = "ADAPTIVE"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .midnight: return "Celestial Midnight"
        case .goldenSeraph: return "Golden Seraph"
        case .adaptive: return "Adaptive Celestial"
        }
    }

    public var subtitle: String {
        switch self {
        case .midnight: return "Obsidian glass with deep sapphire luminescence"
        case .goldenSeraph: return "Warm onyx surfaces with champagne and seraphic gold"
        case .adaptive: return "Live artwork color extraction with Liquid Glass refraction"
        }
    }

    public var defaultAccentHex: UInt32 {
        switch self {
        case .midnight: return 0xFF0A84FF
        case .goldenSeraph: return 0xFFFFD60A
        case .adaptive: return 0xFFFF5C74
        }
    }
}

public enum AppearanceMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case system = "system"
    case dark = "dark"
    case light = "light"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system: return "Automatic (System)"
        case .dark: return "Dark"
        case .light: return "Light"
        }
    }

    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .dark: return .dark
        case .light: return .light
        }
    }
}

public enum ThemeCompatibility: String, Codable, Sendable {
    case full = "FULL"
    case partial = "PARTIAL"
    case unsupported = "UNSUPPORTED"
}

public enum ThemePresentation: String, Codable, Sendable {
    case standard = "STANDARD"
    case glassify = "GLASSIFY"
}

/// Native-only rendering hints. Remote CSS and JavaScript are never executed.
public struct NativeEffects: Codable, Sendable, Equatable, Hashable {
    public let presentation: ThemePresentation
    public let dynamicArtwork: Bool
    public let glassOpacity: Double
    public let surfaceTint: Double
    public let preferLiquidGlass: Bool

    public init(
        presentation: ThemePresentation = .standard,
        dynamicArtwork: Bool = false,
        glassOpacity: Double = 0.84,
        surfaceTint: Double = 0.0,
        preferLiquidGlass: Bool = false
    ) {
        self.presentation = presentation
        self.dynamicArtwork = dynamicArtwork
        self.glassOpacity = min(max(glassOpacity, 0.35), 0.96)
        self.surfaceTint = min(max(surfaceTint, 0.0), 0.18)
        self.preferLiquidGlass = preferLiquidGlass
    }

    public static let glassify = NativeEffects(
        presentation: .glassify,
        dynamicArtwork: true,
        glassOpacity: 0.70,
        surfaceTint: 0.08,
        preferLiquidGlass: true
    )
}

/// ARGB 32-bit color palette converted safely from Spicetify/Celestify theme definitions.
public struct NativeColors: Codable, Sendable, Equatable, Hashable {
    public let background: UInt32
    public let surface: UInt32
    public let elevated: UInt32
    public let text: UInt32
    public let secondary: UInt32
    public let accent: UInt32

    public init(
        background: UInt32,
        surface: UInt32,
        elevated: UInt32,
        text: UInt32,
        secondary: UInt32,
        accent: UInt32
    ) {
        self.background = background
        self.surface = surface
        self.elevated = elevated
        self.text = text
        self.secondary = secondary
        self.accent = accent
    }
}

public struct ConvertedTheme: Codable, Sendable, Equatable, Hashable {
    public let schemes: [String: NativeColors]
    public let compatibility: ThemeCompatibility
    public let notices: [String]
    public let effects: NativeEffects

    public init(
        schemes: [String: NativeColors],
        compatibility: ThemeCompatibility,
        notices: [String] = [],
        effects: NativeEffects = NativeEffects()
    ) {
        self.schemes = schemes
        self.compatibility = compatibility
        self.notices = notices
        self.effects = effects
    }
}

public struct ThemeCandidate: Codable, Sendable, Hashable, Identifiable {
    public var id: String { "\(repository)/\(path)" }
    public let repository: String
    public let path: String
    public let revision: String
    public let files: Set<String>
    public let description: String
    public let author: String

    public init(
        repository: String,
        path: String,
        revision: String,
        files: Set<String>,
        description: String,
        author: String
    ) {
        self.repository = repository
        self.path = path
        self.revision = revision
        self.files = files
        self.description = description
        self.author = author
    }

    public var name: String {
        let leaf = path.split(separator: "/").last.map(String.init) ?? ""
        if !leaf.isEmpty { return leaf }
        return repository.split(separator: "/").last.map(String.init) ?? repository
    }

    public var pageURL: String {
        path.isEmpty
            ? "https://github.com/\(repository)"
            : "https://github.com/\(repository)/tree/\(revision)/\(path)"
    }
}

public struct ThemePreview: Sendable, Hashable, Identifiable {
    public var id: String { candidate.id }
    public let candidate: ThemeCandidate
    public let converted: ConvertedTheme
    public let name: String
    public let author: String
    public let description: String
    public let screenshotData: Data?

    public init(
        candidate: ThemeCandidate,
        converted: ConvertedTheme,
        name: String,
        author: String,
        description: String,
        screenshotData: Data? = nil
    ) {
        self.candidate = candidate
        self.converted = converted
        self.name = name
        self.author = author
        self.description = description
        self.screenshotData = screenshotData
    }
}

public struct InstalledTheme: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let author: String
    public let repository: String
    public let schemeName: String
    public let colors: NativeColors
    public let effects: NativeEffects
    public let notices: [String]

    public init(
        id: String,
        name: String,
        author: String,
        repository: String,
        schemeName: String,
        colors: NativeColors,
        effects: NativeEffects,
        notices: [String] = []
    ) {
        self.id = id
        self.name = name
        self.author = author
        self.repository = repository
        self.schemeName = schemeName
        self.colors = colors
        self.effects = effects
        self.notices = notices
    }
}

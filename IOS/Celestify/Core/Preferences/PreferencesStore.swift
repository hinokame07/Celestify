//
//  PreferencesStore.swift
//  Celestify
//
//  Built on Myspoti (https://github.com/kota-zo/myspoti), GPL-3.0.
//

import Foundation
import Observation

public enum StreamingQuality: String, Codable, Sendable, CaseIterable, Identifiable {
    case auto = "AUTO"
    case low = "LOW"
    case normal = "NORMAL"
    case high = "HIGH"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .auto: return "Automatic"
        case .low: return "Low (24–96 kbps)"
        case .normal: return "Normal (160 kbps)"
        case .high: return "Very High (320 kbps)"
        }
    }

    public var detail: String {
        switch self {
        case .auto: return "Adapts dynamically to connection bandwidth"
        case .low: return "Minimizes cellular data usage"
        case .normal: return "Balanced clarity and bandwidth"
        case .high: return "Highest Web Player stream bitrate available"
        }
    }
}

public enum DownloadQuality: String, Codable, Sendable, CaseIterable, Identifiable {
    case off = "OFF"
    case small = "SMALL"
    case cd = "CD"
    case hiRes = "HI_RES"
    case ask = "ASK"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .off: return "Off"
        case .small: return "Compact AAC / Ogg"
        case .cd: return "Lossless CD (16-bit / 44.1 kHz)"
        case .hiRes: return "Hi-Res Lossless (up to 24-bit)"
        case .ask: return "Ask Every Time"
        }
    }
}

@Observable
@MainActor
public final class PreferencesStore {
    public static let shared = PreferencesStore()

    private let defaults: UserDefaults

    // MARK: - Display, Palette & Liquid Glass
    public var celestialPalette: CelestialPalette {
        didSet { defaults.set(celestialPalette.rawValue, forKey: Keys.celestialPalette) }
    }
    public var appearanceMode: AppearanceMode {
        didSet { defaults.set(appearanceMode.rawValue, forKey: Keys.appearanceMode) }
    }
    public var liquidGlassEnabled: Bool {
        didSet { defaults.set(liquidGlassEnabled, forKey: Keys.liquidGlassEnabled) }
    }
    public var dynamicArtworkColors: Bool {
        didSet { defaults.set(dynamicArtworkColors, forKey: Keys.dynamicArtworkColors) }
    }
    public var ambientParticles: Bool {
        didSet { defaults.set(ambientParticles, forKey: Keys.ambientParticles) }
    }
    public var particleIntensity: Int {
        didSet { defaults.set(min(max(particleIntensity, 0), 2), forKey: Keys.particleIntensity) }
    }
    public var lyricsGlow: Bool {
        didSet { defaults.set(lyricsGlow, forKey: Keys.lyricsGlow) }
    }
    public var reduceAnimations: Bool {
        didSet { defaults.set(reduceAnimations, forKey: Keys.reduceAnimations) }
    }
    public var libraryGridView: Bool {
        didSet { defaults.set(libraryGridView, forKey: Keys.libraryGridView) }
    }
    public var musicVideoEnabled: Bool {
        didSet { defaults.set(musicVideoEnabled, forKey: Keys.musicVideoEnabled) }
    }
    public var pureBlackOLED: Bool {
        didSet { defaults.set(pureBlackOLED, forKey: "pure_black_oled") }
    }
    public var audioNormalization: Bool {
        didSet { defaults.set(audioNormalization, forKey: "audio_normalization") }
    }

    // MARK: - Playback
    public var wifiStreamingQuality: StreamingQuality {
        didSet { defaults.set(wifiStreamingQuality.rawValue, forKey: Keys.wifiStreamingQuality) }
    }
    public var cellularStreamingQuality: StreamingQuality {
        didSet { defaults.set(cellularStreamingQuality.rawValue, forKey: Keys.cellularStreamingQuality) }
    }
    public var autoplaySimilar: Bool {
        didSet { defaults.set(autoplaySimilar, forKey: Keys.autoplaySimilar) }
    }
    public var crossfadeSeconds: Int {
        didSet { defaults.set(min(max(crossfadeSeconds, 0), 12), forKey: Keys.crossfadeSeconds) }
    }
    public var headsetSkipEpisodes: Bool {
        didSet { defaults.set(headsetSkipEpisodes, forKey: Keys.headsetSkipEpisodes) }
    }
    public var connectMirrorEnabled: Bool {
        didSet { defaults.set(connectMirrorEnabled, forKey: Keys.connectMirrorEnabled) }
    }

    // MARK: - Lyrics, Timing, Translation & Spicy Stage
    public var lyricsWordSync: Bool {
        didSet { defaults.set(lyricsWordSync, forKey: Keys.lyricsWordSync) }
    }
    public var lyricsExtraSources: Bool {
        didSet { defaults.set(lyricsExtraSources, forKey: Keys.lyricsExtraSources) }
    }
    public var lyricsOffsetMs: Int {
        didSet { defaults.set(min(max(lyricsOffsetMs, -2000), 2000), forKey: Keys.lyricsOffsetMs) }
    }
    public var lyricTranslateLanguage: String {
        didSet { defaults.set(lyricTranslateLanguage, forKey: Keys.lyricTranslateLanguage) }
    }
    public var spicyCatalogueKey: String {
        didSet { defaults.set(spicyCatalogueKey.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.spicyCatalogueKey) }
    }
    public var spicyStageStyle: SpicyStageStyle {
        didSet { defaults.set(spicyStageStyle.rawValue, forKey: Keys.spicyStageStyle) }
    }
    public var spicyStageBackground: SpicyStageBackground {
        didSet { defaults.set(spicyStageBackground.rawValue, forKey: Keys.spicyStageBackground) }
    }
    public var spicyBackgroundBlur: Int {
        didSet { defaults.set(min(max(spicyBackgroundBlur, 0), 64), forKey: Keys.spicyBackgroundBlur) }
    }
    public var spicyLeadMs: Int {
        didSet { defaults.set(min(max(spicyLeadMs, 0), 800), forKey: Keys.spicyLeadMs) }
    }
    public var spicyDuets: Bool {
        didSet { defaults.set(spicyDuets, forKey: Keys.spicyDuets) }
    }
    public var spicyBackingVocals: Bool {
        didSet { defaults.set(spicyBackingVocals, forKey: Keys.spicyBackingVocals) }
    }
    public var spicyRomanize: Bool {
        didSet { defaults.set(spicyRomanize, forKey: Keys.spicyRomanize) }
    }
    public var spicyGeniusMeanings: Bool {
        didSet { defaults.set(spicyGeniusMeanings, forKey: Keys.spicyGeniusMeanings) }
    }
    public var spicyProviderFirst: Bool {
        didSet { defaults.set(spicyProviderFirst, forKey: Keys.spicyProviderFirst) }
    }
    public var spicyDiagnostics: Bool {
        didSet { defaults.set(spicyDiagnostics, forKey: Keys.spicyDiagnostics) }
    }
    public var lyricFontScale: Double {
        didSet { defaults.set(min(max(lyricFontScale, 0.75), 1.45), forKey: Keys.lyricFontScale) }
    }

    // MARK: - Downloads & Data Saver
    public var downloadQuality: DownloadQuality {
        didSet { defaults.set(downloadQuality.rawValue, forKey: Keys.downloadQuality) }
    }
    public var dataSaverEnabled: Bool {
        didSet { defaults.set(dataSaverEnabled, forKey: Keys.dataSaverEnabled) }
    }
    public var energySaverEnabled: Bool {
        didSet { defaults.set(energySaverEnabled, forKey: Keys.energySaverEnabled) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.celestialPalette = CelestialPalette(rawValue: defaults.string(forKey: Keys.celestialPalette) ?? "") ?? .adaptive
        self.appearanceMode = AppearanceMode(rawValue: defaults.string(forKey: Keys.appearanceMode) ?? "") ?? .dark
        self.liquidGlassEnabled = defaults.object(forKey: Keys.liquidGlassEnabled) as? Bool ?? true
        self.dynamicArtworkColors = defaults.object(forKey: Keys.dynamicArtworkColors) as? Bool ?? true
        self.ambientParticles = defaults.object(forKey: Keys.ambientParticles) as? Bool ?? true
        self.particleIntensity = (defaults.object(forKey: Keys.particleIntensity) as? Int ?? 1).clamped(to: 0...2)
        self.lyricsGlow = defaults.object(forKey: Keys.lyricsGlow) as? Bool ?? true
        self.reduceAnimations = defaults.object(forKey: Keys.reduceAnimations) as? Bool ?? false
        self.libraryGridView = defaults.object(forKey: Keys.libraryGridView) as? Bool ?? false
        self.musicVideoEnabled = defaults.object(forKey: Keys.musicVideoEnabled) as? Bool ?? true
        self.pureBlackOLED = defaults.object(forKey: "pure_black_oled") as? Bool ?? true
        self.audioNormalization = defaults.object(forKey: "audio_normalization") as? Bool ?? true

        self.wifiStreamingQuality = StreamingQuality(rawValue: defaults.string(forKey: Keys.wifiStreamingQuality) ?? "") ?? .high
        self.cellularStreamingQuality = StreamingQuality(rawValue: defaults.string(forKey: Keys.cellularStreamingQuality) ?? "") ?? .auto
        self.autoplaySimilar = defaults.object(forKey: Keys.autoplaySimilar) as? Bool ?? true
        self.crossfadeSeconds = (defaults.object(forKey: Keys.crossfadeSeconds) as? Int ?? 0).clamped(to: 0...12)
        self.headsetSkipEpisodes = defaults.object(forKey: Keys.headsetSkipEpisodes) as? Bool ?? false
        self.connectMirrorEnabled = defaults.object(forKey: Keys.connectMirrorEnabled) as? Bool ?? true

        self.lyricsWordSync = defaults.object(forKey: Keys.lyricsWordSync) as? Bool ?? true
        self.lyricsExtraSources = defaults.object(forKey: Keys.lyricsExtraSources) as? Bool ?? false
        self.lyricsOffsetMs = (defaults.object(forKey: Keys.lyricsOffsetMs) as? Int ?? 0).clamped(to: -2000...2000)
        self.lyricTranslateLanguage = defaults.string(forKey: Keys.lyricTranslateLanguage) ?? ""
        self.spicyCatalogueKey = defaults.string(forKey: Keys.spicyCatalogueKey) ?? ""
        self.spicyStageStyle = SpicyStageStyle(rawValue: defaults.string(forKey: Keys.spicyStageStyle) ?? "") ?? .celestify
        self.spicyStageBackground = SpicyStageBackground(rawValue: defaults.string(forKey: Keys.spicyStageBackground) ?? "") ?? .dynamicMesh
        self.spicyBackgroundBlur = (defaults.object(forKey: Keys.spicyBackgroundBlur) as? Int ?? 24).clamped(to: 0...64)
        self.spicyLeadMs = (defaults.object(forKey: Keys.spicyLeadMs) as? Int ?? 350).clamped(to: 0...800)
        self.spicyDuets = defaults.object(forKey: Keys.spicyDuets) as? Bool ?? true
        self.spicyBackingVocals = defaults.object(forKey: Keys.spicyBackingVocals) as? Bool ?? true
        self.spicyRomanize = defaults.object(forKey: Keys.spicyRomanize) as? Bool ?? false
        self.spicyGeniusMeanings = defaults.object(forKey: Keys.spicyGeniusMeanings) as? Bool ?? true
        self.spicyProviderFirst = defaults.object(forKey: Keys.spicyProviderFirst) as? Bool ?? false
        self.spicyDiagnostics = defaults.object(forKey: Keys.spicyDiagnostics) as? Bool ?? false
        self.lyricFontScale = min(max(defaults.object(forKey: Keys.lyricFontScale) as? Double ?? 1.0, 0.75), 1.45)

        self.downloadQuality = DownloadQuality(rawValue: defaults.string(forKey: Keys.downloadQuality) ?? "") ?? .cd
        self.dataSaverEnabled = defaults.object(forKey: Keys.dataSaverEnabled) as? Bool ?? false
        self.energySaverEnabled = defaults.object(forKey: Keys.energySaverEnabled) as? Bool ?? false
    }

    private enum Keys {
        static let celestialPalette = "celestify.palette"
        static let appearanceMode = "celestify.appearance"
        static let liquidGlassEnabled = "immersive_liquid_glass"
        static let dynamicArtworkColors = "dynamic_artwork_colors"
        static let ambientParticles = "ambient_particles"
        static let particleIntensity = "particle_intensity"
        static let lyricsGlow = "lyrics_glow"
        static let reduceAnimations = "reduce_animations"
        static let libraryGridView = "library_grid_view"
        static let musicVideoEnabled = "music_video_enabled"

        static let wifiStreamingQuality = "streaming_wifi_quality"
        static let cellularStreamingQuality = "streaming_cell_quality"
        static let autoplaySimilar = "autoplay_similar"
        static let crossfadeSeconds = "crossfade_seconds"
        static let headsetSkipEpisodes = "headset_skip_episodes"
        static let connectMirrorEnabled = "connect_mirror"

        static let lyricsWordSync = "lyrics_word_sync"
        static let lyricsExtraSources = "lyrics_extra_sources"
        static let lyricsOffsetMs = "lyrics_offset_ms"
        static let lyricTranslateLanguage = "lyric_translate_lang"
        static let spicyCatalogueKey = "spicy_catalogue_key"
        static let spicyStageStyle = "spicy_stage_style"
        static let spicyStageBackground = "spicy_stage_bg"
        static let spicyBackgroundBlur = "spicy_bg_blur"
        static let spicyLeadMs = "spicy_lead_ms"
        static let spicyDuets = "spicy_duets"
        static let spicyBackingVocals = "spicy_backing_vocals"
        static let spicyRomanize = "spicy_romanize"
        static let spicyGeniusMeanings = "spicy_genius_meanings"
        static let spicyProviderFirst = "spicy_provider_first"
        static let spicyDiagnostics = "spicy_diagnostics"
        static let lyricFontScale = "lyric_font_scale"

        static let downloadQuality = "download_quality"
        static let dataSaverEnabled = "data_saver"
        static let energySaverEnabled = "energy_saver"
    }
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}

//
//  LyricsStageView.swift
//  Celestify
//
//  Synchronized lyrics with inline translations and romanization:
//  - `LyricClock` timestamped smoothstep playhead steering
//  - Per-syllable horizontal fill & spring glow lift (`SyllableFlowLayout`)
//  - Duet vocalist opposite alignment (`speaker == .duet`) & `x-bg` backing vocals
//  - Inline Romanization (`Romanizer` + TTML `x-roman`) & Bilingual Translation
//  - Custom `.ttml` local import & +/- 50ms Lyric Offset calibration
//  Built on Myspoti (https://github.com/kota-zo/myspoti), GPL-3.0.
//

import SwiftUI
import UniformTypeIdentifiers

public struct LyricsStageView: View {
    public let track: Track
    public var onShowMeaning: ((String?) -> Void)?

    @Environment(AppDependencies.self) private var deps
    @Environment(\.celestialTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var lyricForeground: Color { theme.isLight ? theme.primaryText : .white }

    @State private var baseLyrics: Lyrics?
    @State private var displayedLyrics: Lyrics?
    @State private var isLoading = true
    @State private var clock = LyricClock()
    @State private var lastScrolledLineIndex: Int = -1
    @State private var manualScrollSuppressionUntil: Date = .distantPast
    @State private var autoScrollGeneration = 0
    @State private var showingOffsetPopover = false
    @State private var showingTTMLImporter = false

    public init(track: Track, onShowMeaning: ((String?) -> Void)? = nil) {
        self.track = track
        self.onShowMeaning = onShowMeaning
    }

    private var isCompactStyle: Bool {
        deps.preferences.spicyStageStyle == .simple || deps.preferences.spicyStageStyle == .minimal
    }

    public var body: some View {
        VStack(spacing: 0) {
            stageControlStrip
                .padding(.horizontal, 18)
                .padding(.bottom, 8)

            if isLoading && displayedLyrics == nil {
                Spacer()
                ProgressView("Loading lyrics…")
                    .tint(lyricForeground)
                    .foregroundStyle(theme.secondaryText)
                Spacer()
            } else if let lyrics = displayedLyrics, !lyrics.lines.isEmpty {
                TimelineView(.animation(minimumInterval: 1.0 / 120.0, paused: !deps.player.isPlaying)) { context in
                    let nowMs = context.date.timeIntervalSinceReferenceDate * 1000.0
                    let posMs: Int64 = {
                        if deps.player.isPlaying && !deps.player.isBuffering {
                            return clock.frame(
                                nowMs: nowMs,
                                reportedMs: deps.player.effectiveLyricPositionMs(),
                                discontinuity: deps.player.seekDiscontinuity
                            )
                        } else {
                            let held = deps.player.effectiveLyricPositionMs()
                            clock.hold(positionMs: held, nowMs: nowMs)
                            return held
                        }
                    }()
                    let clockActiveIndex = lyrics.synced
                        ? LyricTiming.activeLineIndex(in: lyrics.lines, at: posMs)
                        : -1
                    let interlude = lyrics.synced
                        ? LyricTiming.interludeState(in: lyrics.lines, at: posMs)
                        : nil
                    let activeIsInstrumental = lyrics.lines.indices.contains(clockActiveIndex)
                        && lyrics.lines[clockActiveIndex].isInstrumental
                    let activeIdx = interlude != nil && !activeIsInstrumental ? -1 : clockActiveIndex

                    ScrollViewReader { proxy in
                        ScrollView(showsIndicators: false) {
                            LazyVStack(alignment: .leading, spacing: isCompactStyle ? 16 : 24) {
                                Spacer().frame(height: 24)

                                ForEach(lyrics.lines.indices, id: \.self) { idx in
                                    let line = lyrics.lines[idx]
                                    if let interlude,
                                       interlude.startMs == 0,
                                       idx == 0 {
                                        interludeDots(progress: interlude.progress)
                                    }
                                    let isFrameSensitive = lyrics.wordSynced
                                        && activeIdx >= 0
                                        && abs(idx - activeIdx) <= 2
                                    let rowInterludeProgress = idx == activeIdx ? interlude?.progress : nil
                                    let rowKey = LyricLineRenderKey(
                                        line: line,
                                        index: idx,
                                        activeIndex: activeIdx,
                                        framePositionMs: isFrameSensitive ? posMs : nil,
                                        interludeProgress: rowInterludeProgress,
                                        synced: lyrics.synced,
                                        wordSynced: lyrics.wordSynced,
                                        isRTL: lyrics.isRTL,
                                        isCompactStyle: isCompactStyle,
                                        duetAlignment: deps.preferences.spicyDuets,
                                        fontScale: deps.preferences.lyricFontScale,
                                        romanize: deps.preferences.spicyRomanize,
                                        translationLanguage: deps.preferences.lyricTranslateLanguage,
                                        backingVocals: deps.preferences.spicyBackingVocals,
                                        glow: deps.preferences.lyricsGlow,
                                        reduceMotion: reduceMotion
                                    )
                                    EquatableContent(
                                        key: rowKey,
                                        content: lyricLineView(
                                            line: line,
                                            index: idx,
                                            activeIndex: activeIdx,
                                            positionMs: isFrameSensitive ? posMs : line.startMs,
                                            interludeProgress: rowInterludeProgress,
                                            synced: lyrics.synced,
                                            wordSynced: lyrics.wordSynced,
                                            isRTL: lyrics.isRTL
                                        )
                                    )
                                    .equatable()
                                    .id(idx)

                                    if let interlude,
                                       line.endMs == interlude.startMs {
                                        interludeDots(progress: interlude.progress)
                                    }
                                }

                                VStack(alignment: .leading, spacing: 6) {
                                    if !lyrics.songwriters.isEmpty {
                                        Text("Written by \(lyrics.songwriters.joined(separator: ", "))")
                                            .font(.caption)
                                            .foregroundStyle(theme.secondaryText)
                                    }
                                    Text("Source: \(lyrics.provider)")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(theme.secondaryText)
                                }
                                .padding(.top, 20)
                                .padding(.bottom, 80)
                            }
                            .padding(.horizontal, 22)
                        }
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 8)
                                .onChanged { _ in
                                    manualScrollSuppressionUntil = Date().addingTimeInterval(4.0)
                                }
                                .onEnded { _ in
                                    Task {
                                        try? await Task.sleep(nanoseconds: 4_000_000_000)
                                        guard Date() >= manualScrollSuppressionUntil else { return }
                                        manualScrollSuppressionUntil = .distantPast
                                        autoScrollGeneration += 1
                                    }
                                }
                        )
                        .onChange(of: activeIdx) { _, newIdx in
                            guard newIdx >= 0,
                                  newIdx != lastScrolledLineIndex,
                                  Date() >= manualScrollSuppressionUntil else { return }
                            lastScrolledLineIndex = newIdx
                            if reduceMotion {
                                proxy.scrollTo(newIdx, anchor: UnitPoint(x: 0.5, y: 0.36))
                            } else {
                                withAnimation(.spring(response: 0.44, dampingFraction: 0.86)) {
                                    proxy.scrollTo(newIdx, anchor: UnitPoint(x: 0.5, y: 0.36))
                                }
                            }
                        }
                        .onChange(of: autoScrollGeneration) { _, _ in
                            guard activeIdx >= 0 else { return }
                            lastScrolledLineIndex = activeIdx
                            if reduceMotion {
                                proxy.scrollTo(activeIdx, anchor: UnitPoint(x: 0.5, y: 0.36))
                            } else {
                                withAnimation(.spring(response: 0.44, dampingFraction: 0.86)) {
                                    proxy.scrollTo(activeIdx, anchor: UnitPoint(x: 0.5, y: 0.36))
                                }
                            }
                        }
                    }
                }
            } else {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "quote.bubble")
                        .font(.system(size: 40))
                        .foregroundStyle(theme.secondaryText)
                    Text("No Lyrics Found for This Track")
                        .font(.headline)
                        .foregroundStyle(theme.primaryText)
                    Button {
                        showingTTMLImporter = true
                    } label: {
                        Label("Import Custom .ttml Lyrics", systemImage: "doc.badge.plus")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(lyricForeground)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .liquidGlass(shape: Capsule(), interactive: true)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
        }
        .task(id: track.uri) {
            await loadLyricsAndEnhancements()
        }
        .fileImporter(
            isPresented: $showingTTMLImporter,
            allowedContentTypes: [.xml, .plainText],
            allowsMultipleSelection: false
        ) { result in
            // FIX: the `case` pattern needs `= result` (the initializer).
            guard case .success(let urls) = result, let url = urls.first else { return }
            Task {
                // Files picked via fileImporter live outside the app sandbox,
                // so security-scoped access is required to read them.
                let granted = url.startAccessingSecurityScopedResource()
                defer { if granted { url.stopAccessingSecurityScopedResource() } }

                if let imported = try? await SpicyImportsStore.shared.importFile(
                    from: url,
                    forTrackID: track.spotifyID,
                    trackDisplayTitle: track.name
                ) {
                    baseLyrics = imported
                    await refreshEnhancements()
                }
            }
        }
    }

    // MARK: - Top Controls

    private var stageControlStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                pillToggle(
                    title: "Romanize",
                    icon: "character.phonetic",
                    isOn: deps.preferences.spicyRomanize
                ) {
                    deps.preferences.spicyRomanize.toggle()
                    Task { await refreshEnhancements() }
                }

                let translateActive = !deps.preferences.lyricTranslateLanguage.isEmpty
                Menu {
                    ForEach(TranslationLanguageOption.supported) { opt in
                        Button {
                            deps.preferences.lyricTranslateLanguage = opt.code
                            Task { await refreshEnhancements() }
                        } label: {
                            HStack {
                                Text(opt.name)
                                if deps.preferences.lyricTranslateLanguage == opt.code {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Label(translateActive ? "Translate (\(deps.preferences.lyricTranslateLanguage.uppercased()))" : "Translate", systemImage: "globe")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(translateActive ? theme.onAccent : lyricForeground)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .frame(minHeight: 44)
                        .background {
                            if translateActive {
                                Capsule().fill(theme.accent)
                            } else {
                                Capsule().fill(theme.elevated)
                            }
                        }
                }

                if deps.preferences.spicyGeniusMeanings, let onShowMeaning {
                    Button {
                        let posMs = deps.player.effectiveLyricPositionMs()
                        let activeLine = displayedLyrics.flatMap { l -> String? in
                            let idx = LyricTiming.activeLineIndex(in: l.lines, at: posMs)
                            return l.lines.indices.contains(idx) ? l.lines[idx].words : nil
                        }
                        onShowMeaning(activeLine)
                    } label: {
                        Label("Song meaning", systemImage: "text.quote")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(lyricForeground)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .frame(minHeight: 44)
                            .liquidGlass(shape: Capsule(), interactive: true)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    showingOffsetPopover.toggle()
                } label: {
                    let off = deps.preferences.lyricsOffsetMs
                    Label(off == 0 ? "Sync 0ms" : "Sync \(off > 0 ? "+" : "")\(off)ms", systemImage: "metronome")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(off == 0 ? lyricForeground : theme.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .frame(minHeight: 44)
                        .liquidGlass(shape: Capsule(), interactive: true)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingOffsetPopover) {
                    offsetCalibrationView
                        .presentationCompactAdaptation(.popover)
                }

                Menu {
                    ForEach(SpicyStageStyle.allCases) { style in
                        Button {
                            deps.preferences.spicyStageStyle = style
                        } label: {
                            HStack {
                                Text(style.rawValue)
                                if deps.preferences.spicyStageStyle == style {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                    Divider()
                    Button {
                        showingTTMLImporter = true
                    } label: {
                        Label("Import Custom .ttml", systemImage: "doc.badge.plus")
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(lyricForeground)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .frame(width: 44, height: 44)
                        .liquidGlass(shape: Capsule(), interactive: true)
                }
            }
        }
    }

    private func pillToggle(title: String, icon: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: {
            HapticsManager.shared.selection()
            action()
        }) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isOn ? theme.onAccent : lyricForeground)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .frame(minHeight: 44)
                .background {
                    if isOn {
                        Capsule().fill(theme.accent)
                    } else {
                        Capsule().fill(theme.elevated)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private var offsetCalibrationView: some View {
        VStack(spacing: 12) {
            Text("Lyric Timing Calibration")
                .font(.subheadline.weight(.semibold))
            Text("\(deps.preferences.lyricsOffsetMs) ms")
                .font(.title3.monospacedDigit().weight(.bold))
            HStack(spacing: 12) {
                Button("-50 ms") { deps.preferences.lyricsOffsetMs -= 50 }
                    .buttonStyle(.bordered)
                Button("Reset") { deps.preferences.lyricsOffsetMs = 0 }
                    .buttonStyle(.bordered)
                Button("+50 ms") { deps.preferences.lyricsOffsetMs += 50 }
                    .buttonStyle(.bordered)
            }
        }
        .padding(16)
    }

    private func interludeDots(progress: Double) -> some View {
        let breath = 0.94 + 0.06 * sin(Date().timeIntervalSinceReferenceDate * 2.4)
        return HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { dot in
                let fill = min(max(progress * 3 - Double(dot), 0), 1)
                Circle()
                    .fill(lyricForeground.opacity(0.30 + 0.62 * fill))
                    .frame(width: 9, height: 9)
                    .scaleEffect(reduceMotion ? 1 : CGFloat(0.9 + 0.1 * breath))
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Individual Lyric Line Rendering

    @ViewBuilder
    private func lyricLineView(
        line: LyricLine,
        index: Int,
        activeIndex: Int,
        positionMs: Int64,
        interludeProgress: Double?,
        synced: Bool,
        wordSynced: Bool,
        isRTL: Bool
    ) -> some View {
        let isActive = !synced || index == activeIndex
        let distance = synced && activeIndex >= 0 ? abs(index - activeIndex) : 0
        let opacity: Double = {
            if !synced { return 0.92 }
            if isActive { return 1.0 }
            switch distance {
            case 1: return 0.46
            case 2: return 0.30
            default: return 0.18
            }
        }()

        let alignOpposite = deps.preferences.spicyDuets && (line.speaker == .duet)
        let baseFontSize = CGFloat((isCompactStyle ? 22.0 : 27.0) * deps.preferences.lyricFontScale)

        VStack(alignment: alignOpposite ? .trailing : .leading, spacing: 6) {
            if line.isInstrumental {
                if isActive {
                    interludeDots(progress: interludeProgress ?? 0)
                }
            } else if wordSynced && !line.wordTimings.isEmpty && isActive && !reduceMotion {
                SyllableFlowLayout(spacingX: 0, spacingY: 4, alignTrailing: alignOpposite) {
                    ForEach(line.wordTimings.indices, id: \.self) { wIdx in
                        let word = line.wordTimings[wIdx]
                        let nextStart: Int64? = (wIdx + 1 < line.wordTimings.count) ? line.wordTimings[wIdx + 1].startMs : nil
                        let prog = LyricTiming.wordSweepProgress(
                            word,
                            nextWordStartMs: nextStart,
                            lineEndMs: line.endMs,
                            at: positionMs
                        )
                        SyllableWordText(
                            text: word.text,
                            trailingSpace: !word.isPartOfWord,
                            progress: prog,
                            fontSize: baseFontSize,
                            glowEnabled: deps.preferences.lyricsGlow && !reduceMotion
                        )
                    }
                }
            } else {
                Text(line.words)
                    .font(.system(size: baseFontSize, weight: .bold, design: .default))
                    .foregroundStyle(lyricForeground.opacity(opacity))
                    .multilineTextAlignment(alignOpposite ? .trailing : .leading)
            }

            if deps.preferences.spicyRomanize,
               let rom = line.romanized,
               !rom.isEmpty {
                Text(rom)
                    .font(.system(size: 14, weight: .medium, design: .default))
                    .foregroundStyle(lyricForeground.opacity(isActive ? 0.72 : 0.30))
                    .multilineTextAlignment(alignOpposite ? .trailing : .leading)
            }

            if !deps.preferences.lyricTranslateLanguage.isEmpty,
               let tr = line.translation,
               !tr.isEmpty {
                Text(tr)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(theme.accent.opacity(isActive ? 0.95 : 0.42))
                    .multilineTextAlignment(alignOpposite ? .trailing : .leading)
            }

            if deps.preferences.spicyBackingVocals,
               let bg = line.backgroundText,
               !bg.isEmpty {
                Text("(\(bg))")
                    .font(.system(size: 16, weight: .semibold, design: .default))
                    .italic()
                    .foregroundStyle(lyricForeground.opacity(isActive ? 0.62 : 0.24))
            }
        }
        .frame(maxWidth: .infinity, alignment: alignOpposite ? .trailing : .leading)
        .scaleEffect(isActive && synced && !reduceMotion ? 1.02 : 1.0, anchor: alignOpposite ? .trailing : .leading)
        .blur(radius: (!synced || isActive || reduceMotion) ? 0 : min(CGFloat(distance) * 0.65, 2.2))
        .animation(
            reduceMotion
                ? .easeInOut(duration: 0.16)
                : .spring(response: 0.38, dampingFraction: 0.88),
            value: opacity
        )
        .environment(\.layoutDirection, isRTL ? .rightToLeft : .leftToRight)
        .contentShape(Rectangle())
        .onTapGesture {
            guard synced else { return }
            HapticsManager.shared.softDetent()
            manualScrollSuppressionUntil = .distantPast
            deps.player.seek(toMs: line.startMs)
        }
    }

    // MARK: - Loading, Romanization & Translation

    private func loadLyricsAndEnhancements() async {
        isLoading = true
        baseLyrics = nil
        displayedLyrics = nil
        clock.restart()
        lastScrolledLineIndex = -1
        manualScrollSuppressionUntil = .distantPast

        let isrc = await deps.api.trackISRC(trackURI: track.uri)
        let query = LyricsTrackQuery(
            id: track.spotifyID,
            title: track.name,
            artist: track.artistNames,
            album: track.album?.name ?? "",
            durationMs: track.durationMs,
            isrc: isrc
        )
        let resolved = await deps.lyricsRepository.resolve(
            track: query,
            wordSyncPreferred: deps.preferences.lyricsWordSync,
            extraSourcesEnabled: deps.preferences.lyricsExtraSources,
            spicyKey: deps.preferences.spicyCatalogueKey,
            providerFirst: deps.preferences.spicyProviderFirst,
            onEarlySpotifyLineSync: { early in
                await MainActor.run {
                    if self.displayedLyrics == nil {
                        self.displayedLyrics = early
                    }
                }
            }
        )
        self.baseLyrics = resolved
        await refreshEnhancements()
        isLoading = false
    }

    private func refreshEnhancements() async {
        guard var working = baseLyrics else {
            displayedLyrics = nil
            return
        }
        if deps.preferences.spicyRomanize {
            working = await Task.detached(priority: .userInitiated) {
                Romanizer.applyRomanization(to: working)
            }.value
        }
        let targetLang = deps.preferences.lyricTranslateLanguage
        if !targetLang.isEmpty,
           let translated = try? await LyricTranslationService.shared.translateLyrics(working, targetLanguage: targetLang) {
            working = translated
        }
        displayedLyrics = working
    }
}

private struct LyricLineRenderKey: Equatable {
    let line: LyricLine
    let index: Int
    let activeIndex: Int
    let framePositionMs: Int64?
    let interludeProgress: Double?
    let synced: Bool
    let wordSynced: Bool
    let isRTL: Bool
    let isCompactStyle: Bool
    let duetAlignment: Bool
    let fontScale: Double
    let romanize: Bool
    let translationLanguage: String
    let backingVocals: Bool
    let glow: Bool
    let reduceMotion: Bool
}

private struct EquatableContent<Content: View, Key: Equatable>: View, Equatable {
    let key: Key
    let content: Content

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.key == rhs.key
    }

    var body: some View {
        content
    }
}

// MARK: - Per-Syllable Partial Fill View & Wrapping Layout

public struct SyllableWordText: View {
    @Environment(\.celestialTheme) private var theme

    public let text: String
    public let trailingSpace: Bool
    public let progress: Double
    public let fontSize: CGFloat
    public let glowEnabled: Bool

    public init(text: String, trailingSpace: Bool = false, progress: Double, fontSize: CGFloat, glowEnabled: Bool) {
        self.text = text
        self.trailingSpace = trailingSpace
        self.progress = progress
        self.fontSize = fontSize
        self.glowEnabled = glowEnabled
    }

    public var body: some View {
        let clampedProgress = min(max(progress, 0), 1)
        let gradientProgress = CGFloat(clampedProgress)
        let glowAmount = sin(Double.pi * clampedProgress)
        let liftY = -2.0 * CGFloat(glowAmount)
        let fillColor = theme.isLight ? theme.primaryText : Color.white
        let displayText = Text(text) + (trailingSpace ? Text(" ") : Text(""))

        displayText
            .font(.system(size: fontSize, weight: .bold, design: .default))
            .foregroundStyle(fillColor.opacity(0.34))
            .overlay {
                GeometryReader { geo in
                    displayText
                        .font(.system(size: fontSize, weight: .bold, design: .default))
                        .foregroundStyle(fillColor)
                        .frame(width: geo.size.width, alignment: .leading)
                        .mask(alignment: .leading) {
                            if clampedProgress <= 0 {
                                Color.clear
                            } else if clampedProgress >= 1 {
                                Color.white
                            } else {
                                LinearGradient(
                                    stops: [
                                        .init(color: .white, location: max(0, gradientProgress - 0.025)),
                                        .init(color: .clear, location: min(1, gradientProgress + 0.025))
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            }
                        }
                }
            }
            .shadow(
                color: glowEnabled ? fillColor.opacity(0.30 * glowAmount) : .clear,
                radius: 2 + 5 * CGFloat(glowAmount),
                y: 0
            )
            .offset(y: liftY)
    }
}

public struct SyllableFlowLayout: Layout {
    public var spacingX: CGFloat
    public var spacingY: CGFloat
    public var alignTrailing: Bool

    public init(spacingX: CGFloat = 0, spacingY: CGFloat = 4, alignTrailing: Bool = false) {
        self.spacingX = spacingX
        self.spacingY = spacingY
        self.alignTrailing = alignTrailing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = computeRows(maxWidth: maxWidth, subviews: subviews)
        let totalHeight = rows.reduce(CGFloat(0)) { acc, row in
            acc + row.height
        } + CGFloat(max(0, rows.count - 1)) * spacingY
        let widest = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? widest, height: totalHeight)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(maxWidth: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = alignTrailing ? (bounds.maxX - row.width) : bounds.minX
            for item in row.items {
                item.subview.place(
                    at: CGPoint(x: x, y: y + (row.height - item.size.height) * 0.5),
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + spacingX
            }
            y += row.height + spacingY
        }
    }

    private struct RowItem {
        let subview: LayoutSubview
        let size: CGSize
    }

    private struct Row {
        var items: [RowItem] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func computeRows(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let nextWidth = current.items.isEmpty ? size.width : (current.width + spacingX + size.width)
            if !current.items.isEmpty && nextWidth > maxWidth {
                rows.append(current)
                current = Row(items: [RowItem(subview: subview, size: size)], width: size.width, height: size.height)
            } else {
                current.items.append(RowItem(subview: subview, size: size))
                current.width = nextWidth
                current.height = max(current.height, size.height)
            }
        }
        if !current.items.isEmpty {
            rows.append(current)
        }
        return rows
    }
}

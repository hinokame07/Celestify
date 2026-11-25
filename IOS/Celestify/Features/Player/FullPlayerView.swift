//
//  FullPlayerView.swift
//  Celestify
//
//  Apple Music iOS 26-inspired Full-Screen Liquid Glass Now Playing experience:
//  - Live Artwork Atmospheric Backdrop + looping Spotify Canvas video stage
//  - Seamless toggle between Artwork Stage, Spicy Lyrics Stage, and Up Next Queue
//  - Interactive Liquid Scrubber, Transport Controls, Volume, Connect/Jam & Credits
//  Built on Myspoti (https://github.com/kota-zo/myspoti), GPL-3.0.
//

import AVKit
import SwiftUI

public enum FullPlayerPane: String, CaseIterable {
    case artwork
    case lyrics
    case queue
}

public struct FullPlayerView: View {
    @Environment(AppDependencies.self) private var deps
    @Environment(\.dismiss) private var dismiss
    @Environment(\.celestialTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var activePane: FullPlayerPane = .artwork
    @State private var isScrubbing = false
    @State private var scrubFraction: Double = 0
    @State private var showingConnectSheet = false
    @State private var showingCreditsSheet = false
    @State private var meaningFocusedLine: String?
    @State private var showingMeaningSheet = false
    @State private var sleepTimerTask: Task<Void, Never>?
    @State private var sleepTimerMinutes: Int = 0

    public init() {}

    public var body: some View {
        ZStack {
            AtmosphericBackdrop(
                palette: deps.player.artworkPalette,
                isPlaying: deps.player.isPlaying,
                intensity: activePane == .lyrics ? 0.85 : 1.0
            )

            if let canvas = deps.player.currentCanvas,
               canvas.isVideo,
               let canvasURL = URL(string: canvas.url),
               activePane == .artwork {
                LoopingCanvasVideoView(url: canvasURL)
                    .opacity(0.32)
                    .ignoresSafeArea()
            }

            if let currentItem = deps.player.currentTrack {
                // FIX: `currentTrack` is already a `Track`, so no `.asTrack()` conversion.
                let track = currentItem
                VStack(spacing: 14) {
                    grabberAndContextHeader(track: track)
                        .padding(.horizontal, 22)
                        .padding(.top, 10)

                    switch activePane {
                    case .artwork:
                        artworkMainStage(track: track)
                    case .lyrics:
                        LyricsStageView(track: track) { lineText in
                            meaningFocusedLine = lineText
                            showingMeaningSheet = true
                        }
                    case .queue:
                        QueueInlinePane()
                    }

                    compactMetadataAndScrubber(track: track)
                        .padding(.horizontal, 24)

                    transportControlsRow
                        .padding(.horizontal, 28)

                    bottomUtilityStrip(track: track)
                        .padding(.horizontal, 28)
                        .padding(.bottom, 14)
                }
            } else {
                VStack(spacing: 14) {
                    Text("Nothing Playing")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                    Button("Close") { dismiss() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingConnectSheet) {
            ConnectAndJamSheet()
        }
        .sheet(isPresented: $showingCreditsSheet) {
            if let currentItem = deps.player.currentTrack {
                TrackCreditsSheet(track: currentItem)
            }
        }
        .sheet(isPresented: $showingMeaningSheet) {
            if let currentItem = deps.player.currentTrack {
                SongMeaningSheet(track: currentItem, focusedLyricLine: meaningFocusedLine)
            }
        }
    }

    // MARK: - Header

    private func grabberAndContextHeader(track: Track) -> some View {
        VStack(spacing: 10) {
            Capsule()
                .fill(Color.white.opacity(0.36))
                .frame(width: 40, height: 5)
                .onTapGesture { dismiss() }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(deps.player.sourceLabel.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white.opacity(0.55))
                    if !deps.player.contextName.isEmpty {
                        Text(deps.player.contextName)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)
                    }
                }

                Spacer()

                Menu {
                    Button {
                        showingCreditsSheet = true
                    } label: {
                        Label("View Song Credits", systemImage: "person.text.rectangle")
                    }

                    Button {
                        meaningFocusedLine = nil
                        showingMeaningSheet = true
                    } label: {
                        Label("Genius Song Meaning", systemImage: "sparkles.rectangle.stack")
                    }

                    if let firstArtist = track.artists.first, !firstArtist.uri.isEmpty {
                        Button {
                            dismiss()
                            deps.router.navigate(to: .artist(uri: firstArtist.uri, initialName: firstArtist.name))
                        } label: {
                            Label("Go to Artist", systemImage: "music.mic")
                        }
                    }

                    if let album = track.album, !album.uri.isEmpty {
                        Button {
                            dismiss()
                            deps.router.navigate(to: .album(uri: album.uri, initialName: album.name))
                        } label: {
                            Label("Go to Album", systemImage: "square.stack")
                        }
                    }

                    Menu("Sleep Timer") {
                        ForEach([0, 15, 30, 45, 60], id: \.self) { mins in
                            Button(mins == 0 ? "Off" : "In \(mins) minutes") {
                                scheduleSleepTimer(minutes: mins)
                            }
                        }
                    }

                    if !track.spotifyID.isEmpty,
                       let shareURL = URL(string: "https://open.spotify.com/track/\(track.spotifyID)") {
                        ShareLink(item: shareURL) {
                            Label("Share Track", systemImage: "square.and.arrow.up")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .liquidGlass(shape: Circle(), interactive: true)
                }
                .accessibilityLabel("More Track Options")
            }
        }
    }

    // MARK: - Artwork Centerpiece

    private func artworkMainStage(track: Track) -> some View {
        GeometryReader { geo in
            let side = min(geo.size.width - 48, geo.size.height - 12, 356)
            VStack {
                Spacer(minLength: 0)
                ArtworkView(
                    urlString: track.coverURL,
                    size: max(180, side),
                    cornerRadius: 24
                )
                .scaleEffect(deps.player.isPlaying || reduceMotion ? 1.0 : 0.87)
                .shadow(
                    color: Color(argb: deps.player.artworkPalette.vibrantARGB).opacity(deps.player.isPlaying ? 0.50 : 0.22),
                    radius: deps.player.isPlaying ? 32 : 14,
                    y: deps.player.isPlaying ? 18 : 8
                )
                .animation(.spring(response: 0.45, dampingFraction: 0.78), value: deps.player.isPlaying)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Title, Like & Scrubber

    private func compactMetadataAndScrubber(track: Track) -> some View {
        VStack(spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                if activePane != .artwork {
                    ArtworkView(urlString: track.coverURL, size: 46, cornerRadius: 10)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(track.name)
                        .font(activePane == .artwork ? .title3.weight(.bold) : .headline.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(track.artistNames)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    deps.player.toggleCurrentTrackLiked()
                } label: {
                    Image(systemName: deps.player.isCurrentTrackLiked ? "heart.fill" : "heart")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(deps.player.isCurrentTrackLiked ? theme.accent : .white.opacity(0.78))
                        .frame(width: 40, height: 40)
                        .liquidGlass(shape: Circle(), interactive: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(deps.player.isCurrentTrackLiked ? "Saved in Liked Songs" : "Save to Liked Songs")
            }

            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                let totalMs = max(1, deps.player.durationMs)
                let livePosMs = deps.player.currentPositionMs()
                let displayedFraction = isScrubbing
                    ? scrubFraction
                    : min(max(Double(livePosMs) / Double(totalMs), 0.0), 1.0)
                let shownMs = Int64((displayedFraction * Double(totalMs)).rounded())
                let remainMs = max(0, totalMs - shownMs)

                VStack(spacing: 6) {
                    GeometryReader { barGeo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.22))
                                .frame(height: isScrubbing ? 11 : 6)

                            Capsule()
                                .fill(Color.white)
                                .frame(
                                    width: max(0, barGeo.size.width * displayedFraction),
                                    height: isScrubbing ? 11 : 6
                                )
                        }
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { drag in
                                    if !isScrubbing {
                                        isScrubbing = true
                                        HapticsManager.shared.selection()
                                    }
                                    scrubFraction = min(max(drag.location.x / max(1, barGeo.size.width), 0.0), 1.0)
                                }
                                .onEnded { _ in
                                    let target = Int64((scrubFraction * Double(totalMs)).rounded())
                                    isScrubbing = false
                                    HapticsManager.shared.softDetent()
                                    deps.player.seek(toMs: target)
                                }
                        )
                    }
                    .frame(height: 18)
                    .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isScrubbing)

                    HStack {
                        Text(TrackRowView.formatDuration(shownMs))
                        Spacer()
                        if sleepTimerMinutes > 0 {
                            Label("\(sleepTimerMinutes)m", systemImage: "moon.zzz.fill")
                                .foregroundStyle(theme.accent)
                            Spacer()
                        }
                        Text("-\(TrackRowView.formatDuration(remainMs))")
                    }
                    .font(.caption2.monospacedDigit().weight(.medium))
                    .foregroundStyle(.white.opacity(0.62))
                }
            }
        }
    }

    // MARK: - Transport Controls

    private var transportControlsRow: some View {
        HStack {
            Button {
                deps.player.toggleShuffle()
            } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(deps.player.isShuffled ? theme.accent : .white.opacity(0.65))
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Shuffle")

            Spacer()

            Button {
                deps.player.skipPrevious()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous")

            Spacer()

            Button {
                HapticsManager.shared.tap()
                deps.player.togglePlayPause()
            } label: {
                ZStack {
                    if deps.player.isBuffering {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.3)
                    } else {
                        Image(systemName: deps.player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 40, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 72, height: 72)
                .liquidGlass(shape: Circle(), interactive: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(deps.player.isPlaying ? "Pause" : "Play")

            Spacer()

            Button {
                deps.player.skipNext()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next")

            Spacer()

            Button {
                deps.player.cycleRepeatMode()
            } label: {
                Image(systemName: deps.player.repeatMode == .track ? "repeat.1" : "repeat")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(deps.player.repeatMode == .off ? .white.opacity(0.65) : theme.accent)
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Repeat Mode")
        }
    }

    // MARK: - Bottom Utility Strip

    private func bottomUtilityStrip(track: Track) -> some View {
        HStack {
            Button {
                HapticsManager.shared.selection()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    activePane = (activePane == .lyrics) ? .artwork : .lyrics
                }
            } label: {
                Image(systemName: activePane == .lyrics ? "quote.bubble.fill" : "quote.bubble")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(activePane == .lyrics ? theme.accent : .white.opacity(0.75))
                    .frame(width: 44, height: 40)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Toggle Spicy Lyrics")

            Spacer()

            Button {
                showingConnectSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "airplayaudio")
                        .font(.system(size: 18, weight: .semibold))
                    if let remote = deps.player.activeRemoteDeviceName {
                        Text(remote)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(deps.player.activeRemoteDeviceName != nil ? theme.accent : .white.opacity(0.75))
                .padding(.horizontal, 10)
                .frame(height: 40)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Devices and Jam")

            Spacer()

            Button {
                HapticsManager.shared.selection()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    activePane = (activePane == .queue) ? .artwork : .queue
                }
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(activePane == .queue ? theme.accent : .white.opacity(0.75))
                    .frame(width: 44, height: 40)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Toggle Playback Queue")
        }
        .accessibilityElement(children: .contain)
        .id(track.uri)
    }

    private func scheduleSleepTimer(minutes: Int) {
        sleepTimerTask?.cancel()
        sleepTimerMinutes = minutes
        guard minutes > 0 else { return }
        sleepTimerTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(minutes) * 60 * 1_000_000_000)
            guard !Task.isCancelled else { return }
            deps.player.pause()
            sleepTimerMinutes = 0
        }
    }
}

// MARK: - Inline Queue, Connect/Jam & Credits Supporting Views

public struct QueueInlinePane: View {
    @Environment(AppDependencies.self) private var deps

    public init() {}

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if !deps.player.queue.queued.isEmpty {
                    HStack {
                        Text("Next in Queue")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                        Spacer()
                        Button("Clear") {
                            deps.player.clearUserQueue()
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.75))
                    }
                    ForEach(deps.player.queue.queued) { item in
                        queueItemRow(item)
                    }
                }

                Text("Playing Next")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.top, 6)

                if deps.player.queue.nextUp.isEmpty {
                    Text("Upcoming tracks from your current album, playlist, or Autoplay radio appear here.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.vertical, 12)
                } else {
                    ForEach(deps.player.queue.nextUp.prefix(30)) { item in
                        queueItemRow(item)
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
        }
    }

    // NOTE: `item` here is a `NowPlayingItem`, which does have `asTrack()`. Left unchanged.
    private func queueItemRow(_ item: NowPlayingItem) -> some View {
        Button {
            deps.player.playTrack(item.asTrack())
        } label: {
            HStack(spacing: 12) {
                ArtworkView(urlString: item.imageURL, size: 44, cornerRadius: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(item.artists.map(\.name).joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "line.3.horizontal")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .buttonStyle(.plain)
    }
}

public struct ConnectAndJamSheet: View {
    @Environment(AppDependencies.self) private var deps
    @Environment(\.dismiss) private var dismiss
    @Environment(\.celestialTheme) private var theme
    @State private var jamJoinCode = ""

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                Section("Spotify Connect Devices") {
                    if deps.player.connectDevices.isEmpty {
                        Text("This iPhone (Celestify Web Engine)")
                            .font(.subheadline.weight(.semibold))
                    } else {
                        ForEach(deps.player.connectDevices) { device in
                            Button {
                                Task { await deps.player.transfer(to: device) }
                            } label: {
                                HStack {
                                    Image(systemName: device.type.lowercased().contains("speaker") ? "hifispeaker.fill" : "iphone")
                                        .foregroundStyle(device.isActive ? theme.accent : .secondary)
                                    VStack(alignment: .leading) {
                                        Text(device.name)
                                            .foregroundStyle(.primary)
                                        Text(device.type)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if device.isActive {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(theme.accent)
                                    }
                                }
                            }
                        }
                    }
                }

                Section("Output Volume") {
                    Slider(
                        value: Binding(
                            get: { deps.player.volume },
                            set: { deps.player.setVolume($0) }
                        ),
                        in: 0...1
                    )
                }

                Section("Spotify Jam") {
                    if let jam = deps.player.activeJamSession {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Active Jam (\(jam.members.count) listeners)")
                                .font(.subheadline.weight(.semibold))
                            if let token = jam.joinCode, !token.isEmpty {
                                Text("Invite code: \(token)")
                                    .font(.caption.monospaced())
                            }
                            Button("Leave Jam", role: .destructive) {
                                Task {
                                    try? await deps.api.leaveJamSession(sessionID: jam.id)
                                    await deps.player.refreshConnectDevices()
                                }
                            }
                        }
                    } else {
                        Button("Start a Spotify Jam") {
                            Task {
                                _ = try? await deps.api.createJamSession()
                                await deps.player.refreshConnectDevices()
                            }
                        }
                        if !jamJoinCode.isEmpty {
                            Text("Entered code: \(jamJoinCode)")
                                .font(.caption)
                        }
                    }
                }
            }
            .navigationTitle("Connect & Jam")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await deps.player.refreshConnectDevices()
            }
        }
        .presentationDetents([.medium, .large])
    }
}

public struct TrackCreditsSheet: View {
    public let track: Track

    @Environment(AppDependencies.self) private var deps
    @Environment(\.dismiss) private var dismiss
    @State private var credits: TrackCredits?
    @State private var isLoading = true

    public init(track: Track) {
        self.track = track
    }

    public var body: some View {
        NavigationStack {
            List {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity)
                } else if let credits {
                    Section("Track") {
                        LabeledContent("Title", value: credits.title.isEmpty ? track.name : credits.title)
                        if !credits.sources.isEmpty {
                            LabeledContent("Source", value: credits.sources.joined(separator: ", "))
                        }
                    }
                    ForEach(credits.roles) { group in
                        Section(group.role) {
                            ForEach(group.names, id: \.self) { person in
                                Text(person)
                            }
                        }
                    }
                } else {
                    Text("Credits unavailable for this track.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Song Credits")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                credits = try? await deps.api.trackCredits(trackURI: track.uri)
                isLoading = false
            }
        }
        .presentationDetents([.medium, .large])
    }
}

public struct LoopingCanvasVideoView: UIViewRepresentable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public func makeUIView(context: Context) -> UIView {
        let container = CanvasContainerUIView()
        context.coordinator.configure(url: url, in: container)
        return container
    }

    public func updateUIView(_ uiView: UIView, context: Context) {
        if let c = uiView as? CanvasContainerUIView {
            context.coordinator.configure(url: url, in: c)
        }
    }

    public final class CanvasContainerUIView: UIView {
        let playerLayer = AVPlayerLayer()
        override init(frame: CGRect) {
            super.init(frame: frame)
            playerLayer.videoGravity = .resizeAspectFill
            layer.addSublayer(playerLayer)
        }
        required init?(coder: NSCoder) { nil }
        override public func layoutSubviews() {
            super.layoutSubviews()
            playerLayer.frame = bounds
        }
    }

    public final class Coordinator {
        private var currentURL: URL?
        private var queuePlayer: AVQueuePlayer?
        private var looper: AVPlayerLooper?

        func configure(url: URL, in view: CanvasContainerUIView) {
            guard currentURL != url else { return }
            currentURL = url
            let item = AVPlayerItem(url: url)
            let qp = AVQueuePlayer(playerItem: item)
            qp.isMuted = true
            looper = AVPlayerLooper(player: qp, templateItem: item)
            view.playerLayer.player = qp
            qp.play()
            queuePlayer = qp
        }
    }
}

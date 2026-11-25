//
//  PlayerController.swift
//  Celestify
//
//  Unified playback & queue controller porting Android SongPlayer.kt:
//  coordinates SpotifyWebPlayerBridge, Spotify Connect devices, NativeAudioPlayer
//  (encrypted downloads, local files, Soundfinder podcast episodes, extensions),
//  live ArtworkPalette extraction, Lock Screen NowPlaying, ListenHistory recording,
//  and GeniusMeaning prefetching.
//  Built on Myspoti (https://github.com/kota-zo/myspoti), GPL-3.0.
//

import Foundation
import Observation
import UIKit

@Observable
@MainActor
public final class PlayerController {
    internal static weak var sharedInstanceRef: PlayerController?

    // MARK: - Observable Playback State
    public private(set) var currentTrack: Track?
    public private(set) var isPlaying: Bool = false
    public private(set) var isBuffering: Bool = false
    public private(set) var adPlaying: Bool = false
    public private(set) var durationMs: Int64 = 0
    public private(set) var anchorPositionMs: Int64 = 0
    public private(set) var anchorMonotonicSeconds: Double = ProcessInfo.processInfo.systemUptime
    public private(set) var playbackSpeed: Double = 1.0

    public private(set) var contextURI: String = ""
    public private(set) var contextName: String = ""
    public private(set) var isShuffled: Bool = false
    public private(set) var isSmartShuffle: Bool = false
    public private(set) var repeatMode: RepeatMode = .off
    public private(set) var isCurrentTrackLiked: Bool = false
    public private(set) var sourceLabel: String = "Spotify"
    public private(set) var volume: Double = 0.85

    public private(set) var queue: PlaybackQueue = PlaybackQueue()
    public private(set) var connectDevices: [ConnectDevice] = []
    public private(set) var activeRemoteDeviceName: String?
    public private(set) var activeJamSession: JamSession?
    public private(set) var artworkPalette: ArtworkPalette = .celestialDefault
    public private(set) var currentCanvas: TrackCanvas?

    /// Incremented on every explicit seek or track change so `LyricClock` glides smoothly.
    public private(set) var seekDiscontinuity: Int64 = 0

    // MARK: - Dependencies
    private let api: SpotifyAPIClient
    private let bridge: SpotifyWebPlayerBridge
    private let nativePlayer = NativeAudioPlayer()
    private let nowPlaying = NowPlayingCoordinator.shared
    private let offlineStore: OfflineStore
    private let listenHistory: ListenHistoryStore
    private let extensions: ExtensionManager
    private let keychain: KeychainStore

    private var localQueue: [Track] = []
    private var localQueueIndex: Int = 0
    private var trackListenStartedUptime: Double?
    private var accumulatedListenMs: Int64 = 0
    private var trackedListenURI: String?

    public init(
        api: SpotifyAPIClient,
        bridge: SpotifyWebPlayerBridge,
        offlineStore: OfflineStore = .shared,
        listenHistory: ListenHistoryStore = .shared,
        extensions: ExtensionManager = .shared,
        keychain: KeychainStore = .shared
    ) {
        self.api = api
        self.bridge = bridge
        self.offlineStore = offlineStore
        self.listenHistory = listenHistory
        self.extensions = extensions
        self.keychain = keychain
        Self.sharedInstanceRef = self

        wireCallbacks()
        restoreLastPlayedTrack()
    }

    // MARK: - Extrapolated Frame-Rate Position

    public func currentPositionMs() -> Int64 {
        if nativePlayer.isActive {
            return nativePlayer.currentPositionMs
        }
        guard isPlaying && !isBuffering else {
            return anchorPositionMs
        }
        let elapsedSec = max(0, ProcessInfo.processInfo.systemUptime - anchorMonotonicSeconds)
        let extrapolated = anchorPositionMs + Int64((elapsedSec * 1000.0 * playbackSpeed).rounded())
        return durationMs > 0 ? min(extrapolated, durationMs) : extrapolated
    }

    /// Position compensated for Bluetooth/AirPlay hardware output latency and user lyric offset.
    public func effectiveLyricPositionMs() -> Int64 {
        LyricTiming.effectivePositionMs(
            playbackMs: currentPositionMs(),
            outputLagMs: nowPlaying.currentOutputLagMs,
            userOffsetMs: PreferencesStore.shared.lyricsOffsetMs
        )
    }

    // MARK: - Transport Actions

    public func playTrack(
        _ track: Track,
        inContext contextTracks: [Track] = [],
        contextURI: String = "",
        contextName: String = ""
    ) {
        flushListenHistoryIfNeeded()
        currentTrack = track
        durationMs = track.durationMs
        anchorPositionMs = 0
        anchorMonotonicSeconds = ProcessInfo.processInfo.systemUptime
        seekDiscontinuity &+= 1
        isBuffering = true
        isPlaying = true
        self.contextURI = contextURI
        self.contextName = contextName.isEmpty ? (track.album?.name ?? "") : contextName
        persistLastPlayedTrack(track)
        beginListenTracking(for: track)

        Task {
            await refreshTrackAncillaries(for: track)
        }

        // 1. Local File playback
        if let localURL = track.localFileURL {
            localQueue = contextTracks.isEmpty ? [track] : contextTracks
            localQueueIndex = localQueue.firstIndex(where: { $0.id == track.id }) ?? 0
            sourceLabel = "Local File"
            isBuffering = false
            nativePlayer.playURL(localURL)
            syncNowPlayingCenter()
            return
        }

        // 2. Encrypted Offline Download playback (`MSE1`)
        if let encURL = offlineStore.encryptedFileURL(for: track.spotifyID) {
            Task {
                if let masterKey = try? await keychain.loadOrCreateOfflineMasterKey() {
                    localQueue = contextTracks.isEmpty ? [track] : contextTracks
                    localQueueIndex = localQueue.firstIndex(where: { $0.id == track.id }) ?? 0
                    sourceLabel = "Downloaded · Encrypted"
                    isBuffering = false
                    nativePlayer.playEncryptedOfflineFile(fileURL: encURL, masterKey: masterKey)
                    syncNowPlayingCenter()
                }
            }
            return
        }

        // 3. Installed Audio-Source Extension
        Task {
            if let extAudio = await extensions.resolveAudioSource(track: track) {
                localQueue = contextTracks.isEmpty ? [track] : contextTracks
                localQueueIndex = localQueue.firstIndex(where: { $0.id == track.id }) ?? 0
                sourceLabel = "\(extAudio.providerLabel) · \(extAudio.qualityLabel)"
                isBuffering = false
                nativePlayer.playURL(extAudio.streamURL, headers: extAudio.headers)
                syncNowPlayingCenter()
                return
            }

            // 4. Podcast Episode direct Soundfinder CDN passthrough
            if track.isEpisode, let cdnURL = await api.episodeDirectStreamURL(episodeURI: track.uri) {
                localQueue = contextTracks.isEmpty ? [track] : contextTracks
                localQueueIndex = localQueue.firstIndex(where: { $0.id == track.id }) ?? 0
                sourceLabel = "Spotify Podcast"
                isBuffering = false
                nativePlayer.playURL(cdnURL)
                syncNowPlayingCenter()
                return
            }

            // 5. Spotify Web Player Engine (or active Connect device)
            nativePlayer.stop()
            sourceLabel = activeRemoteDeviceName.map { "Connect · \($0)" } ?? "Spotify"
            nowPlaying.activateAudioSession()

            do {
                var playArgs: [String: JSONValue] = ["uri": .string(track.uri)]
                if !contextURI.isEmpty {
                    playArgs["contextUri"] = .string(contextURI)
                } else if !contextTracks.isEmpty {
                    playArgs["uris"] = .array(contextTracks.map { .string($0.uri) })
                }
                _ = try await bridge.call("player.play", args: .object(playArgs))
                isBuffering = false
            } catch {
                // Fallback to 30s preview stream if WebKit EME is restricted on this device and no Connect target is active
                if let preview = track.previewURL, let pURL = URL(string: preview) {
                    sourceLabel = "Spotify Preview"
                    isBuffering = false
                    nativePlayer.playURL(pURL)
                } else {
                    isBuffering = false
                    isPlaying = false
                    DiagnosticLogbook.shared.log("player", "Play failed: \(error.localizedDescription)")
                }
            }
            syncNowPlayingCenter()
        }
    }

    public func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            resume()
        }
    }

    public func resume() {
        isPlaying = true
        anchorMonotonicSeconds = ProcessInfo.processInfo.systemUptime
        trackListenStartedUptime = anchorMonotonicSeconds
        if nativePlayer.isActive {
            nativePlayer.resume()
        } else {
            Task { _ = try? await bridge.call("player.resume") }
        }
        syncNowPlayingCenter()
    }

    public func pause() {
        let pos = currentPositionMs()
        anchorPositionMs = pos
        isPlaying = false
        pauseListenAccumulation()
        if nativePlayer.isActive {
            nativePlayer.pause()
        } else {
            Task { _ = try? await bridge.call("player.pause") }
        }
        syncNowPlayingCenter()
    }

    public func skipNext() {
        HapticsManager.shared.tap()
        seekDiscontinuity &+= 1
        if nativePlayer.isActive && !localQueue.isEmpty {
            let nextIdx = localQueueIndex + 1
            if nextIdx < localQueue.count {
                localQueueIndex = nextIdx
                playTrack(localQueue[nextIdx], inContext: localQueue, contextURI: contextURI, contextName: contextName)
            } else if repeatMode == .context {
                localQueueIndex = 0
                playTrack(localQueue[0], inContext: localQueue, contextURI: contextURI, contextName: contextName)
            }
            return
        }
        Task { _ = try? await bridge.call("player.next") }
    }

    public func skipPrevious() {
        HapticsManager.shared.tap()
        if currentPositionMs() > 3_500 {
            seek(toMs: 0)
            return
        }
        seekDiscontinuity &+= 1
        if nativePlayer.isActive && !localQueue.isEmpty {
            let prevIdx = max(0, localQueueIndex - 1)
            localQueueIndex = prevIdx
            playTrack(localQueue[prevIdx], inContext: localQueue, contextURI: contextURI, contextName: contextName)
            return
        }
        Task { _ = try? await bridge.call("player.previous") }
    }

    public func seek(toMs targetMs: Int64) {
        let clamped = max(0, durationMs > 0 ? min(targetMs, durationMs) : targetMs)
        anchorPositionMs = clamped
        anchorMonotonicSeconds = ProcessInfo.processInfo.systemUptime
        seekDiscontinuity &+= 1
        if nativePlayer.isActive {
            nativePlayer.seek(toMs: clamped)
        } else {
            Task { _ = try? await bridge.call("player.seek", args: .object(["positionMs": .int(clamped)])) }
        }
        syncNowPlayingCenter()
    }

    public func setVolume(_ value: Double) {
        let clamped = min(max(value, 0.0), 1.0)
        volume = clamped
        nativePlayer.setVolume(Float(clamped))
        Task { _ = try? await bridge.call("playback.setVolume", args: .object(["volume": .double(clamped)])) }
    }

    public func toggleShuffle() {
        let next = !isShuffled
        isShuffled = next
        HapticsManager.shared.selection()
        Task { _ = try? await bridge.call("player.setShuffle", args: .object(["shuffle": .bool(next)])) }
    }

    public func cycleRepeatMode() {
        let next = repeatMode.next
        repeatMode = next
        HapticsManager.shared.selection()
        Task { _ = try? await bridge.call("player.setRepeat", args: .object(["mode": .int(Int64(next.rawValue))])) }
    }

    public func toggleCurrentTrackLiked() {
        guard let uri = currentTrack?.uri, uri.hasPrefix("spotify:track:") else { return }
        let target = !isCurrentTrackLiked
        isCurrentTrackLiked = target
        HapticsManager.shared.softDetent()
        Task {
            try? await api.setLibrarySaved(target, uris: [uri])
        }
    }

    public func addToQueue(_ track: Track) {
        HapticsManager.shared.softDetent()
        if nativePlayer.isActive {
            localQueue.append(track)
            let item = NowPlayingItem(uri: track.uri, name: track.name, artists: track.artists, album: track.album, imageURL: track.coverURL, durationMs: track.durationMs, explicit: track.explicit)
            queue = PlaybackQueue(current: queue.current, queued: queue.queued + [item], nextUp: queue.nextUp)
            return
        }
        Task {
            _ = try? await bridge.call("player.addToQueue", args: .object(["uri": .string(track.uri)]))
        }
    }

    public func clearUserQueue() {
        Task { _ = try? await bridge.call("queue.clear") }
        queue = PlaybackQueue(current: queue.current, queued: [], nextUp: queue.nextUp)
    }

    public func applyCrossfade(seconds: Int) {
        Task {
            _ = try? await bridge.call("player.setCrossfade", args: .object(["seconds": .int(Int64(seconds))]))
        }
    }

    // MARK: - Connect & Jam

    public func refreshConnectDevices() async {
        if let list = try? await api.connectDevices() {
            connectDevices = list
            activeRemoteDeviceName = list.first(where: { $0.isActive && !$0.isSelf })?.name
        }
        activeJamSession = await api.activeJamSession()
    }

    public func transfer(to device: ConnectDevice) async {
        try? await api.transferPlayback(toDeviceID: device.id)
        await refreshConnectDevices()
    }

    public func resetForLogout() {
        flushListenHistoryIfNeeded()
        nativePlayer.stop()
        currentTrack = nil
        isPlaying = false
        isBuffering = false
        durationMs = 0
        anchorPositionMs = 0
        queue = PlaybackQueue()
        connectDevices = []
        activeRemoteDeviceName = nil
        activeJamSession = nil
        nowPlaying.updateNowPlaying(track: nil, isPlaying: false, positionMs: 0, durationMs: 0)
    }

    // MARK: - Internal Wiring & Ancillary Prefetching

    private func wireCallbacks() {
        bridge.onStateChanged = { [weak self] state in
            self?.applyBridgeState(state)
        }
        bridge.onQueueChanged = { [weak self] q in
            self?.queue = q
        }
        nativePlayer.onProgress = { [weak self] posMs, durMs, playing in
            guard let self else { return }
            self.anchorPositionMs = posMs
            self.anchorMonotonicSeconds = ProcessInfo.processInfo.systemUptime
            if durMs > 0 { self.durationMs = durMs }
            self.isPlaying = playing
            self.syncNowPlayingCenter()
        }
        nativePlayer.onEnded = { [weak self] in
            guard let self else { return }
            if self.repeatMode == .track, let current = self.currentTrack {
                self.seek(toMs: 0)
                self.nativePlayer.resume()
                _ = current
            } else {
                self.skipNext()
            }
        }

        nowPlaying.onPlay = { [weak self] in self?.resume() }
        nowPlaying.onPause = { [weak self] in self?.pause() }
        nowPlaying.onTogglePlayPause = { [weak self] in self?.togglePlayPause() }
        nowPlaying.onNext = { [weak self] in self?.skipNext() }
        nowPlaying.onPrevious = { [weak self] in self?.skipPrevious() }
        nowPlaying.onSeek = { [weak self] ms in self?.seek(toMs: ms) }
        nowPlaying.onToggleLike = { [weak self] in self?.toggleCurrentTrackLiked() }
    }

    private func applyBridgeState(_ snapshot: PlayerStateSnapshot) {
        guard !nativePlayer.isActive else { return }
        let prevURI = currentTrack?.uri
        if let item = snapshot.item {
            let mapped = item.asTrack()
            currentTrack = mapped
            durationMs = mapped.durationMs
            if mapped.uri != prevURI {
                flushListenHistoryIfNeeded()
                seekDiscontinuity &+= 1
                persistLastPlayedTrack(mapped)
                beginListenTracking(for: mapped)
                Task { await refreshTrackAncillaries(for: mapped) }
            }
        }
        let jumped = abs(snapshot.positionMs - currentPositionMs()) > 900
        anchorPositionMs = snapshot.positionMs
        anchorMonotonicSeconds = ProcessInfo.processInfo.systemUptime
        if jumped { seekDiscontinuity &+= 1 }

        let wasPlaying = isPlaying
        isPlaying = !snapshot.isPaused
        isBuffering = snapshot.isBuffering
        playbackSpeed = snapshot.speed
        isShuffled = snapshot.shuffle
        repeatMode = snapshot.repeatMode
        if let ctx = snapshot.contextURI { contextURI = ctx }
        if let ctxName = snapshot.contextName, !ctxName.isEmpty { contextName = ctxName }

        if wasPlaying && !isPlaying {
            pauseListenAccumulation()
        } else if !wasPlaying && isPlaying {
            trackListenStartedUptime = anchorMonotonicSeconds
        }
        syncNowPlayingCenter()
    }

    private func refreshTrackAncillaries(for track: Track) async {
        // 1. Check Liked status
        if track.uri.hasPrefix("spotify:track:") {
            if let flags = try? await api.areInLibrary(uris: [track.uri]), let first = flags.first {
                isCurrentTrackLiked = first
            }
            // 2. Fetch Canvas loop if enabled
            if PreferencesStore.shared.musicVideoEnabled {
                currentCanvas = await api.trackCanvas(trackURI: track.uri)
            } else {
                currentCanvas = nil
            }
            // 3. Prefetch Genius Song Meaning after 1.5s settle (matching App.kt)
            if PreferencesStore.shared.spicyGeniusMeanings {
                Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    await GeniusMeaningService.shared.prefetch(
                        trackID: track.spotifyID,
                        title: track.name,
                        artist: track.artistNames
                    )
                }
            }
        }

        // 4. Load cover image & extract live ArtworkPalette
        if let coverStr = track.coverURL, let url = URL(string: coverStr),
           let uiImage = await ArtworkCache.shared.image(for: url) {
            let extracted = ArtworkPaletteExtractor.extract(from: uiImage)
            artworkPalette = extracted
            nowPlaying.updateNowPlaying(
                track: track,
                isPlaying: isPlaying,
                positionMs: currentPositionMs(),
                durationMs: durationMs,
                rate: playbackSpeed,
                artworkImage: uiImage
            )
        }
    }

    private func syncNowPlayingCenter() {
        nowPlaying.updateNowPlaying(
            track: currentTrack,
            isPlaying: isPlaying,
            positionMs: currentPositionMs(),
            durationMs: durationMs,
            rate: playbackSpeed
        )
    }

    // MARK: - ListenHistory Tracking & Last-Track Persistence

    private func beginListenTracking(for track: Track) {
        trackedListenURI = track.uri
        accumulatedListenMs = 0
        trackListenStartedUptime = ProcessInfo.processInfo.systemUptime
    }

    private func pauseListenAccumulation() {
        if let started = trackListenStartedUptime {
            let delta = Int64((ProcessInfo.processInfo.systemUptime - started) * 1000.0)
            accumulatedListenMs += max(0, delta)
            trackListenStartedUptime = nil
        }
    }

    private func flushListenHistoryIfNeeded() {
        pauseListenAccumulation()
        guard let prev = currentTrack,
              prev.uri == trackedListenURI,
              accumulatedListenMs >= ListenHistoryStore.minimumCountedPlayMs else {
            accumulatedListenMs = 0
            return
        }
        let src: ListenSource = {
            if prev.isLocal { return .local }
            if offlineStore.downloadedTracks[prev.spotifyID] != nil { return .download }
            return .spotify
        }()
        listenHistory.record(
            ListenRecord(
                key: prev.uri,
                title: prev.name,
                artist: prev.artistNames,
                album: prev.album?.name ?? "",
                coverURL: prev.coverURL ?? "",
                playedMs: accumulatedListenMs,
                source: src
            )
        )
        accumulatedListenMs = 0
    }

    private func persistLastPlayedTrack(_ track: Track) {
        if let data = try? JSONEncoder().encode(track) {
            UserDefaults.standard.set(data, forKey: "celestify.last_track.v1")
        }
    }

    private func restoreLastPlayedTrack() {
        if let data = UserDefaults.standard.data(forKey: "celestify.last_track.v1"),
           let saved = try? JSONDecoder().decode(Track.self, from: data) {
            currentTrack = saved
            durationMs = saved.durationMs
        }
    }
}

//
//  NowPlayingCoordinator.swift
//  Celestify
//
//  AVAudioSession lifecycle, Lock Screen / Control Center MPNowPlayingInfoCenter,
//  MPRemoteCommandCenter transport bindings, headphone unplug pause handling,
//  and real-time Bluetooth/AirPlay audio output latency measurement for LyricTiming.
//  Built on Myspoti (https://github.com/kota-zo/myspoti), GPL-3.0.
//

import AVFoundation
import Foundation
import MediaPlayer
import UIKit

@MainActor
public final class NowPlayingCoordinator {
    public static let shared = NowPlayingCoordinator()

    public var onPlay: (() -> Void)?
    public var onPause: (() -> Void)?
    public var onTogglePlayPause: (() -> Void)?
    public var onNext: (() -> Void)?
    public var onPrevious: (() -> Void)?
    public var onSeek: ((Int64) -> Void)?
    public var onToggleLike: (() -> Void)?

    private var commandsRegistered = false
    private var lastArtworkURL: String?
    private var cachedArtwork: MPMediaItemArtwork?

    private init() {
        observeAudioNotifications()
    }

    public func activateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, policy: .longFormAudio, options: [])
            try session.setActive(true)
        } catch {
            DiagnosticLogbook.shared.log("audio", "AVAudioSession activation failed: \(error.localizedDescription)")
        }
        registerRemoteCommandsIfNeeded()
    }

    /// Real hardware + Bluetooth/AirPlay output latency in milliseconds for precise lyric synchronization.
    public var currentOutputLagMs: Int64 {
        let session = AVAudioSession.sharedInstance()
        let seconds = session.outputLatency + session.ioBufferDuration
        return max(0, Int64((seconds * 1000.0).rounded()))
    }

    public func updateNowPlaying(
        track: Track?,
        isPlaying: Bool,
        positionMs: Int64,
        durationMs: Int64,
        rate: Double = 1.0,
        artworkImage: UIImage? = nil
    ) {
        guard let track else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        if let artworkImage, track.coverURL != lastArtworkURL || cachedArtwork == nil {
            lastArtworkURL = track.coverURL
            let size = artworkImage.size
            cachedArtwork = MPMediaItemArtwork(boundsSize: size) { _ in artworkImage }
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.name,
            MPMediaItemPropertyArtist: track.artistNames,
            MPMediaItemPropertyAlbumTitle: track.album?.name ?? "",
            MPMediaItemPropertyPlaybackDuration: Double(max(0, durationMs)) / 1000.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: Double(max(0, positionMs)) / 1000.0,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? rate : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0
        ]
        if let cachedArtwork {
            info[MPMediaItemPropertyArtwork] = cachedArtwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
    }

    private func registerRemoteCommandsIfNeeded() {
        guard !commandsRegistered else { return }
        commandsRegistered = true

        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.onPlay?() }
            return .success
        }

        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.onPause?() }
            return .success
        }

        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.onTogglePlayPause?() }
            return .success
        }

        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                if PreferencesStore.shared.headsetSkipEpisodes,
                   let current = PlayerController.sharedInstanceRef?.currentTrack,
                   current.isEpisode {
                    PlayerController.sharedInstanceRef?.seek(toMs: (PlayerController.sharedInstanceRef?.currentPositionMs() ?? 0) + 15_000)
                } else {
                    self?.onNext?()
                }
            }
            return .success
        }

        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                if PreferencesStore.shared.headsetSkipEpisodes,
                   let current = PlayerController.sharedInstanceRef?.currentTrack,
                   current.isEpisode {
                    PlayerController.sharedInstanceRef?.seek(toMs: max(0, (PlayerController.sharedInstanceRef?.currentPositionMs() ?? 0) - 15_000))
                } else {
                    self?.onPrevious?()
                }
            }
            return .success
        }

        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let posEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            let targetMs = Int64((posEvent.positionTime * 1000.0).rounded())
            Task { @MainActor in self?.onSeek?(targetMs) }
            return .success
        }
    }

    private func observeAudioNotifications() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            guard let typeVal = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeVal) else { return }
            Task { @MainActor in
                switch type {
                case .began:
                    self?.onPause?()
                case .ended:
                    if let optVal = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt {
                        let opts = AVAudioSession.InterruptionOptions(rawValue: optVal)
                        if opts.contains(.shouldResume) {
                            self?.onPlay?()
                        }
                    }
                @unknown default:
                    break
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            guard let reasonVal = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: reasonVal),
                  reason == .oldDeviceUnavailable else { return }
            Task { @MainActor in
                self?.onPause?()
            }
        }
    }
}

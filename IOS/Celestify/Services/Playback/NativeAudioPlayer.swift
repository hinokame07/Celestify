//
//  NativeAudioPlayer.swift
//  Celestify
//
//  Native AVPlayer engine for local audio files, AES-256-CTR encrypted offline
//  downloads (`celestify-enc://`), Soundfinder podcast passthrough streams,
//  JavaScriptCore audio-source extensions, and track previews.
//  Built on Myspoti (https://github.com/kota-zo/myspoti), GPL-3.0.
//

import AVFoundation
import Foundation

@MainActor
public final class NativeAudioPlayer {
    public var onProgress: ((Int64, Int64, Bool) -> Void)?
    public var onEnded: (() -> Void)?

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var activeCryptoLoader: OfflineCryptoAssetLoader?
    private let loaderQueue = DispatchQueue(label: "app.celestify.ios.crypto-loader", qos: .userInitiated)
    public private(set) var isActive: Bool = false

    public init() {
        attachPeriodicObserver()
    }

    public func playURL(_ url: URL, headers: [String: String] = [:], startAtMs: Int64 = 0) {
        cleanupCurrentItem()
        isActive = true
        NowPlayingCoordinator.shared.activateAudioSession()

        let asset: AVURLAsset
        if headers.isEmpty {
            asset = AVURLAsset(url: url)
        } else {
            asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        }

        let item = AVPlayerItem(asset: asset)
        installItem(item, startAtMs: startAtMs)
    }

    public func playEncryptedOfflineFile(fileURL: URL, masterKey: Data, startAtMs: Int64 = 0) {
        cleanupCurrentItem()
        isActive = true
        NowPlayingCoordinator.shared.activateAudioSession()

        let loader = OfflineCryptoAssetLoader(fileURL: fileURL, masterKey: masterKey)
        self.activeCryptoLoader = loader

        var comps = URLComponents(url: fileURL, resolvingAgainstBaseURL: false) ?? URLComponents()
        comps.scheme = OfflineCryptoAssetLoader.customScheme
        guard let customURL = comps.url else { return }

        let asset = AVURLAsset(url: customURL)
        asset.resourceLoader.setDelegate(loader, queue: loaderQueue)
        let item = AVPlayerItem(asset: asset)
        installItem(item, startAtMs: startAtMs)
    }

    public func resume() {
        guard isActive else { return }
        player.play()
    }

    public func pause() {
        player.pause()
    }

    public func stop() {
        isActive = false
        player.pause()
        cleanupCurrentItem()
        player.replaceCurrentItem(with: nil)
    }

    public func seek(toMs ms: Int64) {
        let time = CMTime(value: max(0, ms), timescale: 1000)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    public func setVolume(_ volume: Float) {
        player.volume = min(max(volume, 0.0), 1.0)
    }

    public var currentPositionMs: Int64 {
        let secs = player.currentTime().seconds
        return secs.isFinite ? max(0, Int64((secs * 1000.0).rounded())) : 0
    }

    public var durationMs: Int64 {
        guard let dur = player.currentItem?.duration.seconds, dur.isFinite else { return 0 }
        return max(0, Int64((dur * 1000.0).rounded()))
    }

    public var isPlaying: Bool {
        isActive && player.timeControlStatus == .playing
    }

    private func installItem(_ item: AVPlayerItem, startAtMs: Int64) {
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.onEnded?()
            }
        }
        player.replaceCurrentItem(with: item)
        if startAtMs > 0 {
            seek(toMs: startAtMs)
        }
        player.play()
    }

    private func cleanupCurrentItem() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        activeCryptoLoader = nil
    }

    private func attachPeriodicObserver() {
        let interval = CMTime(value: 1, timescale: 10)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isActive else { return }
                self.onProgress?(self.currentPositionMs, self.durationMs, self.isPlaying)
            }
        }
    }
}

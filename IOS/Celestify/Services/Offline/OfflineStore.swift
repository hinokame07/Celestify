//
//  OfflineStore.swift
//  Celestify
//
//  Manages encrypted offline tracks (`OfflineStore`), user-imported local audio
//  files from the iOS Files app, and device-local playlists.
//  Ported from Myspoti (OfflineStore.kt, OfflineDownloader.kt, LocalFiles).
//  Built on Myspoti (https://github.com/kota-zo/myspoti), GPL-3.0.
//

import AVFoundation
import Foundation
import Observation

public struct OfflineTrackRecord: Codable, Sendable, Identifiable, Hashable {
    public var id: String { trackID }
    public let trackID: String
    public let uri: SpotifyURI
    public let title: String
    public let artist: String
    public let album: String
    public let albumID: String
    public let durationMs: Int64
    public let coverURL: String?
    public let encryptedFileName: String
    public let sourceName: String
    public let bytesCount: Int64
    public let addedAt: Date
    public let isEpisode: Bool

    public func asTrack() -> Track {
        Track(
            uri: uri,
            name: title,
            durationMs: durationMs,
            artists: [ArtistRef(uri: "", name: artist)],
            album: AlbumRef(uri: albumID.isEmpty ? "" : "spotify:album:\(albumID)", name: album, images: coverURL.map { [MediaImage(url: $0)] } ?? []),
            playable: true
        )
    }
}

public enum OfflineDownloadState: Equatable, Sendable {
    case queued
    case downloading(progress: Double)
    case completed
    case unavailable
    case failed(String)
}

public struct LocalAudioFile: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let title: String
    public let artist: String
    public let album: String
    public let durationMs: Int64
    public let storedFileName: String
    public let addedAt: Date

    public func asTrack(in directory: URL) -> Track {
        let url = directory.appendingPathComponent(storedFileName)
        return Track(
            uri: "local:file:\(id)",
            name: title,
            durationMs: durationMs,
            artists: [ArtistRef(uri: "", name: artist)],
            album: AlbumRef(uri: "", name: album),
            playable: true,
            localFileURL: url
        )
    }
}

@Observable
@MainActor
public final class OfflineStore {
    public static let shared = OfflineStore()

    public private(set) var downloadedTracks: [String: OfflineTrackRecord] = [:]
    public private(set) var downloadStates: [String: OfflineDownloadState] = [:]
    public private(set) var localFiles: [LocalAudioFile] = []

    public let audioDirectory: URL
    public let localFilesDirectory: URL
    private let offlineIndexURL: URL
    private let localIndexURL: URL

    public init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.audioDirectory = support.appendingPathComponent("OfflineAudio", isDirectory: true)
        self.localFilesDirectory = support.appendingPathComponent("LocalAudioFiles", isDirectory: true)
        self.offlineIndexURL = support.appendingPathComponent("offline-index.json")
        self.localIndexURL = support.appendingPathComponent("local-files-index.json")
        try? FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: localFilesDirectory, withIntermediateDirectories: true)
        loadFromDisk()
    }

    public var sortedDownloads: [OfflineTrackRecord] {
        downloadedTracks.values.sorted { $0.addedAt > $1.addedAt }
    }

    public var localTracks: [Track] {
        localFiles.sorted { $0.addedAt > $1.addedAt }.map { $0.asTrack(in: localFilesDirectory) }
    }

    public var totalOfflineBytes: Int64 {
        downloadedTracks.values.reduce(0) { $0 + $1.bytesCount }
    }

    public func encryptedFileURL(for trackID: String) -> URL? {
        guard let record = downloadedTracks[trackID] else { return nil }
        let url = audioDirectory.appendingPathComponent(record.encryptedFileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Podcast & Extension Offline Download

    public func download(
        track: Track,
        api: SpotifyAPIClient,
        extensions: ExtensionManager = .shared,
        keychain: KeychainStore = .shared,
        http: HTTPClient = .shared
    ) async {
        let trackID = track.spotifyID
        guard !trackID.isEmpty, downloadedTracks[trackID] == nil else { return }
        downloadStates[trackID] = .queued

        do {
            downloadStates[trackID] = .downloading(progress: 0.1)
            var streamURL: URL?
            var headers: [String: String] = [:]
            var sourceLabel = "Podcast CDN"

            if track.isEpisode {
                streamURL = await api.episodeDirectStreamURL(episodeURI: track.uri)
            } else if let extStream = await extensions.resolveAudioSource(track: track) {
                streamURL = extStream.streamURL
                headers = extStream.headers
                sourceLabel = extStream.providerLabel
            }

            guard let resolvedURL = streamURL else {
                downloadStates[trackID] = .unavailable
                return
            }

            downloadStates[trackID] = .downloading(progress: 0.4)
            let res = try await http.send(url: resolvedURL, headers: headers, maxBytes: 120 * 1024 * 1024)
            guard (200...299).contains(res.statusCode), !res.data.isEmpty else {
                downloadStates[trackID] = .failed("HTTP \(res.statusCode)")
                return
            }

            downloadStates[trackID] = .downloading(progress: 0.85)
            let masterKey = try await keychain.loadOrCreateOfflineMasterKey()
            let encrypted = try OfflineCrypto.encryptData(res.data, masterKey: masterKey)

            let fileName = "\(trackID).mse1"
            let outURL = audioDirectory.appendingPathComponent(fileName)
            try encrypted.write(to: outURL, options: .atomic)

            let record = OfflineTrackRecord(
                trackID: trackID,
                uri: track.uri,
                title: track.name,
                artist: track.artistNames,
                album: track.album?.name ?? "",
                albumID: track.album?.spotifyID ?? "",
                durationMs: track.durationMs,
                coverURL: track.coverURL,
                encryptedFileName: fileName,
                sourceName: sourceLabel,
                bytesCount: Int64(encrypted.count),
                addedAt: Date(),
                isEpisode: track.isEpisode
            )
            downloadedTracks[trackID] = record
            downloadStates[trackID] = .completed
            persistDownloads()
        } catch {
            downloadStates[trackID] = .failed(error.localizedDescription)
        }
    }

    public func removeDownload(trackID: String) {
        if let record = downloadedTracks.removeValue(forKey: trackID) {
            try? FileManager.default.removeItem(at: audioDirectory.appendingPathComponent(record.encryptedFileName))
            downloadStates.removeValue(forKey: trackID)
            persistDownloads()
        }
    }

    public func removeAllDownloads() {
        for record in downloadedTracks.values {
            try? FileManager.default.removeItem(at: audioDirectory.appendingPathComponent(record.encryptedFileName))
        }
        downloadedTracks.removeAll()
        downloadStates.removeAll()
        persistDownloads()
    }

    // MARK: - Local Audio File Import (Files App)

    public func importLocalAudioFile(from externalURL: URL) async throws {
        let scoped = externalURL.startAccessingSecurityScopedResource()
        defer { if scoped { externalURL.stopAccessingSecurityScopedResource() } }

        let id = UUID().uuidString
        let ext = externalURL.pathExtension.isEmpty ? "m4a" : externalURL.pathExtension
        let storedName = "\(id).\(ext)"
        let destURL = localFilesDirectory.appendingPathComponent(storedName)
        try FileManager.default.copyItem(at: externalURL, to: destURL)

        let asset = AVURLAsset(url: destURL)
        let durationSec = (try? await asset.load(.duration).seconds) ?? 0
        let durationMs = durationSec.isFinite ? Int64(durationSec * 1000) : 0

        var title = externalURL.deletingPathExtension().lastPathComponent
        var artist = "Local File"
        var album = "On This iPhone"

        if let metadata = try? await asset.load(.commonMetadata) {
            for item in metadata {
                guard let key = item.commonKey else { continue }
                if key == .commonKeyTitle, let v = try? await item.load(.stringValue), !v.isEmpty {
                    title = v
                } else if key == .commonKeyArtist, let v = try? await item.load(.stringValue), !v.isEmpty {
                    artist = v
                } else if key == .commonKeyAlbumName, let v = try? await item.load(.stringValue), !v.isEmpty {
                    album = v
                }
            }
        }

        let record = LocalAudioFile(
            id: id,
            title: title,
            artist: artist,
            album: album,
            durationMs: durationMs,
            storedFileName: storedName,
            addedAt: Date()
        )
        localFiles.append(record)
        persistLocalFiles()
    }

    public func removeLocalFile(id: String) {
        if let idx = localFiles.firstIndex(where: { $0.id == id }) {
            let removed = localFiles.remove(at: idx)
            try? FileManager.default.removeItem(at: localFilesDirectory.appendingPathComponent(removed.storedFileName))
            persistLocalFiles()
        }
    }

    private func loadFromDisk() {
        if let data = try? Data(contentsOf: offlineIndexURL),
           let records = try? JSONDecoder().decode([OfflineTrackRecord].self, from: data) {
            downloadedTracks = Dictionary(uniqueKeysWithValues: records.map { ($0.trackID, $0) })
        }
        if let data = try? Data(contentsOf: localIndexURL),
           let locals = try? JSONDecoder().decode([LocalAudioFile].self, from: data) {
            localFiles = locals
        }
    }

    private func persistDownloads() {
        let list = Array(downloadedTracks.values)
        if let data = try? JSONEncoder().encode(list) {
            try? data.write(to: offlineIndexURL, options: .atomic)
        }
    }

    private func persistLocalFiles() {
        if let data = try? JSONEncoder().encode(localFiles) {
            try? data.write(to: localIndexURL, options: .atomic)
        }
    }
}

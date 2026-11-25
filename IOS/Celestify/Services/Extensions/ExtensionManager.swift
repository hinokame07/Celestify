//
//  ExtensionManager.swift
//  Celestify
//
//  Sandboxed JavaScriptCore extension host supporting lyrics, audio-source,
//  and download-source hooks installed from GitHub repositories.
//  Ported from Myspoti (:extensions module & Extensions.kt).
//  Built on Myspoti (https://github.com/kota-zo/myspoti), GPL-3.0.
//

import Foundation
import JavaScriptCore

public enum ExtensionCapability: String, Codable, Sendable, CaseIterable, Hashable {
    case lyrics = "lyrics"
    case audioSource = "audio-source"
    case downloadSource = "download-source"

    public var displayTitle: String {
        switch self {
        case .lyrics: return "Lyrics Provider"
        case .audioSource: return "Audio Stream Source"
        case .downloadSource: return "Offline Download Source"
        }
    }
}

public struct ExtensionManifest: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let version: String
    public let author: String
    public let summary: String
    public let repository: String
    public let capabilities: [ExtensionCapability]
    public let allowedDomains: [String]
    public var isEnabled: Bool
    public let scriptSource: String

    public init(
        id: String,
        name: String,
        version: String,
        author: String,
        summary: String,
        repository: String,
        capabilities: [ExtensionCapability],
        allowedDomains: [String] = [],
        isEnabled: Bool = true,
        scriptSource: String
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.author = author
        self.summary = summary
        self.repository = repository
        self.capabilities = capabilities
        self.allowedDomains = allowedDomains
        self.isEnabled = isEnabled
        self.scriptSource = scriptSource
    }
}

public struct ExtensionAudioResult: Sendable, Hashable {
    public let streamURL: URL
    public let headers: [String: String]
    public let providerLabel: String
    public let qualityLabel: String
}

public actor ExtensionManager {
    public static let shared = ExtensionManager()

    private let http: HTTPClient
    private let registryURL: URL
    private var extensions: [ExtensionManifest] = []
    private var errorLog: [String: String] = [:]

    public init(http: HTTPClient = .shared) {
        self.http = http
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Extensions", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.registryURL = dir.appendingPathComponent("registry.json")
        if let data = try? Data(contentsOf: registryURL),
           let decoded = try? JSONDecoder().decode([ExtensionManifest].self, from: data) {
            self.extensions = decoded
        }
    }

    public func installedExtensions() -> [ExtensionManifest] {
        extensions
    }

    public func lastErrors() -> [String: String] {
        errorLog
    }

    public func setEnabled(_ enabled: Bool, extensionID: String) {
        guard let idx = extensions.firstIndex(where: { $0.id == extensionID }) else { return }
        extensions[idx].isEnabled = enabled
        persist()
    }

    public func moveExtension(fromOffsets: IndexSet, toOffset: Int) {
        var copy = extensions
        let moving = fromOffsets.map { copy[$0] }
        for idx in fromOffsets.sorted(by: >) {
            copy.remove(at: idx)
        }
        let target = min(max(0, toOffset), copy.count)
        copy.insert(contentsOf: moving, at: target)
        extensions = copy
        persist()
    }

    public func uninstall(extensionID: String) {
        extensions.removeAll { $0.id == extensionID }
        errorLog.removeValue(forKey: extensionID)
        persist()
    }

    public func installFromGitHub(repositoryInput: String) async throws -> ExtensionManifest {
        let repo = try ThemeManager.normalizeRepository(repositoryInput)
        let headers = ["Accept": "application/vnd.github+json", "User-Agent": "Celestify-iOS-Extensions/2.4"]
        let meta = try await http.getJSON(url: URL(string: "https://api.github.com/repos/\(repo)")!, headers: headers)
        let branch = meta.str("default_branch") ?? "main"

        let manifestURL = URL(string: "https://raw.githubusercontent.com/\(repo)/\(branch)/manifest.json")!
        let mJson = try await http.getJSON(url: manifestURL)
        guard let extID = mJson.str("id"), !extID.isEmpty,
              let name = mJson.str("name"), !name.isEmpty else {
            throw HTTPError.transportError("Invalid extension manifest.json")
        }

        let entryFile = mJson.str("main") ?? "index.js"
        let scriptURL = URL(string: "https://raw.githubusercontent.com/\(repo)/\(branch)/\(entryFile)")!
        let scriptRes = try await http.send(url: scriptURL, maxBytes: 1_024 * 1_024)
        guard scriptRes.statusCode == 200 else {
            throw HTTPError.badStatus(code: scriptRes.statusCode, bodySnippet: "Missing \(entryFile)", retryAfterSeconds: nil)
        }

        let caps = mJson.list("capabilities").compactMap { $0.str().flatMap(ExtensionCapability.init(rawValue:)) }
        let domains = mJson.list("domains").compactMap { $0.str() }

        let manifest = ExtensionManifest(
            id: extID,
            name: name,
            version: mJson.str("version") ?? "1.0.0",
            author: mJson.str("author") ?? (repo.components(separatedBy: "/").first ?? ""),
            summary: mJson.str("description") ?? (meta.str("description") ?? ""),
            repository: repo,
            capabilities: caps.isEmpty ? [.lyrics] : caps,
            allowedDomains: domains,
            isEnabled: true,
            scriptSource: scriptRes.text
        )

        extensions.removeAll { $0.id == manifest.id }
        extensions.append(manifest)
        persist()
        DiagnosticLogbook.shared.log("extensions", "Installed extension \(manifest.name) (\(manifest.version))")
        return manifest
    }

    // MARK: - Hook Execution in Isolated JSContext

    public func queryLyricsExtensions(track: LyricsTrackQuery) async -> Lyrics? {
        let candidates = extensions.filter { $0.isEnabled && $0.capabilities.contains(.lyrics) }
        for ext in candidates {
            if let result = evaluateLyricsHook(manifest: ext, track: track) {
                return result
            }
        }
        return nil
    }

    public func resolveAudioSource(track: Track) async -> ExtensionAudioResult? {
        let candidates = extensions.filter { $0.isEnabled && $0.capabilities.contains(.audioSource) }
        for ext in candidates {
            if let result = evaluateAudioHook(manifest: ext, track: track) {
                return result
            }
        }
        return nil
    }

    private func evaluateLyricsHook(manifest: ExtensionManifest, track: LyricsTrackQuery) -> Lyrics? {
        guard let ctx = makeSandboxedContext(for: manifest) else { return nil }
        guard let fn = ctx.objectForKeyedSubscript("getLyrics"), !fn.isUndefined else { return nil }
        let arg: [String: Any] = [
            "id": track.id,
            "title": track.title,
            "artist": track.artist,
            "album": track.album,
            "durationMs": track.durationMs,
            "isrc": track.isrc ?? ""
        ]
        guard let res = fn.call(withArguments: [arg]), res.isObject,
              let dict = res.toDictionary() else {
            return nil
        }
        if let lrc = dict["lrc"] as? String, !lrc.isEmpty {
            let parsed = LrcParser.parseDocument(lrc)
            guard !parsed.lines.isEmpty else { return nil }
            return Lyrics(
                lines: parsed.lines,
                synced: parsed.isSynced,
                wordSynced: parsed.isWordSynced,
                provider: manifest.name
            )
        }
        if let ttml = dict["ttml"] as? String, let parsed = try? TtmlLyricsParser.parse(ttml) {
            return Lyrics(
                lines: parsed.lines,
                synced: parsed.synced,
                wordSynced: parsed.wordSynced,
                provider: manifest.name,
                isRTL: parsed.isRTL,
                songwriters: parsed.songwriters
            )
        }
        return nil
    }

    private func evaluateAudioHook(manifest: ExtensionManifest, track: Track) -> ExtensionAudioResult? {
        guard let ctx = makeSandboxedContext(for: manifest) else { return nil }
        guard let fn = ctx.objectForKeyedSubscript("getAudioStream"), !fn.isUndefined else { return nil }
        let arg: [String: Any] = [
            "id": track.spotifyID,
            "uri": track.uri,
            "title": track.name,
            "artist": track.artistNames,
            "durationMs": track.durationMs
        ]
        guard let res = fn.call(withArguments: [arg]), res.isObject,
              let dict = res.toDictionary(),
              let urlStr = dict["url"] as? String,
              let url = URL(string: urlStr),
              url.scheme == "https" else {
            return nil
        }
        let headers = (dict["headers"] as? [String: String]) ?? [:]
        return ExtensionAudioResult(
            streamURL: url,
            headers: headers,
            providerLabel: manifest.name,
            qualityLabel: (dict["quality"] as? String) ?? "Stream"
        )
    }

    private func makeSandboxedContext(for manifest: ExtensionManifest) -> JSContext? {
        guard let vm = JSVirtualMachine(), let ctx = JSContext(virtualMachine: vm) else { return nil }
        ctx.name = "CelestifyExt:\(manifest.id)"
        ctx.exceptionHandler = { [weak self] _, exception in
            let msg = exception?.toString() ?? "Unknown JS exception"
            Task { await self?.recordError(extensionID: manifest.id, message: msg) }
        }
        ctx.evaluateScript(manifest.scriptSource)
        return ctx
    }

    private func recordError(extensionID: String, message: String) {
        errorLog[extensionID] = message
        DiagnosticLogbook.shared.log("extensions", "[\(extensionID)] \(message)")
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(extensions) {
            try? data.write(to: registryURL, options: .atomic)
        }
    }
}

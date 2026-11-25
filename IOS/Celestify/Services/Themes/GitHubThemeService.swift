//
//  GitHubThemeService.swift
//  Celestify
//
//  Native Spicetify (`color.ini` / `user.css`), `celestify.json`, and Glassify
//  theme converter & GitHub repository importer. Remote CSS/JS is never executed.
//  Ported from Celestify (NativeTheme.kt & GitHubThemes.kt).
//  Glassify compatibility profile licensed under AGPL-3.0 (see THIRD_PARTY_NOTICES.md).
//

import Foundation
import Observation

public enum ThemeImportError: Error, LocalizedError, Sendable, Equatable {
    case invalidRepositoryURL(String)
    case invalidThemePayload(String)
    case repositoryTooLarge
    case githubError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidRepositoryURL(let msg): return msg
        case .invalidThemePayload(let msg): return msg
        case .repositoryTooLarge: return "Repository is too large to inspect safely."
        case .githubError(let msg): return msg
        }
    }
}

public enum SpicetifyThemeParser {
    public static let maxTextBytes = 512 * 1024

    /// Parses `#RRGGBB`, `#RGB`, or `rgb(r, g, b)` strings into opaque ARGB `UInt32`.
    public static func parseColor(_ raw: String) -> UInt32? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasSuffix(";") {
            value = String(value.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let hexCandidate = value.hasPrefix("#") ? String(value.dropFirst()) : value
        if hexCandidate.count == 6,
           hexCandidate.allSatisfy(\.isHexDigit),
           let parsed = UInt32(hexCandidate, radix: 16) {
            return 0xFF000000 | parsed
        }
        if hexCandidate.count == 3,
           hexCandidate.allSatisfy(\.isHexDigit) {
            let expanded = hexCandidate.map { "\($0)\($0)" }.joined()
            if let parsed = UInt32(expanded, radix: 16) {
                return 0xFF000000 | parsed
            }
        }
        if value.lowercased().hasPrefix("rgb(") && value.hasSuffix(")") {
            let inner = value.dropFirst(4).dropLast()
            let comps = inner.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            if comps.count == 3 && comps.allSatisfy({ (0...255).contains($0) }) {
                return 0xFF000000 | (UInt32(comps[0]) << 16) | (UInt32(comps[1]) << 8) | UInt32(comps[2])
            }
        }
        return nil
    }

    public static func relativeLuminance(_ argb: UInt32) -> Double {
        CelestialTokens.luminance(of: argb)
    }

    public static func contrastRatio(_ a: UInt32, _ b: UInt32) -> Double {
        let la = relativeLuminance(a)
        let lb = relativeLuminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// Enforces dark surface luminance and WCAG AA (`>= 4.5:1`) foreground contrast.
    public static func normalize(_ colors: NativeColors) -> NativeColors {
        func ensureDark(_ c: UInt32, fallback: UInt32) -> UInt32 {
            relativeLuminance(c) <= 0.045 ? (c | 0xFF000000) : fallback
        }
        let bg = ensureDark(colors.background, fallback: 0xFF000000)
        let surface = ensureDark(colors.surface, fallback: 0xFF1C1C1E)
        let elevated = ensureDark(colors.elevated, fallback: 0xFF2C2C2E)
        let backgrounds = [bg, surface, elevated]

        func ensureReadable(_ value: UInt32, fallback: UInt32) -> UInt32 {
            backgrounds.allSatisfy { contrastRatio(value, $0) >= 4.5 } ? (value | 0xFF000000) : fallback
        }

        return NativeColors(
            background: bg,
            surface: surface,
            elevated: elevated,
            text: ensureReadable(colors.text, fallback: 0xFFF5F5F7),
            secondary: ensureReadable(colors.secondary, fallback: 0xFFA1A1A6),
            accent: colors.accent | 0xFF000000
        )
    }

    public static func parse(ini: String?, css: String?, nativeJSON: String? = nil) throws -> ConvertedTheme {
        for sample in [ini, css, nativeJSON].compactMap({ $0 }) {
            guard sample.utf8.count <= maxTextBytes,
                  !sample.hasPrefix("PK\u{03}\u{04}"),
                  !sample.contains("\0") else {
                throw ThemeImportError.invalidThemePayload("Invalid theme text or binary archive. Only text theme files are supported.")
            }
        }

        if let nativeJSON {
            guard let root = JSONValue.parse(nativeJSON),
                  let dict = root.obj(),
                  Set(dict.keys).isSubset(of: ["schema", "colors"]),
                  root.int("schema") == 1,
                  let colorsObj = root.obj("colors"),
                  Set(colorsObj.keys) == Set(["background", "surface", "elevated", "text", "secondary", "accent"]) else {
                throw ThemeImportError.invalidThemePayload("Unsupported celestify.json native theme manifest.")
            }
            func reqColor(_ key: String) throws -> UInt32 {
                guard let raw = colorsObj[key]?.str(), let c = parseColor(raw) else {
                    throw ThemeImportError.invalidThemePayload("Invalid color for '\(key)'")
                }
                return c
            }
            let original = try NativeColors(
                background: reqColor("background"),
                surface: reqColor("surface"),
                elevated: reqColor("elevated"),
                text: reqColor("text"),
                secondary: reqColor("secondary"),
                accent: reqColor("accent")
            )
            let safe = normalize(original)
            let isFull = (original == safe) && (css?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            return ConvertedTheme(
                schemes: ["Native": safe],
                compatibility: isFull ? .full : .partial,
                notices: isFull ? [] : ["Colors adapted for dark mode readability. Desktop CSS is not executed."]
            )
        }

        var sections: [String: [String: UInt32]] = [:]
        var currentSection = "Default"

        if let ini {
            for rawLine in ini.components(separatedBy: .newlines) {
                let line = rawLine.replacingOccurrences(of: "\u{FEFF}", with: "").trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("[") && line.hasSuffix("]") && line.count >= 2 {
                    currentSection = String(line.dropFirst().dropLast().prefix(100))
                    guard sections.count < 80 else {
                        throw ThemeImportError.invalidThemePayload("Too many color schemes in color.ini")
                    }
                } else if !line.hasPrefix(";") && !line.hasPrefix("#"), let eqIdx = line.firstIndex(of: "=") {
                    let key = line[..<eqIdx].trimmingCharacters(in: .whitespaces).lowercased()
                    let valPart = line[line.index(after: eqIdx)...].split(separator: ";", omittingEmptySubsequences: false).first.map(String.init) ?? ""
                    if let parsedColor = parseColor(valPart) {
                        var map = sections[currentSection] ?? [:]
                        map[key] = parsedColor
                        sections[currentSection] = map
                    }
                }
            }
        }

        if sections.isEmpty, let css {
            let regex = try! NSRegularExpression(pattern: #"--spice-([a-z-]+)\s*:\s*([^;}]+)"#)
            let nsRange = NSRange(css.startIndex..<css.endIndex, in: css)
            var cssMap: [String: UInt32] = [:]
            for m in regex.matches(in: css, range: nsRange) {
                if let kR = Range(m.range(at: 1), in: css),
                   let vR = Range(m.range(at: 2), in: css),
                   let c = parseColor(String(css[vR])) {
                    cssMap[String(css[kR])] = c
                }
            }
            if !cssMap.isEmpty {
                sections["CSS colors"] = cssMap
            }
        }

        var mappedSchemes: [String: NativeColors] = [:]
        for (schemeName, props) in sections {
            guard let main = props["main"], (props["button"] != nil || props["text"] != nil) else { continue }
            let rawColors = NativeColors(
                background: main,
                surface: props["sidebar"] ?? main,
                elevated: props["card"] ?? props["player"] ?? main,
                text: props["text"] ?? 0xFFF5F5F7,
                secondary: props["subtext"] ?? 0xFFA1A1A6,
                accent: props["button-active"] ?? props["button"] ?? props["accent"] ?? 0xFFFF5C74
            )
            mappedSchemes[schemeName] = normalize(rawColors)
        }

        return ConvertedTheme(
            schemes: mappedSchemes,
            compatibility: mappedSchemes.isEmpty ? .unsupported : .partial,
            notices: [
                "Native color conversion only. Desktop CSS selectors, custom fonts, and scripts are never executed."
            ]
        )
    }
}

public enum GlassifyAdapter {
    public static let repositorySlug = "sanoojes/spicetify-glassify"

    public static let defaultColors = NativeColors(
        background: 0xFF000000,
        surface: 0xFF1C1C1E,
        elevated: 0xFF2C2C2E,
        text: 0xFFF5F5F7,
        secondary: 0xFFA1A1A6,
        accent: 0xFFFF5C74
    )

    public static func adapt(repository: String, manifest: JSONValue?, converted: ConvertedTheme) throws -> ConvertedTheme {
        guard repository.lowercased() == repositorySlug else { return converted }
        let manifestName = manifest?.str("name") ?? ""
        guard manifestName.isEmpty || manifestName.caseInsensitiveCompare("Glassify") == .orderedSame else {
            throw ThemeImportError.invalidThemePayload("Unexpected Glassify manifest")
        }
        let schemes = converted.schemes.isEmpty ? ["Glassify · Dynamic": defaultColors] : converted.schemes
        return ConvertedTheme(
            schemes: schemes,
            compatibility: .partial,
            notices: converted.notices + [
                "Glassify is rendered natively with iOS Liquid Glass, artwork colors, and translucent chrome. Desktop scripts are not executed."
            ],
            effects: .glassify
        )
    }
}

// MARK: - GitHub Repository Discovery & Theme Store

@Observable
@MainActor
public final class ThemeManager {
    public static let shared = ThemeManager()

    public private(set) var installedThemes: [InstalledTheme] = []
    public private(set) var activeThemeID: String?

    public var activeTheme: InstalledTheme? {
        guard let activeThemeID else { return nil }
        return installedThemes.first { $0.id == activeThemeID }
    }

    private let http: HTTPClient
    private let storageURL: URL
    private let defaults = UserDefaults.standard

    public init(http: HTTPClient = .shared) {
        self.http = http
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Themes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.storageURL = dir.appendingPathComponent("installed-themes.json")
        self.activeThemeID = defaults.string(forKey: "celestify.active_imported_theme")
        loadFromDisk()
    }

    public func activateTheme(id: String?) {
        activeThemeID = id
        defaults.set(id, forKey: "celestify.active_imported_theme")
    }

    public func installAndActivate(_ theme: InstalledTheme) {
        installedThemes.removeAll { $0.id == theme.id }
        installedThemes.append(theme)
        saveToDisk()
        activateTheme(id: theme.id)
    }

    public func removeTheme(id: String) {
        installedThemes.removeAll { $0.id == id }
        if activeThemeID == id {
            activateTheme(id: nil)
        }
        saveToDisk()
    }

    public nonisolated static func normalizeRepository(_ input: String) throws -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let urlStr = trimmed.hasPrefix("https://") ? trimmed : "https://github.com/\(trimmed)"
        guard let comps = URLComponents(string: urlStr),
              comps.scheme == "https",
              comps.host == "github.com",
              comps.user == nil,
              comps.port == nil,
              comps.query == nil,
              comps.fragment == nil else {
            throw ThemeImportError.invalidRepositoryURL("Enter a public https://github.com/owner/repository URL.")
        }
        var path = comps.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.hasSuffix(".git") { path = String(path.dropLast(4)) }
        let parts = path.split(separator: "/").map(String.init)
        let allowed = try! NSRegularExpression(pattern: #"^[A-Za-z0-9_-][A-Za-z0-9_.-]{0,99}$"#)
        guard parts.count == 2,
              parts.allSatisfy({ p in
                  p != ".." && allowed.firstMatch(in: p, range: NSRange(p.startIndex..<p.endIndex, in: p)) != nil
              }) else {
            throw ThemeImportError.invalidRepositoryURL("Use the repository root URL without branch or file paths.")
        }
        return "\(parts[0])/\(parts[1])"
    }

    public func discoverThemes(in repositoryInput: String) async throws -> [ThemeCandidate] {
        let repo = try Self.normalizeRepository(repositoryInput)
        let headers = ["Accept": "application/vnd.github+json", "User-Agent": "Celestify-iOS-Themes/2.4"]

        let meta = try await http.getJSON(url: URL(string: "https://api.github.com/repos/\(repo)")!, headers: headers, maxBytes: 512 * 1024)
        guard let defaultBranch = meta.str("default_branch") else {
            throw ThemeImportError.githubError("Repository metadata missing default branch.")
        }
        let encodedBranch = defaultBranch.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? defaultBranch
        let commitJSON = try await http.getJSON(url: URL(string: "https://api.github.com/repos/\(repo)/commits/\(encodedBranch)")!, headers: headers, maxBytes: 2 * 1024 * 1024)
        guard let sha = commitJSON.str("sha"), sha.count == 40 else {
            throw ThemeImportError.githubError("Could not resolve commit SHA.")
        }

        let treeJSON = try await http.getJSON(url: URL(string: "https://api.github.com/repos/\(repo)/git/trees/\(sha)?recursive=1")!, headers: headers, maxBytes: 6 * 1024 * 1024)
        if treeJSON.bool("truncated") == true {
            throw ThemeImportError.repositoryTooLarge
        }

        let allFiles = Set(treeJSON.list("tree").compactMap { node -> String? in
            guard node.str("type") == "blob",
                  node.str("mode") == "100644",
                  let path = node.str("path"),
                  !path.hasPrefix("/"),
                  !path.contains("..") else { return nil }
            return path
        })

        let markerNames: Set<String> = ["color.ini", "user.css", "celestify.json"]
        var directories = Set<String>()
        for file in allFiles {
            let leaf = file.split(separator: "/").last.map(String.init) ?? file
            if markerNames.contains(leaf) {
                let dir = file.contains("/") ? file.components(separatedBy: "/").dropLast().joined(separator: "/") : ""
                directories.insert(dir)
            }
        }

        let description = meta.str("description") ?? ""
        let owner = meta.str("owner.login") ?? repo.components(separatedBy: "/").first ?? ""

        return directories.sorted().map { dir in
            let subset = allFiles.filter { dir.isEmpty || $0.hasPrefix("\(dir)/") }
            return ThemeCandidate(
                repository: repo,
                path: dir,
                revision: sha,
                files: subset,
                description: String(description.prefix(400)),
                author: owner
            )
        }
    }

    public func previewTheme(_ candidate: ThemeCandidate) async throws -> ThemePreview {
        func fetchText(_ filename: String) async throws -> String? {
            let target = candidate.path.isEmpty ? filename : "\(candidate.path)/\(filename)"
            guard candidate.files.contains(target) else { return nil }
            let encoded = target.split(separator: "/")
                .map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
                .joined(separator: "/")
            let url = URL(string: "https://raw.githubusercontent.com/\(candidate.repository)/\(candidate.revision)/\(encoded)")!
            let res = try await http.send(url: url, maxBytes: SpicetifyThemeParser.maxTextBytes)
            guard res.statusCode == 200 else { return nil }
            return res.text
        }

        async let iniTask = fetchText("color.ini")
        async let cssTask = fetchText("user.css")
        async let nativeTask = fetchText("celestify.json")
        async let manifestTask = fetchText("manifest.json")

        let ini = try await iniTask
        let css = try await cssTask
        let native = try await nativeTask
        let manifestText = try await manifestTask
        let manifestJSON: JSONValue? = manifestText.flatMap { txt in
            let parsed = JSONValue.parse(txt)
            if let first = parsed?.list().first { return first }
            return parsed
        }

        let baseConverted = try SpicetifyThemeParser.parse(ini: ini, css: css, nativeJSON: native)
        let adapted = try GlassifyAdapter.adapt(repository: candidate.repository, manifest: manifestJSON, converted: baseConverted)

        return ThemePreview(
            candidate: candidate,
            converted: adapted,
            name: manifestJSON?.str("name") ?? candidate.name,
            author: candidate.author,
            description: manifestJSON?.str("description") ?? candidate.description
        )
    }

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([InstalledTheme].self, from: data) else { return }
        installedThemes = decoded
    }

    private func saveToDisk() {
        if let data = try? JSONEncoder().encode(installedThemes) {
            try? data.write(to: storageURL, options: .atomic)
        }
    }
}

//
//  SettingsSubViews.swift
//  Celestify
//
//  Settings detail screens:
//  - `ThemeImporterView` (Spicetify / `celestify.json` / `sanoojes/spicetify-glassify` native converter)
//  - `ListeningRecapView` (Swift Charts 8-week histogram + Top 10 Tracks/Artists/Albums)
//  - `ExtensionsSettingsView` (JavaScriptCore GitHub extension installer & priority manager)
//  - `DiagnosticLogbookView` (Redacted log viewer & exporter)
//  - `AboutLicensesView` (Prominent Myspoti GPL-3.0 & spicetify-glassify AGPL-3.0 credits)
//

import Charts
import SwiftUI

// MARK: - Native GitHub / Spicetify / Glassify Theme Importer

public struct ThemeImporterView: View {
    @Environment(AppDependencies.self) private var deps
    @Environment(\.celestialTheme) private var theme

    @State private var repoInput = ""
    @State private var candidates: [ThemeCandidate] = []
    @State private var selectedPreview: ThemePreview?
    @State private var selectedScheme: String = ""
    @State private var isScanning = false
    @State private var errorMessage: String?

    public init() {}

    public var body: some View {
        List {
            Section {
                Button {
                    repoInput = GlassifyAdapter.repositorySlug
                    Task { await scanRepository() }
                } label: {
                    Label("Inspect Glassify (\(GlassifyAdapter.repositorySlug))", systemImage: "sparkles")
                }

                Button {
                    repoInput = "spicetify/spicetify-themes"
                    Task { await scanRepository() }
                } label: {
                    Label("Inspect Official Spicetify Themes", systemImage: "swatchpalette")
                }
            } header: {
                Text("Curated Compatible Repositories")
            } footer: {
                Text("Celestify converts color.ini, --spice-* CSS variables, and celestify.json into native SwiftUI tokens with WCAG 4.5:1 dark contrast normalization. Remote CSS and JS are never executed.")
            }

            Section("Import from GitHub Repository") {
                TextField("owner/repository or https://github.com/...", text: $repoInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button {
                    Task { await scanRepository() }
                } label: {
                    if isScanning {
                        ProgressView()
                    } else {
                        Text("Scan Repository for Themes")
                    }
                }
                .disabled(repoInput.trimmingCharacters(in: .whitespaces).isEmpty || isScanning)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }

            if !candidates.isEmpty {
                Section("Discovered Themes (\(candidates.count))") {
                    ForEach(candidates) { candidate in
                        Button {
                            Task { await loadPreview(candidate) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(candidate.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text(candidate.path.isEmpty ? candidate.repository : candidate.path)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "eye")
                                    .foregroundStyle(theme.accent)
                            }
                        }
                    }
                }
            }

            if let preview = selectedPreview {
                Section("Preview: \(preview.name)") {
                    let schemeNames = preview.converted.schemes.keys.sorted()
                    if !schemeNames.isEmpty {
                        Picker("Color Scheme", selection: $selectedScheme) {
                            ForEach(schemeNames, id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }

                        if let colors = preview.converted.schemes[selectedScheme] ?? preview.converted.schemes.values.first {
                            HStack(spacing: 10) {
                                swatch(colors.background, label: "BG")
                                swatch(colors.surface, label: "Surface")
                                swatch(colors.elevated, label: "Card")
                                swatch(colors.text, label: "Text")
                                swatch(colors.accent, label: "Accent")
                            }
                            .padding(.vertical, 6)

                            Button("Install & Activate Theme") {
                                let id = "\(preview.candidate.id)#\(selectedScheme)"
                                let installed = InstalledTheme(
                                    id: id,
                                    name: "\(preview.name) (\(selectedScheme))",
                                    author: preview.author,
                                    repository: preview.candidate.repository,
                                    schemeName: selectedScheme,
                                    colors: colors,
                                    effects: preview.converted.effects,
                                    notices: preview.converted.notices
                                )
                                deps.themeManager.installAndActivate(installed)
                            }
                            .fontWeight(.semibold)
                            .foregroundStyle(theme.accent)
                        }
                    } else {
                        Text("No compatible color tokens found in this theme.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(preview.converted.notices, id: \.self) { note in
                        Text(note)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Installed Native Themes") {
                Button {
                    deps.themeManager.activateTheme(id: nil)
                } label: {
                    HStack {
                        Text("Built-in Celestial Palette")
                            .foregroundStyle(.primary)
                        Spacer()
                        if deps.themeManager.activeThemeID == nil {
                            Image(systemName: "checkmark")
                                .foregroundStyle(theme.accent)
                        }
                    }
                }

                ForEach(deps.themeManager.installedThemes) { item in
                    HStack {
                        Button {
                            deps.themeManager.activateTheme(id: item.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .foregroundStyle(.primary)
                                Text(item.repository)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if deps.themeManager.activeThemeID == item.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(theme.accent)
                        }
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) {
                            deps.themeManager.removeTheme(id: item.id)
                        }
                    }
                }
            }
        }
        .navigationTitle("Native Themes")
    }

    private func swatch(_ argb: UInt32, label: String) -> some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(argb: argb))
                .frame(width: 44, height: 34)
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.8)
                }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func scanRepository() async {
        isScanning = true
        errorMessage = nil
        selectedPreview = nil
        do {
            candidates = try await deps.themeManager.discoverThemes(in: repoInput)
        } catch {
            errorMessage = error.localizedDescription
        }
        isScanning = false
    }

    private func loadPreview(_ candidate: ThemeCandidate) async {
        errorMessage = nil
        do {
            let preview = try await deps.themeManager.previewTheme(candidate)
            selectedPreview = preview
            selectedScheme = preview.converted.schemes.keys.sorted().first ?? ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Listening History & Recap (Swift Charts)

public struct ListeningRecapView: View {
    @Environment(AppDependencies.self) private var deps
    @Environment(\.celestialTheme) private var theme
    @State private var refreshTick = 0

    public init() {}

    public var body: some View {
        let _ = refreshTick
        let recap = deps.listenHistory.recap()
        let weekly = deps.listenHistory.weeklyBreakdown(weeks: 8)

        List {
            Section("Overview (On-Device Private History)") {
                HStack {
                    statBlock(value: "\(recap.totalMinutes)", label: "Minutes")
                    Divider()
                    statBlock(value: "\(recap.totalListens)", label: "Songs ≥30s")
                    Divider()
                    statBlock(value: "\(recap.topArtists.count)", label: "Top Artists")
                }
                .padding(.vertical, 6)
            }

            Section("Last 8 Weeks (Minutes)") {
                Chart(weekly) { bucket in
                    BarMark(
                        x: .value("Week", bucket.weekStartDate, unit: .weekOfYear),
                        y: .value("Minutes", bucket.minutes)
                    )
                    .foregroundStyle(theme.accent.gradient)
                    .cornerRadius(5)
                }
                .frame(height: 170)
                .padding(.vertical, 8)
            }

            if !recap.topTracks.isEmpty {
                Section("Top Songs") {
                    ForEach(Array(recap.topTracks.enumerated()), id: \.element.id) { idx, item in
                        rankedRow(rank: idx + 1, item: item, circular: false)
                    }
                }
            }

            if !recap.topArtists.isEmpty {
                Section("Top Artists") {
                    ForEach(Array(recap.topArtists.enumerated()), id: \.element.id) { idx, item in
                        rankedRow(rank: idx + 1, item: item, circular: true)
                    }
                }
            }

            if !recap.topAlbums.isEmpty {
                Section("Top Albums") {
                    ForEach(Array(recap.topAlbums.enumerated()), id: \.element.id) { idx, item in
                        rankedRow(rank: idx + 1, item: item, circular: false)
                    }
                }
            }

            if recap.totalListens > 0 {
                Section {
                    Button("Clear Local Listening History", role: .destructive) {
                        deps.listenHistory.clear()
                        refreshTick += 1
                    }
                }
            }
        }
        .navigationTitle("Listening Recap")
    }

    private func statBlock(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(theme.accent)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func rankedRow(rank: Int, item: RankedListenEntity, circular: Bool) -> some View {
        HStack(spacing: 12) {
            Text("#\(rank)")
                .font(.subheadline.monospacedDigit().weight(.bold))
                .foregroundStyle(theme.accent)
                .frame(width: 28)

            ArtworkView(urlString: item.coverURL, size: 44, cornerRadius: 8, isCircular: circular)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(item.playCount)×")
                    .font(.caption.weight(.bold).monospacedDigit())
                Text("\(item.minutes)m")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - JavaScriptCore Extensions Manager

public struct ExtensionsSettingsView: View {
    @Environment(AppDependencies.self) private var deps

    @State private var installed: [ExtensionManifest] = []
    @State private var errors: [String: String] = [:]
    @State private var repoInput = ""
    @State private var statusMsg = ""
    @State private var isInstalling = false

    public init() {}

    public var body: some View {
        List {
            Section {
                TextField("owner/repository", text: $repoInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button {
                    isInstalling = true
                    Task {
                        do {
                            let ext = try await deps.extensions.installFromGitHub(repositoryInput: repoInput)
                            repoInput = ""
                            statusMsg = "Installed \(ext.name) v\(ext.version)"
                            await reload()
                        } catch {
                            statusMsg = error.localizedDescription
                        }
                        isInstalling = false
                    }
                } label: {
                    Text(isInstalling ? "Installing…" : "Install Extension from GitHub")
                }
                .disabled(repoInput.trimmingCharacters(in: .whitespaces).isEmpty || isInstalling)

                if !statusMsg.isEmpty {
                    Text(statusMsg)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Install Extension")
            } footer: {
                Text("Extensions execute inside an isolated Apple JavaScriptCore virtual machine without DOM or Keychain access.")
            }

            Section("Installed Extensions (Drag to Prioritize)") {
                if installed.isEmpty {
                    Text("No extensions installed.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(installed) { ext in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(ext.name) · v\(ext.version)")
                                        .font(.subheadline.weight(.semibold))
                                    Text(ext.capabilities.map(\.displayTitle).joined(separator: ", "))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { ext.isEnabled },
                                    set: { val in
                                        Task {
                                            await deps.extensions.setEnabled(val, extensionID: ext.id)
                                            await reload()
                                        }
                                    }
                                ))
                                .labelsHidden()
                            }
                            if let err = errors[ext.id] {
                                Text("Last error: \(err)")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                        .swipeActions {
                            Button("Uninstall", role: .destructive) {
                                Task {
                                    await deps.extensions.uninstall(extensionID: ext.id)
                                    await reload()
                                }
                            }
                        }
                    }
                    .onMove { from, to in
                        Task {
                            await deps.extensions.moveExtension(fromOffsets: from, toOffset: to)
                            await reload()
                        }
                    }
                }
            }
        }
        .navigationTitle("Extensions")
        .toolbar { EditButton() }
        .task { await reload() }
    }

    private func reload() async {
        installed = await deps.extensions.installedExtensions()
        errors = await deps.extensions.lastErrors()
    }
}

// MARK: - Diagnostic Logbook View

public struct DiagnosticLogbookView: View {
    @State private var entries: [DiagnosticEntry] = []

    public init() {}

    private var formattedExportText: String {
        let iso = ISO8601DateFormatter()
        return entries.map { entry in
            // FIX: DiagnosticEntry uses `timestamp` and `category` (not `at` / `tag`).
            "[\(iso.string(from: entry.timestamp))] [\(entry.category)] \(entry.message)"
        }.joined(separator: "\n")
    }

    public var body: some View {
        List {
            Section {
                ShareLink(item: formattedExportText.isEmpty ? "Celestify Diagnostic Logbook (empty)" : formattedExportText) {
                    Label("Export Redacted Logbook", systemImage: "square.and.arrow.up")
                }
                Button("Clear Logbook", role: .destructive) {
                    DiagnosticLogbook.shared.clear()
                    entries = []
                }
            } footer: {
                Text("Bearer tokens, sp_dc cookies, client-tokens, and authorization headers are automatically scrubbed before storage or export.")
            }

            Section("Recent Events (\(entries.count))") {
                ForEach(entries.reversed()) { entry in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(entry.category.uppercased())
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.tint)
                            Spacer()
                            Text(entry.timestamp, style: .time)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Text(entry.message)
                            .font(.caption.monospaced())
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("Diagnostics")
        .onAppear {
            entries = DiagnosticLogbook.shared.snapshot()
        }
    }
}

// MARK: - About & Mandatory Open-Source Attribution

public struct AboutLicensesView: View {
    @Environment(\.celestialTheme) private var theme

    public init() {}

    public var body: some View {
        List {
            Section("Celestify for iOS") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Celestify 2.4 · Native iOS Port")
                        .font(.headline.weight(.bold))
                    Text("An immersive Liquid Glass music client featuring syllable-synced Spicy Lyrics, live album-art atmospheres, Genius song stories, and native theme conversion.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Upstream Foundation (GPL-3.0)") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Built on Myspoti by kota-zo")
                        .font(.subheadline.weight(.bold))
                    Text("Celestify is built on Myspoti's clean-room Spotify Web Player bridge, GraphQL/spclient protocol implementation, encrypted offline storage, and lyrics architecture. Licensed under the GNU General Public License v3.0 or later.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Link(destination: URL(string: "https://github.com/kota-zo/myspoti")!) {
                        Label("github.com/kota-zo/myspoti", systemImage: "arrow.up.right.square")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(theme.accent)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Third-Party Compatibility & Attributions") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("spicetify-glassify by sanoojes (AGPL-3.0)")
                        .font(.subheadline.weight(.bold))
                    Text("Celestify includes a native compatibility adapter (`GlassifyAdapter`) for `sanoojes/spicetify-glassify`, rendering translucent glass palettes natively in SwiftUI without executing remote CSS or scripts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Link(destination: URL(string: "https://github.com/sanoojes/spicetify-glassify")!) {
                        Label("github.com/sanoojes/spicetify-glassify", systemImage: "arrow.up.right.square")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(theme.accent)
                    }
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Lyrics & Editorial Sources")
                        .font(.subheadline.weight(.bold))
                    Text("Word-synced & line-synced lyrics powered by Spotify Color Lyrics, Spicy Lyrics (`spicylyrics.org`), LyricsPlus, lrc.red, Kugou, and LRCLIB. Song stories and verified line annotations powered by Genius (`genius.com`).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("About & Licenses")
    }
}

//
//  SettingsView.swift
//  Celestify
//
//  Full Settings & Personalization hub: Multi-account Keychain switcher,
//  Celestial Palettes & Native Spicetify/Glassify Themes, Spicy Lyrics &
//  Translation, Playback & Crossfade, Listening Recap, JavaScriptCore Extensions,
//  Diagnostic Logbook, and GPL-3.0 / AGPL-3.0 Open-Source Attributions.
//  Built on Myspoti (https://github.com/kota-zo/myspoti), GPL-3.0.
//

import SwiftUI

public struct SettingsView: View {
    @Environment(AppDependencies.self) private var deps
    @Environment(\.celestialTheme) private var theme

    @State private var showingAddAccountSheet = false
    @State private var showingSignOutConfirmation = false

    public init() {}

    public var body: some View {
        List {
            // MARK: Account & Multi-Session
            Section("Spotify Account") {
                if let active = deps.authManager.currentAccount {
                    HStack(spacing: 12) {
                        ArtworkView(
                            urlString: active.avatarURL,
                            size: 52,
                            cornerRadius: 26,
                            isCircular: true,
                            fallbackSystemImage: "person.crop.circle.fill"
                        )
                        VStack(alignment: .leading, spacing: 3) {
                            Text(active.displayName)
                                .font(.headline)
                            let handle = active.id.hasPrefix("acct-") ? active.displayName : active.id
                            let plan = (active.product ?? "spotify").capitalized
                            Text("@\(handle) · \(plan)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(theme.accent)
                    }
                    .padding(.vertical, 4)
                }

                if deps.authManager.savedAccounts.count > 1 {
                    ForEach(deps.authManager.savedAccounts.filter { $0.id != deps.authManager.currentAccount?.id }) { other in
                        Button {
                            Task { await deps.authManager.switchToAccount(other) }
                        } label: {
                            Label("Switch to \(other.displayName)", systemImage: "arrow.left.arrow.right.circle")
                        }
                    }
                }

                Button {
                    showingAddAccountSheet = true
                } label: {
                    Label("Add Another Spotify Account", systemImage: "person.badge.plus")
                }

                Button(role: .destructive) {
                    showingSignOutConfirmation = true
                } label: {
                    Label("Sign Out Current Account", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }

            // MARK: Appearance, Liquid Glass & Themes
            Section("Appearance & Liquid Glass") {
                Picker("Color Palette", selection: Bindable(deps.preferences).celestialPalette) {
                    ForEach(CelestialPalette.allCases) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }

                Picker("Appearance", selection: Bindable(deps.preferences).appearanceMode) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                Toggle("Liquid Glass Surfaces", isOn: Bindable(deps.preferences).liquidGlassEnabled)
                Toggle("Live Artwork Colors", isOn: Bindable(deps.preferences).dynamicArtworkColors)
                Toggle("Pure Black OLED Background", isOn: Bindable(deps.preferences).pureBlackOLED)

                NavigationLink {
                    ThemeImporterView()
                } label: {
                    HStack {
                        Label("GitHub & Spicetify Themes", systemImage: "paintbrush.pointed")
                        Spacer()
                        Text(deps.themeManager.activeTheme?.name ?? "Built-in")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // MARK: Spicy Lyrics & Genius Meanings
            Section {
                Picker("Stage Typography", selection: Bindable(deps.preferences).spicyStageStyle) {
                    ForEach(SpicyStageStyle.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                Toggle("Word & Syllable Sync", isOn: Bindable(deps.preferences).lyricsWordSync)
                Toggle("Syllable Glow Highlight", isOn: Bindable(deps.preferences).lyricsGlow)
                Toggle("Automatic Romanization (CJK / Cyrillic)", isOn: Bindable(deps.preferences).spicyRomanize)

                Picker("Inline Translation", selection: Bindable(deps.preferences).lyricTranslateLanguage) {
                    ForEach(TranslationLanguageOption.supported) { opt in
                        Text(opt.name).tag(opt.code)
                    }
                }

                Toggle("Genius Song Stories & Annotations", isOn: Bindable(deps.preferences).spicyGeniusMeanings)
                Toggle("Supplemental Providers (NetEase & Genius)", isOn: Bindable(deps.preferences).lyricsExtraSources)
            } header: {
                Text("Spicy Lyrics & Cinema")
            } footer: {
                Text("When Supplemental Providers is enabled, track title and artist name may be sent to NetEase Cloud Music or Genius if primary word-synced providers have no match.")
            }

            // MARK: Playback & Audio
            Section("Playback & Audio") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Crossfade")
                        Spacer()
                        Text(deps.preferences.crossfadeSeconds == 0 ? "Off" : "\(deps.preferences.crossfadeSeconds)s")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(
                        value: Binding(
                            get: { Double(deps.preferences.crossfadeSeconds) },
                            set: {
                                let secs = Int($0.rounded())
                                deps.preferences.crossfadeSeconds = secs
                                deps.player.applyCrossfade(seconds: secs)
                            }
                        ),
                        in: 0...12,
                        step: 1
                    )
                }

                Toggle("Volume Normalization", isOn: Bindable(deps.preferences).audioNormalization)
                Toggle("Autoplay Similar Songs When Queue Ends", isOn: Bindable(deps.preferences).autoplaySimilar)
                Toggle("Headphone Buttons Skip ±15s in Podcasts", isOn: Bindable(deps.preferences).headsetSkipEpisodes)
                Toggle("Spotify Canvas Looping Videos", isOn: Bindable(deps.preferences).musicVideoEnabled)
            }

            // MARK: Insights & Extensions
            Section("Insights & Extensibility") {
                NavigationLink {
                    ListeningRecapView()
                } label: {
                    Label("Listening History & Recap", systemImage: "chart.bar.xaxis")
                }

                NavigationLink {
                    ExtensionsSettingsView()
                } label: {
                    Label("Extensions (JavaScriptCore)", systemImage: "puzzlepiece.extension")
                }
            }

            // MARK: Storage & Diagnostics
            Section("Storage & Privacy") {
                let mb = Double(deps.offlineStore.totalOfflineBytes) / (1024.0 * 1024.0)
                LabeledContent("Encrypted Offline Audio", value: String(format: "%.1f MB", mb))

                Button("Clear Artwork & Lyrics Cache") {
                    Task {
                        await ArtworkCache.shared.clear()
                        await deps.lyricsRepository.forgetAll()
                        HapticsManager.shared.softDetent()
                    }
                }

                if !deps.offlineStore.downloadedTracks.isEmpty {
                    Button("Remove All Offline Downloads", role: .destructive) {
                        deps.offlineStore.removeAllDownloads()
                    }
                }

                NavigationLink {
                    DiagnosticLogbookView()
                } label: {
                    Label("Diagnostic Logbook (Redacted)", systemImage: "doc.text.magnifyingglass")
                }
            }

            // MARK: About & Mandatory Open-Source Attribution
            Section("About & Open-Source Attribution") {
                NavigationLink {
                    AboutLicensesView()
                } label: {
                    Label("About Celestify & Licenses", systemImage: "info.circle")
                }

                LabeledContent("Version", value: "2.4.0 (iOS Native)")
                LabeledContent("License", value: "GPL-3.0-or-later")
            }

            Section {
                Spacer().frame(height: 90)
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $showingAddAccountSheet) {
            SpotifyLoginSheetContainer(
                initialURL: URL(string: "https://accounts.spotify.com/en/login?continue=https%3A%2F%2Fopen.spotify.com%2F")!
            )
        }
        .confirmationDialog("Sign out of Spotify?", isPresented: $showingSignOutConfirmation, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) {
                Task { await deps.authManager.logoutCurrentAccount() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

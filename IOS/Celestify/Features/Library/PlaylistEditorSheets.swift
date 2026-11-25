//
//  PlaylistEditorSheets.swift
//  Celestify
//
//  Liked Songs detail screen, Create Playlist sheet, Spotify Blend creator/joiner,
//  and Playlist Merge wizard (porting PlaylistMerge.kt round-robin deduplication).
//  Built on Myspoti (https://github.com/kota-zo/myspoti), GPL-3.0.
//

import SwiftUI

public struct LikedSongsDetailView: View {
    @Environment(AppDependencies.self) private var deps
    @Environment(\.celestialTheme) private var theme

    @State private var tracks: [Track] = []
    @State private var totalCount: Int = 0
    @State private var isLoading = true
    @State private var filterText = ""

    public init() {}

    private var displayedTracks: [Track] {
        guard !filterText.trimmingCharacters(in: .whitespaces).isEmpty else { return tracks }
        return tracks.filter {
            $0.name.localizedCaseInsensitiveContains(filterText) ||
            $0.artistNames.localizedCaseInsensitiveContains(filterText)
        }
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                VStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(theme.elevated)
                            .frame(width: 176, height: 176)
                        Image(systemName: "heart.fill")
                            .font(.system(size: 52))
                            .foregroundStyle(theme.accent)
                    }

                    Text("Liked Songs")
                        .font(.title.weight(.bold))
                        .foregroundStyle(theme.primaryText)

                    Text("\(totalCount) songs")
                        .font(.subheadline)
                        .foregroundStyle(theme.secondaryText)

                    HStack(spacing: 14) {
                        Button {
                            guard let first = displayedTracks.first else { return }
                            deps.player.playTrack(first, inContext: displayedTracks, contextURI: "spotify:collection:tracks", contextName: "Liked Songs")
                        } label: {
                            Label("Play", systemImage: "play.fill")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(theme.accent, in: Capsule())
                        }
                        .buttonStyle(.plain)

                        Button {
                            guard let random = displayedTracks.randomElement() else { return }
                            deps.player.playTrack(random, inContext: displayedTracks.shuffled(), contextURI: "spotify:collection:tracks", contextName: "Liked Songs")
                        } label: {
                            Label("Shuffle", systemImage: "shuffle")
                                .font(.headline)
                                .foregroundStyle(theme.primaryText)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .liquidGlass(shape: Capsule(), interactive: true)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 12)

                TextField("Find in Liked Songs…", text: $filterText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .liquidGlass(shape: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 16)

                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView().tint(theme.accent).padding(28)
                        Spacer()
                    }
                } else {
                    ForEach(displayedTracks) { track in
                        TrackRowView(track: track) {
                            deps.player.playTrack(track, inContext: displayedTracks, contextURI: "spotify:collection:tracks", contextName: "Liked Songs")
                        }
                        .padding(.horizontal, 16)
                    }
                }

                Spacer(minLength: 130)
            }
        }
        .navigationTitle("Liked Songs")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let page = try? await deps.api.likedTracks(offset: 0, limit: 100) {
                tracks = page.items.map(\.track)
                totalCount = page.total
            }
            isLoading = false
        }
    }
}

public struct CreatePlaylistSheet: View {
    public let onCreated: (String) -> Void
    @Environment(AppDependencies.self) private var deps
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var description = ""
    @State private var isSaving = false

    public init(onCreated: @escaping (String) -> Void) {
        self.onCreated = onCreated
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Playlist Info") {
                    TextField("Playlist Title", text: $name)
                    TextField("Description (optional)", text: $description)
                }
            }
            .navigationTitle("New Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        isSaving = true
                        Task {
                            let uri = (try? await deps.api.createPlaylist(name: name)) ?? ""
                            if !uri.isEmpty && !description.isEmpty {
                                try? await deps.api.renamePlaylist(playlistURI: uri, name: name, description: description)
                            }
                            dismiss()
                            onCreated(uri)
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

public struct BlendManagerSheet: View {
    @Environment(AppDependencies.self) private var deps
    @Environment(\.dismiss) private var dismiss

    @State private var generatedInviteURL: String = ""
    @State private var joinCodeInput: String = ""
    @State private var statusMessage: String = ""

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                Section("Start a New Spotify Blend") {
                    Button("Generate Blend Invite Link") {
                        Task {
                            do {
                                generatedInviteURL = try await deps.api.createBlendInvite()
                                statusMessage = "Share this link with a friend to create a daily-updated Blend."
                            } catch {
                                statusMessage = error.localizedDescription
                            }
                        }
                    }
                    if !generatedInviteURL.isEmpty, let url = URL(string: generatedInviteURL) {
                        ShareLink(item: url) {
                            Label("Share \(generatedInviteURL)", systemImage: "square.and.arrow.up")
                        }
                    }
                }

                Section("Join Friend's Blend") {
                    TextField("Invite code or link", text: $joinCodeInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Join Blend") {
                        Task {
                            if let uri = try? await deps.api.joinBlend(linkOrID: joinCodeInput), !uri.isEmpty {
                                dismiss()
                                deps.router.openSpotifyURI(uri)
                            } else {
                                statusMessage = "Could not join Blend with that invite token."
                            }
                        }
                    }
                    .disabled(joinCodeInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                if !statusMessage.isEmpty {
                    Section {
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Spotify Blends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

public struct PlaylistMergeSheet: View {
    public let playlists: [LibraryItem]
    public let onMerged: (String) -> Void

    @Environment(AppDependencies.self) private var deps
    @Environment(\.dismiss) private var dismiss

    @State private var selectedURIs: Set<String> = []
    @State private var mergedTitle = String(localized: "New Mix")
    @State private var interleaveRoundRobin = true
    @State private var isMerging = false

    public init(playlists: [LibraryItem], onMerged: @escaping (String) -> Void) {
        self.playlists = playlists
        self.onMerged = onMerged
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Merged Playlist") {
                    TextField("Title", text: $mergedTitle)
                    Toggle("Round-Robin Interleave Tracks", isOn: $interleaveRoundRobin)
                }

                Section("Select 2 or More Playlists (\(selectedURIs.count) selected)") {
                    ForEach(playlists) { pl in
                        Button {
                            if selectedURIs.contains(pl.uri) {
                                selectedURIs.remove(pl.uri)
                            } else {
                                selectedURIs.insert(pl.uri)
                            }
                        } label: {
                            HStack {
                                ArtworkView(urlString: pl.images.mediumURL, size: 40, cornerRadius: 8)
                                Text(pl.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selectedURIs.contains(pl.uri) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Merge Playlists")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isMerging ? "Merging…" : "Merge") {
                        isMerging = true
                        Task { await executeMerge() }
                    }
                    .disabled(selectedURIs.count < 2 || isMerging)
                }
            }
        }
    }

    private func executeMerge() async {
        var lists: [[String]] = []
        for uri in selectedURIs {
            if let (_, page) = try? await deps.api.playlistWithTracks(idOrURI: uri) {
                lists.append(page.items.map(\.uri).filter { $0.hasPrefix("spotify:track:") })
            }
        }

        var deduplicated: [String] = []
        var seen = Set<String>()
        if interleaveRoundRobin {
            let maxLen = lists.map(\.count).max() ?? 0
            for idx in 0..<maxLen {
                for list in lists where idx < list.count {
                    let u = list[idx]
                    if seen.insert(u).inserted {
                        deduplicated.append(u)
                    }
                }
            }
        } else {
            for list in lists {
                for u in list where seen.insert(u).inserted {
                    deduplicated.append(u)
                }
            }
        }

        if let newURI = try? await deps.api.createPlaylist(name: mergedTitle), !newURI.isEmpty {
            try? await deps.api.addTracksToPlaylist(playlistURI: newURI, trackURIs: Array(deduplicated.prefix(400)))
            dismiss()
            onMerged(newURI)
        } else {
            isMerging = false
        }
    }
}

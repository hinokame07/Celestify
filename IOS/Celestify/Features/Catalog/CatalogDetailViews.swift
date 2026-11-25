//
//  CatalogDetailViews.swift
//  Celestify
//
//  Catalog & Social detail destinations: Album, Artist, Playlist (with Blend
//  stories), Podcast Show/Episode, and User Profile.
//  Built on Myspoti (https://github.com/kota-zo/myspoti), GPL-3.0.
//

import SwiftUI

// MARK: - Album Detail

public struct AlbumDetailView: View {
    public let uri: String
    public let initialName: String?

    @Environment(AppDependencies.self) private var deps
    @Environment(\.celestialTheme) private var theme

    @State private var album: Album?
    @State private var tracks: [Track] = []
    @State private var similarAlbums: [Album] = []
    @State private var isSaved = false
    @State private var isLoading = true

    public init(uri: String, initialName: String? = nil) {
        self.uri = uri
        self.initialName = initialName
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if let album {
                    VStack(spacing: 14) {
                        ArtworkView(
                            urlString: album.images.largestURL,
                            size: 214,
                            cornerRadius: 20
                        )
                        .shadow(color: .black.opacity(0.14), radius: 8, y: 4)

                        VStack(spacing: 5) {
                            Text(album.name)
                                .font(.title2.weight(.bold))
                                .foregroundStyle(theme.primaryText)
                                .multilineTextAlignment(.center)

                            if let firstArtist = album.artists.first {
                                Button {
                                    deps.router.navigate(to: .artist(uri: firstArtist.uri, initialName: firstArtist.name))
                                } label: {
                                    Text(album.artistNames)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(theme.accent)
                                }
                                .buttonStyle(.plain)
                            }

                            Text("\(album.type.capitalized) · \(album.releaseYear ?? "")")
                                .font(.caption)
                                .foregroundStyle(theme.secondaryText)
                        }

                        HStack(spacing: 12) {
                            Button {
                                guard let first = tracks.first else { return }
                                deps.player.playTrack(first, inContext: tracks, contextURI: album.uri, contextName: album.name)
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
                                guard let random = tracks.randomElement() else { return }
                                deps.player.playTrack(random, inContext: tracks.shuffled(), contextURI: album.uri, contextName: album.name)
                            } label: {
                                Label("Shuffle", systemImage: "shuffle")
                                    .font(.headline)
                                    .foregroundStyle(theme.primaryText)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .liquidGlass(shape: Capsule(), interactive: true)
                            }
                            .buttonStyle(.plain)

                            Button {
                                isSaved.toggle()
                                let target = isSaved
                                Task { try? await deps.api.setLibrarySaved(target, uris: [album.uri]) }
                            } label: {
                                Image(systemName: isSaved ? "checkmark.circle.fill" : "plus.circle")
                                    .font(.title2)
                                    .foregroundStyle(isSaved ? theme.accent : theme.primaryText)
                                    .frame(width: 46, height: 46)
                                    .liquidGlass(shape: Circle(), interactive: true)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(isSaved ? "Remove Album from Library" : "Save Album to Library")
                        }
                        .padding(.horizontal, 20)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)

                    VStack(spacing: 2) {
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { idx, track in
                            TrackRowView(track: track, indexNumber: idx + 1, showArtwork: false) {
                                deps.player.playTrack(track, inContext: tracks, contextURI: album.uri, contextName: album.name)
                            }
                        }
                    }
                    .padding(.horizontal, 16)

                    if let label = album.label, !label.isEmpty {
                        Text(label)
                            .font(.caption)
                            .foregroundStyle(theme.secondaryText)
                            .padding(.horizontal, 16)
                            .padding(.top, 6)
                    }

                    if !similarAlbums.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("You Might Also Like")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(theme.primaryText)
                                .padding(.horizontal, 16)

                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 14) {
                                    ForEach(similarAlbums) { other in
                                        MediaCardView(
                                            title: other.name,
                                            subtitle: other.artistNames,
                                            imageURL: other.images.mediumURL,
                                            size: 136
                                        ) {
                                            deps.router.navigate(to: .album(uri: other.uri, initialName: other.name))
                                        }
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                    }
                } else if isLoading {
                    HStack {
                        Spacer()
                        ProgressView().tint(theme.accent).padding(48)
                        Spacer()
                    }
                }

                Spacer(minLength: 130)
            }
        }
        .navigationTitle(album?.name ?? initialName ?? "Album")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: uri) {
            isLoading = true
            if let (alb, page) = try? await deps.api.albumWithTracks(idOrURI: uri) {
                album = alb
                tracks = page.items
                if let firstTrack = page.items.first {
                    similarAlbums = (try? await deps.api.similarAlbums(trackURI: firstTrack.uri)) ?? []
                }
            }
            if let flags = try? await deps.api.areInLibrary(uris: [uri]), let first = flags.first {
                isSaved = first
            }
            isLoading = false
        }
    }
}

// MARK: - Artist Detail

public struct ArtistDetailView: View {
    public let uri: String
    public let initialName: String?

    @Environment(AppDependencies.self) private var deps
    @Environment(\.celestialTheme) private var theme

    @State private var page: ArtistPage?
    @State private var isFollowing = false
    @State private var isLoading = true

    public init(uri: String, initialName: String? = nil) {
        self.uri = uri
        self.initialName = initialName
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                if let page {
                    let topTrackModels = page.topTracks.map(\.track)
                    VStack(spacing: 12) {
                        ArtworkView(
                            urlString: page.headerImages.largestURL ?? page.artist.images.largestURL,
                            size: 168,
                            cornerRadius: 84,
                            isCircular: true,
                            fallbackSystemImage: "music.mic"
                        )
                        .shadow(color: .black.opacity(0.14), radius: 8, y: 4)

                        Text(page.artist.name)
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(theme.primaryText)
                            .multilineTextAlignment(.center)

                        if let listeners = page.artist.monthlyListeners, listeners > 0 {
                            Text("\(listeners.formatted()) monthly listeners")
                                .font(.subheadline)
                                .foregroundStyle(theme.secondaryText)
                        }

                        HStack(spacing: 12) {
                            Button {
                                guard let first = topTrackModels.first else { return }
                                deps.player.playTrack(first, inContext: topTrackModels, contextURI: page.artist.uri, contextName: page.artist.name)
                            } label: {
                                Label("Play Popular", systemImage: "play.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 22)
                                    .padding(.vertical, 12)
                                    .background(theme.accent, in: Capsule())
                            }
                            .buttonStyle(.plain)

                            Button {
                                isFollowing.toggle()
                                let target = isFollowing
                                Task { try? await deps.api.setLibrarySaved(target, uris: [page.artist.uri]) }
                            } label: {
                                Text(isFollowing ? "Following" : "Follow")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(theme.primaryText)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)
                                    .liquidGlass(shape: Capsule(), interactive: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)

                    if !topTrackModels.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Popular Songs")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(theme.primaryText)
                                .padding(.horizontal, 16)

                            ForEach(Array(topTrackModels.prefix(8).enumerated()), id: \.element.id) { idx, track in
                                TrackRowView(track: track, indexNumber: idx + 1) {
                                    deps.player.playTrack(track, inContext: topTrackModels, contextURI: page.artist.uri, contextName: page.artist.name)
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                    }

                    if !page.popularReleases.isEmpty {
                        shelfSection(title: "Releases", items: page.popularReleases)
                    }

                    if !page.appearsOn.isEmpty {
                        shelfSection(title: "Appears On", items: page.appearsOn)
                    }

                    if !page.related.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Fans Also Like")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(theme.primaryText)
                                .padding(.horizontal, 16)

                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 14) {
                                    ForEach(page.related) { rel in
                                        MediaCardView(
                                            title: rel.name,
                                            subtitle: "Artist",
                                            imageURL: rel.images.mediumURL,
                                            isCircular: true,
                                            size: 124
                                        ) {
                                            deps.router.navigate(to: .artist(uri: rel.uri, initialName: rel.name))
                                        }
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                    }

                    if let bio = page.biography, !bio.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("About")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(theme.primaryText)
                            Text(bio)
                                .font(.footnote)
                                .foregroundStyle(theme.secondaryText)
                                .lineLimit(8)
                        }
                        .padding(16)
                        .background(theme.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(theme.separator, lineWidth: 1)
                        }
                        .padding(.horizontal, 16)
                    }
                } else if isLoading {
                    HStack {
                        Spacer()
                        ProgressView().tint(theme.accent).padding(48)
                        Spacer()
                    }
                }

                Spacer(minLength: 130)
            }
        }
        .navigationTitle(page?.artist.name ?? initialName ?? "Artist")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: uri) {
            isLoading = true
            page = try? await deps.api.artistPage(idOrURI: uri)
            if let flags = try? await deps.api.areInLibrary(uris: [uri]), let first = flags.first {
                isFollowing = first
            }
            isLoading = false
        }
    }

    private func shelfSection(title: String, items: [Album]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(theme.primaryText)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(items) { album in
                        MediaCardView(
                            title: album.name,
                            subtitle: album.releaseYear ?? "",
                            imageURL: album.images.mediumURL,
                            size: 144
                        ) {
                            deps.router.navigate(to: .album(uri: album.uri, initialName: album.name))
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

// MARK: - Playlist Detail

public struct PlaylistDetailView: View {
    public let uri: String
    public let initialName: String?

    @Environment(AppDependencies.self) private var deps
    @Environment(\.celestialTheme) private var theme

    @State private var playlist: Playlist?
    @State private var tracks: [Track] = []
    @State private var filterText = ""
    @State private var isSaved = false
    @State private var isLoading = true
    @State private var blendStory: BlendStory?
    @State private var showingBlendStory = false

    public init(uri: String, initialName: String? = nil) {
        self.uri = uri
        self.initialName = initialName
    }

    private var displayedTracks: [Track] {
        guard !filterText.trimmingCharacters(in: .whitespaces).isEmpty else { return tracks }
        return tracks.filter {
            $0.name.localizedCaseInsensitiveContains(filterText) ||
            $0.artistNames.localizedCaseInsensitiveContains(filterText)
        }
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if let playlist {
                    VStack(spacing: 12) {
                        ArtworkView(
                            urlString: playlist.images.largestURL,
                            size: 204,
                            cornerRadius: 20
                        )
                        .shadow(color: .black.opacity(0.14), radius: 8, y: 4)

                        Text(playlist.name)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(theme.primaryText)
                            .multilineTextAlignment(.center)

                        if let desc = playlist.description, !desc.isEmpty {
                            Text(desc)
                                .font(.caption)
                                .foregroundStyle(theme.secondaryText)
                                .multilineTextAlignment(.center)
                                .lineLimit(3)
                                .padding(.horizontal, 24)
                        }

                        Text("\(playlist.owner ?? "Spotify") · \(tracks.count) tracks")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(theme.secondaryText)

                        HStack(spacing: 12) {
                            Button {
                                guard let first = displayedTracks.first else { return }
                                deps.player.playTrack(first, inContext: displayedTracks, contextURI: playlist.uri, contextName: playlist.name)
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
                                deps.player.playTrack(random, inContext: displayedTracks.shuffled(), contextURI: playlist.uri, contextName: playlist.name)
                            } label: {
                                Label("Shuffle", systemImage: "shuffle")
                                    .font(.headline)
                                    .foregroundStyle(theme.primaryText)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .liquidGlass(shape: Capsule(), interactive: true)
                            }
                            .buttonStyle(.plain)

                            Menu {
                                Button {
                                    isSaved.toggle()
                                    let target = isSaved
                                    Task { try? await deps.api.setLibrarySaved(target, uris: [playlist.uri]) }
                                } label: {
                                    Label(isSaved ? "Remove from Library" : "Save to Library", systemImage: isSaved ? "trash" : "plus.circle")
                                }

                                if blendStory != nil {
                                    Button {
                                        showingBlendStory = true
                                    } label: {
                                        Label("View blend story", systemImage: "text.quote")
                                    }
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .font(.title2)
                                    .foregroundStyle(theme.primaryText)
                                    .frame(width: 46, height: 46)
                                    .liquidGlass(shape: Circle(), interactive: true)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)

                    TextField("Find in playlist…", text: $filterText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .liquidGlass(shape: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(.horizontal, 16)

                    ForEach(displayedTracks) { track in
                        TrackRowView(track: track) {
                            deps.player.playTrack(track, inContext: displayedTracks, contextURI: playlist.uri, contextName: playlist.name)
                        }
                        .padding(.horizontal, 16)
                    }
                } else if isLoading {
                    HStack {
                        Spacer()
                        ProgressView().tint(theme.accent).padding(48)
                        Spacer()
                    }
                }

                Spacer(minLength: 130)
            }
        }
        .navigationTitle(playlist?.name ?? initialName ?? "Playlist")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingBlendStory) {
            if let story = blendStory {
                NavigationStack {
                    VStack(spacing: 16) {
                        Text(story.title)
                            .font(.title2.weight(.bold))
                            .multilineTextAlignment(.center)
                        if let sub = story.subtitle {
                            Text(sub)
                                .font(.headline)
                                .foregroundStyle(theme.accent)
                        }
                        if let detail = story.detail {
                            Text(detail)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(28)
                    .navigationTitle("Blend Story")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingBlendStory = false }
                        }
                    }
                }
                .presentationDetents([.medium])
            }
        }
        .task(id: uri) {
            isLoading = true
            if let (pl, page) = try? await deps.api.playlistWithTracks(idOrURI: uri) {
                playlist = pl
                tracks = page.items
                if pl.isBlend || pl.name.localizedCaseInsensitiveContains("Blend") {
                    blendStory = await deps.api.blendStory(playlistURI: pl.uri)
                }
            }
            isLoading = false
        }
    }
}

// MARK: - Podcast Show & Episode Details

public struct ShowDetailView: View {
    public let uri: String
    public let initialName: String?

    @Environment(AppDependencies.self) private var deps
    @Environment(\.celestialTheme) private var theme
    @State private var show: Show?
    @State private var episodes: [Episode] = []
    @State private var isLoading = true

    public init(uri: String, initialName: String? = nil) {
        self.uri = uri
        self.initialName = initialName
    }

    public var body: some View {
        List {
            if let show {
                Section {
                    HStack(spacing: 14) {
                        ArtworkView(urlString: show.images.mediumURL, size: 76, cornerRadius: 14)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(show.name)
                                .font(.headline.weight(.bold))
                            Text(show.publisher)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let desc = show.description, !desc.isEmpty {
                        Text(desc)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                    }
                }
            }

            if isLoading {
                ProgressView().frame(maxWidth: .infinity)
            } else {
                Section("Episodes") {
                    ForEach(episodes) { ep in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(ep.name)
                                .font(.headline)
                            if let desc = ep.description, !desc.isEmpty {
                                Text(desc)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                            }
                            HStack {
                                Button {
                                    deps.player.playTrack(ep.asTrack())
                                } label: {
                                    Label("Play Episode", systemImage: "play.circle.fill")
                                        .font(.footnote.weight(.semibold))
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(theme.accent)

                                Button {
                                    Task { await deps.offlineStore.download(track: ep.asTrack(), api: deps.api) }
                                } label: {
                                    Label("Offline", systemImage: "arrow.down.circle")
                                        .font(.footnote)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        }
        .navigationTitle(show?.name ?? initialName ?? "Podcast")
        .task(id: uri) {
            if let (sh, page) = try? await deps.api.showWithEpisodes(idOrURI: uri) {
                show = sh
                episodes = page.items
            }
            isLoading = false
        }
    }
}

public struct EpisodeDetailView: View {
    public let uri: String
    public let initialName: String?

    @Environment(AppDependencies.self) private var deps
    @Environment(\.celestialTheme) private var theme
    @State private var episode: Episode?

    public init(uri: String, initialName: String? = nil) {
        self.uri = uri
        self.initialName = initialName
    }

    public var body: some View {
        let track = episode?.asTrack() ?? Track(uri: uri, name: initialName ?? "Episode", durationMs: 0)
        VStack(spacing: 20) {
            ArtworkView(urlString: episode?.images.largestURL, size: 180, cornerRadius: 22, fallbackSystemImage: "waveform.badge.mic")
            Text(track.name)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
            if let desc = episode?.description {
                Text(desc)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
                    .multilineTextAlignment(.center)
            }
            Button {
                deps.player.playTrack(track)
            } label: {
                Label("Stream Episode", systemImage: "play.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background(theme.accent, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .navigationTitle("Episode")
        .task(id: uri) {
            episode = try? await deps.api.episodeDetail(idOrURI: uri)
        }
    }
}

// MARK: - User Profile Detail

public struct UserProfileDetailView: View {
    public let uri: String
    public let initialName: String?

    @Environment(AppDependencies.self) private var deps
    @Environment(\.celestialTheme) private var theme
    @State private var profile: UserProfile?
    @State private var isLoading = true

    public init(uri: String, initialName: String? = nil) {
        self.uri = uri
        self.initialName = initialName
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if let profile {
                    VStack(spacing: 10) {
                        ArtworkView(
                            urlString: profile.images.largestURL,
                            size: 132,
                            cornerRadius: 66,
                            isCircular: true,
                            fallbackSystemImage: "person.crop.circle.fill"
                        )
                        Text(profile.name)
                            .font(.title.weight(.bold))
                            .foregroundStyle(theme.primaryText)
                        Text("\(profile.followers ?? 0) followers · \(profile.following ?? 0) following")
                            .font(.subheadline)
                            .foregroundStyle(theme.secondaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 16)

                    if !profile.recentArtists.isEmpty {
                        Text("Recently Played Artists")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(theme.primaryText)
                            .padding(.horizontal, 16)
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 14) {
                                ForEach(profile.recentArtists) { artist in
                                    MediaCardView(
                                        title: artist.name,
                                        subtitle: "Artist",
                                        imageURL: artist.images.mediumURL,
                                        isCircular: true,
                                        size: 120
                                    ) {
                                        deps.router.navigate(to: .artist(uri: artist.uri, initialName: artist.name))
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }

                    if !profile.playlists.isEmpty {
                        Text("Public Playlists")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(theme.primaryText)
                            .padding(.horizontal, 16)
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 14) {
                                ForEach(profile.playlists) { pl in
                                    MediaCardView(
                                        title: pl.name,
                                        subtitle: pl.owner ?? "",
                                        imageURL: pl.images.mediumURL,
                                        size: 140
                                    ) {
                                        deps.router.navigate(to: .playlist(uri: pl.uri, initialName: pl.name))
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                } else if isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(48)
                }

                Spacer(minLength: 130)
            }
        }
        .navigationTitle(profile?.name ?? initialName ?? "Profile")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: uri) {
            let userID = MediaKind.spotifyID(from: uri)
            profile = try? await deps.api.userProfile(userID: userID)
            isLoading = false
        }
    }
}

//
//  SearchView.swift
//  Celestify
//
//  Multi-entity Spotify Search (`searchTracks`, `searchArtists`, `searchAlbums`,
//  `searchPlaylists`, `searchPodcasts`, `searchUsers`), live autocomplete
//  suggestions, recent searches, and Browse Category tiles.
//  Built on Myspoti (https://github.com/kota-zo/myspoti), GPL-3.0.
//

import SwiftUI

public enum SearchScopeFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case tracks = "Songs"
    case artists = "Artists"
    case albums = "Albums"
    case playlists = "Playlists"
    case podcasts = "Podcasts"
    case users = "Profiles"

    public var id: String { rawValue }
}

public struct SearchView: View {
    @Environment(AppDependencies.self) private var deps
    @Environment(\.celestialTheme) private var theme

    @State private var query = ""
    @State private var scope: SearchScopeFilter = .all
    @State private var results = SearchResults()
    @State private var showCards: [MediaCard] = []
    @State private var userCards: [MediaCard] = []
    @State private var suggestions: [String] = []
    @State private var categories: [MediaCard] = []
    @State private var recentQueries: [String] = []
    @State private var isSearching = false

    public init() {}

    public var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 20) {
                Text("Search")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(theme.primaryText)
                    .padding(.horizontal, 16)

                searchBarField
                    .padding(.horizontal, 16)

                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    emptyQueryContent
                } else {
                    scopeFilterPills
                    activeQueryResults
                }

                Spacer(minLength: 130)
            }
            .padding(.top, 12)
        }
        .task {
            recentQueries = UserDefaults.standard.stringArray(forKey: "celestify.recent_searches") ?? []
            if categories.isEmpty {
                categories = (try? await deps.api.browseCategories()) ?? []
            }
        }
        .task(id: query) {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                results = SearchResults()
                showCards = []
                userCards = []
                suggestions = []
                return
            }
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled else { return }
            await performSearch(trimmed)
        }
    }

    private var searchBarField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(theme.secondaryText)

            TextField("Songs, artists, lyrics, podcasts…", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(theme.primaryText)
                .submitLabel(.search)
                .onSubmit {
                    saveRecentQuery(query)
                }

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(theme.secondaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .liquidGlass(shape: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private var scopeFilterPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SearchScopeFilter.allCases) { item in
                    let active = scope == item
                    Button {
                        HapticsManager.shared.selection()
                        scope = item
                    } label: {
                        Text(item.rawValue)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(active ? theme.onAccent : theme.primaryText)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .frame(minHeight: 44)
                            .background {
                                if active {
                                    Capsule().fill(theme.accent)
                                } else {
                                    Capsule().fill(theme.elevated)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private var emptyQueryContent: some View {
        if !recentQueries.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Recent Searches")
                        .font(.headline)
                        .foregroundStyle(theme.primaryText)
                    Spacer()
                    Button("Clear") {
                        recentQueries = []
                        UserDefaults.standard.removeObject(forKey: "celestify.recent_searches")
                    }
                    .font(.footnote)
                    .foregroundStyle(theme.accent)
                }
                .padding(.horizontal, 16)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(recentQueries, id: \.self) { q in
                            Button {
                                query = q
                            } label: {
                                Label(q, systemImage: "clock.arrow.circlepath")
                                    .font(.footnote)
                                    .foregroundStyle(theme.primaryText)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .frame(minHeight: 44)
                                    .liquidGlass(shape: Capsule(), interactive: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }

        VStack(alignment: .leading, spacing: 12) {
            Text("Browse Categories")
                .font(.title3.weight(.bold))
                .foregroundStyle(theme.primaryText)
                .padding(.horizontal, 16)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                spacing: 12
            ) {
                ForEach(Array(categories.enumerated()), id: \.element.id) { index, category in
                    let hueColor = Self.categoryTileColor(index: index)
                    Button {
                        deps.router.navigate(to: .browseCategory(id: category.uri, title: category.title))
                    } label: {
                        ZStack(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(hueColor.gradient)
                                .frame(height: 98)

                            HStack {
                                Spacer()
                                VStack {
                                    Spacer()
                                    ArtworkView(urlString: category.images.mediumURL, size: 62, cornerRadius: 10)
                                        .rotationEffect(.degrees(18))
                                        .offset(x: 8, y: 8)
                                }
                            }

                            Text(category.title)
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                                .padding(12)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private var activeQueryResults: some View {
        let trackList = results.tracks.items
        let artistList = results.artists.items
        let albumList = results.albums.items
        let playlistList = results.playlists.items

        if isSearching && trackList.isEmpty && artistList.isEmpty {
            HStack {
                Spacer()
                ProgressView()
                    .tint(theme.accent)
                    .padding(.vertical, 36)
                Spacer()
            }
        } else {
            if !suggestions.isEmpty && scope == .all {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions.prefix(6), id: \.self) { suggestion in
                            Button {
                                query = suggestion
                                saveRecentQuery(suggestion)
                            } label: {
                                Label(suggestion, systemImage: "sparkle.magnifyingglass")
                                    .font(.caption)
                                    .foregroundStyle(theme.secondaryText)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.white.opacity(0.06), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }

            if (scope == .all || scope == .tracks), !trackList.isEmpty {
                sectionHeader("Songs")
                VStack(spacing: 2) {
                    ForEach(scope == .all ? Array(trackList.prefix(6)) : trackList) { track in
                        TrackRowView(track: track) {
                            saveRecentQuery(query)
                            deps.player.playTrack(track, inContext: trackList)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }

            if (scope == .all || scope == .artists), !artistList.isEmpty {
                sectionHeader("Artists")
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(artistList) { artist in
                            MediaCardView(
                                title: artist.name,
                                subtitle: "Artist",
                                imageURL: artist.images.mediumURL,
                                isCircular: true,
                                size: 124
                            ) {
                                saveRecentQuery(query)
                                deps.router.navigate(to: .artist(uri: artist.uri, initialName: artist.name))
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }

            if (scope == .all || scope == .albums), !albumList.isEmpty {
                sectionHeader("Albums")
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(albumList) { album in
                            MediaCardView(
                                title: album.name,
                                subtitle: album.artistNames,
                                imageURL: album.images.mediumURL,
                                size: 144
                            ) {
                                saveRecentQuery(query)
                                deps.router.navigate(to: .album(uri: album.uri, initialName: album.name))
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }

            if (scope == .all || scope == .playlists), !playlistList.isEmpty {
                sectionHeader("Playlists")
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(playlistList) { pl in
                            MediaCardView(
                                title: pl.name,
                                subtitle: pl.owner ?? "",
                                imageURL: pl.images.mediumURL,
                                size: 144
                            ) {
                                saveRecentQuery(query)
                                deps.router.navigate(to: .playlist(uri: pl.uri, initialName: pl.name))
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }

            if (scope == .all || scope == .podcasts), !showCards.isEmpty {
                sectionHeader("Podcasts & Shows")
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(showCards) { card in
                            MediaCardView(
                                title: card.title,
                                subtitle: card.subtitle ?? "",
                                imageURL: card.images.mediumURL,
                                size: 144
                            ) {
                                saveRecentQuery(query)
                                deps.router.openSpotifyURI(card.uri, fallbackTitle: card.title)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }

            if (scope == .all || scope == .users), !userCards.isEmpty {
                sectionHeader("Profiles")
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(userCards) { profile in
                            MediaCardView(
                                title: profile.title,
                                subtitle: profile.subtitle ?? "",
                                imageURL: profile.images.mediumURL,
                                isCircular: true,
                                size: 116
                            ) {
                                deps.router.openSpotifyURI(profile.uri, fallbackTitle: profile.title)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.title3.weight(.bold))
            .foregroundStyle(theme.primaryText)
            .padding(.horizontal, 16)
    }

    private func performSearch(_ text: String) async {
        isSearching = true
        async let searchTask = deps.api.searchAll(query: text, limit: 15)
        async let showsTask = deps.api.searchShows(query: text, limit: 10)
        async let usersTask = deps.api.searchUsers(query: text, limit: 10)
        async let suggestTask = deps.api.searchSuggestions(query: text)
        if let res = try? await searchTask {
            results = res
        }
        showCards = (try? await showsTask)?.items ?? []
        userCards = (try? await usersTask)?.items ?? []
        suggestions = (try? await suggestTask) ?? []
        isSearching = false
    }

    private func saveRecentQuery(_ q: String) {
        let trimmed = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var updated = recentQueries.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
        updated.insert(trimmed, at: 0)
        recentQueries = Array(updated.prefix(10))
        UserDefaults.standard.set(recentQueries, forKey: "celestify.recent_searches")
    }

    private static func categoryTileColor(index: Int) -> Color {
        let palette: [UInt32] = [
            0xFF1F3B73, 0xFF7B1FA2, 0xFFC2185B, 0xFF00695C,
            0xFF283593, 0xFFAD1457, 0xFF0277BD, 0xFF4527A0
        ]
        return Color(argb: palette[index % palette.count])
    }
}

public struct BrowseCategoryDetailView: View {
    public let categoryID: String
    public let title: String

    @Environment(AppDependencies.self) private var deps
    @Environment(\.celestialTheme) private var theme
    @State private var sections: [HomeSection] = []
    @State private var isLoading = true

    public init(categoryID: String, title: String) {
        self.categoryID = categoryID
        self.title = title
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                ForEach(sections) { section in
                    Text(section.title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(theme.primaryText)
                        .padding(.horizontal, 16)

                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 14) {
                            ForEach(section.items) { card in
                                MediaCardView(
                                    title: card.title,
                                    subtitle: card.subtitle ?? "",
                                    imageURL: card.images.mediumURL,
                                    size: 148
                                ) {
                                    deps.router.openSpotifyURI(card.uri, fallbackTitle: card.title)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 120)
        }
        .navigationTitle(title)
        .task {
            sections = (try? await deps.api.categorySections(uri: categoryID)) ?? []
            isLoading = false
        }
    }
}

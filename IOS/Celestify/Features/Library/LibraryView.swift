//
//  LibraryView.swift
//  Celestify
//
//  User's Spotify Library (`libraryV3`), Liked Songs, AES-256-CTR Offline
//  Downloads, Local Audio Files (Files app `.fileImporter`), Create Playlist,
//  Spotify Blends, and Playlist Merge.
//  Built on Myspoti (https://github.com/kota-zo/myspoti), GPL-3.0.
//

import SwiftUI
import UniformTypeIdentifiers

public enum LibraryFilterKind: String, CaseIterable, Identifiable {
    case all = "All"
    case playlists = "Playlists"
    case albums = "Albums"
    case artists = "Artists"
    case shows = "Podcasts"
    case downloaded = "Downloaded"
    case localFiles = "Local Files"

    public var id: String { rawValue }
}

public enum LibrarySortOrder: String, CaseIterable, Identifiable {
    case recents = "Recents"
    case alphabetical = "Alphabetical"
    case creator = "Creator"

    public var id: String { rawValue }
}

public struct LibraryView: View {
    @Environment(AppDependencies.self) private var deps
    @Environment(\.celestialTheme) private var theme

    @State private var items: [LibraryItem] = []
    @State private var filter: LibraryFilterKind = .all
    @State private var sortOrder: LibrarySortOrder = .recents
    @State private var isGridLayout = false
    @State private var filterQuery = ""
    @State private var isLoading = false

    @State private var showingCreatePlaylist = false
    @State private var showingBlendSheet = false
    @State private var showingMergeSheet = false
    @State private var showingLocalImporter = false

    public init() {}

    private var filteredItems: [LibraryItem] {
        var list = items
        switch filter {
        case .all: break
        case .playlists: list = list.filter { $0.kind == .playlist || $0.kind == .collection }
        case .albums: list = list.filter { $0.kind == .album }
        case .artists: list = list.filter { $0.kind == .artist }
        case .shows: list = list.filter { $0.kind == .show }
        case .downloaded, .localFiles: list = []
        }
        if !filterQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            list = list.filter {
                $0.name.localizedCaseInsensitiveContains(filterQuery) ||
                ($0.subtitle ?? "").localizedCaseInsensitiveContains(filterQuery)
            }
        }
        switch sortOrder {
        case .recents:
            return list.sorted { a, b in
                if a.pinned != b.pinned { return a.pinned && !b.pinned }
                return false
            }
        case .alphabetical:
            return list.sorted { a, b in
                if a.pinned != b.pinned { return a.pinned && !b.pinned }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
        case .creator:
            return list.sorted { a, b in
                if a.pinned != b.pinned { return a.pinned && !b.pinned }
                return (a.subtitle ?? "").localizedCaseInsensitiveCompare(b.subtitle ?? "") == .orderedAscending
            }
        }
    }

    public var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 16) {
                headerBar
                filterChipsRow
                sortAndSearchRow

                if filter == .all {
                    builtInCollectionsStrip
                        .padding(.horizontal, 16)
                }

                if filter == .downloaded {
                    DownloadedTracksInlineList()
                        .padding(.horizontal, 16)
                } else if filter == .localFiles {
                    LocalFilesInlineList(onImportTap: { showingLocalImporter = true })
                        .padding(.horizontal, 16)
                } else if isGridLayout {
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)],
                        spacing: 18
                    ) {
                        ForEach(filteredItems) { item in
                            MediaCardView(
                                title: item.name,
                                subtitle: item.subtitle ?? "",
                                imageURL: item.images.mediumURL,
                                isCircular: item.kind == .artist,
                                size: 160
                            ) {
                                navigateTo(item)
                            }
                            .contextMenu { libraryContextMenu(for: item) }
                        }
                    }
                    .padding(.horizontal, 16)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredItems) { item in
                            libraryRow(item)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                Spacer(minLength: 130)
            }
            .padding(.top, 12)
        }
        .refreshable {
            await loadLibrary()
        }
        .task {
            if items.isEmpty {
                await loadLibrary()
            }
        }
        .fileImporter(
            isPresented: $showingLocalImporter,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                Task {
                    for u in urls {
                        try? await deps.offlineStore.importLocalAudioFile(from: u)
                    }
                }
            }
        }
        .sheet(isPresented: $showingCreatePlaylist) {
            CreatePlaylistSheet { createdURI in
                Task { await loadLibrary() }
                if !createdURI.isEmpty {
                    deps.router.openSpotifyURI(createdURI)
                }
            }
        }
        .sheet(isPresented: $showingBlendSheet) {
            BlendManagerSheet()
        }
        .sheet(isPresented: $showingMergeSheet) {
            PlaylistMergeSheet(playlists: items.filter { $0.kind == .playlist }) { mergedURI in
                Task { await loadLibrary() }
                if !mergedURI.isEmpty {
                    deps.router.openSpotifyURI(mergedURI)
                }
            }
        }
    }

    private var headerBar: some View {
        HStack {
            Text("Your Library")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(theme.primaryText)

            Spacer()

            Menu {
                Button {
                    showingCreatePlaylist = true
                } label: {
                    Label("New Playlist", systemImage: "music.note.list")
                }

                Button {
                    showingMergeSheet = true
                } label: {
                    Label("Merge Playlists", systemImage: "arrow.triangle.merge")
                }

                Button {
                    showingBlendSheet = true
                } label: {
                    Label("Create or Join Blend", systemImage: "person.2.crop.square.stack")
                }

                Divider()

                Button {
                    showingLocalImporter = true
                } label: {
                    Label("Import Local Audio Files", systemImage: "folder.badge.plus")
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(theme.primaryText)
                    .frame(width: 38, height: 38)
                    .liquidGlass(shape: Circle(), interactive: true)
            }
            .accessibilityLabel("Create or Import")
        }
        .padding(.horizontal, 16)
    }

    private var filterChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LibraryFilterKind.allCases) { kind in
                    let selected = filter == kind
                    Button {
                        HapticsManager.shared.selection()
                        filter = kind
                    } label: {
                        Text(kind.rawValue)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(selected ? .white : theme.primaryText)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background {
                                if selected {
                                    Capsule().fill(theme.accent)
                                } else {
                                    Capsule().fill(Color.white.opacity(0.08))
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var sortAndSearchRow: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(LibrarySortOrder.allCases) { order in
                    Button {
                        sortOrder = order
                    } label: {
                        HStack {
                            Text(order.rawValue)
                            if sortOrder == order { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.arrow.down")
                    Text(sortOrder.rawValue)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.secondaryText)
            }

            TextField("Filter library…", text: $filterQuery)
                .font(.footnote)
                .foregroundStyle(theme.primaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.06), in: Capsule())

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isGridLayout.toggle()
                }
            } label: {
                Image(systemName: isGridLayout ? "list.bullet" : "square.grid.2x2")
                    .font(.subheadline)
                    .foregroundStyle(theme.secondaryText)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isGridLayout ? "Switch to List View" : "Switch to Grid View")
        }
        .padding(.horizontal, 16)
    }

    private var builtInCollectionsStrip: some View {
        VStack(spacing: 10) {
            Button {
                deps.router.navigate(to: .likedSongs)
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color(argb: 0xFF5E5CE6), theme.accent],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 56, height: 56)
                        Image(systemName: "heart.fill")
                            .font(.title3)
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Image(systemName: "pin.fill")
                                .font(.caption2)
                                .foregroundStyle(theme.accent)
                            Text("Liked Songs")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(theme.primaryText)
                        }
                        Text("Synced Spotify Collection")
                            .font(.caption)
                            .foregroundStyle(theme.secondaryText)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func libraryRow(_ item: LibraryItem) -> some View {
        Button {
            navigateTo(item)
        } label: {
            HStack(spacing: 14) {
                ArtworkView(
                    urlString: item.images.mediumURL,
                    size: 56,
                    cornerRadius: 11,
                    isCircular: item.kind == .artist
                )
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        if item.pinned {
                            Image(systemName: "pin.fill")
                                .font(.caption2)
                                .foregroundStyle(theme.accent)
                        }
                        Text(item.name)
                            .font(.body.weight(.medium))
                            .foregroundStyle(theme.primaryText)
                            .lineLimit(1)
                    }
                    Text((item.subtitle?.isEmpty == false ? item.subtitle! : item.kind.rawValue.capitalized))
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            libraryContextMenu(for: item)
        }
    }

    @ViewBuilder
    private func libraryContextMenu(for item: LibraryItem) -> some View {
        Button {
            Task {
                try? await deps.api.setPinned(!item.pinned, uri: item.uri)
                await loadLibrary()
            }
        } label: {
            Label(item.pinned ? "Unpin Item" : "Pin Item", systemImage: item.pinned ? "pin.slash" : "pin")
        }

        if item.kind != .collection {
            Button(role: .destructive) {
                Task {
                    try? await deps.api.setLibrarySaved(false, uris: [item.uri])
                    await loadLibrary()
                }
            } label: {
                Label("Remove from Library", systemImage: "trash")
            }
        }
    }

    private func navigateTo(_ item: LibraryItem) {
        if item.kind == .collection || item.uri.contains(":collection") {
            deps.router.navigate(to: .likedSongs)
        } else {
            deps.router.openSpotifyURI(item.uri, fallbackTitle: item.name)
        }
    }

    private func loadLibrary() async {
        isLoading = true
        if let page = try? await deps.api.libraryItems(limit: 200) {
            items = page.items.filter { !$0.uri.contains(":collection") }
        }
        isLoading = false
    }
}

public struct DownloadedTracksInlineList: View {
    @Environment(AppDependencies.self) private var deps
    @Environment(\.celestialTheme) private var theme

    public init() {}

    public var body: some View {
        let records = deps.offlineStore.sortedDownloads
        if records.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "arrow.down.circle.dotted")
                    .font(.largeTitle)
                    .foregroundStyle(theme.secondaryText)
                Text("No Encrypted Offline Tracks Yet")
                    .font(.headline)
                    .foregroundStyle(theme.primaryText)
                Text("Download podcast episodes or extension-backed tracks from any track's menu. Stored encrypted with AES-256-CTR in your iPhone Keychain.")
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .padding(28)
            .frame(maxWidth: .infinity)
        } else {
            let tracks = records.map { $0.asTrack() }
            VStack(spacing: 4) {
                ForEach(records) { rec in
                    TrackRowView(track: rec.asTrack()) {
                        deps.player.playTrack(rec.asTrack(), inContext: tracks, contextName: "Downloaded")
                    }
                }
            }
        }
    }
}

public struct LocalFilesInlineList: View {
    public let onImportTap: () -> Void
    @Environment(AppDependencies.self) private var deps
    @Environment(\.celestialTheme) private var theme

    public init(onImportTap: @escaping () -> Void) {
        self.onImportTap = onImportTap
    }

    public var body: some View {
        let tracks = deps.offlineStore.localTracks
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onImportTap) {
                Label("Import Audio from Files App", systemImage: "folder.badge.plus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(theme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)

            if tracks.isEmpty {
                Text("Import FLAC, ALAC, WAV, MP3, or M4A tracks from iCloud Drive or On My iPhone.")
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
                    .padding(.vertical, 12)
            } else {
                ForEach(tracks) { track in
                    TrackRowView(track: track) {
                        deps.player.playTrack(track, inContext: tracks, contextName: "Local Files")
                    }
                }
            }
        }
    }
}

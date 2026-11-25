//
//  RootShellView.swift
//  Celestify
//
//  Root SwiftUI navigation shell coordinating authentication states, ambient
//  Celestial backdrops, 4 independent NavigationStacks, floating Liquid Glass
//  chrome, and the Full-Screen Now Playing cover.
//  Built on Myspoti (https://github.com/kota-zo/myspoti), GPL-3.0.
//

import SwiftUI

public struct RootShellView: View {
    @Environment(AppDependencies.self) private var deps
    @Environment(\.colorScheme) private var systemColorScheme

    public init() {}

    public var body: some View {
        let resolvedTheme = deps.resolvedTheme(for: systemColorScheme)

        ZStack {
            switch deps.authManager.state {
            case .restoringSession, .bootstrappingPlayer:
                ZStack {
                    AtmosphericBackdrop(palette: .celestialDefault, isPlaying: false, intensity: 0.7)
                    VStack(spacing: 14) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 44, weight: .semibold))
                            .foregroundStyle(resolvedTheme.accent)
                        ProgressView()
                            .tint(.white)
                    }
                }

            case .unauthenticated, .signingIn, .sessionExpired:
                OnboardingLoginView()

            case .authenticated:
                authenticatedShell(theme: resolvedTheme)
            }
        }
        .environment(\.celestial, resolvedTheme)
        .preferredColorScheme(deps.preferences.appearanceMode.colorScheme)
    }

    private func authenticatedShell(theme: CelestialTokens) -> some View {
        @Bindable var router = deps.router

        return ZStack(alignment: .bottom) {
            (deps.preferences.pureBlackOLED && !theme.isLight ? Color.black : theme.background)
                .ignoresSafeArea()

            if deps.preferences.dynamicArtworkColors && deps.player.currentTrack != nil {
                AtmosphericBackdrop(
                    palette: deps.player.artworkPalette,
                    isPlaying: deps.player.isPlaying,
                    intensity: 0.35
                )
            }

            Group {
                switch router.selectedTab {
                case .home:
                    NavigationStack(path: $router.homePath) {
                        HomeView()
                            .navigationDestination(for: AppRoute.self) { routeDestination($0) }
                    }
                case .search:
                    NavigationStack(path: $router.searchPath) {
                        SearchView()
                            .navigationDestination(for: AppRoute.self) { routeDestination($0) }
                    }
                case .library:
                    NavigationStack(path: $router.libraryPath) {
                        LibraryView()
                            .navigationDestination(for: AppRoute.self) { routeDestination($0) }
                    }
                case .settings:
                    NavigationStack(path: $router.settingsPath) {
                        SettingsView()
                            .navigationDestination(for: AppRoute.self) { routeDestination($0) }
                    }
                }
            }
            .tint(theme.accent)

            FloatingBottomChrome()
        }
        .fullScreenCover(isPresented: $router.isShowingFullPlayer) {
            FullPlayerView()
                .environment(deps)
                .environment(\.celestial, theme)
        }
    }

    @ViewBuilder
    private func routeDestination(_ route: AppRoute) -> some View {
        switch route {
        case .album(let uri, let initialName):
            AlbumDetailView(uri: uri, initialName: initialName)
        case .artist(let uri, let initialName):
            ArtistDetailView(uri: uri, initialName: initialName)
        case .playlist(let uri, let initialName):
            PlaylistDetailView(uri: uri, initialName: initialName)
        case .show(let uri, let initialName):
            ShowDetailView(uri: uri, initialName: initialName)
        case .episode(let uri, let initialName):
            EpisodeDetailView(uri: uri, initialName: initialName)
        case .user(let uri, let initialName):
            UserProfileDetailView(uri: uri, initialName: initialName)
        case .likedSongs:
            LikedSongsDetailView()
        case .downloadedTracks:
            ScrollView {
                DownloadedTracksInlineList()
                    .padding(16)
            }
            .navigationTitle("Downloaded")
        case .localFiles:
            ScrollView {
                LocalFilesInlineList(onImportTap: {})
                    .padding(16)
            }
            .navigationTitle("Local Files")
        case .listeningRecap:
            ListeningRecapView()
        case .browseCategory(let id, let title):
            BrowseCategoryDetailView(categoryID: id, title: title)
        }
    }
}

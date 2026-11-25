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

        return ZStack {
            (deps.preferences.pureBlackOLED && !theme.isLight ? Color.black : theme.background)
                .ignoresSafeArea()

            if deps.preferences.dynamicArtworkColors && deps.player.currentTrack != nil {
                AtmosphericBackdrop(
                    palette: deps.player.artworkPalette,
                    isPlaying: deps.player.isPlaying,
                    intensity: 0.35
                )
            }

            tabShell(router: $router, theme: theme)
                .tint(theme.accent)
        }
        .fullScreenCover(isPresented: $router.isShowingFullPlayer) {
            FullPlayerView()
                .environment(deps)
                .environment(\.celestial, theme)
        }
    }

    @ViewBuilder
    private func tabShell(router: Bindable<AppRouter>, theme: CelestialTokens) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), let currentTrack = deps.player.currentTrack {
            appTabs(router: router)
                .tabBarMinimizeBehavior(.onScrollDown)
                .tabViewBottomAccessory {
                    MiniPlayerBar(track: currentTrack)
                }
        } else {
            tabsWithFallbackAccessory(router: router, theme: theme)
        }
        #else
        tabsWithFallbackAccessory(router: router, theme: theme)
        #endif
    }

    private func tabsWithFallbackAccessory(
        router: Bindable<AppRouter>,
        theme: CelestialTokens
    ) -> some View {
        appTabs(router: router)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let currentTrack = deps.player.currentTrack {
                    MiniPlayerBar(track: currentTrack)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .overlay(alignment: .top) {
                            Rectangle()
                                .fill(theme.separator)
                                .frame(height: 0.5)
                        }
                }
            }
    }

    @ViewBuilder
    private func appTabs(router: Bindable<AppRouter>) -> some View {
        let selection = tabSelection(for: router)
        if #available(iOS 18.0, *) {
            TabView(selection: selection) {
                Tab(AppTab.home.title, systemImage: AppTab.home.systemImage, value: AppTab.home) {
                    homeStack(path: router.homePath)
                }
                Tab(AppTab.search.title, systemImage: AppTab.search.systemImage, value: AppTab.search) {
                    searchStack(path: router.searchPath)
                }
                Tab(AppTab.library.title, systemImage: AppTab.library.systemImage, value: AppTab.library) {
                    libraryStack(path: router.libraryPath)
                }
                Tab(AppTab.settings.title, systemImage: AppTab.settings.systemImage, value: AppTab.settings) {
                    settingsStack(path: router.settingsPath)
                }
            }
        } else {
            TabView(selection: selection) {
                homeStack(path: router.homePath)
                    .tabItem { Label(AppTab.home.title, systemImage: AppTab.home.systemImage) }
                    .tag(AppTab.home)
                searchStack(path: router.searchPath)
                    .tabItem { Label(AppTab.search.title, systemImage: AppTab.search.systemImage) }
                    .tag(AppTab.search)
                libraryStack(path: router.libraryPath)
                    .tabItem { Label(AppTab.library.title, systemImage: AppTab.library.systemImage) }
                    .tag(AppTab.library)
                settingsStack(path: router.settingsPath)
                    .tabItem { Label(AppTab.settings.title, systemImage: AppTab.settings.systemImage) }
                    .tag(AppTab.settings)
            }
        }
    }

    private func tabSelection(for router: Bindable<AppRouter>) -> Binding<AppTab> {
        Binding(
            get: { router.wrappedValue.selectedTab },
            set: { selectedTab in
                HapticsManager.shared.selection()
                if router.wrappedValue.selectedTab == selectedTab {
                    router.wrappedValue.popToRoot(of: selectedTab)
                } else {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                        router.wrappedValue.selectedTab = selectedTab
                    }
                }
            }
        )
    }

    private func homeStack(path: Binding<NavigationPath>) -> some View {
        NavigationStack(path: path) {
            HomeView()
                .navigationDestination(for: AppRoute.self) { routeDestination($0) }
        }
    }

    private func searchStack(path: Binding<NavigationPath>) -> some View {
        NavigationStack(path: path) {
            SearchView()
                .navigationDestination(for: AppRoute.self) { routeDestination($0) }
        }
    }

    private func libraryStack(path: Binding<NavigationPath>) -> some View {
        NavigationStack(path: path) {
            LibraryView()
                .navigationDestination(for: AppRoute.self) { routeDestination($0) }
        }
    }

    private func settingsStack(path: Binding<NavigationPath>) -> some View {
        NavigationStack(path: path) {
            SettingsView()
                .navigationDestination(for: AppRoute.self) { routeDestination($0) }
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

//
//  AppDependencies.swift
//  Celestify
//
//  Central @Observable dependency container injected into the SwiftUI hierarchy.
//  Built on Myspoti (https://github.com/kota-zo/myspoti), GPL-3.0.
//

import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
public final class AppDependencies {
    public let preferences: PreferencesStore
    public let themeManager: ThemeManager
    public let router: AppRouter
    public let authManager: SpotifyAuthManager
    public let tokenCoordinator: SpotifyTokenCoordinator
    public let bridge: SpotifyWebPlayerBridge
    public let gql: SpotifyGraphQLClient
    public let api: SpotifyAPIClient
    public let player: PlayerController
    public let lyricsRepository: LyricsRepository
    public let offlineStore: OfflineStore
    public let listenHistory: ListenHistoryStore
    public let extensions: ExtensionManager

    // FIX: main-actor-isolated defaults (`.shared`, `AppRouter()`) are not allowed
    // as default argument values here, so they are optional and resolved inside
    // the init body, which runs on the main actor.
    public init(
        preferences: PreferencesStore? = nil,
        themeManager: ThemeManager? = nil,
        router: AppRouter? = nil,
        keychain: KeychainStore = .shared,
        http: HTTPClient = .shared
    ) {
        let preferences = preferences ?? PreferencesStore.shared
        let themeManager = themeManager ?? ThemeManager.shared
        let router = router ?? AppRouter()

        self.preferences = preferences
        self.themeManager = themeManager
        self.router = router

        let coordinator = SpotifyTokenCoordinator(http: http, keychain: keychain)
        self.tokenCoordinator = coordinator

        let webBridge = SpotifyWebPlayerBridge()
        self.bridge = webBridge

        let gqlClient = SpotifyGraphQLClient(tokens: coordinator, http: http)
        self.gql = gqlClient

        let apiClient = SpotifyAPIClient(
            tokens: coordinator,
            gql: gqlClient,
            bridge: webBridge
        )
        self.api = apiClient

        let auth = SpotifyAuthManager(keychain: keychain)
        self.authManager = auth

        let offline = OfflineStore.shared
        let history = ListenHistoryStore.shared
        let exts = ExtensionManager.shared

        self.offlineStore = offline
        self.listenHistory = history
        self.extensions = exts
        self.lyricsRepository = LyricsRepository(api: apiClient, http: http)

        self.player = PlayerController(
            api: apiClient,
            bridge: webBridge,
            offlineStore: offline,
            listenHistory: history,
            extensions: exts,
            keychain: keychain
        )

        Task {
            await coordinator.attachBridge(webBridge)
            await gqlClient.attachBridge(webBridge)
        }

        auth.onSessionActivated = { [weak self] session in
            guard let self else { return }
            self.bridge.start(localizedPlayerURL: session.localizedPlayerURL)
            Task {
                if let profile = try? await self.api.currentUserProfile() {
                    await self.authManager.updateAccountProfile(profile)
                }
            }
        }

        auth.onSessionCleared = { [weak self] in
            guard let self else { return }
            self.player.resetForLogout()
            self.bridge.stopAndReset()
            await self.tokenCoordinator.invalidateTokens()
        }
    }

    public func resolvedTheme(for colorScheme: ColorScheme = .dark) -> CelestialTokens {
        CelestialTokens.resolve(
            palette: preferences.celestialPalette,
            colorScheme: preferences.appearanceMode.colorScheme ?? colorScheme,
            dynamicColorsEnabled: preferences.dynamicArtworkColors,
            artworkPalette: player.artworkPalette,
            importedTheme: themeManager.activeTheme
        )
    }
}

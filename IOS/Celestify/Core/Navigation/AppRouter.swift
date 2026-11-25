//
//  AppRouter.swift
//  Celestify
//
//  Built on Myspoti (https://github.com/kota-zo/myspoti), GPL-3.0.
//

import Foundation
import Observation
import SwiftUI

public enum AppTab: String, Codable, Sendable, CaseIterable, Identifiable {
    case home
    case search
    case library
    case settings

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .home: return String(localized: "Home")
        case .search: return String(localized: "Search")
        case .library: return String(localized: "Library")
        case .settings: return String(localized: "Settings")
        }
    }

    public var sfSymbol: String {
        switch self {
        case .home: return "house.fill"
        case .search: return "magnifyingglass"
        case .library: return "square.stack.fill"
        case .settings: return "gearshape.fill"
        }
    }

    public var systemImage: String { sfSymbol }
}

public typealias CelestifyTab = AppTab

public enum AppRoute: Hashable, Sendable {
    case album(uri: String, initialName: String? = nil)
    case artist(uri: String, initialName: String? = nil)
    case playlist(uri: String, initialName: String? = nil)
    case show(uri: String, initialName: String? = nil)
    case episode(uri: String, initialName: String? = nil)
    case user(uri: String, initialName: String? = nil)
    case likedSongs
    case downloadedTracks
    case localFiles
    case listeningRecap
    case browseCategory(id: String, title: String)
}

public enum IncomingDeepLink: Equatable, Sendable {
    case authCallback(URL)
    case blendInvite(String)
    case playlistInvite(playlistID: String, token: String?)
    case route(AppRoute)
}

@Observable
@MainActor
public final class AppRouter {
    public var selectedTab: AppTab = .home
    public var homePath = NavigationPath()
    public var searchPath = NavigationPath()
    public var libraryPath = NavigationPath()
    public var settingsPath = NavigationPath()

    public var isShowingFullPlayer: Bool = false
    public var isCinemaPresented: Bool = false
    public var pendingBlendInvite: String?
    public var tabReselectToken: Int = 0

    public init() {}

    public func popToRoot(of tab: AppTab) {
        switch tab {
        case .home:
            if !homePath.isEmpty { homePath = NavigationPath() } else { tabReselectToken &+= 1 }
        case .search:
            if !searchPath.isEmpty { searchPath = NavigationPath() } else { tabReselectToken &+= 1 }
        case .library:
            if !libraryPath.isEmpty { libraryPath = NavigationPath() } else { tabReselectToken &+= 1 }
        case .settings:
            if !settingsPath.isEmpty { settingsPath = NavigationPath() } else { tabReselectToken &+= 1 }
        }
    }

    public func navigate(to route: AppRoute) {
        isShowingFullPlayer = false
        switch selectedTab {
        case .home: homePath.append(route)
        case .search: searchPath.append(route)
        case .library: libraryPath.append(route)
        case .settings: settingsPath.append(route)
        }
    }

    public func openSpotifyURI(_ uri: SpotifyURI, fallbackTitle: String? = nil) {
        let id = MediaKind.spotifyID(from: uri)
        switch MediaKind.from(uri: uri) {
        case .album:
            navigate(to: .album(uri: uri.hasPrefix("spotify:") ? uri : "spotify:album:\(id)", initialName: fallbackTitle))
        case .artist:
            navigate(to: .artist(uri: uri.hasPrefix("spotify:") ? uri : "spotify:artist:\(id)", initialName: fallbackTitle))
        case .playlist:
            navigate(to: .playlist(uri: uri.hasPrefix("spotify:") ? uri : "spotify:playlist:\(id)", initialName: fallbackTitle))
        case .show:
            navigate(to: .show(uri: uri.hasPrefix("spotify:") ? uri : "spotify:show:\(id)", initialName: fallbackTitle))
        case .episode:
            navigate(to: .episode(uri: uri.hasPrefix("spotify:") ? uri : "spotify:episode:\(id)", initialName: fallbackTitle))
        case .user:
            navigate(to: .user(uri: uri.hasPrefix("spotify:") ? uri : "spotify:user:\(id)", initialName: fallbackTitle))
        case .genre:
            navigate(to: .browseCategory(id: uri, title: fallbackTitle ?? id))
        case .collection:
            navigate(to: .likedSongs)
        default:
            break
        }
    }

    @discardableResult
    public func handleIncomingURL(_ url: URL) -> Bool {
        guard let parsed = Self.parseDeepLink(url) else { return false }
        switch parsed {
        case .route(let route):
            navigate(to: route)
            return true
        case .blendInvite(let raw):
            pendingBlendInvite = raw
            return true
        case .playlistInvite(let playlistID, _):
            navigate(to: .playlist(uri: "spotify:playlist:\(playlistID)", initialName: nil))
            return true
        case .authCallback:
            return false
        }
    }

    public static func parseDeepLink(_ url: URL) -> IncomingDeepLink? {
        let host = url.host?.lowercased() ?? ""
        let scheme = url.scheme?.lowercased() ?? ""

        if host == "accounts.spotify.com" || host == "wl.spotify.com" || (scheme == "celestify" && host == "auth") {
            return .authCallback(url)
        }

        if scheme == "spotify" {
            let raw = url.absoluteString
            let parts = raw.split(separator: ":").map(String.init)
            guard parts.count >= 3 else { return nil }
            let kind = parts[1]
            let id = parts[2].components(separatedBy: "?").first ?? parts[2]
            switch kind {
            case "album": return .route(.album(uri: "spotify:album:\(id)"))
            case "artist": return .route(.artist(uri: "spotify:artist:\(id)"))
            case "playlist": return .route(.playlist(uri: "spotify:playlist:\(id)"))
            case "show": return .route(.show(uri: "spotify:show:\(id)"))
            case "episode": return .route(.episode(uri: "spotify:episode:\(id)"))
            case "user": return .route(.user(uri: "spotify:user:\(id)"))
            default: return nil
            }
        }

        if host.hasSuffix("spotify.com") {
            let path = url.path
            if path.contains("/blend/taste-match/") || path.contains("/blend/invitation/") {
                return .blendInvite(url.absoluteString)
            }
            let segments = url.pathComponents.filter { $0 != "/" && !$0.hasPrefix("intl-") }
            guard segments.count >= 2 else { return nil }
            let kind = segments[0]
            let id = segments[1]
            let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let pt = queryItems.first(where: { $0.name == "pt" })?.value
            switch kind {
            case "playlist":
                if let pt, !pt.isEmpty {
                    return .playlistInvite(playlistID: id, token: pt)
                }
                return .route(.playlist(uri: "spotify:playlist:\(id)"))
            case "album": return .route(.album(uri: "spotify:album:\(id)"))
            case "artist": return .route(.artist(uri: "spotify:artist:\(id)"))
            case "show": return .route(.show(uri: "spotify:show:\(id)"))
            case "episode": return .route(.episode(uri: "spotify:episode:\(id)"))
            case "user": return .route(.user(uri: "spotify:user:\(id)"))
            default: return nil
            }
        }

        return nil
    }
}

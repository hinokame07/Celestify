//
//  DomainModels.swift
//  Celestify
//
//  Built on Myspoti (https://github.com/kota-zo/myspoti), GPL-3.0.
//  Copyright (C) 2026 Celestify Contributors. Licensed under GPL-3.0.
//

import Foundation

public typealias SpotifyURI = String

// MARK: - Media Primitives

public enum MediaKind: String, Codable, Sendable, CaseIterable, Hashable {
    case track = "TRACK"
    case album = "ALBUM"
    case artist = "ARTIST"
    case playlist = "PLAYLIST"
    case show = "SHOW"
    case episode = "EPISODE"
    case audiobook = "AUDIOBOOK"
    case chapter = "CHAPTER"
    case folder = "FOLDER"
    case user = "USER"
    case genre = "GENRE"
    case collection = "COLLECTION"
    case unknown = "UNKNOWN"

    public static func from(uri: SpotifyURI) -> MediaKind {
        let parts = uri.split(separator: ":")
        guard parts.count >= 2 else { return .unknown }
        if parts.contains("folder") { return .folder }
        switch parts[1] {
        case "track": return .track
        case "album": return .album
        case "artist": return .artist
        case "playlist": return .playlist
        case "show": return .show
        case "episode": return .episode
        case "audiobook": return .audiobook
        case "chapter": return .chapter
        case "user":
            if parts.count >= 4 && parts[2] == "collection" { return .collection }
            return .user
        case "collection": return .collection
        case "genre", "page": return .genre
        default: return .unknown
        }
    }

    public static func spotifyID(from uri: SpotifyURI) -> String {
        uri.split(separator: ":").last.map(String.init) ?? uri
    }
}

public struct MediaImage: Codable, Sendable, Hashable {
    public let url: String
    public let width: Int?
    public let height: Int?

    public init(url: String, width: Int? = nil, height: Int? = nil) {
        self.url = url
        self.width = width
        self.height = height
    }
}

public extension Array where Element == MediaImage {
    var largestURL: String? {
        self.max(by: { ($0.width ?? 0) < ($1.width ?? 0) })?.url ?? first?.url
    }

    var mediumURL: String? {
        let sorted = self.sorted { ($0.width ?? 300) < ($1.width ?? 300) }
        return sorted.first(where: { ($0.width ?? 0) >= 240 })?.url ?? largestURL
    }

    var smallURL: String? {
        self.min(by: { ($0.width ?? Int.max) < ($1.width ?? Int.max) })?.url ?? first?.url
    }
}

public struct ArtistRef: Codable, Sendable, Hashable, Identifiable {
    public var id: String { uri }
    public let uri: SpotifyURI
    public let name: String

    public init(uri: SpotifyURI, name: String) {
        self.uri = uri
        self.name = name
    }

    public var spotifyID: String { MediaKind.spotifyID(from: uri) }
}

public struct AlbumRef: Codable, Sendable, Hashable, Identifiable {
    public var id: String { uri.isEmpty ? name : uri }
    public let uri: SpotifyURI
    public let name: String
    public let images: [MediaImage]

    public init(uri: SpotifyURI, name: String, images: [MediaImage] = []) {
        self.uri = uri
        self.name = name
        self.images = images
    }

    public var spotifyID: String { MediaKind.spotifyID(from: uri) }
}

// MARK: - Pagination

public struct Page<T: Sendable & Hashable>: Sendable, Hashable {
    public let items: [T]
    public let offset: Int
    public let total: Int
    public let nextOffset: Int?

    public init(items: [T], offset: Int = 0, total: Int = 0, nextOffset: Int? = nil) {
        self.items = items
        self.offset = offset
        self.total = total
        self.nextOffset = nextOffset
    }

    public static var empty: Page<T> {
        Page(items: [], offset: 0, total: 0, nextOffset: nil)
    }
}

// MARK: - Catalog Entities

public struct Track: Codable, Sendable, Hashable, Identifiable {
    public var id: String { uid.map { "\(uri)#\($0)" } ?? uri }
    public let uri: SpotifyURI
    public let name: String
    public let durationMs: Int64
    public let artists: [ArtistRef]
    public let album: AlbumRef?
    public let explicit: Bool
    public let playable: Bool
    public let uid: String?
    public let addedAt: String?
    public let hasVideo: Bool
    public let previewURL: String?
    public let localFileURL: URL?

    public init(
        uri: SpotifyURI,
        name: String,
        durationMs: Int64,
        artists: [ArtistRef] = [],
        album: AlbumRef? = nil,
        explicit: Bool = false,
        playable: Bool = true,
        uid: String? = nil,
        addedAt: String? = nil,
        hasVideo: Bool = false,
        previewURL: String? = nil,
        localFileURL: URL? = nil
    ) {
        self.uri = uri
        self.name = name
        self.durationMs = durationMs
        self.artists = artists
        self.album = album
        self.explicit = explicit
        self.playable = playable
        self.uid = uid
        self.addedAt = addedAt
        self.hasVideo = hasVideo
        self.previewURL = previewURL
        self.localFileURL = localFileURL
    }

    public var spotifyID: String { MediaKind.spotifyID(from: uri) }
    public var artistNames: String { artists.map(\.name).joined(separator: ", ") }
    public var coverURL: String? { album?.images.largestURL }
    public var isEpisode: Bool { uri.hasPrefix("spotify:episode:") }
    public var isLocal: Bool { uri.hasPrefix("local:") || localFileURL != nil }
}

public struct SavedTrack: Codable, Sendable, Hashable, Identifiable {
    public var id: String { track.id }
    public let track: Track
    public let addedAt: String?

    public init(track: Track, addedAt: String? = nil) {
        self.track = track
        self.addedAt = addedAt
    }
}

public struct Album: Codable, Sendable, Hashable, Identifiable {
    public var id: String { uri }
    public let uri: SpotifyURI
    public let name: String
    public let artists: [ArtistRef]
    public let images: [MediaImage]
    public let type: String
    public let releaseDate: String?
    public let trackCount: Int
    public let label: String?

    public init(
        uri: SpotifyURI,
        name: String,
        artists: [ArtistRef] = [],
        images: [MediaImage] = [],
        type: String = "ALBUM",
        releaseDate: String? = nil,
        trackCount: Int = 0,
        label: String? = nil
    ) {
        self.uri = uri
        self.name = name
        self.artists = artists
        self.images = images
        self.type = type
        self.releaseDate = releaseDate
        self.trackCount = trackCount
        self.label = label
    }

    public var spotifyID: String { MediaKind.spotifyID(from: uri) }
    public var artistNames: String { artists.map(\.name).joined(separator: ", ") }
    public var releaseYear: String? { releaseDate?.prefix(4).description }
}

public struct Artist: Codable, Sendable, Hashable, Identifiable {
    public var id: String { uri }
    public let uri: SpotifyURI
    public let name: String
    public let images: [MediaImage]
    public let followers: Int64?
    public let monthlyListeners: Int64?
    public let verified: Bool

    public init(
        uri: SpotifyURI,
        name: String,
        images: [MediaImage] = [],
        followers: Int64? = nil,
        monthlyListeners: Int64? = nil,
        verified: Bool = false
    ) {
        self.uri = uri
        self.name = name
        self.images = images
        self.followers = followers
        self.monthlyListeners = monthlyListeners
        self.verified = verified
    }

    public var spotifyID: String { MediaKind.spotifyID(from: uri) }
}

public struct TopTrack: Codable, Sendable, Hashable, Identifiable {
    public var id: String { track.id }
    public let track: Track
    public let playcount: Int64?

    public init(track: Track, playcount: Int64? = nil) {
        self.track = track
        self.playcount = playcount
    }
}

public struct ArtistPage: Sendable, Hashable {
    public let artist: Artist
    public let biography: String?
    public let headerImages: [MediaImage]
    public let topTracks: [TopTrack]
    public let popularReleases: [Album]
    public let appearsOn: [Album]
    public let related: [Artist]

    public init(
        artist: Artist,
        biography: String? = nil,
        headerImages: [MediaImage] = [],
        topTracks: [TopTrack] = [],
        popularReleases: [Album] = [],
        appearsOn: [Album] = [],
        related: [Artist] = []
    ) {
        self.artist = artist
        self.biography = biography
        self.headerImages = headerImages
        self.topTracks = topTracks
        self.popularReleases = popularReleases
        self.appearsOn = appearsOn
        self.related = related
    }
}

public struct Playlist: Codable, Sendable, Hashable, Identifiable {
    public var id: String { uri }
    public let uri: SpotifyURI
    public let name: String
    public let description: String?
    public let owner: String?
    public let images: [MediaImage]
    public let trackCount: Int
    public let editable: Bool
    public let ownerURI: SpotifyURI?
    public let ownerImages: [MediaImage]
    public let followers: Int64?
    public let isBlend: Bool
    public let canLeave: Bool

    public init(
        uri: SpotifyURI,
        name: String,
        description: String? = nil,
        owner: String? = nil,
        images: [MediaImage] = [],
        trackCount: Int = 0,
        editable: Bool = false,
        ownerURI: SpotifyURI? = nil,
        ownerImages: [MediaImage] = [],
        followers: Int64? = nil,
        isBlend: Bool = false,
        canLeave: Bool = false
    ) {
        self.uri = uri
        self.name = name
        self.description = description
        self.owner = owner
        self.images = images
        self.trackCount = trackCount
        self.editable = editable
        self.ownerURI = ownerURI
        self.ownerImages = ownerImages
        self.followers = followers
        self.isBlend = isBlend
        self.canLeave = canLeave
    }

    public var spotifyID: String { MediaKind.spotifyID(from: uri) }
}

public enum PlaylistAccess: String, Codable, Sendable, CaseIterable {
    case viewer = "VIEWER"
    case blocked = "BLOCKED"
    case collaborator = "CONTRIBUTOR"

    public static func from(permission: String?) -> PlaylistAccess {
        switch permission?.uppercased() {
        case "BLOCKED": return .blocked
        case "CONTRIBUTOR": return .collaborator
        default: return .viewer
        }
    }
}

public enum PlaylistSortOrder: String, Codable, Sendable, CaseIterable {
    case custom
    case title
    case artist
    case album
    case recentlyAdded
    case duration

    public var displayTitle: String {
        switch self {
        case .custom: return "Custom Order"
        case .title: return "Title"
        case .artist: return "Artist"
        case .album: return "Album"
        case .recentlyAdded: return "Recently Added"
        case .duration: return "Duration"
        }
    }
}

public struct PlaylistMember: Codable, Sendable, Hashable, Identifiable {
    public var id: String { uri }
    public let uri: SpotifyURI
    public let username: String
    public let name: String
    public let images: [MediaImage]
    public let isOwner: Bool
    public let trackCount: Int

    public init(
        uri: SpotifyURI,
        username: String,
        name: String,
        images: [MediaImage] = [],
        isOwner: Bool = false,
        trackCount: Int = 0
    ) {
        self.uri = uri
        self.username = username
        self.name = name
        self.images = images
        self.isOwner = isOwner
        self.trackCount = trackCount
    }
}

public struct MediaCard: Codable, Sendable, Hashable, Identifiable {
    public var id: String { uri }
    public let uri: SpotifyURI
    public let kind: MediaKind
    public let title: String
    public let subtitle: String?
    public let images: [MediaImage]

    public init(
        uri: SpotifyURI,
        kind: MediaKind,
        title: String,
        subtitle: String? = nil,
        images: [MediaImage] = []
    ) {
        self.uri = uri
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.images = images
    }

    public var spotifyID: String { MediaKind.spotifyID(from: uri) }
}

// MARK: - Podcasts & Shows

public struct Show: Codable, Sendable, Hashable, Identifiable {
    public var id: String { uri }
    public let uri: SpotifyURI
    public let name: String
    public let publisher: String
    public let description: String?
    public let images: [MediaImage]
    public let saved: Bool
    public let rating: Double?
    public let topics: [String]

    public init(
        uri: SpotifyURI,
        name: String,
        publisher: String,
        description: String? = nil,
        images: [MediaImage] = [],
        saved: Bool = false,
        rating: Double? = nil,
        topics: [String] = []
    ) {
        self.uri = uri
        self.name = name
        self.publisher = publisher
        self.description = description
        self.images = images
        self.saved = saved
        self.rating = rating
        self.topics = topics
    }

    public var spotifyID: String { MediaKind.spotifyID(from: uri) }
}

public struct Episode: Codable, Sendable, Hashable, Identifiable {
    public var id: String { uri }
    public let uri: SpotifyURI
    public let name: String
    public let description: String?
    public let durationMs: Int64
    public let releaseDate: String?
    public let images: [MediaImage]
    public let show: AlbumRef?
    public let playedPositionMs: Int64
    public let played: Bool
    public let explicit: Bool
    public let playable: Bool
    public let previewURL: String?

    public init(
        uri: SpotifyURI,
        name: String,
        description: String? = nil,
        durationMs: Int64 = 0,
        releaseDate: String? = nil,
        images: [MediaImage] = [],
        show: AlbumRef? = nil,
        playedPositionMs: Int64 = 0,
        played: Bool = false,
        explicit: Bool = false,
        playable: Bool = true,
        previewURL: String? = nil
    ) {
        self.uri = uri
        self.name = name
        self.description = description
        self.durationMs = durationMs
        self.releaseDate = releaseDate
        self.images = images
        self.show = show
        self.playedPositionMs = playedPositionMs
        self.played = played
        self.explicit = explicit
        self.playable = playable
        self.previewURL = previewURL
    }

    public var spotifyID: String { MediaKind.spotifyID(from: uri) }

    public func asTrack() -> Track {
        let cover = images.isEmpty ? (show?.images ?? []) : images
        return Track(
            uri: uri,
            name: name,
            durationMs: durationMs,
            artists: show.map { [ArtistRef(uri: $0.uri, name: $0.name)] } ?? [],
            album: AlbumRef(uri: show?.uri ?? "", name: show?.name ?? "", images: cover),
            explicit: explicit,
            playable: playable,
            previewURL: previewURL
        )
    }
}

// MARK: - Home, Search & Library

public struct HomeChip: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let label: String

    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }
}

public struct HomeSection: Codable, Sendable, Hashable, Identifiable {
    public var id: String { uri.isEmpty ? title : uri }
    public let uri: SpotifyURI
    public let title: String
    public let subtitle: String?
    public let items: [MediaCard]

    public init(uri: SpotifyURI, title: String, subtitle: String? = nil, items: [MediaCard] = []) {
        self.uri = uri
        self.title = title
        self.subtitle = subtitle
        self.items = items
    }
}

public struct HomeFeed: Codable, Sendable, Hashable {
    public let greeting: String?
    public let chips: [HomeChip]
    public let sections: [HomeSection]

    public init(greeting: String? = nil, chips: [HomeChip] = [], sections: [HomeSection] = []) {
        self.greeting = greeting
        self.chips = chips
        self.sections = sections
    }
}

public struct SearchResults: Sendable, Hashable {
    public let tracks: Page<Track>
    public let artists: Page<Artist>
    public let albums: Page<Album>
    public let playlists: Page<Playlist>

    public init(
        tracks: Page<Track> = .empty,
        artists: Page<Artist> = .empty,
        albums: Page<Album> = .empty,
        playlists: Page<Playlist> = .empty
    ) {
        self.tracks = tracks
        self.artists = artists
        self.albums = albums
        self.playlists = playlists
    }
}

public enum LibraryFilter: String, Codable, Sendable, CaseIterable {
    case all = "ALL"
    case playlists = "Playlists"
    case artists = "Artists"
    case albums = "Albums"
    case podcasts = "Podcasts & Shows"
    case downloaded = "Downloaded"

    public var gqlID: String? {
        switch self {
        case .all, .downloaded: return nil
        default: return rawValue
        }
    }

    public var displayTitle: String {
        switch self {
        case .all: return "All"
        case .playlists: return "Playlists"
        case .artists: return "Artists"
        case .albums: return "Albums"
        case .podcasts: return "Podcasts"
        case .downloaded: return "Downloaded"
        }
    }
}

public enum LibrarySort: Int, Codable, Sendable, CaseIterable {
    case recents = 0
    case recentlyAdded = 1
    case alphabetical = 2
    case creator = 3
    case custom = 4

    public var displayTitle: String {
        switch self {
        case .recents: return "Recents"
        case .recentlyAdded: return "Recently Added"
        case .alphabetical: return "Alphabetical"
        case .creator: return "Creator"
        case .custom: return "Custom Order"
        }
    }
}

public struct LibraryItem: Codable, Sendable, Hashable, Identifiable {
    public var id: String { uri }
    public let uri: SpotifyURI
    public let kind: MediaKind
    public let name: String
    public let subtitle: String?
    public let images: [MediaImage]
    public var pinned: Bool
    public let addedAt: String?
    public let count: Int?

    public init(
        uri: SpotifyURI,
        kind: MediaKind,
        name: String,
        subtitle: String? = nil,
        images: [MediaImage] = [],
        pinned: Bool = false,
        addedAt: String? = nil,
        count: Int? = nil
    ) {
        self.uri = uri
        self.kind = kind
        self.name = name
        self.subtitle = subtitle
        self.images = images
        self.pinned = pinned
        self.addedAt = addedAt
        self.count = count
    }

    public var spotifyID: String { MediaKind.spotifyID(from: uri) }
}

// MARK: - Player, Queue, Connect & Jam

public enum PlaybackItemKind: String, Codable, Sendable, Hashable {
    case track = "TRACK"
    case episode = "EPISODE"
    case ad = "AD"
}

public enum RepeatMode: Int, Codable, Sendable, CaseIterable {
    case off = 0
    case context = 1
    case track = 2

    public var next: RepeatMode {
        switch self {
        case .off: return .context
        case .context: return .track
        case .track: return .off
        }
    }
}

public struct NowPlayingItem: Codable, Sendable, Hashable, Identifiable {
    public var id: String { uid.map { "\(uri)#\($0)" } ?? uri }
    public let kind: PlaybackItemKind
    public let uri: SpotifyURI
    public let uid: String?
    public let name: String
    public let artists: [ArtistRef]
    public let album: AlbumRef?
    public let imageURL: String?
    public let durationMs: Int64
    public let explicit: Bool
    public let provider: String?
    public let mediaType: String?

    public init(
        kind: PlaybackItemKind = .track,
        uri: SpotifyURI,
        uid: String? = nil,
        name: String,
        artists: [ArtistRef] = [],
        album: AlbumRef? = nil,
        imageURL: String? = nil,
        durationMs: Int64 = 0,
        explicit: Bool = false,
        provider: String? = nil,
        mediaType: String? = nil
    ) {
        self.kind = kind
        self.uri = uri
        self.uid = uid
        self.name = name
        self.artists = artists
        self.album = album
        self.imageURL = imageURL
        self.durationMs = durationMs
        self.explicit = explicit
        self.provider = provider
        self.mediaType = mediaType
    }

    public var spotifyID: String { MediaKind.spotifyID(from: uri) }
    public var artistNames: String { artists.map(\.name).joined(separator: ", ") }

    public func asTrack() -> Track {
        Track(
            uri: uri,
            name: name,
            durationMs: durationMs,
            artists: artists,
            album: album.map { AlbumRef(uri: $0.uri, name: $0.name, images: imageURL.map { [MediaImage(url: $0)] } ?? $0.images) },
            explicit: explicit,
            uid: uid
        )
    }
}

public struct PlayerRestrictions: Codable, Sendable, Hashable {
    public let canPause: Bool
    public let canResume: Bool
    public let canSeek: Bool
    public let canSkipNext: Bool
    public let canSkipPrevious: Bool

    public init(
        canPause: Bool = true,
        canResume: Bool = true,
        canSeek: Bool = true,
        canSkipNext: Bool = true,
        canSkipPrevious: Bool = true
    ) {
        self.canPause = canPause
        self.canResume = canResume
        self.canSeek = canSeek
        self.canSkipNext = canSkipNext
        self.canSkipPrevious = canSkipPrevious
    }
}

public struct PlayerStateSnapshot: Codable, Sendable, Hashable {
    public let item: NowPlayingItem?
    public let contextURI: SpotifyURI?
    public let contextName: String?
    public let previous: NowPlayingItem?
    public let next: NowPlayingItem?
    public let isPaused: Bool
    public let isBuffering: Bool
    public let positionMs: Int64
    public let timestampMs: Int64
    public let speed: Double
    public let shuffle: Bool
    public let repeatMode: RepeatMode
    public let restrictions: PlayerRestrictions

    public init(
        item: NowPlayingItem? = nil,
        contextURI: SpotifyURI? = nil,
        contextName: String? = nil,
        previous: NowPlayingItem? = nil,
        next: NowPlayingItem? = nil,
        isPaused: Bool = true,
        isBuffering: Bool = false,
        positionMs: Int64 = 0,
        timestampMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        speed: Double = 1.0,
        shuffle: Bool = false,
        repeatMode: RepeatMode = .off,
        restrictions: PlayerRestrictions = PlayerRestrictions()
    ) {
        self.item = item
        self.contextURI = contextURI
        self.contextName = contextName
        self.previous = previous
        self.next = next
        self.isPaused = isPaused
        self.isBuffering = isBuffering
        self.positionMs = positionMs
        self.timestampMs = timestampMs
        self.speed = speed
        self.shuffle = shuffle
        self.repeatMode = repeatMode
        self.restrictions = restrictions
    }
}

public struct PlaybackQueue: Codable, Sendable, Hashable {
    public let current: NowPlayingItem?
    public let queued: [NowPlayingItem]
    public let nextUp: [NowPlayingItem]

    public init(current: NowPlayingItem? = nil, queued: [NowPlayingItem] = [], nextUp: [NowPlayingItem] = []) {
        self.current = current
        self.queued = queued
        self.nextUp = nextUp
    }
}

public struct ConnectDevice: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let type: String
    public let isActive: Bool
    public let isSelf: Bool
    public let volume: Double?
    public let canSetVolume: Bool

    public init(
        id: String,
        name: String,
        type: String,
        isActive: Bool = false,
        isSelf: Bool = false,
        volume: Double? = nil,
        canSetVolume: Bool = false
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.isActive = isActive
        self.isSelf = isSelf
        self.volume = volume
        self.canSetVolume = canSetVolume
    }

    public var sfSymbol: String {
        switch type.lowercased() {
        case let s where s.contains("computer") || s.contains("laptop"): return "laptopcomputer"
        case let s where s.contains("tv") || s.contains("cast"): return "tv"
        case let s where s.contains("speaker"): return "hifispeaker.fill"
        case let s where s.contains("tablet") || s.contains("ipad"): return "ipad"
        case let s where s.contains("car") || s.contains("auto"): return "car.fill"
        default: return "iphone"
        }
    }
}

public struct JamMember: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let username: String
    public let name: String
    public let imageURL: String?
    public let isHost: Bool

    public init(id: String, username: String, name: String, imageURL: String? = nil, isHost: Bool = false) {
        self.id = id
        self.username = username
        self.name = name
        self.imageURL = imageURL
        self.isHost = isHost
    }
}

public struct JamSession: Codable, Sendable, Hashable {
    public let id: String
    public let joinCode: String?
    public let shareURI: String?
    public let isHost: Bool
    public let isListening: Bool
    public let canControlPlayback: Bool
    public let members: [JamMember]

    public init(
        id: String,
        joinCode: String? = nil,
        shareURI: String? = nil,
        isHost: Bool = false,
        isListening: Bool = true,
        canControlPlayback: Bool = true,
        members: [JamMember] = []
    ) {
        self.id = id
        self.joinCode = joinCode
        self.shareURI = shareURI
        self.isHost = isHost
        self.isListening = isListening
        self.canControlPlayback = canControlPlayback
        self.members = members
    }
}

// MARK: - Users, Social, Blends, Recents & Track Extras

public struct UserProfile: Codable, Sendable, Hashable, Identifiable {
    public var id: String { uri }
    public let uri: SpotifyURI
    public let username: String
    public let name: String
    public let images: [MediaImage]
    public let country: String?
    public let product: String?
    public let explicitFiltered: Bool
    public let followers: Int?
    public let following: Int?
    public let isFollowing: Bool
    public let playlists: [Playlist]
    public let recentArtists: [Artist]

    public init(
        uri: SpotifyURI,
        username: String,
        name: String,
        images: [MediaImage] = [],
        country: String? = nil,
        product: String? = nil,
        explicitFiltered: Bool = false,
        followers: Int? = nil,
        following: Int? = nil,
        isFollowing: Bool = false,
        playlists: [Playlist] = [],
        recentArtists: [Artist] = []
    ) {
        self.uri = uri
        self.username = username
        self.name = name
        self.images = images
        self.country = country
        self.product = product
        self.explicitFiltered = explicitFiltered
        self.followers = followers
        self.following = following
        self.isFollowing = isFollowing
        self.playlists = playlists
        self.recentArtists = recentArtists
    }

    public var isPremium: Bool {
        guard let p = product?.lowercased() else { return false }
        return p != "free" && p != "open"
    }
}

public struct FriendActivity: Codable, Sendable, Hashable, Identifiable {
    public var id: String { "\(userURI):\(timestampMs)" }
    public let timestampMs: Int64
    public let userURI: SpotifyURI
    public let userName: String
    public let userImageURL: String?
    public let trackURI: SpotifyURI
    public let trackName: String
    public let artistURI: SpotifyURI?
    public let artistName: String?
    public let albumURI: SpotifyURI?
    public let albumName: String?
    public let imageURL: String?
    public let contextURI: SpotifyURI?
    public let contextName: String?

    public init(
        timestampMs: Int64,
        userURI: SpotifyURI,
        userName: String,
        userImageURL: String? = nil,
        trackURI: SpotifyURI,
        trackName: String,
        artistURI: SpotifyURI? = nil,
        artistName: String? = nil,
        albumURI: SpotifyURI? = nil,
        albumName: String? = nil,
        imageURL: String? = nil,
        contextURI: SpotifyURI? = nil,
        contextName: String? = nil
    ) {
        self.timestampMs = timestampMs
        self.userURI = userURI
        self.userName = userName
        self.userImageURL = userImageURL
        self.trackURI = trackURI
        self.trackName = trackName
        self.artistURI = artistURI
        self.artistName = artistName
        self.albumURI = albumURI
        self.albumName = albumName
        self.imageURL = imageURL
        self.contextURI = contextURI
        self.contextName = contextName
    }
}

public struct TrackCreditRole: Codable, Sendable, Hashable, Identifiable {
    public var id: String { role }
    public let role: String
    public let names: [String]

    public init(role: String, names: [String]) {
        self.role = role
        self.names = names
    }
}

public struct TrackCredits: Codable, Sendable, Hashable {
    public let title: String
    public let roles: [TrackCreditRole]
    public let sources: [String]

    public init(title: String, roles: [TrackCreditRole] = [], sources: [String] = []) {
        self.title = title
        self.roles = roles
        self.sources = sources
    }
}

public struct TrackCanvas: Codable, Sendable, Hashable {
    public let url: String
    public let type: String

    public init(url: String, type: String) {
        self.url = url
        self.type = type
    }

    public var isVideo: Bool {
        type.uppercased().contains("VIDEO") || url.lowercased().hasSuffix(".mp4")
    }
}

public enum BlendInvitationState: String, Codable, Sendable {
    case waiting
    case joinable
    case full
    case joined
    case deleted
    case unknown
}

public struct BlendMember: Codable, Sendable, Hashable, Identifiable {
    public var id: String { username }
    public let username: String
    public let name: String
    public let imageURL: String?

    public init(username: String, name: String, imageURL: String? = nil) {
        self.username = username
        self.name = name
        self.imageURL = imageURL
    }
}

public struct BlendInvitation: Codable, Sendable, Hashable {
    public let state: BlendInvitationState
    public let title: String?
    public let subtitle: String?
    public let inviter: BlendMember?
    public let members: [BlendMember]
    public let playlistURI: SpotifyURI?

    public init(
        state: BlendInvitationState,
        title: String? = nil,
        subtitle: String? = nil,
        inviter: BlendMember? = nil,
        members: [BlendMember] = [],
        playlistURI: SpotifyURI? = nil
    ) {
        self.state = state
        self.title = title
        self.subtitle = subtitle
        self.inviter = inviter
        self.members = members
        self.playlistURI = playlistURI
    }
}

public struct BlendStory: Codable, Sendable, Hashable {
    public let title: String
    public let subtitle: String?
    public let detail: String?
    public let backgroundHex: String?
    public let titleColorHex: String?
    public let textColorHex: String?
    public let imageURL: String?

    public init(
        title: String,
        subtitle: String? = nil,
        detail: String? = nil,
        backgroundHex: String? = nil,
        titleColorHex: String? = nil,
        textColorHex: String? = nil,
        imageURL: String? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.detail = detail
        self.backgroundHex = backgroundHex
        self.titleColorHex = titleColorHex
        self.textColorHex = textColorHex
        self.imageURL = imageURL
    }
}

public struct RecentEntry: Codable, Sendable, Hashable, Identifiable {
    public var id: String { "\(uri):\(playedAtMs ?? 0):\(group ?? "")" }
    public let uri: SpotifyURI
    public let kind: MediaKind
    public let title: String
    public let subtitle: String?
    public let images: [MediaImage]
    public let durationMs: Int64
    public let explicit: Bool
    public let playedAtMs: Int64?
    public let typeLabel: String?
    public let childrenGroup: String?
    public let group: String?
    public let groupCount: Int?
    public let saved: Bool
    public let isMusic: Bool

    public init(
        uri: SpotifyURI,
        kind: MediaKind,
        title: String,
        subtitle: String? = nil,
        images: [MediaImage] = [],
        durationMs: Int64 = 0,
        explicit: Bool = false,
        playedAtMs: Int64? = nil,
        typeLabel: String? = nil,
        childrenGroup: String? = nil,
        group: String? = nil,
        groupCount: Int? = nil,
        saved: Bool = false,
        isMusic: Bool = true
    ) {
        self.uri = uri
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.images = images
        self.durationMs = durationMs
        self.explicit = explicit
        self.playedAtMs = playedAtMs
        self.typeLabel = typeLabel
        self.childrenGroup = childrenGroup
        self.group = group
        self.groupCount = groupCount
        self.saved = saved
        self.isMusic = isMusic
    }
}

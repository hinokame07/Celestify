//
//  SpotifyMappers.swift
//  Celestify
//
//  Maps Spotify Pathfinder v2 GraphQL, spclient REST, and Web Player bridge
//  JSON structures into strongly typed Swift domain models.
//  Ported from Myspoti (:api-spotify Mappers.kt, SpotifyMore.kt, SpotifyRecents.kt).
//  Built on Myspoti (https://github.com/kota-zo/myspoti), GPL-3.0.
//

import Foundation

public enum SpotifyMappers {
    public static func images(_ sources: [JSONValue]) -> [MediaImage] {
        sources.compactMap { s in
            guard let url = s.str("url"), !url.isEmpty else { return nil }
            let w = s.int("width") ?? s.int("maxWidth")
            let h = s.int("height") ?? s.int("maxHeight")
            return MediaImage(url: url, width: w, height: h)
        }
    }

    public static func artistRefs(_ node: JSONValue?) -> [ArtistRef] {
        guard let node else { return [] }
        return node.list("items").compactMap { a in
            guard let uri = a.str("uri") else { return nil }
            let name = a.str("profile.name") ?? a.str("name") ?? ""
            return ArtistRef(uri: uri, name: name)
        }
    }

    public static func track(_ d: JSONValue?, uid: String? = nil) -> Track? {
        guard let d, let uri = d.str("uri"), uri.hasPrefix("spotify:track:") else { return nil }
        let primaryArtists = artistRefs(d.at("artists"))
        let resolvedArtists = primaryArtists.isEmpty
            ? (artistRefs(d.at("firstArtist")) + artistRefs(d.at("otherArtists")))
            : primaryArtists

        let albumNode = d.at("albumOfTrack")
        let albumRef = albumNode.map { a in
            AlbumRef(
                uri: a.str("uri") ?? "",
                name: a.str("name") ?? "",
                images: images(a.list("coverArt.sources"))
            )
        }

        let duration = d.int64("duration.totalMilliseconds")
            ?? d.int64("trackDuration.totalMilliseconds")
            ?? 0

        let preview = d.str("audioPreview.url")
            ?? d.list("previews.audioPreviews.items").first?.str("url")

        return Track(
            uri: uri,
            name: d.str("name") ?? "",
            durationMs: duration,
            artists: resolvedArtists,
            album: albumRef,
            explicit: d.str("contentRating.label") == "EXPLICIT",
            playable: d.bool("playability.playable") ?? true,
            uid: uid,
            hasVideo: (d.int64("associationsV3.videoAssociations.totalCount") ?? 0) > 0,
            previewURL: preview
        )
    }

    public static func playlistItem(_ d: JSONValue?, uid: String? = nil) -> Track? {
        guard let d else { return nil }
        if d.str("uri")?.hasPrefix("spotify:episode:") == true {
            return episode(d)?.asTrack()
        }
        return track(d, uid: uid)
    }

    public static func artist(_ d: JSONValue?) -> Artist? {
        guard let d, let uri = d.str("uri") else { return nil }
        return Artist(
            uri: uri,
            name: d.str("profile.name") ?? d.str("name") ?? "",
            images: images(d.list("visuals.avatarImage.sources")),
            followers: d.int64("stats.followers"),
            monthlyListeners: d.int64("stats.monthlyListeners"),
            verified: d.bool("profile.verified")
                ?? d.bool("onPlatformReputationTrait.verification.isVerified")
                ?? false
        )
    }

    public static func album(_ d: JSONValue?) -> Album? {
        guard let d, let uri = d.str("uri") else { return nil }
        let releaseDate = d.str("date.isoString") ?? d.int64("date.year").map(String.init)
        return Album(
            uri: uri,
            name: d.str("name") ?? "",
            artists: artistRefs(d.at("artists")),
            images: images(d.list("coverArt.sources")),
            type: d.str("type") ?? "ALBUM",
            releaseDate: releaseDate,
            trackCount: d.int("tracksV2.totalCount") ?? d.int("tracks.totalCount") ?? 0,
            label: d.str("label")
        )
    }

    public static func release(_ row: JSONValue?) -> Album? {
        guard let row else { return nil }
        let inner = row.list("releases.items").first ?? row
        return album(inner)
    }

    public static func playlist(_ d: JSONValue?) -> Playlist? {
        guard let d, let uri = d.str("uri") else { return nil }
        let desc = d.str("description").flatMap { $0.isEmpty ? nil : stripHTML($0) }
        let imgSources = d.list("images.items").flatMap { images($0.list("sources")) }
        return Playlist(
            uri: uri,
            name: d.str("name") ?? "",
            description: desc,
            owner: d.str("ownerV2.data.name"),
            images: imgSources,
            trackCount: d.int("content.totalCount") ?? 0,
            editable: d.bool("currentUserCapabilities.canEditItems") ?? false,
            ownerURI: d.str("ownerV2.data.uri"),
            ownerImages: images(d.list("ownerV2.data.avatar.sources")),
            followers: d.int64("followers"),
            isBlend: d.str("format") == "blend",
            canLeave: d.bool("currentUserCapabilities.canCancelMembership") ?? false
        )
    }

    public static func episode(_ d: JSONValue?) -> Episode? {
        guard let d, let uri = d.str("uri") else { return nil }
        let showNode = d.at("podcastV2.data")
        let showRef = showNode.map {
            AlbumRef(
                uri: $0.str("uri") ?? "",
                name: $0.str("name") ?? "",
                images: images($0.list("coverArt.sources"))
            )
        }
        return Episode(
            uri: uri,
            name: d.str("name") ?? "",
            description: d.str("description"),
            durationMs: d.int64("duration.totalMilliseconds") ?? 0,
            releaseDate: d.str("releaseDate.isoString"),
            images: images(d.list("coverArt.sources")),
            show: showRef,
            playedPositionMs: d.int64("playedState.playPositionMilliseconds") ?? 0,
            played: d.str("playedState.state") == "COMPLETED",
            explicit: d.str("contentRating.label") == "EXPLICIT",
            playable: d.bool("playability.playable") ?? true,
            previewURL: d.str("previewPlayback.audioPreview.cdnUrl")
        )
    }

    public static func show(_ d: JSONValue?) -> Show? {
        guard let d, let uri = d.str("uri") else { return nil }
        return Show(
            uri: uri,
            name: d.str("name") ?? "",
            publisher: d.str("publisher.name") ?? "",
            description: d.str("description"),
            images: images(d.list("coverArt.sources")),
            saved: d.bool("saved") ?? false,
            rating: d.double("rating.averageRating.average"),
            topics: d.list("topics.items").compactMap { $0.str("title") }
        )
    }

    public static func card(_ wrapper: JSONValue?) -> MediaCard? {
        guard let wrapper else { return nil }
        let d = wrapper.at("data") ?? wrapper
        guard let uri = d.str("uri") ?? wrapper.str("_uri") ?? wrapper.str("uri") else { return nil }
        let type = d.typename()
        var kind = MediaKind.from(uri: uri)
        if type == "Audiobook" { kind = .audiobook }

        guard let title = d.str("name")
            ?? d.str("profile.name")
            ?? d.str("displayName")
            ?? d.str("title.transformedLabel")
            ?? d.str("title") else {
            return nil
        }

        let subtitle: String? = {
            switch type {
            case "Playlist":
                return d.str("ownerV2.data.name") ?? d.str("description").map(stripHTML)
            case "Album", "Track":
                let names = artistRefs(d.at("artists")).map(\.name).joined(separator: ", ")
                return names.isEmpty ? nil : names
            case "Podcast":
                return d.str("publisher.name")
            case "Audiobook":
                let authors = d.list("authorsV2").compactMap { $0.str("name") }.joined(separator: ", ")
                return authors.isEmpty ? nil : authors
            case "Episode", "Chapter":
                return d.str("podcastV2.data.name")
            case "PseudoPlaylist":
                return d.int("count").map { "\($0) songs" }
            default:
                return nil
            }
        }()

        let rawSources: [JSONValue] = {
            let candidates = [
                d.list("coverArt.sources"),
                d.list("visuals.avatarImage.sources"),
                d.list("images.items").flatMap { $0.list("sources") },
                d.list("avatar.sources"),
                d.list("image.sources"),
                d.list("albumOfTrack.coverArt.sources")
            ]
            return candidates.first(where: { !$0.isEmpty }) ?? []
        }()

        return MediaCard(
            uri: uri,
            kind: kind,
            title: title,
            subtitle: subtitle,
            images: images(rawSources)
        )
    }

    public static func page<T: Sendable & Hashable>(
        _ node: JSONValue?,
        offset: Int,
        transform: (JSONValue) -> T?
    ) -> Page<T> {
        guard let node else { return .empty }
        let rows = node.list("items")
        let items = rows.compactMap(transform)
        let total = node.int("totalCount") ?? items.count
        let next = node.int("pagingInfo.nextOffset")
            ?? (!rows.isEmpty && (offset + rows.count) < total ? offset + rows.count : nil)
        return Page(items: items, offset: offset, total: total, nextOffset: next)
    }

    // MARK: - Bridge Player & Queue Mappers

    public static func nowPlaying(_ t: JSONValue?) -> NowPlayingItem? {
        guard let t, let uri = t.str("uri") else { return nil }
        let kind: PlaybackItemKind = {
            switch t.str("kind") {
            case "ad": return .ad
            case "episode": return .episode
            default: return uri.hasPrefix("spotify:ad:") ? .ad : .track
            }
        }()
        let artists = t.list("artists").compactMap { a -> ArtistRef? in
            guard let aURI = a.str("uri") else { return nil }
            return ArtistRef(uri: aURI, name: a.str("name") ?? "")
        }
        let albumRef = t.at("album").map { a in
            AlbumRef(
                uri: a.str("uri") ?? "",
                name: a.str("name") ?? "",
                images: t.str("image").map { [MediaImage(url: $0)] } ?? []
            )
        }
        return NowPlayingItem(
            kind: kind,
            uri: uri,
            uid: t.str("uid"),
            name: t.str("name") ?? "",
            artists: artists,
            album: albumRef,
            imageURL: t.str("image"),
            durationMs: t.int64("durationMs") ?? 0,
            explicit: t.bool("explicit") ?? false,
            provider: t.str("provider"),
            mediaType: t.str("mediaType")
        )
    }

    public static func playerState(_ s: JSONValue?) -> PlayerStateSnapshot? {
        guard let s else { return nil }
        if s.at("restrictions") == nil && s.at("isPaused") == nil { return nil }
        let r = s.at("restrictions")
        let rep: RepeatMode = {
            switch s.int("repeat") {
            case 1: return .context
            case 2: return .track
            default: return .off
            }
        }()
        return PlayerStateSnapshot(
            item: nowPlaying(s.at("track")),
            contextURI: s.str("contextUri"),
            contextName: s.str("contextName"),
            previous: nowPlaying(s.at("previous")),
            next: nowPlaying(s.at("next")),
            isPaused: s.bool("isPaused") ?? true,
            isBuffering: s.bool("isBuffering") ?? false,
            positionMs: s.int64("positionMs") ?? 0,
            timestampMs: s.int64("timestamp") ?? Int64(Date().timeIntervalSince1970 * 1000),
            speed: s.double("speed") ?? 1.0,
            shuffle: s.bool("shuffle") ?? false,
            repeatMode: rep,
            restrictions: PlayerRestrictions(
                canPause: r?.bool("canPause") ?? true,
                canResume: r?.bool("canResume") ?? true,
                canSeek: r?.bool("canSeek") ?? true,
                canSkipNext: r?.bool("canSkipNext") ?? true,
                canSkipPrevious: r?.bool("canSkipPrevious") ?? true
            )
        )
    }

    public static func queue(_ q: JSONValue?) -> PlaybackQueue {
        guard let q else { return PlaybackQueue() }
        return PlaybackQueue(
            current: nowPlaying(q.at("current")),
            queued: q.list("queued").compactMap(nowPlaying),
            nextUp: q.list("nextUp").compactMap(nowPlaying)
        )
    }

    public static func stripHTML(_ raw: String) -> String {
        raw.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

//
//  SpotifyAPIClient.swift
//  Celestify
//
//  Complete Spotify domain client implementing Search, Catalog, Library, Playlists,
//  Home, Browse/Categories, Podcasts (with Soundfinder passthrough), Users & Friend Activity,
//  TrackExtras (Color-Lyrics v2, Canvas, Credits, Seed Radio), Blends, Recents, Connect Devices & Jam.
//  Ported from Myspoti (:api-spotify SpotifyContent.kt, SpotifyLibrary.kt, SpotifyMore.kt, SpotifyBlends.kt, SpotifyRecents.kt).
//  Built on Myspoti (https://github.com/kota-zo/myspoti), GPL-3.0.
//

import Foundation

public final class SpotifyAPIClient: Sendable {
    public let tokens: SpotifyTokenCoordinator
    public let gql: SpotifyGraphQLClient
    public let bridge: SpotifyWebPlayerBridge

    public init(
        tokens: SpotifyTokenCoordinator,
        gql: SpotifyGraphQLClient,
        bridge: SpotifyWebPlayerBridge
    ) {
        self.tokens = tokens
        self.gql = gql
        self.bridge = bridge
    }

    // MARK: - Home & Browse

    public func homeFeed(facet: String? = nil) async throws -> HomeFeed {
        let tz = TimeZone.current.identifier
        var vars: [String: JSONValue] = [
            "timeZone": .string(tz),
            "sp_t": .string(""),
            "facet": facet.flatMap { $0.isEmpty ? nil : .string($0) } ?? .null,
            "sectionItemsLimit": .int(20),
            "homeEndUserIntegration": .string("INTEGRATION_WEB_PLAYER"),
            "includeEpisodeContentRatingsV2": .bool(true),
            "includeHomeChapterVideoCards": .bool(false)
        ]
        let root = try await gql.query("home", variables: vars)
        DiagnosticLogbook.shared.log("home", "Received Home GraphQL response")
        let home = try root.entity("data.home", operation: "home")
        let greeting = home.str("greeting.transformedLabel") ?? home.str("greeting.text")
        let chips = home.list("homeChips").compactMap { chip -> HomeChip? in
            guard let id = chip.str("id"),
                  let label = chip.str("label.transformedLabel") ?? chip.str("label.originalLabel") else { return nil }
            return HomeChip(id: id, label: label)
        }
        let sourceSections = home.list("sectionContainer.sections.items")
        var rejectedCardCount = 0
        var emptySectionCount = 0
        let sections = sourceSections.compactMap { sec -> HomeSection? in
            let typeName = sec.at("data")?.typename() ?? ""
            if typeName.contains("Wrapped") || typeName.contains("Promo") || typeName.contains("Banner") {
                return nil
            }
            let sourceCards = sec.list("sectionItems.items")
            let cards = sourceCards.compactMap { item -> MediaCard? in
                SpotifyMappers.card(item.at("content"))
            }
            rejectedCardCount += sourceCards.count - cards.count
            guard !cards.isEmpty else {
                emptySectionCount += 1
                return nil
            }
            let uri = sec.str("uri") ?? UUID().uuidString
            let title = sec.str("data.title.transformedLabel") ?? sec.str("data.title.text") ?? ""
            let subtitle = sec.str("data.subtitle.transformedLabel")
            return HomeSection(uri: uri, title: title, subtitle: subtitle, items: cards)
        }
        DiagnosticLogbook.shared.log(
            "home",
            "Home mapping: \(sourceSections.count) source sections, \(sections.count) displayable, \(rejectedCardCount) rejected cards, \(emptySectionCount) empty sections"
        )
        return HomeFeed(greeting: greeting, chips: chips, sections: sections)
    }

    public func browseCategories(offset: Int = 0, limit: Int = 40) async throws -> [MediaCard] {
        let res = try await gql.query("browseAll", variables: ["offset": .int(Int64(offset)), "limit": .int(Int64(limit))])
        let items = res.list("data.browseStart.sections.items")
            .flatMap { $0.list("sectionItems.items") }
        return items.compactMap { row -> MediaCard? in
            let content = row.at("content.data") ?? row.at("content")
            guard let uri = row.str("uri") ?? content?.str("uri"),
                  let title = content?.str("data.cardRepresentation.title.transformedLabel")
                    ?? content?.str("title.transformedLabel")
                    ?? content?.str("name") else { return nil }
            let imgs = SpotifyMappers.images(
                content?.list("data.cardRepresentation.artwork.sources")
                    ?? content?.list("artwork.sources")
                    ?? []
            )
            return MediaCard(uri: uri, kind: .genre, title: title, images: imgs)
        }
    }

    public func categorySections(uri: SpotifyURI) async throws -> [HomeSection] {
        let pageID = MediaKind.spotifyID(from: uri)
        let res = try await gql.query("browsePage", variables: [
            "uri": .string(uri.hasPrefix("spotify:") ? uri : "spotify:page:\(pageID)"),
            "offset": .int(0),
            "limit": .int(20)
        ])
        return res.list("data.browse.sections.items").compactMap { sec -> HomeSection? in
            let cards = sec.list("sectionItems.items").compactMap { SpotifyMappers.card($0.at("content")) }
            guard !cards.isEmpty else { return nil }
            let title = sec.str("data.title.transformedLabel") ?? ""
            return HomeSection(uri: sec.str("uri") ?? title, title: title, items: cards)
        }
    }

    // MARK: - Search

    private func searchVars(query: String, offset: Int, limit: Int) -> [String: JSONValue] {
        [
            "searchTerm": .string(query),
            "offset": .int(Int64(offset)),
            "limit": .int(Int64(limit)),
            "numberOfTopResults": .int(Int64(limit)),
            "includeAudiobooks": .bool(true),
            "includeAuthors": .bool(true),
            "includePreReleases": .bool(false),
            "includeAlbumPreReleases": .bool(false),
            "includeEpisodeContentRatingsV2": .bool(true)
        ]
    }

    public func searchAll(query: String, limit: Int = 15) async throws -> SearchResults {
        async let t = searchTracks(query: query, offset: 0, limit: limit)
        async let ar = searchArtists(query: query, offset: 0, limit: limit)
        async let al = searchAlbums(query: query, offset: 0, limit: limit)
        async let pl = searchPlaylists(query: query, offset: 0, limit: limit)
        return try await SearchResults(tracks: t, artists: ar, albums: al, playlists: pl)
    }

    public func searchTracks(query: String, offset: Int = 0, limit: Int = 25) async throws -> Page<Track> {
        let r = try await gql.query("searchTracks", variables: searchVars(query: query, offset: offset, limit: limit))
        return SpotifyMappers.page(r.at("data.searchV2.tracksV2"), offset: offset) {
            SpotifyMappers.track($0.at("item.data"))
        }
    }

    public func searchArtists(query: String, offset: Int = 0, limit: Int = 25) async throws -> Page<Artist> {
        let r = try await gql.query("searchArtists", variables: searchVars(query: query, offset: offset, limit: limit))
        return SpotifyMappers.page(r.at("data.searchV2.artists"), offset: offset) {
            SpotifyMappers.artist($0.at("data"))
        }
    }

    public func searchAlbums(query: String, offset: Int = 0, limit: Int = 25) async throws -> Page<Album> {
        let r = try await gql.query("searchAlbums", variables: searchVars(query: query, offset: offset, limit: limit))
        return SpotifyMappers.page(r.at("data.searchV2.albumsV2"), offset: offset) {
            SpotifyMappers.album($0.at("data"))
        }
    }

    public func searchPlaylists(query: String, offset: Int = 0, limit: Int = 25) async throws -> Page<Playlist> {
        let r = try await gql.query("searchPlaylists", variables: searchVars(query: query, offset: offset, limit: limit))
        return SpotifyMappers.page(r.at("data.searchV2.playlists"), offset: offset) {
            SpotifyMappers.playlist($0.at("data"))
        }
    }

    public func searchShows(query: String, offset: Int = 0, limit: Int = 25) async throws -> Page<MediaCard> {
        let r = try await gql.query("searchPodcasts", variables: searchVars(query: query, offset: offset, limit: limit))
        return SpotifyMappers.page(r.at("data.searchV2.podcasts"), offset: offset, transform: SpotifyMappers.card)
    }

    public func searchUsers(query: String, offset: Int = 0, limit: Int = 25) async throws -> Page<MediaCard> {
        let r = try await gql.query("searchUsers", variables: searchVars(query: query, offset: offset, limit: limit))
        return SpotifyMappers.page(r.at("data.searchV2.users"), offset: offset, transform: SpotifyMappers.card)
    }

    public func searchSuggestions(query: String, limit: Int = 8) async throws -> [String] {
        let r = try await gql.query("searchSuggestions", variables: [
            "query": .string(query),
            "limit": .int(Int64(limit)),
            "numberOfTopResults": .int(Int64(limit)),
            "offset": .int(0),
            "includeAuthors": .bool(true),
            "includeAlbumPreReleases": .bool(false),
            "includeEpisodeContentRatingsV2": .bool(true)
        ])
        return r.list("data.searchV2.topResultsV2.itemsV2").compactMap { hit in
            let item = hit.at("item")
            guard item?.typename() == "SearchAutoCompleteEntity" else { return nil }
            return item?.str("text") ?? item?.str("data.text")
        }
    }

    // MARK: - Catalog (Track, ISRC, Album, Artist)

    public func trackISRC(trackURI: SpotifyURI) async -> String? {
        let id = MediaKind.spotifyID(from: trackURI)
        guard let hex = SpotifyBase62.toHex32(id),
              let url = URL(string: "https://spclient.wg.spotify.com/metadata/4/track/\(hex)?market=from_token"),
              let meta = try? await tokens.getAuthenticatedJSON(url: url) else {
            return nil
        }
        return meta.list("external_id").first(where: { $0.str("type") == "isrc" })?.str("id")
    }

    public func track(uri: SpotifyURI) async throws -> Track {
        let normURI = uri.hasPrefix("spotify:track:") ? uri : "spotify:track:\(uri)"
        let r = try await gql.query("getTrack", variables: [
            "uri": .string(normURI),
            "includeVideoAssociationItems": .bool(false)
        ])
        let node = try r.entity("data.trackUnion", operation: "getTrack")
        guard let mapped = SpotifyMappers.track(node) else {
            throw GraphQLError.entityNotFound(operation: "getTrack", path: normURI)
        }
        return mapped
    }

    public func albumWithTracks(idOrURI: String, offset: Int = 0, limit: Int = 100) async throws -> (Album, Page<Track>) {
        let uri = idOrURI.hasPrefix("spotify:album:") ? idOrURI : "spotify:album:\(idOrURI)"
        let r = try await gql.query("getAlbum", variables: [
            "uri": .string(uri),
            "locale": .string(""),
            "offset": .int(Int64(offset)),
            "limit": .int(Int64(limit))
        ])
        let node = try r.entity("data.albumUnion", operation: "getAlbum")
        guard let alb = SpotifyMappers.album(node) else {
            throw GraphQLError.entityNotFound(operation: "getAlbum", path: uri)
        }
        let tracksPage = SpotifyMappers.page(node.at("tracksV2"), offset: offset) { row -> Track? in
            guard let t = SpotifyMappers.track(row.at("track"), uid: row.str("uid")) else { return nil }
            if t.album != nil { return t }
            return Track(
                uri: t.uri,
                name: t.name,
                durationMs: t.durationMs,
                artists: t.artists.isEmpty ? alb.artists : t.artists,
                album: AlbumRef(uri: alb.uri, name: alb.name, images: alb.images),
                explicit: t.explicit,
                playable: t.playable,
                uid: t.uid,
                hasVideo: t.hasVideo,
                previewURL: t.previewURL
            )
        }
        return (alb, tracksPage)
    }

    public func artistPage(idOrURI: String) async throws -> ArtistPage {
        let uri = idOrURI.hasPrefix("spotify:artist:") ? idOrURI : "spotify:artist:\(idOrURI)"
        let r = try await gql.query("queryArtistOverview", variables: [
            "uri": .string(uri),
            "locale": .string(""),
            "preReleaseV2": .bool(false)
        ])
        let node = try r.entity("data.artistUnion", operation: "queryArtistOverview")
        guard let base = SpotifyMappers.artist(node) else {
            throw GraphQLError.entityNotFound(operation: "queryArtistOverview", path: uri)
        }
        let topTracks = node.list("discography.topTracks.items").compactMap { row -> TopTrack? in
            guard let t = SpotifyMappers.track(row.at("track"), uid: row.str("uid")) else { return nil }
            return TopTrack(track: t, playcount: row.int64("track.playcount"))
        }
        return ArtistPage(
            artist: base,
            biography: node.str("profile.biography.text").map(SpotifyMappers.stripHTML),
            headerImages: SpotifyMappers.images(node.list("headerImage.data.sources")),
            topTracks: topTracks,
            popularReleases: node.list("discography.popularReleasesAlbums.items").compactMap(SpotifyMappers.album),
            appearsOn: node.list("relatedContent.appearsOn.items").compactMap(SpotifyMappers.release),
            related: node.list("relatedContent.relatedArtists.items").compactMap(SpotifyMappers.artist)
        )
    }

    public func artistDiscography(uri: SpotifyURI, offset: Int = 0, limit: Int = 50) async throws -> Page<Album> {
        let r = try await gql.query("queryArtistDiscographyAll", variables: [
            "uri": .string(uri),
            "offset": .int(Int64(offset)),
            "limit": .int(Int64(limit)),
            "order": .string("DATE_DESC")
        ])
        let node = try r.entity("data.artistUnion", operation: "queryArtistDiscographyAll")
        return SpotifyMappers.page(node.at("discography.all"), offset: offset, transform: SpotifyMappers.release)
    }

    public func similarAlbums(trackURI: SpotifyURI, limit: Int = 10) async throws -> [Album] {
        let r = try await gql.query("similarAlbumsBasedOnThisTrack", variables: [
            "uri": .string(trackURI),
            "limit": .int(Int64(limit)),
            "albumsOnly": .bool(true)
        ])
        return r.list("data.seoRecommendedTrackAlbum.items").compactMap { SpotifyMappers.album($0.at("data")) }
    }

    // MARK: - Library & Liked Songs

    public func libraryItems(
        filter: LibraryFilter = .all,
        sort: LibrarySort = .recents,
        folderURI: SpotifyURI? = nil,
        offset: Int = 0,
        limit: Int = 100
    ) async throws -> Page<LibraryItem> {
        let filtersArray: [JSONValue] = filter.gqlID.map { [.string($0)] } ?? []
        let r = try await gql.query("libraryV3", variables: [
            "filters": .array(filtersArray),
            "order": .int(Int64(sort.rawValue)),
            "textFilter": .string(""),
            "features": .array([
                .string("LIKED_SONGS"),
                .string("YOUR_EPISODES_V2"),
                .string("PRERELEASES"),
                .string("PRERELEASES_V2")
            ]),
            "limit": .int(Int64(limit)),
            "offset": .int(Int64(offset)),
            "flatten": .bool(false),
            "expandedFolders": .array([]),
            "folderUri": folderURI.map(JSONValue.string) ?? .null,
            "includeFoldersWhenFlattening": .bool(true)
        ])
        let lib = try r.entity("data.me.libraryV3", operation: "libraryV3")
        let rows = lib.list("items")
        let items = rows.compactMap { row -> LibraryItem? in
            guard let c = SpotifyMappers.card(row.at("item")) else { return nil }
            let d = row.at("item.data")
            let kind: MediaKind = d?.typename() == "Folder" ? .folder : c.kind
            let count = (d?.int("playlistCount").map { $0 + (d?.int("folderCount") ?? 0) }) ?? d?.int("count")
            return LibraryItem(
                uri: c.uri,
                kind: kind,
                name: c.title,
                subtitle: c.subtitle,
                images: c.images,
                pinned: row.bool("pinned") ?? false,
                addedAt: row.str("addedAt.isoString"),
                count: count
            )
        }
        let total = lib.int("totalCount") ?? items.count
        let next = (!rows.isEmpty && offset + rows.count < total) ? offset + rows.count : nil
        return Page(items: items, offset: offset, total: total, nextOffset: next)
    }

    public func likedTracks(offset: Int = 0, limit: Int = 50) async throws -> Page<SavedTrack> {
        let r = try await gql.query("fetchLibraryTracks", variables: [
            "offset": .int(Int64(offset)),
            "limit": .int(Int64(limit))
        ])
        let node = r.at("data.me.library.tracks")
        let rows = node?.list("items") ?? []
        let items = rows.compactMap { row -> SavedTrack? in
            var data = row.at("track.data")
            if data?.str("uri") == nil, let fallbackURI = row.str("track._uri"), var dict = data?.obj() {
                dict["uri"] = .string(fallbackURI)
                data = .object(dict)
            }
            guard let t = SpotifyMappers.track(data) else { return nil }
            return SavedTrack(track: t, addedAt: row.str("addedAt.isoString"))
        }
        let total = node?.int("totalCount") ?? items.count
        let next = (!rows.isEmpty && offset + rows.count < total) ? offset + rows.count : nil
        return Page(items: items, offset: offset, total: total, nextOffset: next)
    }

    public func areInLibrary(uris: [SpotifyURI]) async throws -> [Bool] {
        guard !uris.isEmpty else { return [] }
        let r = try await gql.query("areEntitiesInLibrary", variables: [
            "uris": .array(uris.map(JSONValue.string))
        ])
        let flags = r.list("data.lookup").map { $0.bool("data.saved") ?? false }
        if flags.count == uris.count { return flags }
        // Bridge fallback
        if let arr = try? await bridge.call("library.contains", args: .object(["uris": .array(uris.map(JSONValue.string))])) {
            return arr.list().map { $0.bool() ?? false }
        }
        return Array(repeating: false, count: uris.count)
    }

    public func setLibrarySaved(_ saved: Bool, uris: [SpotifyURI]) async throws {
        guard !uris.isEmpty else { return }
        let op = saved ? "addToLibrary" : "removeFromLibrary"
        _ = try await gql.query(op, variables: [
            "uris": .array(uris.map(JSONValue.string))
        ])
    }

    public func setPinned(_ pinned: Bool, uri: SpotifyURI) async throws {
        let op = pinned ? "pinLibraryItem" : "unpinLibraryItem"
        _ = try await gql.query(op, variables: ["pinnableItemUri": .string(uri)])
    }

    public func createFolder(name: String) async throws -> SpotifyURI {
        let res = try await bridge.service("RootlistAPI", method: "createFolder", args: [
            .string(name),
            .object(["before": .string("start")])
        ])
        return res.str("uri") ?? ""
    }

    // MARK: - Playlists

    public func playlistWithTracks(idOrURI: String, offset: Int = 0, limit: Int = 100) async throws -> (Playlist, Page<Track>) {
        let uri = idOrURI.hasPrefix("spotify:playlist:") ? idOrURI : "spotify:playlist:\(idOrURI)"
        let headerRes = try await gql.query("fetchPlaylist", variables: [
            "uri": .string(uri),
            "offset": .int(Int64(offset)),
            "limit": .int(Int64(limit)),
            "enableWatchFeedEntrypoint": .bool(false),
            "includeEpisodeContentRatingsV2": .bool(true)
        ])
        let node = try headerRes.entity("data.playlistV2", operation: "fetchPlaylist")
        guard let pl = SpotifyMappers.playlist(node) else {
            throw GraphQLError.entityNotFound(operation: "fetchPlaylist", path: uri)
        }
        let content = node.at("content")
        let items = content?.list("items").compactMap { row -> Track? in
            guard let t = SpotifyMappers.playlistItem(row.at("itemV2.data"), uid: row.str("uid")) else { return nil }
            return Track(
                uri: t.uri,
                name: t.name,
                durationMs: t.durationMs,
                artists: t.artists,
                album: t.album,
                explicit: t.explicit,
                playable: t.playable,
                uid: t.uid,
                addedAt: row.str("addedAt.isoString"),
                hasVideo: t.hasVideo,
                previewURL: t.previewURL
            )
        } ?? []
        let total = content?.int("totalCount") ?? items.count
        let next = (offset + limit < total) ? offset + limit : nil
        return (pl, Page(items: items, offset: offset, total: total, nextOffset: next))
    }

    public func createPlaylist(name: String) async throws -> SpotifyURI {
        let res = try await bridge.service("RootlistAPI", method: "createPlaylist", args: [
            .string(name),
            .object(["before": .string("start")])
        ])
        if case .string(let uri) = res { return uri }
        return res.str("uri") ?? ""
    }

    public func addTracksToPlaylist(playlistURI: SpotifyURI, trackURIs: [SpotifyURI]) async throws {
        _ = try await gql.query("addToPlaylist", variables: [
            "playlistUri": .string(playlistURI),
            "uris": .array(trackURIs.map(JSONValue.string)),
            "newPosition": .object(["moveType": .string("BOTTOM_OF_PLAYLIST"), "fromUid": .null])
        ])
    }

    public func removePlaylistItems(playlistURI: SpotifyURI, uids: [String]) async throws {
        _ = try await gql.query("removeFromPlaylist", variables: [
            "playlistUri": .string(playlistURI),
            "uids": .array(uids.map(JSONValue.string))
        ])
    }

    public func renamePlaylist(playlistURI: SpotifyURI, name: String, description: String? = nil) async throws {
        var attrs: [String: JSONValue] = ["name": .string(name)]
        if let description { attrs["description"] = .string(description) }
        _ = try await bridge.service("PlaylistAPI", method: "updateDetails", args: [
            .string(playlistURI),
            .object(attrs)
        ])
    }

    public func claimCollaboratorInvite(token: String) async throws -> SpotifyURI? {
        let url = URL(string: "https://spclient.wg.spotify.com/playlist-permission/v1/token/\(token)/claim")!
        let res = try await tokens.sendAuthenticated(method: "POST", url: url)
        return JSONValue.parse(res.data)?.str("uri")
    }

    // MARK: - Podcasts & Soundfinder Passthrough Audio

    public func showWithEpisodes(idOrURI: String, offset: Int = 0, limit: Int = 50) async throws -> (Show, Page<Episode>) {
        let uri = idOrURI.hasPrefix("spotify:show:") ? idOrURI : "spotify:show:\(idOrURI)"
        let r = try await gql.query("queryPodcastEpisodes", variables: [
            "uri": .string(uri),
            "offset": .int(Int64(offset)),
            "limit": .int(Int64(limit))
        ])
        let node = try r.entity("data.podcastUnionV2", operation: "queryPodcastEpisodes")
        guard let sh = SpotifyMappers.show(node) else {
            throw GraphQLError.entityNotFound(operation: "queryPodcastEpisodes", path: uri)
        }
        let epPage = SpotifyMappers.page(node.at("episodesV2"), offset: offset) {
            SpotifyMappers.episode($0.at("entity.data"))
        }
        return (sh, epPage)
    }

    public func episodeDetail(idOrURI: String) async throws -> Episode {
        let uri = idOrURI.hasPrefix("spotify:episode:") ? idOrURI : "spotify:episode:\(idOrURI)"
        let r = try await gql.query("getEpisodeOrChapter", variables: ["uri": .string(uri)])
        let node = try r.entity("data.episodeUnionV2", operation: "getEpisodeOrChapter")
        guard let ep = SpotifyMappers.episode(node) else {
            throw GraphQLError.entityNotFound(operation: "getEpisodeOrChapter", path: uri)
        }
        return ep
    }

    /// Resolves unencrypted podcast episode CDN stream URL via Spotify Soundfinder (`SpotifyPodcasts.episodeFile`).
    public func episodeDirectStreamURL(episodeURI: SpotifyURI) async -> URL? {
        let id = MediaKind.spotifyID(from: episodeURI)
        guard let url = URL(string: "https://spclient.wg.spotify.com/soundfinder/v1/unauth/episode/\(id)/com.widevine.alpha?market=from_token"),
              let json = try? await tokens.getAuthenticatedJSON(url: url) else {
            return nil
        }
        if json.str("passthrough") != "NONE",
           let passthrough = json.str("passthroughUrl") ?? json.list("url").first?.str(),
           let streamURL = URL(string: passthrough) {
            return streamURL
        }
        return nil
    }

    public func savedEpisodes(offset: Int = 0, limit: Int = 50) async throws -> Page<Episode> {
        let r = try await gql.query("fetchPlaylistContents", variables: [
            "uri": .string("spotify:user:_:collection:your-episodes"),
            "offset": .int(Int64(offset)),
            "limit": .int(Int64(limit)),
            "includeEpisodeContentRatingsV2": .bool(true)
        ])
        let content = r.at("data.playlistV2.content")
        return SpotifyMappers.page(content, offset: offset) {
            SpotifyMappers.episode($0.at("itemV2.data"))
        }
    }

    // MARK: - Users, Current Profile & Friend Activity

    public func currentUserProfile() async throws -> UserProfile {
        async let profTask = gql.query("profileAttributes")
        async let acctTask = gql.query("accountAttributes")
        let prof = (try? await profTask)?.at("data.me.profile")
        let acct = (try? await acctTask)?.at("data.me.account")
        let uri = prof?.str("uri") ?? "spotify:user:me"
        let username = prof?.str("username") ?? MediaKind.spotifyID(from: uri)
        return UserProfile(
            uri: uri,
            username: username,
            name: prof?.str("name") ?? username,
            images: SpotifyMappers.images(prof?.list("avatar.sources") ?? []),
            country: acct?.str("country"),
            product: acct?.str("product"),
            explicitFiltered: acct?.bool("DisabledExplicitContent") ?? false
        )
    }

    public func userProfile(userID: String) async throws -> UserProfile {
        let encoded = userID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? userID
        let url = URL(string: "https://spclient.wg.spotify.com/user-profile-view/v3/profile/\(encoded)?playlist_limit=20&artist_limit=15&episode_limit=0&market=from_token")!
        let json = try await tokens.getAuthenticatedJSON(url: url)
        let uri = json.str("uri") ?? "spotify:user:\(userID)"
        let playlists = json.list("public_playlists").compactMap { p -> Playlist? in
            guard let pURI = p.str("uri") else { return nil }
            let img = p.str("image_url").map { [MediaImage(url: $0)] } ?? []
            return Playlist(
                uri: pURI,
                name: p.str("name") ?? "",
                owner: p.str("owner_name"),
                images: img,
                followers: p.int64("followers_count")
            )
        }
        let artists = json.list("recently_played_artists").compactMap { a -> Artist? in
            guard let aURI = a.str("uri") else { return nil }
            let img = a.str("image_url").map { [MediaImage(url: $0)] } ?? []
            return Artist(uri: aURI, name: a.str("name") ?? "", images: img, followers: a.int64("followers_count"))
        }
        return UserProfile(
            uri: uri,
            username: userID,
            name: json.str("name") ?? userID,
            images: json.str("image_url").map { [MediaImage(url: $0)] } ?? [],
            followers: json.int("followers_count"),
            following: json.int("following_count"),
            isFollowing: json.bool("is_following") ?? false,
            playlists: playlists,
            recentArtists: artists
        )
    }

    public func friendActivity() async throws -> [FriendActivity] {
        let hosts = [
            "https://guc-spclient.spotify.com/presence-view/v1/buddylist",
            "https://spclient.wg.spotify.com/presence-view/v1/buddylist"
        ]
        for raw in hosts {
            guard let url = URL(string: raw),
                  let json = try? await tokens.getAuthenticatedJSON(url: url) else { continue }
            let friends = json.list("friends")
            return friends.compactMap { f -> FriendActivity? in
                guard let userURI = f.str("user.uri"),
                      let trackURI = f.str("track.uri"),
                      let trackName = f.str("track.name") else { return nil }
                return FriendActivity(
                    timestampMs: f.int64("timestamp") ?? 0,
                    userURI: userURI,
                    userName: f.str("user.name") ?? MediaKind.spotifyID(from: userURI),
                    userImageURL: f.str("user.imageUrl"),
                    trackURI: trackURI,
                    trackName: trackName,
                    artistURI: f.str("track.artist.uri"),
                    artistName: f.str("track.artist.name"),
                    albumURI: f.str("track.album.uri"),
                    albumName: f.str("track.album.name"),
                    imageURL: f.str("track.imageUrl"),
                    contextURI: f.str("track.context.uri"),
                    contextName: f.str("track.context.name")
                )
            }
        }
        return []
    }

    // MARK: - Track Extras (Color-Lyrics v2, Canvas, Credits, Seed Radio)

    public func spotifyColorLyrics(trackID: String) async throws -> Lyrics? {
        guard let url = URL(string: "https://spclient.wg.spotify.com/color-lyrics/v2/track/\(trackID)?format=json&vocalRemoval=false&market=from_token") else {
            return nil
        }
        let res = try await tokens.sendAuthenticated(method: "GET", url: url)
        if res.statusCode == 404 { return nil }
        guard (200...299).contains(res.statusCode), let root = JSONValue.parse(res.data) else {
            return nil
        }
        guard let lyr = root.at("lyrics") else { return nil }
        if lyr.bool("isDenseTypeface") != nil && lyr.str("capStatus") == "CAPPED" {
            return nil
        }
        let syncType = lyr.str("syncType") ?? "UNSYNCED"
        let isSynced = syncType != "UNSYNCED"
        var hasSyllables = false

        let rawLines = lyr.list("lines")
        var mappedLines: [LyricLine] = []
        for (index, item) in rawLines.enumerated() {
            let startMs = item.int64("startTimeMs") ?? 0
            let nextStart = index + 1 < rawLines.count ? rawLines[index + 1].int64("startTimeMs") : nil
            let wordsText = item.str("words") ?? ""
            let syllables = item.list("syllables").compactMap { syl -> LyricWord? in
                guard let text = syl.str("text") ?? syl.str("chars"),
                      let sMs = syl.int64("startTimeMs") else { return nil }
                let dur = syl.int64("numChars").map { _ in Int64(250) }
                let eMs = syl.int64("endTimeMs") ?? (sMs + (dur ?? 250))
                return LyricWord(text: text, startMs: sMs, endMs: eMs)
            }
            if !syllables.isEmpty { hasSyllables = true }
            mappedLines.append(
                LyricLine(
                    startMs: startMs,
                    endMs: item.int64("endTimeMs").flatMap { $0 > startMs ? $0 : nextStart } ?? nextStart,
                    words: wordsText,
                    speaker: .main,
                    wordTimings: syllables
                )
            )
        }
        guard !mappedLines.isEmpty else { return nil }

        let colors: LyricsColors? = root.at("colors").flatMap { c in
            guard let bg = c.int64("background"),
                  let txt = c.int64("text"),
                  let hl = c.int64("highlightText") else { return nil }
            return LyricsColors(
                background: Int32(truncatingIfNeeded: bg),
                text: Int32(truncatingIfNeeded: txt),
                highlightText: Int32(truncatingIfNeeded: hl)
            )
        }

        return Lyrics(
            lines: mappedLines,
            synced: isSynced,
            wordSynced: syncType == "SYLLABLE_SYNCED" || hasSyllables,
            provider: lyr.str("providerDisplayName") ?? "Spotify",
            colors: colors,
            isRTL: lyr.bool("isRtlLanguage") ?? false
        )
    }

    public func trackCanvas(trackURI: SpotifyURI) async -> TrackCanvas? {
        let uri = trackURI.hasPrefix("spotify:track:") ? trackURI : "spotify:track:\(trackURI)"
        guard let r = try? await gql.query("canvas", variables: ["trackUri": .string(uri)]) else {
            return nil
        }
        guard let first = r.list("data.trackUnion.canvas.Lock").first
            ?? r.at("data.trackUnion.canvas") else { return nil }
        guard let url = first.str("url"), !url.isEmpty else { return nil }
        return TrackCanvas(url: url, type: first.str("type") ?? "VIDEO_LOOPING_RANDOM")
    }

    public func trackCredits(trackURI: SpotifyURI) async throws -> TrackCredits {
        let uri = trackURI.hasPrefix("spotify:track:") ? trackURI : "spotify:track:\(trackURI)"
        let r = try await gql.query("queryTrackCreditsGroupedModal", variables: ["uri": .string(uri)])
        let node = r.at("data.trackUnion.creditsTrait") ?? r.at("data.trackUnion")
        let title = r.str("data.trackUnion.name") ?? node?.str("trackTitle") ?? ""
        let roles = (node?.list("roleCredits") ?? []).compactMap { role -> TrackCreditRole? in
            guard let roleTitle = role.str("roleTitle") else { return nil }
            let names = role.list("artists").compactMap { $0.str("name") }
            guard !names.isEmpty else { return nil }
            return TrackCreditRole(role: roleTitle, names: names)
        }
        let sources = (node?.list("sources") ?? []).compactMap { $0.str("name") }
        return TrackCredits(title: title, roles: roles, sources: sources)
    }

    public func seedRadioPlaylistURI(seedURI: SpotifyURI) async throws -> SpotifyURI? {
        let encoded = seedURI.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? seedURI
        let url = URL(string: "https://spclient.wg.spotify.com/inspiredby-mix/v2/seed_to_playlist/\(encoded)?response-format=json")!
        let json = try await tokens.getAuthenticatedJSON(url: url)
        return json.list("mediaItems").first?.str("uri")
    }

    // MARK: - Blends & Recents

    public func createBlendInvite() async throws -> String {
        let url = URL(string: "https://spclient.wg.spotify.com/blend-invitation/v1/generate")!
        let res = try await tokens.sendAuthenticated(method: "POST", url: url)
        return JSONValue.parse(res.data)?.str("invite") ?? ""
    }

    public func viewBlendInvitation(linkOrID: String) async throws -> BlendInvitation {
        let id = Self.extractBlendID(from: linkOrID)
        let url = URL(string: "https://spclient.wg.spotify.com/blend-invitation/v3/view-invitation/\(id)")!
        let v = try await tokens.getAuthenticatedJSON(url: url)
        let state: BlendInvitationState = {
            switch v.str("page_type") {
            case "PENDING_INVITATION": return .waiting
            case "READY_TO_JOIN_EMPTY_BLEND", "READY_TO_JOIN_ALREADY_CREATED_BLEND": return .joinable
            case "MAX_MEMBERS": return .full
            case "ALREADY_JOINED": return .joined
            case "DELETED": return .deleted
            default: return .unknown
            }
        }()
        func mapMember(_ m: JSONValue?) -> BlendMember? {
            guard let username = m?.str("username") else { return nil }
            return BlendMember(username: username, name: m?.str("name") ?? username, imageURL: m?.str("image_url"))
        }
        return BlendInvitation(
            state: state,
            title: v.str("title"),
            subtitle: v.str("subtitle"),
            inviter: mapMember(v.at("recipient")),
            members: v.list("members").compactMap(mapMember),
            playlistURI: v.str("playlist_uri")
        )
    }

    public func joinBlend(linkOrID: String) async throws -> SpotifyURI {
        let id = Self.extractBlendID(from: linkOrID)
        let url = URL(string: "https://spclient.wg.spotify.com/blend-invitation/v2/join/\(id)")!
        let res = try await tokens.sendAuthenticated(method: "PUT", url: url)
        return JSONValue.parse(res.data)?.str("playlist_uri") ?? ""
    }

    public func blendStory(playlistURI: SpotifyURI) async -> BlendStory? {
        let id = MediaKind.spotifyID(from: playlistURI)
        guard let url = URL(string: "https://spclient.wg.spotify.com/blend-invitation/v3/data-stories/\(id)"),
              let v = try? await tokens.getAuthenticatedJSON(url: url) else { return nil }
        let intro = v.at("intro_story")
        let first = v.list("stories").first
        guard let title = intro?.str("title1.text") ?? first?.str("subtitle.text") else { return nil }
        return BlendStory(
            title: title,
            subtitle: intro?.str("subtitle1.text"),
            detail: first?.str("body.text"),
            backgroundHex: intro?.str("background_color") ?? first?.str("background_color"),
            titleColorHex: intro?.str("title1.text_color"),
            textColorHex: intro?.str("subtitle1.text_color") ?? first?.str("body.text_color"),
            imageURL: first?.str("image")
        )
    }

    public func recentlyPlayed(offset: Int = 0, limit: Int = 50) async throws -> Page<RecentEntry> {
        let r = try await gql.query("recents", variables: [
            "uris": .array([.string("spotify:list:recents:page")]),
            "offset": .int(Int64(offset)),
            "limit": .int(Int64(limit))
        ])
        let rowsNode = r.list("data.lists").first?.at("items")
        let page = SpotifyMappers.page(rowsNode, offset: offset) { row -> RecentEntry? in
            guard let entity = row.at("entity") else { return nil }
            let d = entity.at("data") ?? entity
            guard let uri = d.str("uri") ?? entity.str("_uri"),
                  let title = d.str("identityTrait.name") ?? d.str("name") else { return nil }
            let people = d.list("identityTrait.contributors.items").compactMap { $0.str("name") }.joined(separator: ", ")
            let sq = SpotifyMappers.images(d.list("visualIdentityTrait.squareCoverImage.image.data.sources"))
            let imgs = sq.isEmpty ? SpotifyMappers.images(d.list("visualIdentityTrait.image.data.sources")) : sq
            let attrs = row.list("formatListAttributes")
            let keys = attrs.compactMap { $0.str("key") }
            func attrVal(_ k: String) -> String? {
                attrs.first(where: { $0.str("key") == k })?.str("value")
            }
            let group = keys.first(where: { $0.hasPrefix("group_id_") && $0 != "group_id_0" })
                .map { String($0.dropFirst("group_id_".count)) }
            let meta = SpotifyMiniProtobuf.decodeRecentsGroupMetadata(base64: attrVal("group_metadata"))
            let kind = MediaKind.from(uri: uri)
            let isMusic = meta?.contentType.map { $0 == "music" }
                ?? (![MediaKind.show, .episode, .audiobook, .chapter].contains(kind))

            return RecentEntry(
                uri: uri,
                kind: kind,
                title: title,
                subtitle: people.isEmpty ? nil : people,
                images: imgs,
                durationMs: (d.int64("consumptionExperienceTrait.duration.seconds") ?? 0) * 1000,
                explicit: d.list("consumptionExperienceTrait.contentRatings")
                    .contains { $0.str() == "CONTENT_RATING_EXPLICIT" },
                typeLabel: d.str("identityTrait.type"),
                childrenGroup: attrVal("children_group_id"),
                group: group,
                groupCount: meta?.count,
                saved: keys.contains("recent_type_saved"),
                isMusic: isMusic
            )
        }
        DiagnosticLogbook.shared.log(
            "home",
            "Recently played mapping: \(rowsNode?.list("items").count ?? 0) source rows, \(page.items.count) displayable"
        )
        return page
    }

    // MARK: - Connect Devices & Jam

    public func connectDevices() async throws -> [ConnectDevice] {
        let res = try await bridge.service("ConnectDevicesAPI", method: "getDevices")
        return res.list().compactMap { d -> ConnectDevice? in
            guard let id = d.str("id") else { return nil }
            return ConnectDevice(
                id: id,
                name: d.str("name") ?? "Spotify Device",
                type: d.str("type") ?? "SPEAKER",
                isActive: d.bool("isActive") ?? false,
                isSelf: d.bool("isSelf") ?? false,
                volume: d.double("volume"),
                canSetVolume: d.bool("canSetVolume") ?? false
            )
        }
    }

    public func transferPlayback(toDeviceID deviceID: String) async throws {
        _ = try await bridge.service(
            "ConnectTransferAPI",
            method: "transferPlayback",
            args: [.string(deviceID), .object(["playOnTransfer": .bool(true)])]
        )
    }

    public func activeJamSession() async -> JamSession? {
        guard let res = try? await bridge.service("SocialConnectAPI", method: "getActiveSession"),
              let id = res.str("sessionId") ?? res.str("id"), !id.isEmpty else {
            return nil
        }
        let members = res.list("sessionMembers").compactMap { m -> JamMember? in
            guard let mid = m.str("id") ?? m.str("username") else { return nil }
            return JamMember(
                id: mid,
                username: m.str("username") ?? mid,
                name: m.str("displayName") ?? m.str("username") ?? mid,
                imageURL: m.str("imageUrl") ?? m.str("largeImageUrl"),
                isHost: m.bool("isOwner") ?? m.bool("isHost") ?? false
            )
        }
        return JamSession(
            id: id,
            joinCode: res.str("joinSessionToken") ?? res.str("joinSessionUri"),
            shareURI: res.str("joinSessionUri"),
            isHost: res.bool("isSessionOwner") ?? false,
            isListening: res.bool("isListening") ?? true,
            canControlPlayback: res.bool("isControllingPlayback") ?? true,
            members: members
        )
    }

    public func createJamSession() async throws -> JamSession? {
        _ = try await bridge.service("SocialConnectAPI", method: "createSession")
        return await activeJamSession()
    }

    public func leaveJamSession(sessionID: String) async throws {
        _ = try await bridge.service("SocialConnectAPI", method: "leaveSession", args: [.string(sessionID)])
    }

    private static func extractBlendID(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let regex = try? NSRegularExpression(pattern: #"/blend/(?:taste-match|invitation)/([A-Za-z0-9]+)"#),
           let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)),
           let r = Range(match.range(at: 1), in: trimmed) {
            return String(trimmed[r])
        }
        return trimmed
    }
}

//
//  GeniusMeaningService.swift
//  Celestify
//
//  Fetches song background stories and community line-by-line referent annotations
//  from Genius (`genius.com/api/search/song`, `/api/songs/{id}`, `/api/referents`),
//  matching Android GeniusMeaning.kt.
//  Built on Myspoti (https://github.com/kota-zo/myspoti), GPL-3.0.
//

import Foundation

public actor GeniusMeaningService {
    public static let shared = GeniusMeaningService()

    private let http: HTTPClient
    private var cache: [String: GeniusSongMeaning] = [:]
    private var missCache: [String: Date] = [:]

    public init(http: HTTPClient = .shared) {
        self.http = http
    }

    public func prefetch(trackID: String, title: String, artist: String) async {
        _ = try? await lookup(trackID: trackID, title: title, artist: artist)
    }

    public func lookup(trackID: String, title: String, artist: String) async throws -> GeniusSongMeaning? {
        let key = trackID.isEmpty ? "\(title.lowercased())|\(artist.lowercased())" : trackID
        if let hit = cache[key] { return hit }
        if let missedAt = missCache[key], Date().timeIntervalSince(missedAt) < 300 {
            return nil
        }

        let cleanTitle = LyricsRepository.cleanSearchTitle(title)
        let primaryArtist = artist.split(separator: ",").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? artist
        guard !cleanTitle.isEmpty else { return nil }

        var searchComps = URLComponents(string: "https://genius.com/api/search/song")!
        searchComps.queryItems = [
            URLQueryItem(name: "per_page", value: "5"),
            URLQueryItem(name: "q", value: "\(cleanTitle) \(primaryArtist)")
        ]
        guard let searchURL = searchComps.url else { return nil }

        let searchJSON = try await http.getJSON(url: searchURL)
        let hits = searchJSON.list("response.sections").first?.list("hits") ?? []

        let normTargetTitle = LyricTiming.normalizedMatchKey(cleanTitle)
        let normTargetArtist = LyricTiming.normalizedMatchKey(primaryArtist)

        var matchedSong: JSONValue?
        for hit in hits {
            guard let res = hit.at("result") else { continue }
            let hitTitle = LyricTiming.normalizedMatchKey(LyricsRepository.cleanSearchTitle(res.str("title") ?? ""))
            let hitArtist = LyricTiming.normalizedMatchKey(res.str("primary_artist.name") ?? "")
            if !hitTitle.isEmpty && (hitTitle == normTargetTitle || hitTitle.hasPrefix(normTargetTitle) || normTargetTitle.hasPrefix(hitTitle)) &&
               (normTargetArtist.isEmpty || hitArtist.contains(normTargetArtist) || normTargetArtist.contains(hitArtist)) {
                matchedSong = res
                break
            }
        }

        guard let songNode = matchedSong, let songID = songNode.int("id") else {
            missCache[key] = Date()
            return nil
        }

        async let songDetailTask = http.getJSON(
            url: URL(string: "https://genius.com/api/songs/\(songID)?text_format=plain")!
        )
        async let referentsTask = http.getJSON(
            url: URL(string: "https://genius.com/api/referents?song_id=\(songID)&per_page=50&text_format=plain")!
        )

        let songDetail = try? await songDetailTask
        let referentsJSON = try? await referentsTask

        let rawSummary = songDetail?.str("response.song.description.plain")?.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary: String? = (rawSummary != nil && rawSummary != "?" && !rawSummary!.isEmpty) ? rawSummary : nil

        let referents = referentsJSON?.list("response.referents") ?? []
        var annotations: [GeniusReferentAnnotation] = []
        for ref in referents {
            guard let fragment = ref.str("fragment")?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !fragment.isEmpty else { continue }
            let normFrag = LyricTiming.normalizedMatchKey(fragment)
            guard normFrag.count >= 4 else { continue }

            guard let firstAnn = ref.list("annotations").first else { continue }
            let votes = firstAnn.int("votes_total") ?? 0
            if votes < 0 { continue }
            guard let body = firstAnn.str("body.plain")?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !body.isEmpty else { continue }

            annotations.append(
                GeniusReferentAnnotation(
                    id: firstAnn.int("id") ?? ref.int("id") ?? fragment.hashValue,
                    fragment: fragment,
                    normalizedFragment: normFrag,
                    annotationText: body,
                    votesTotal: votes,
                    verified: firstAnn.bool("verified") ?? false
                )
            )
        }

        if summary == nil && annotations.isEmpty {
            missCache[key] = Date()
            return nil
        }

        let meaning = GeniusSongMeaning(
            songID: songID,
            title: songNode.str("title") ?? title,
            artist: songNode.str("primary_artist.name") ?? primaryArtist,
            url: songNode.str("url"),
            summary: summary,
            annotations: annotations
        )
        cache[key] = meaning
        return meaning
    }

    /// Finds the best matching Genius referent annotation for a given lyric line.
    public nonisolated static func annotation(for line: LyricLine, in meaning: GeniusSongMeaning?) -> GeniusReferentAnnotation? {
        guard let meaning, !line.isInstrumental else { return nil }
        let normLine = LyricTiming.normalizedMatchKey(line.words)
        guard normLine.count >= 5 else { return nil }
        return meaning.annotations.first { ann in
            ann.normalizedFragment.contains(normLine) || normLine.contains(ann.normalizedFragment)
        }
    }
}

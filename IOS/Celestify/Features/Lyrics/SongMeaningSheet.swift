//
//  SongMeaningSheet.swift
//  Celestify
//
//  Displays Genius song background story and verified referent annotations
//  prioritized around the currently active lyric line.
//  Ported from Celestify (GeniusMeaning.kt & MeaningSheet).
//

import SwiftUI

public struct SongMeaningSheet: View {
    public let track: Track
    public let focusedLyricLine: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.celestialTheme) private var theme

    @State private var meaning: GeniusSongMeaning?
    @State private var isLoading = true

    public init(track: Track, focusedLyricLine: String? = nil) {
        self.track = track
        self.focusedLyricLine = focusedLyricLine
    }

    private var sortedAnnotations: [GeniusReferentAnnotation] {
        guard let meaning else { return [] }
        guard let focused = focusedLyricLine?.trimmingCharacters(in: .whitespacesAndNewlines),
              !focused.isEmpty else {
            return meaning.annotations
        }
        return meaning.annotations.sorted { a, b in
            let aMatch = a.fragment.localizedCaseInsensitiveContains(focused) || focused.localizedCaseInsensitiveContains(a.fragment)
            let bMatch = b.fragment.localizedCaseInsensitiveContains(focused) || focused.localizedCaseInsensitiveContains(b.fragment)
            if aMatch != bMatch { return aMatch && !bMatch }
            return false
        }
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if isLoading {
                        HStack {
                            Spacer()
                            ProgressView("Fetching Genius Story & Annotations…")
                                .padding(40)
                            Spacer()
                        }
                    } else if let meaning {
                        HStack(spacing: 14) {
                            ArtworkView(urlString: track.coverURL, size: 68, cornerRadius: 14)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(meaning.title)
                                    .font(.headline.weight(.bold))
                                Text(meaning.artist)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(16)
                        .background(theme.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(theme.separator, lineWidth: 1)
                        }

                        if let summary = meaning.summary, !summary.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("About This Song", systemImage: "book.pages.fill")
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(theme.accent)

                                Text(summary)
                                    .font(.body)
                                    .lineSpacing(4)
                            }
                            .padding(18)
                            .background(theme.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(theme.separator, lineWidth: 1)
                            }
                        }

                        if !sortedAnnotations.isEmpty {
                            Text("Verified Line Annotations")
                                .font(.title3.weight(.bold))
                                .padding(.top, 4)

                            ForEach(sortedAnnotations) { ref in
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack(alignment: .top, spacing: 8) {
                                        Rectangle()
                                            .fill(theme.accent)
                                            .frame(width: 3)
                                        Text("“\(ref.fragment)”")
                                            .font(.subheadline.weight(.semibold))
                                            .italic()
                                    }

                                    Text(ref.annotationText)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .lineSpacing(3)

                                    HStack {
                                        if ref.verified {
                                            Label("Verified Artist Note", systemImage: "checkmark.seal.fill")
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(.green)
                                        }
                                        Spacer()
                                        if ref.votesTotal > 0 {
                                            Text("+\(ref.votesTotal)")
                                                .font(.caption2.monospacedDigit())
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .padding(16)
                                .background(theme.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .strokeBorder(theme.separator, lineWidth: 1)
                                }
                            }
                        }

                        if let rawURL = meaning.url, let url = URL(string: rawURL), !rawURL.isEmpty {
                            Link(destination: url) {
                                Label("Read Full Entry on Genius", systemImage: "arrow.up.right.square")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(theme.accent)
                            }
                            .padding(.top, 6)
                        }
                    } else {
                        ContentUnavailableView(
                            "No Song Story Available",
                            systemImage: "text.quote",
                            description: Text("Genius does not have an editorial summary or annotations for this track yet.")
                        )
                    }
                }
                .padding(18)
            }
            .navigationTitle("Song Meaning")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                meaning = try? await GeniusMeaningService.shared.lookup(
                    trackID: track.spotifyID,
                    title: track.name,
                    artist: track.artistNames
                )
                isLoading = false
            }
        }
    }
}

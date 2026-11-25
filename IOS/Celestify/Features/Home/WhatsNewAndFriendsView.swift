//
//  WhatsNewAndFriendsView.swift
//  Celestify
//
//  Full Spotify Recents feed (`recents` GraphQL + protobuf group metadata) and
//  live Friend Listening Activity (`presence-view/v1/buddylist`).
//

import SwiftUI

public struct WhatsNewSheet: View {
    @Environment(AppDependencies.self) private var deps
    @Environment(\.dismiss) private var dismiss
    @Environment(\.celestialTheme) private var theme

    @State private var entries: [RecentEntry] = []
    @State private var isLoading = true

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                } else if entries.isEmpty {
                    ContentUnavailableView(
                        "No Recent History Yet",
                        systemImage: "sparkles",
                        description: Text("Songs, albums, playlists, and podcast episodes you play appear here.")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(entries) { item in
                        Button {
                            dismiss()
                            if item.kind == .track || item.kind == .episode {
                                let t = Track(
                                    uri: item.uri,
                                    name: item.title,
                                    durationMs: item.durationMs,
                                    artists: [ArtistRef(uri: "", name: item.subtitle ?? "")],
                                    album: AlbumRef(uri: "", name: "", images: item.images),
                                    explicit: item.explicit
                                )
                                deps.player.playTrack(t)
                            } else {
                                deps.router.openSpotifyURI(item.uri, fallbackTitle: item.title)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                ArtworkView(urlString: item.images.mediumURL, size: 52, cornerRadius: 10)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(theme.primaryText)
                                        .lineLimit(1)
                                    Text(item.subtitle ?? item.kind.rawValue.capitalized)
                                        .font(.caption)
                                        .foregroundStyle(theme.secondaryText)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Spotify Recents")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                entries = (try? await deps.api.recentlyPlayed(limit: 40))?.items ?? []
                isLoading = false
            }
        }
    }
}

public struct FriendActivitySheet: View {
    @Environment(AppDependencies.self) private var deps
    @Environment(\.dismiss) private var dismiss
    @Environment(\.celestialTheme) private var theme

    @State private var activities: [FriendActivity] = []
    @State private var isLoading = true

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                } else if activities.isEmpty {
                    ContentUnavailableView(
                        "No Active Friends Right Now",
                        systemImage: "person.2.slash",
                        description: Text("Friends sharing listening activity on Spotify appear here in real time.")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(activities) { entry in
                        Button {
                            dismiss()
                            let t = Track(
                                uri: entry.trackURI,
                                name: entry.trackName,
                                durationMs: 0,
                                artists: [ArtistRef(uri: entry.artistURI ?? "", name: entry.artistName ?? "")],
                                album: AlbumRef(
                                    uri: entry.albumURI ?? "",
                                    name: entry.albumName ?? "",
                                    images: entry.imageURL.map { [MediaImage(url: $0)] } ?? []
                                )
                            )
                            deps.player.playTrack(t, contextURI: entry.contextURI ?? "", contextName: entry.contextName ?? "")
                        } label: {
                            HStack(spacing: 12) {
                                ArtworkView(
                                    urlString: entry.userImageURL,
                                    size: 46,
                                    cornerRadius: 23,
                                    isCircular: true,
                                    fallbackSystemImage: "person.fill"
                                )
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(entry.userName)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(theme.primaryText)
                                    Text("\(entry.trackName) · \(entry.artistName ?? "")")
                                        .font(.footnote)
                                        .foregroundStyle(theme.accent)
                                        .lineLimit(1)
                                    if let ctx = entry.contextName, !ctx.isEmpty {
                                        Text(ctx)
                                            .font(.caption2)
                                            .foregroundStyle(theme.secondaryText)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                                Image(systemName: "play.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(theme.accent)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Friend Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                activities = (try? await deps.api.friendActivity()) ?? []
                isLoading = false
            }
        }
    }
}

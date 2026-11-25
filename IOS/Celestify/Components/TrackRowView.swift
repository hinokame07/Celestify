//
//  TrackRowView.swift
//  Celestify
//
//  Apple Music-grade track row with swipe-to-queue, animated playing waveform,
//  explicit & offline badges, and rich context menu actions.
//

import SwiftUI

public struct TrackRowView: View {
    public let track: Track
    public let indexNumber: Int?
    public let showArtwork: Bool
    public let onPlay: () -> Void

    @Environment(AppDependencies.self) private var deps
    @Environment(\.celestialTheme) private var theme

    public init(
        track: Track,
        indexNumber: Int? = nil,
        showArtwork: Bool = true,
        onPlay: @escaping () -> Void
    ) {
        self.track = track
        self.indexNumber = indexNumber
        self.showArtwork = showArtwork
        self.onPlay = onPlay
    }

    private var isCurrentTrack: Bool {
        deps.player.currentTrack?.uri == track.uri
    }

    private var isOfflineDownloaded: Bool {
        deps.offlineStore.downloadedTracks[track.spotifyID] != nil
    }

    public var body: some View {
        Button(action: {
            HapticsManager.shared.selection()
            onPlay()
        }) {
            HStack(spacing: 12) {
                if let indexNumber, !showArtwork {
                    Group {
                        if isCurrentTrack && deps.player.isPlaying {
                            PlayingBarsIndicator(color: theme.accent)
                        } else {
                            Text("\(indexNumber)")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(isCurrentTrack ? theme.accent : theme.secondaryText)
                        }
                    }
                    .frame(width: 26)
                }

                if showArtwork {
                    ZStack {
                        ArtworkView(urlString: track.coverURL, size: 48, cornerRadius: 9)
                        if isCurrentTrack {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color.black.opacity(0.42))
                                .frame(width: 48, height: 48)
                            PlayingBarsIndicator(color: theme.accent)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(track.name)
                        .font(.body.weight(isCurrentTrack ? .semibold : .regular))
                        .foregroundStyle(isCurrentTrack ? theme.accent : theme.primaryText)
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        if track.explicit {
                            Image(systemName: "e.square.fill")
                                .font(.caption2)
                                .foregroundStyle(theme.secondaryText)
                        }
                        if isOfflineDownloaded {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(theme.accent)
                        }
                        Text(track.artistNames)
                            .font(.footnote)
                            .foregroundStyle(theme.secondaryText)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 6)

                Text(Self.formatDuration(track.durationMs))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(theme.secondaryText)

                Menu {
                    contextMenuItems
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.secondaryText)
                        .frame(width: 30, height: 36)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("More actions for \(track.name)")
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            contextMenuItems
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                deps.player.addToQueue(track)
            } label: {
                Label("Queue", systemImage: "text.line.first.and.arrowtriangle.forward")
            }
            .tint(theme.accent)
        }
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        Button {
            onPlay()
        } label: {
            Label("Play Now", systemImage: "play.fill")
        }

        Button {
            deps.player.addToQueue(track)
        } label: {
            Label("Add to Queue", systemImage: "text.line.first.and.arrowtriangle.forward")
        }

        Button {
            Task { try? await deps.api.setLibrarySaved(true, uris: [track.uri]) }
        } label: {
            Label("Save to Liked Songs", systemImage: "heart")
        }

        if let firstArtist = track.artists.first, !firstArtist.uri.isEmpty {
            Button {
                deps.router.navigate(to: .artist(uri: firstArtist.uri, initialName: firstArtist.name))
            } label: {
                Label("Go to Artist", systemImage: "music.mic")
            }
        }

        if let album = track.album, !album.uri.isEmpty {
            Button {
                deps.router.navigate(to: .album(uri: album.uri, initialName: album.name))
            } label: {
                Label("Go to Album", systemImage: "square.stack")
            }
        }

        if track.isEpisode || !track.spotifyID.isEmpty {
            Button {
                Task {
                    await deps.offlineStore.download(track: track, api: deps.api)
                }
            } label: {
                Label(isOfflineDownloaded ? "Downloaded" : "Download Offline", systemImage: "arrow.down.circle")
            }
            .disabled(isOfflineDownloaded)
        }

        if let shareURL = URL(string: "https://open.spotify.com/track/\(track.spotifyID)"), !track.spotifyID.isEmpty {
            ShareLink(item: shareURL) {
                Label("Share Link", systemImage: "square.and.arrow.up")
            }
        }
    }

    public static func formatDuration(_ ms: Int64) -> String {
        let totalSecs = max(0, Int(ms / 1000))
        let mins = totalSecs / 60
        let secs = totalSecs % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

public struct PlayingBarsIndicator: View {
    public let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(color: Color) {
        self.color = color
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 0.12, paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2.5) {
                ForEach(0..<3, id: \.self) { idx in
                    let h = reduceMotion ? 0.65 : (0.3 + 0.7 * abs(sin(t * 4.2 + Double(idx) * 1.1)))
                    Capsule(style: .continuous)
                        .fill(color)
                        .frame(width: 3, height: CGFloat(5 + h * 11))
                }
            }
            .frame(width: 15, height: 16)
        }
    }
}

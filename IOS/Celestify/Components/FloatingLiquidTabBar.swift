//
//  FloatingLiquidTabBar.swift
//  Celestify
//
//  Apple iOS 26-inspired floating Liquid Glass bottom chrome pairing the
//  morphing Now Playing Mini-Bar with the 4-destination Liquid Pill Tab Bar.
//

import SwiftUI

public struct FloatingBottomChrome: View {
    @Environment(AppDependencies.self) private var deps
    @Environment(\.celestialTheme) private var theme

    public init() {}

    public var body: some View {
        VStack(spacing: 10) {
            if let currentItem = deps.player.currentTrack {
                MiniPlayerBar(track: currentItem.asTrack())
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(spacing: 4) {
                ForEach(CelestifyTab.allCases) { tab in
                    let isSelected = deps.router.selectedTab == tab
                    Button {
                        HapticsManager.shared.selection()
                        if isSelected {
                            deps.router.popToRoot(of: tab)
                        } else {
                            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                                deps.router.selectedTab = tab
                            }
                        }
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: tab.systemImage)
                                .font(.system(size: 18, weight: isSelected ? .semibold : .regular))
                                .symbolEffect(.bounce, value: isSelected)
                            Text(tab.title)
                                .font(.caption2.weight(isSelected ? .semibold : .medium))
                        }
                        .foregroundStyle(isSelected ? theme.accent : theme.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background {
                            if isSelected {
                                Capsule(style: .continuous)
                                    .fill(theme.accent.opacity(0.16))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tab.title)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .liquidGlass(shape: Capsule(style: .continuous), tint: theme.surface)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }
}

public struct MiniPlayerBar: View {
    public let track: Track

    @Environment(AppDependencies.self) private var deps
    @Environment(\.celestialTheme) private var theme

    public init(track: Track) {
        self.track = track
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    HapticsManager.shared.softDetent()
                    deps.router.isShowingFullPlayer = true
                } label: {
                    HStack(spacing: 11) {
                        ArtworkView(urlString: track.coverURL, size: 44, cornerRadius: 10)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(theme.primaryText)
                                .lineLimit(1)
                            HStack(spacing: 5) {
                                if let remote = deps.player.activeRemoteDeviceName {
                                    Image(systemName: "speaker.wave.2.fill")
                                        .font(.caption2)
                                        .foregroundStyle(theme.accent)
                                    Text(remote)
                                        .font(.caption)
                                        .foregroundStyle(theme.accent)
                                        .lineLimit(1)
                                } else {
                                    Text(track.artistNames)
                                        .font(.caption)
                                        .foregroundStyle(theme.secondaryText)
                                        .lineLimit(1)
                                }
                            }
                        }
                        Spacer(minLength: 4)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Now Playing: \(track.name) by \(track.artistNames). Double-tap to expand.")

                Button {
                    deps.player.toggleCurrentTrackLiked()
                } label: {
                    Image(systemName: deps.player.isCurrentTrackLiked ? "heart.fill" : "heart")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(deps.player.isCurrentTrackLiked ? theme.accent : theme.secondaryText)
                        .frame(width: 34, height: 38)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(deps.player.isCurrentTrackLiked ? "Remove from Liked Songs" : "Save to Liked Songs")

                Button {
                    HapticsManager.shared.tap()
                    deps.player.togglePlayPause()
                } label: {
                    Image(systemName: deps.player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(theme.primaryText)
                        .frame(width: 36, height: 38)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(deps.player.isPlaying ? "Pause" : "Play")

                Button {
                    deps.player.skipNext()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                        .frame(width: 32, height: 38)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Next Track")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                let dur = max(1, deps.player.durationMs)
                let frac = min(max(Double(deps.player.currentPositionMs()) / Double(dur), 0.0), 1.0)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.09))
                        Capsule()
                            .fill(theme.accent)
                            .frame(width: geo.size.width * frac)
                    }
                }
                .frame(height: 2.5)
                .padding(.horizontal, 14)
                .padding(.bottom, 4)
            }
        }
        .liquidGlass(
            shape: RoundedRectangle(cornerRadius: 18, style: .continuous),
            tint: Color(argb: deps.player.artworkPalette.dominantARGB),
            interactive: true
        )
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    if value.translation.height < -30 {
                        deps.router.isShowingFullPlayer = true
                    } else if value.translation.width < -45 {
                        deps.player.skipNext()
                    } else if value.translation.width > 45 {
                        deps.player.skipPrevious()
                    }
                }
        )
    }
}

//
//  MediaCardView.swift
//  Celestify
//
//  Reusable Liquid Glass media cards and compact Home shortcut tiles.
//

import SwiftUI

public struct MediaCardView: View {
    public let title: String
    public let subtitle: String
    public let imageURL: String?
    public let isCircular: Bool
    public let size: CGFloat
    public let action: () -> Void

    @Environment(\.celestialTheme) private var theme

    public init(
        title: String,
        subtitle: String,
        imageURL: String?,
        isCircular: Bool = false,
        size: CGFloat = 148,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.imageURL = imageURL
        self.isCircular = isCircular
        self.size = size
        self.action = action
    }

    public var body: some View {
        Button(action: {
            HapticsManager.shared.selection()
            action()
        }) {
            VStack(alignment: isCircular ? .center : .leading, spacing: 8) {
                ArtworkView(
                    urlString: imageURL,
                    size: size,
                    cornerRadius: 14,
                    isCircular: isCircular,
                    fallbackSystemImage: isCircular ? "person.wave.2.fill" : "music.quarternote.3"
                )
                .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 5)

                VStack(alignment: isCircular ? .center : .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)

                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(theme.secondaryText)
                            .lineLimit(1)
                    }
                }
                .frame(width: size, alignment: isCircular ? .center : .leading)
            }
        }
        .buttonStyle(.plain)
    }
}

public struct HomeShortcutTile: View {
    public let card: MediaCard
    public let action: () -> Void

    @Environment(\.celestialTheme) private var theme

    public init(card: MediaCard, action: @escaping () -> Void) {
        self.card = card
        self.action = action
    }

    public var body: some View {
        Button(action: {
            HapticsManager.shared.selection()
            action()
        }) {
            HStack(spacing: 10) {
                ArtworkView(urlString: card.images.mediumURL, size: 54, cornerRadius: 10)
                Text(card.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 4)
            }
            .padding(.trailing, 10)
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            .liquidGlass(shape: RoundedRectangle(cornerRadius: 12, style: .continuous), tint: theme.elevated, interactive: true)
        }
        .buttonStyle(.plain)
    }
}

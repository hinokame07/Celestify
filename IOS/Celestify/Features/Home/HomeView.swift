//
//  HomeView.swift
//  Celestify
//
//  Home tab featuring time-of-day greeting, facet filter chips, Friend Activity &
//  Recents sheets, 2-column Liquid Glass shortcuts, Spotify Home shelves, and Listening Recap card.
//  Built on Myspoti (https://github.com/kota-zo/myspoti), GPL-3.0.
//

import SwiftUI

public struct HomeView: View {
    @Environment(AppDependencies.self) private var deps
    @Environment(\.celestialTheme) private var theme

    @State private var feed: HomeFeed?
    @State private var selectedFacetID: String?
    @State private var recentEntries: [RecentEntry] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingWhatsNew = false
    @State private var showingFriendActivity = false
    @State private var showingRecap = false

    public init() {}

    public var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 24) {
                headerToolbar

                if let chips = feed?.chips, !chips.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(chips) { chip in
                                let active = selectedFacetID == chip.id
                                Button {
                                    HapticsManager.shared.selection()
                                    selectedFacetID = active ? nil : chip.id
                                    Task { await reload() }
                                } label: {
                                    Text(chip.label)
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(active ? .white : theme.primaryText)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background {
                                            if active {
                                                Capsule().fill(theme.accent)
                                            } else {
                                                Capsule().fill(Color.white.opacity(0.08))
                                            }
                                        }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }

                if let firstSection = feed?.sections.first, !firstSection.items.isEmpty {
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                        spacing: 10
                    ) {
                        ForEach(firstSection.items.prefix(6)) { card in
                            HomeShortcutTile(card: card) {
                                openMediaCard(card)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }

                listeningRecapBanner
                    .padding(.horizontal, 16)

                if !recentEntries.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recently Played")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(theme.primaryText)
                            .padding(.horizontal, 16)

                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 14) {
                                ForEach(recentEntries.prefix(14)) { entry in
                                    MediaCardView(
                                        title: entry.title,
                                        subtitle: entry.subtitle ?? "",
                                        imageURL: entry.images.mediumURL,
                                        isCircular: entry.kind == .artist,
                                        size: 136
                                    ) {
                                        openRecentEntry(entry)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                }

                if let sections = feed?.sections.dropFirst() {
                    ForEach(Array(sections)) { section in
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                if let sub = section.subtitle, !sub.isEmpty {
                                    Text(sub.uppercased())
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(theme.secondaryText)
                                }
                                Text(section.title)
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(theme.primaryText)
                            }
                            .padding(.horizontal, 16)

                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 14) {
                                    ForEach(section.items) { card in
                                        MediaCardView(
                                            title: card.title,
                                            subtitle: card.subtitle ?? "",
                                            imageURL: card.images.mediumURL,
                                            isCircular: card.kind == .artist,
                                            size: 150
                                        ) {
                                            openMediaCard(card)
                                        }
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                    }
                }

                if isLoading && feed == nil {
                    HStack {
                        Spacer()
                        ProgressView("Loading Celestial Home…")
                            .tint(theme.accent)
                            .padding(.vertical, 48)
                        Spacer()
                    }
                } else if let errorMessage, feed == nil {
                    VStack(spacing: 12) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.largeTitle)
                            .foregroundStyle(theme.secondaryText)
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(theme.secondaryText)
                            .multilineTextAlignment(.center)
                        Button("Retry") {
                            Task { await reload() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(theme.accent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(32)
                }

                Spacer(minLength: 130)
            }
            .padding(.top, 12)
        }
        .refreshable {
            await reload()
        }
        .task {
            if feed == nil {
                await reload()
            }
        }
        .sheet(isPresented: $showingWhatsNew) {
            WhatsNewSheet()
        }
        .sheet(isPresented: $showingFriendActivity) {
            FriendActivitySheet()
        }
        .sheet(isPresented: $showingRecap) {
            NavigationStack {
                ListeningRecapView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingRecap = false }
                        }
                    }
            }
        }
    }

    private var headerToolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(greetingTitle)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.primaryText)
                if let name = deps.authManager.currentAccount?.displayName, !name.isEmpty {
                    Text(name)
                        .font(.subheadline)
                        .foregroundStyle(theme.secondaryText)
                }
            }

            Spacer()

            Button {
                showingWhatsNew = true
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                    .frame(width: 38, height: 38)
                    .liquidGlass(shape: Circle(), interactive: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Listening History")

            Button {
                showingFriendActivity = true
            } label: {
                Image(systemName: "person.2.wave.2")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                    .frame(width: 38, height: 38)
                    .liquidGlass(shape: Circle(), interactive: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Friend Listening Activity")

            if let me = deps.authManager.currentAccount {
                Button {
                    deps.router.navigate(to: .user(uri: "spotify:user:\(me.id)", initialName: me.displayName))
                } label: {
                    ArtworkView(
                        urlString: me.avatarURL,
                        size: 38,
                        cornerRadius: 19,
                        isCircular: true,
                        fallbackSystemImage: "person.crop.circle.fill"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Your Profile")
            }
        }
        .padding(.horizontal, 16)
    }

    private var listeningRecapBanner: some View {
        let recap = deps.listenHistory.recap()
        return Button {
            showingRecap = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(theme.accent.opacity(0.2))
                        .frame(width: 46, height: 46)
                    Image(systemName: "chart.bar.xaxis.ascending.badge.clock")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(theme.accent)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Celestial Listening Recap")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.primaryText)
                    Text(
                        recap.totalListens > 0
                        ? "\(recap.totalMinutes) mins across \(recap.totalListens) plays · Tap to inspect"
                        : "On-device private stats start after 30s of playback"
                    )
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.secondaryText)
            }
            .padding(14)
            .liquidGlass(shape: RoundedRectangle(cornerRadius: 18, style: .continuous), interactive: true)
        }
        .buttonStyle(.plain)
    }

    private var greetingTitle: String {
        if let g = feed?.greeting, !g.isEmpty { return g }
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<18: return "Good afternoon"
        default: return "Good evening"
        }
    }

    private func reload() async {
        isLoading = true
        errorMessage = nil
        do {
            async let homeTask = deps.api.homeFeed(facet: selectedFacetID)
            async let recentsTask = deps.api.recentlyPlayed(limit: 20)
            self.feed = try await homeTask
            self.recentEntries = (try? await recentsTask)?.items ?? []
        } catch {
            self.errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func openMediaCard(_ card: MediaCard) {
        if card.kind == .track || card.kind == .episode {
            let track = Track(
                uri: card.uri,
                name: card.title,
                durationMs: 0,
                artists: [ArtistRef(uri: "", name: card.subtitle ?? "")],
                album: AlbumRef(uri: "", name: "", images: card.images)
            )
            deps.player.playTrack(track)
        } else {
            deps.router.openSpotifyURI(card.uri, fallbackTitle: card.title)
        }
    }

    private func openRecentEntry(_ entry: RecentEntry) {
        if entry.kind == .track || entry.kind == .episode {
            let track = Track(
                uri: entry.uri,
                name: entry.title,
                durationMs: entry.durationMs,
                artists: [ArtistRef(uri: "", name: entry.subtitle ?? "")],
                album: AlbumRef(uri: "", name: "", images: entry.images),
                explicit: entry.explicit
            )
            deps.player.playTrack(track)
        } else {
            deps.router.openSpotifyURI(entry.uri, fallbackTitle: entry.title)
        }
    }
}

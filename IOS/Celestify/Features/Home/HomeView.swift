//
//  HomeView.swift
//  Celestify
//
//  Home tab featuring Spotify shelves, recent plays, and listening recap.
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
    @State private var loadGeneration = 0
    @State private var errorMessage: String?
    @State private var showingWhatsNew = false
    @State private var showingFriendActivity = false
    @State private var showingRecap = false

    public init() {}

    public var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 24) {
                headerToolbar

                if isLoading && feed == nil {
                    loadingSkeleton
                } else if let errorMessage {
                    loadErrorState(errorMessage)
                } else if let feed, feed.sections.isEmpty, recentEntries.isEmpty {
                    ContentUnavailableView(
                        "No music yet",
                        systemImage: "music.note.list",
                        description: Text("Your Spotify Home has no content right now.")
                    )
                    .padding(.horizontal, 16)
                }

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
                            .scrollTargetLayout()
                            .padding(.horizontal, 16)
                        }
                        .scrollTargetBehavior(.viewAligned)
                    }
                }

                if let sections = feed?.sections {
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
                                .scrollTargetLayout()
                                .padding(.horizontal, 16)
                            }
                            .scrollTargetBehavior(.viewAligned)
                        }
                    }
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

    private var loadingSkeleton: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Loading your music…")
                .font(.headline)
                .foregroundStyle(theme.secondaryText)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(0..<3, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: 8) {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(theme.secondaryText.opacity(0.12))
                                .frame(width: 132, height: 132)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(theme.secondaryText.opacity(0.12))
                                .frame(width: 100, height: 12)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(theme.secondaryText.opacity(0.08))
                                .frame(width: 72, height: 10)
                        }
                    }
                }
            }
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("Loading your music")
    }

    @ViewBuilder
    private func loadErrorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(theme.secondaryText)
            Text(message)
                .font(.footnote)
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
            Button("Try again") {
                Task { await reload() }
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.accent)
            .disabled(isLoading)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
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
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        errorMessage = nil
        defer {
            if generation == loadGeneration {
                isLoading = false
            }
        }

        DiagnosticLogbook.shared.log("home", "Starting Home load")
        do {
            guard deps.authManager.currentAccount != nil else {
                throw HomeLoadError.notAuthenticated
            }
            DiagnosticLogbook.shared.log("home", "Waiting for authenticated Web Player bridge")
            try await deps.bridge.waitUntilReady(timeoutSeconds: 30)
            guard generation == loadGeneration else { return }
            DiagnosticLogbook.shared.log("home", "Web Player bridge ready; requesting Spotify Home")

            async let feedRequest = loadHomeFeed()
            async let recentsRequest = loadRecentEntries()
            let (feedResult, recentsResult) = await (feedRequest, recentsRequest)
            guard generation == loadGeneration else { return }

            switch feedResult {
            case .success(let loadedFeed):
                self.feed = loadedFeed
                let sectionItemCount = loadedFeed.sections.reduce(0) { $0 + $1.items.count }
                DiagnosticLogbook.shared.log(
                    "home",
                    "Home mapped \(loadedFeed.sections.count) sections and \(sectionItemCount) cards"
                )
            case .failure(let error):
                DiagnosticLogbook.shared.log(
                    "home",
                    "Home feed request failed (\(String(describing: type(of: error))))"
                )
                self.errorMessage = error.localizedDescription
            }

            switch recentsResult {
            case .success(let entries):
                self.recentEntries = entries
                DiagnosticLogbook.shared.log("home", "Recently played mapped \(entries.count) items")
            case .failure(let error):
                self.recentEntries = []
                DiagnosticLogbook.shared.log(
                    "home",
                    "Recently played request failed (\(String(describing: type(of: error))))"
                )
            }
            if case .success(let loadedFeed) = feedResult,
               loadedFeed.sections.isEmpty && recentEntries.isEmpty {
                DiagnosticLogbook.shared.log("home", "Spotify Home completed without displayable content")
            }
        } catch is CancellationError {
            DiagnosticLogbook.shared.log("home", "Home load cancelled")
        } catch {
            DiagnosticLogbook.shared.log(
                "home",
                "Home load failed (\(String(describing: type(of: error))))"
            )
            if generation == loadGeneration {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    private func loadHomeFeed() async -> Result<HomeFeed, Error> {
        do {
            return .success(try await deps.api.homeFeed(facet: selectedFacetID))
        } catch {
            return .failure(error)
        }
    }

    private func loadRecentEntries() async -> Result<[RecentEntry], Error> {
        do {
            return .success(try await deps.api.recentlyPlayed(limit: 20).items)
        } catch {
            return .failure(error)
        }
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

    private enum HomeLoadError: LocalizedError {
        case notAuthenticated

        var errorDescription: String? {
            NSLocalizedString("Sign in to Spotify to load Home.", comment: "Shown when Home is opened without an active Spotify account")
        }
    }
}

//
//  OnboardingLoginView.swift
//  Celestify
//
// Spotify authentication screen:
//  1) Interactive WebKit sign-in (with coherent iOS Safari UA & popup OAuth support)
//  2) Manual `sp_dc` cookie import fallback
//  3) Email magic-link paste fallback
//  Built on Myspoti (https://github.com/kota-zo/myspoti), GPL-3.0.
//

import SwiftUI

public struct OnboardingLoginView: View {
    @Environment(AppDependencies.self) private var deps
    @Environment(\.celestialTheme) private var theme

    @State private var showingWebLogin = false
    @State private var showingCookieSheet = false
    @State private var showingMagicLinkSheet = false
    @State private var spDcInput = ""
    @State private var magicLinkInput = ""
    @State private var magicLinkForwardURL: URL?

    public init() {}

    private var authBannerMessage: String? {
        switch deps.authManager.state {
        case .unauthenticated(let msg): return msg
        case .sessionExpired(let reason): return reason
        default: return nil
        }
    }

    public var body: some View {
        ZStack {
            AtmosphericBackdrop(palette: .celestialDefault, isAnimating: false)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 28) {
                    Spacer(minLength: 42)

                    ZStack {
                        RoundedRectangle(cornerRadius: 34, style: .continuous)
                            .fill(theme.elevated)
                            .frame(width: 112, height: 112)
                            .overlay {
                                Image(systemName: "music.note")
                                    .font(.system(size: 42, weight: .semibold))
                                    .foregroundStyle(theme.accent)
                            }
                    }

                    VStack(spacing: 10) {
                        Text("Celestify")
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(theme.primaryText)

                        Text("Play music, follow lyrics, and manage your Spotify library.")
                            .font(.body)
                            .foregroundStyle(theme.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        featureRow(
                            icon: "waveform.and.magnifyingglass",
                            title: "Lyrics synced to words",
                            subtitle: "Follow lyrics with translation and romanization."
                        )
                        featureRow(
                            icon: "paintbrush.pointed.fill",
                            title: "Appearance",
                            subtitle: "Choose colors and display preferences."
                        )
                        featureRow(
                            icon: "lock.shield.fill",
                            title: "Private by design",
                            subtitle: "Sessions stay in Keychain; offline audio is encrypted."
                        )
                    }
                    .padding(20)
                    .background(theme.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(theme.separator, lineWidth: 1)
                    }
                    .padding(.horizontal, 20)

                    if let banner = authBannerMessage, !banner.isEmpty {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(banner)
                                .font(.footnote)
                                .foregroundStyle(.white)
                            Spacer()
                        }
                        .padding(14)
                        .background(Color.red.opacity(0.22), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.horizontal, 20)
                    }

                    VStack(spacing: 12) {
                        Button {
                            HapticsManager.shared.tap()
                            magicLinkForwardURL = nil
                            showingWebLogin = true
                        } label: {
                            HStack(spacing: 10) {
                                if deps.authManager.state == .signingIn {
                                    ProgressView()
                                        .tint(theme.onAccent)
                                } else {
                                    Image(systemName: "person.badge.key.fill")
                                        .font(.headline)
                                }
                                Text("Continue with Spotify")
                                    .font(.headline.weight(.semibold))
                            }
                            .foregroundStyle(theme.onAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(theme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        HStack(spacing: 12) {
                            Button {
                                showingCookieSheet = true
                            } label: {
                                Label("Import sp_dc Cookie", systemImage: "key.horizontal")
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(theme.primaryText)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .liquidGlass(shape: Capsule(style: .continuous), interactive: true)
                            }
                            .buttonStyle(.plain)

                            Button {
                                showingMagicLinkSheet = true
                            } label: {
                                Label("Email Magic Link", systemImage: "envelope.badge")
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(theme.primaryText)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .liquidGlass(shape: Capsule(style: .continuous), interactive: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)

                    Text("Built on Myspoti (GPL-3.0) · Not affiliated with Spotify AB.")
                        .font(.caption2)
                        .foregroundStyle(theme.secondaryText.opacity(0.8))
                        .padding(.bottom, 28)
                }
            }
        }
        .sheet(isPresented: $showingWebLogin) {
            SpotifyLoginSheetContainer(
                initialURL: magicLinkForwardURL ?? SpotifyAuthManager.loginEntryURL
            )
        }
        .sheet(isPresented: $showingCookieSheet) {
            cookieImportSheet
        }
        .sheet(isPresented: $showingMagicLinkSheet) {
            magicLinkImportSheet
        }
    }

    private func featureRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(theme.accent)
                .frame(width: 34, height: 34)
                .background(theme.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.primaryText)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
            }
        }
    }

    private var cookieImportSheet: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Paste sp_dc cookie value or header", text: $spDcInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Spotify Session Cookie")
                } footer: {
                    Text("If Google/Apple OAuth is restricted on your network, sign in to open.spotify.com in Desktop Safari/Chrome, copy your sp_dc cookie value, and paste it here. Stored encrypted in Apple Keychain.")
                }
            }
            .navigationTitle("Import Session Cookie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingCookieSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sign In") {
                        let raw = spDcInput
                        spDcInput = ""
                        showingCookieSheet = false
                        Task { await deps.authManager.importManualSpDcCookie(raw) }
                    }
                    .disabled(spDcInput.trimmingCharacters(in: .whitespacesAndNewlines).count < 20)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var magicLinkImportSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://accounts.spotify.com/login/ott/...", text: $magicLinkInput)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Spotify Login Link")
                } footer: {
                    Text("Paste a one-time Spotify email sign-in link (`accounts.spotify.com` or `wl.spotify.com`) to complete sign-in directly inside Celestify.")
                }
            }
            .navigationTitle("Paste Magic Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingMagicLinkSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue") {
                        if let url = URL(string: magicLinkInput.trimmingCharacters(in: .whitespacesAndNewlines)),
                           let validated = deps.authManager.normalizeMagicLink(url) {
                            magicLinkForwardURL = validated
                            magicLinkInput = ""
                            showingMagicLinkSheet = false
                            showingWebLogin = true
                        }
                    }
                    .disabled(magicLinkInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

public struct SpotifyLoginSheetContainer: View {
    public let initialURL: URL

    @Environment(AppDependencies.self) private var deps
    @Environment(\.dismiss) private var dismiss
    @State private var statusBanner: String = "Sign in to your Spotify account. Email codes & passkeys are supported."
    @State private var isWebLoading: Bool = true

    public init(initialURL: URL) {
        self.initialURL = initialURL
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    if isWebLoading {
                        ProgressView().scaleEffect(0.75)
                    } else {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                    Text(statusBanner)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(uiColor: .secondarySystemBackground))

                SpotifyLoginWebView(
                    initialURL: initialURL,
                    callbackURL: deps.authManager.pendingAuthCallbackURL,
                    onAuthenticated: { cookies, finalURL in
                        statusBanner = "Verifying Spotify session…"
                        Task {
                            await deps.authManager.completeLoginWithCookies(cookies, finalURL: finalURL)
                            if deps.authManager.state.isAuthenticated {
                                dismiss()
                            }
                        }
                    },
                    onLoadingChanged: { loading in
                        isWebLoading = loading
                    }
                )
                .ignoresSafeArea(edges: .bottom)
            }
            .navigationTitle("Spotify Sign In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

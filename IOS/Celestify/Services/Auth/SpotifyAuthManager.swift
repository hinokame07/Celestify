//
//  SpotifyAuthManager.swift
//  Celestify
//
//  Session lifecycle, Keychain restoration, WKHTTPCookieStore synchronization,
//  OTP/Magic-Link-safe login state machine, logout, and multi-account switching.
//  Built on Myspoti (https://github.com/kota-zo/myspoti), GPL-3.0.
//

import Foundation
import Observation
import WebKit

public enum AuthState: Equatable, Sendable {
    case restoringSession
    case unauthenticated(message: String? = nil)
    case signingIn
    case bootstrappingPlayer
    case authenticated(accountID: String, displayName: String)
    case sessionExpired(reason: String)

    public var isAuthenticated: Bool {
        if case .authenticated = self { return true }
        return false
    }
}

@Observable
@MainActor
public final class SpotifyAuthManager {
    public static let loginEntryURL = URL(string: "https://accounts.spotify.com/login?continue=https%3A%2F%2Fopen.spotify.com%2F")!
    public static let defaultPlayerURL = URL(string: "https://open.spotify.com/")!

    public private(set) var state: AuthState = .restoringSession
    public private(set) var savedAccounts: [StoredAccountSession] = []
    public private(set) var currentAccount: StoredAccountSession?
    public var isLoginSheetPresented: Bool = false
    public var pendingAuthCallbackURL: URL?

    private let keychain: KeychainStore
    public var onSessionActivated: ((StoredAccountSession) async -> Void)?
    public var onSessionCleared: (() async -> Void)?

    public init(keychain: KeychainStore = .shared) {
        self.keychain = keychain
    }

    // MARK: - Startup Restoration

    public func restoreSessionOnLaunch() async {
        DiagnosticLogbook.shared.log("auth", "Restoring session from Keychain")
        let accounts = await keychain.loadAllAccounts()
        savedAccounts = accounts

        guard let active = await keychain.activeAccount() else {
            state = .unauthenticated()
            DiagnosticLogbook.shared.log("auth", "No stored session found")
            return
        }

        guard active.hasValidAuthCookie else {
            DiagnosticLogbook.shared.log("auth", "Stored sp_dc cookie missing or expired for \(active.displayName)")
            currentAccount = active
            state = .sessionExpired(reason: "Your Spotify session expired. Please sign in again to continue listening.")
            return
        }

        currentAccount = active
        state = .bootstrappingPlayer
        await injectCookiesIntoWebKit(active.cookies)
        await onSessionActivated?(active)
        state = .authenticated(accountID: active.id, displayName: active.displayName)
        DiagnosticLogbook.shared.log("auth", "Session restored for \(active.displayName)")
    }

    // MARK: - Login Flow

    public func beginSignIn() {
        state = .signingIn
        isLoginSheetPresented = true
        DiagnosticLogbook.shared.log("auth", "Presenting coherent WebKit Spotify login sheet")
    }

    public func cancelSignIn() {
        isLoginSheetPresented = false
        if let active = currentAccount, active.hasValidAuthCookie {
            state = .authenticated(accountID: active.id, displayName: active.displayName)
        } else {
            state = .unauthenticated()
        }
    }

    /// Handles an incoming magic-link or OAuth callback URL without resetting the active WebView state.
    public func handleIncomingAuthURL(_ url: URL) {
        DiagnosticLogbook.shared.log("auth", "Routing auth callback URL into login WebView: \(url.host ?? "")")
        pendingAuthCallbackURL = url
        if !isLoginSheetPresented {
            isLoginSheetPresented = true
            state = .signingIn
        }
    }

    /// Invoked by `SpotifyLoginWebView` as soon as `WKHTTPCookieStore` receives a non-empty `sp_dc` cookie.
    public func completeLoginWithCookies(_ httpCookies: [HTTPCookie], finalURL: URL?) async {
        let spotifyCookies = httpCookies
            .filter { $0.domain.contains("spotify.com") }
            .map(StoredSessionCookie.from)

        guard spotifyCookies.contains(where: { $0.name == "sp_dc" && !$0.value.isEmpty }) else {
            DiagnosticLogbook.shared.log("auth", "Login callback fired without sp_dc cookie; ignoring")
            return
        }

        isLoginSheetPresented = false
        pendingAuthCallbackURL = nil
        state = .bootstrappingPlayer

        let localizedURL: String? = {
            guard let finalURL,
                  finalURL.host == "open.spotify.com",
                  finalURL.path.hasPrefix("/intl-") else { return nil }
            let firstSeg = finalURL.pathComponents.first(where: { $0.hasPrefix("intl-") })
            return firstSeg.map { "https://open.spotify.com/\($0)/" }
        }()

        // Derive deterministic initial session ID from sp_dc SHA prefix until profileAttributes resolves username
        let spDcValue = spotifyCookies.first(where: { $0.name == "sp_dc" })?.value ?? UUID().uuidString
        let provisionalID = currentAccount?.id ?? "acct-\(abs(spDcValue.hashValue))"
        let session = StoredAccountSession(
            id: provisionalID,
            displayName: currentAccount?.displayName ?? "Spotify Listener",
            avatarURL: currentAccount?.avatarURL,
            product: currentAccount?.product,
            localizedPlayerURL: localizedURL ?? currentAccount?.localizedPlayerURL,
            cookies: spotifyCookies,
            webToken: nil,
            clientToken: nil,
            updatedAt: Date()
        )

        do {
            try await keychain.saveAccount(session, makeActive: true)
            savedAccounts = await keychain.loadAllAccounts()
            currentAccount = session
            await injectCookiesIntoWebKit(spotifyCookies)
            await onSessionActivated?(session)
            state = .authenticated(accountID: session.id, displayName: session.displayName)
            DiagnosticLogbook.shared.log("auth", "Authenticated and persisted cookies to Keychain")
        } catch {
            DiagnosticLogbook.shared.log("auth", "Keychain save failed: \(error.localizedDescription)")
            state = .unauthenticated(message: "Could not securely store your session in Keychain.")
        }
    }

    /// Enriches the stored account profile once `profileAttributes` & `accountAttributes` return.
    public func updateAccountProfile(_ profile: UserProfile) async {
        guard var current = currentAccount else { return }
        let oldID = current.id
        let resolvedID = profile.username.isEmpty ? oldID : profile.username
        let updated = StoredAccountSession(
            id: resolvedID,
            displayName: profile.name.isEmpty ? resolvedID : profile.name,
            avatarURL: profile.images.largestURL,
            product: profile.product,
            localizedPlayerURL: current.localizedPlayerURL,
            cookies: current.cookies,
            webToken: current.webToken,
            clientToken: current.clientToken,
            updatedAt: Date()
        )
        if oldID != resolvedID {
            try? await keychain.removeAccount(id: oldID)
        }
        try? await keychain.saveAccount(updated, makeActive: true)
        savedAccounts = await keychain.loadAllAccounts()
        currentAccount = updated
        if state.isAuthenticated {
            state = .authenticated(accountID: updated.id, displayName: updated.displayName)
        }
    }

    public func markSessionExpired(reason: String) {
        DiagnosticLogbook.shared.log("auth", "Session marked expired: \(reason)")
        state = .sessionExpired(reason: reason)
    }

    /// Validates and normalizes a Spotify login magic link (`accounts.spotify.com` or `wl.spotify.com`), rejecting unsafe schemes.
    public nonisolated func normalizeMagicLink(_ url: URL) -> URL? {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              (host == "accounts.spotify.com" || host == "wl.spotify.com" || host.hasSuffix(".spotify.com")) else {
            return nil
        }
        // Only treat login/magic-link hosts as auth links (catalog open.spotify.com links go to AppRouter)
        if host == "open.spotify.com" && !url.path.contains("login") {
            return nil
        }
        return url
    }

    /// Fallback manual `sp_dc` cookie import for environments where embedded OAuth is blocked.
    public func importManualSpDcCookie(_ rawInput: String) async {
        var cleaned = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = cleaned.range(of: "sp_dc=") {
            cleaned = String(cleaned[range.upperBound...])
            if let semi = cleaned.firstIndex(of: ";") {
                cleaned = String(cleaned[..<semi])
            }
        }
        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "\"' \t\r\n"))
        guard cleaned.count >= 20, !cleaned.contains(where: \.isWhitespace) else {
            state = .unauthenticated(message: "Invalid sp_dc cookie format.")
            return
        }

        let storedCookie = StoredSessionCookie(
            name: "sp_dc",
            value: cleaned,
            domain: ".spotify.com",
            path: "/",
            expiresDate: Date().addingTimeInterval(365 * 24 * 3600),
            isSecure: true,
            isHTTPOnly: true
        )
        guard let httpCookie = storedCookie.toHTTPCookie() else {
            state = .unauthenticated(message: "Could not construct HTTP session cookie.")
            return
        }
        await completeLoginWithCookies([httpCookie], finalURL: Self.defaultPlayerURL)
    }

    // MARK: - Logout & Multi-Account Switching

    public func switchToAccount(_ account: StoredAccountSession) async {
        guard account.id != currentAccount?.id else { return }
        DiagnosticLogbook.shared.log("auth", "Switching active account to \(account.displayName)")
        state = .bootstrappingPlayer
        await onSessionCleared?()
        await purgeWebKitDataStore()
        try? await keychain.setActiveAccountID(account.id)
        currentAccount = account
        await injectCookiesIntoWebKit(account.cookies)
        await onSessionActivated?(account)
        state = .authenticated(accountID: account.id, displayName: account.displayName)
    }

    public func addAnotherAccount() async {
        await purgeWebKitDataStore()
        currentAccount = nil
        beginSignIn()
    }

    public func logoutCurrentAccount() async {
        let removingID = currentAccount?.id
        DiagnosticLogbook.shared.log("auth", "Logging out account \(removingID ?? "current")")
        await onSessionCleared?()
        await purgeWebKitDataStore()

        if let removingID {
            try? await keychain.removeAccount(id: removingID)
        } else {
            try? await keychain.clearAllSessions()
        }

        savedAccounts = await keychain.loadAllAccounts()
        if let next = await keychain.activeAccount(), next.hasValidAuthCookie {
            currentAccount = next
            await injectCookiesIntoWebKit(next.cookies)
            await onSessionActivated?(next)
            state = .authenticated(accountID: next.id, displayName: next.displayName)
        } else {
            currentAccount = nil
            state = .unauthenticated()
        }
    }

    // MARK: - WebKit Cookie Store Sync

    private func injectCookiesIntoWebKit(_ cookies: [StoredSessionCookie]) async {
        let store = WKWebsiteDataStore.default().httpCookieStore
        for stored in cookies {
            if let httpCookie = stored.toHTTPCookie() {
                await store.setCookie(httpCookie)
                HTTPCookieStorage.shared.setCookie(httpCookie)
            }
        }
    }

    private func purgeWebKitDataStore() async {
        let dataStore = WKWebsiteDataStore.default()
        let allTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await dataStore.dataRecords(ofTypes: allTypes)
        await dataStore.removeData(ofTypes: allTypes, for: records)
        let cookies = await dataStore.httpCookieStore.allCookies()
        for cookie in cookies {
            await dataStore.httpCookieStore.deleteCookie(cookie)
        }
        HTTPCookieStorage.shared.cookies?.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
    }
}

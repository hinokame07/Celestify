//
//  SpotifyTokenCoordinator.swift
//  Celestify
//
//  Single-flight Swift actor managing Spotify Web Player access tokens and
//  client-tokens, verifying clientId/appVersion rotation, and performing
//  automatic refresh-and-retry on HTTP 401/403 token expiration.
//  Built on Myspoti (https://github.com/kota-zo/myspoti), GPL-3.0.
//

import Foundation

public struct SpotifyAuthHeaders: Sendable {
    public let authorization: String
    public let clientToken: String
    public let appVersion: String
}

public protocol WebTokenBridgeSource: Sendable {
    func fetchBridgeWebToken() async throws -> StoredWebToken
}

public actor SpotifyTokenCoordinator {
    private let http: HTTPClient
    private let keychain: KeychainStore
    private var bridgeSource: (any WebTokenBridgeSource)?

    private var cachedWebToken: StoredWebToken?
    private var cachedClientToken: StoredClientToken?
    private var inFlightWebTokenTask: Task<StoredWebToken, Error>?
    private var inFlightClientTokenTask: Task<StoredClientToken, Error>?

    public static let defaultWebClientID = "d8a5ed958d274c2e8ee717e6a4b0971d"
    public static let fallbackAppVersion = "1.3.6.1874.g61b9bcdb1ef2"

    public init(http: HTTPClient = .shared, keychain: KeychainStore = .shared) {
        self.http = http
        self.keychain = keychain
    }

    public func attachBridge(_ bridge: any WebTokenBridgeSource) {
        self.bridgeSource = bridge
    }

    public func invalidateTokens() {
        cachedWebToken = nil
        cachedClientToken = nil
        inFlightWebTokenTask?.cancel()
        inFlightWebTokenTask = nil
        inFlightClientTokenTask?.cancel()
        inFlightClientTokenTask = nil
    }

    public func invalidateWebTokenOnly() {
        cachedWebToken = nil
        inFlightWebTokenTask?.cancel()
        inFlightWebTokenTask = nil
    }

    // MARK: - Authenticated Spotify HTTP Calls with Automatic 401 Retry

    public func sendAuthenticated(
        method: String = "GET",
        url: URL,
        accept: String = "application/json",
        contentType: String? = "application/json",
        extraHeaders: [String: String] = [:],
        body: Data? = nil,
        allowRetryOnAuthFailure: Bool = true
    ) async throws -> HTTPResponse {
        let auth = try await validHeaders(forceRefresh: false)
        var headers = buildHeaders(from: auth, accept: accept, contentType: contentType, extra: extraHeaders)
        let first = try await http.send(method: method, url: url, headers: headers, body: body)

        if allowRetryOnAuthFailure && (first.statusCode == 401 || (first.statusCode == 400 && first.text.contains("client-token"))) {
            DiagnosticLogbook.shared.log("token", "HTTP \(first.statusCode) from \(url.host ?? "spotify") — refreshing tokens once and retrying")
            if first.statusCode == 401 {
                invalidateWebTokenOnly()
            } else {
                invalidateTokens()
            }
            let refreshed = try await validHeaders(forceRefresh: true)
            headers = buildHeaders(from: refreshed, accept: accept, contentType: contentType, extra: extraHeaders)
            return try await http.send(method: method, url: url, headers: headers, body: body)
        }

        return first
    }

    public func getAuthenticatedJSON(url: URL, accept: String = "application/json") async throws -> JSONValue {
        let response = try await sendAuthenticated(method: "GET", url: url, accept: accept, contentType: nil)
        guard (200...299).contains(response.statusCode) else {
            throw HTTPError.badStatus(
                code: response.statusCode,
                bodySnippet: String(response.text.prefix(180)),
                retryAfterSeconds: response.retryAfterSeconds
            )
        }
        return JSONValue.parse(response.data) ?? .null
    }

    // MARK: - Header & Token Resolution

    public func validHeaders(forceRefresh: Bool = false) async throws -> SpotifyAuthHeaders {
        let web = try await resolveWebToken(forceRefresh: forceRefresh)
        let client = try await resolveClientToken(
            clientID: web.clientID,
            appVersion: web.appVersion,
            forceRefresh: forceRefresh
        )
        return SpotifyAuthHeaders(
            authorization: "Bearer \(web.accessToken)",
            clientToken: client.token,
            appVersion: web.appVersion
        )
    }

    private func resolveWebToken(forceRefresh: Bool) async throws -> StoredWebToken {
        if !forceRefresh, let cached = cachedWebToken, cached.isValid() {
            return cached
        }
        if !forceRefresh, let active = await keychain.activeAccount()?.webToken, active.isValid() {
            cachedWebToken = active
            return active
        }
        if let existingTask = inFlightWebTokenTask {
            return try await existingTask.value
        }

        let task = Task<StoredWebToken, Error> {
            // 1. Prefer live WebPlayer bridge TokenProvider (identical to Android Myspoti)
            if let bridgeSource {
                if let bridgeToken = try? await bridgeSource.fetchBridgeWebToken(), bridgeToken.isValid() {
                    return bridgeToken
                }
            }
            // 2. Direct fallback using stored sp_dc session cookie against open.spotify.com
            return try await fetchWebTokenFromCookies()
        }
        inFlightWebTokenTask = task
        defer { inFlightWebTokenTask = nil }

        let fresh = try await task.value
        cachedWebToken = fresh
        if var account = await keychain.activeAccount() {
            account.webToken = fresh
            try? await keychain.saveAccount(account, makeActive: false)
        }
        return fresh
    }

    private func fetchWebTokenFromCookies() async throws -> StoredWebToken {
        guard let account = await keychain.activeAccount(), account.hasValidAuthCookie else {
            throw HTTPError.badStatus(code: 401, bodySnippet: "Not signed in to Spotify", retryAfterSeconds: nil)
        }
        let cookieHeader = account.cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        let url = URL(string: "https://open.spotify.com/get_access_token?reason=transport&productType=web-player")!
        let res = try await http.send(
            method: "GET",
            url: url,
            headers: [
                "Cookie": cookieHeader,
                "Accept": "application/json",
                "App-Platform": "WebPlayer"
            ]
        )
        guard (200...299).contains(res.statusCode),
              let json = JSONValue.parse(res.data),
              let token = json.str("accessToken"),
              !token.isEmpty else {
            throw HTTPError.badStatus(code: res.statusCode, bodySnippet: "Could not acquire web access token", retryAfterSeconds: nil)
        }
        let expMs = json.int64("accessTokenExpirationTimestampMs")
            ?? Int64(Date().addingTimeInterval(3300).timeIntervalSince1970 * 1000)
        let clientID = json.str("clientId") ?? Self.defaultWebClientID
        return StoredWebToken(
            accessToken: token,
            expiresAtMs: expMs,
            clientID: clientID,
            appVersion: Self.fallbackAppVersion
        )
    }

    private func resolveClientToken(
        clientID: String,
        appVersion: String,
        forceRefresh: Bool
    ) async throws -> StoredClientToken {
        if !forceRefresh,
           let cached = cachedClientToken,
           cached.isValid(forClientID: clientID, appVersion: appVersion) {
            return cached
        }
        if !forceRefresh,
           let stored = await keychain.activeAccount()?.clientToken,
           stored.isValid(forClientID: clientID, appVersion: appVersion) {
            cachedClientToken = stored
            return stored
        }
        if let existingTask = inFlightClientTokenTask {
            return try await existingTask.value
        }

        let task = Task<StoredClientToken, Error> {
            let deviceID = try await keychain.deviceID()
            let payload: JSONValue = .object([
                "client_data": .object([
                    "client_version": .string(appVersion),
                    "client_id": .string(clientID),
                    "js_sdk_data": .object([
                        "device_brand": .string("Apple"),
                        "device_model": .string("iPhone"),
                        "os": .string("iOS"),
                        "os_version": .string("18.0"),
                        "device_id": .string(deviceID),
                        "device_type": .string("smartphone")
                    ])
                ])
            ])
            let url = URL(string: "https://clienttoken.spotify.com/v1/clienttoken")!
            let res = try await http.send(
                method: "POST",
                url: url,
                headers: [
                    "Accept": "application/json",
                    "Content-Type": "application/json"
                ],
                body: payload.serializedData()
            )
            guard (200...299).contains(res.statusCode),
                  let json = JSONValue.parse(res.data),
                  let token = json.str("granted_token.token"),
                  !token.isEmpty else {
                throw HTTPError.badStatus(code: res.statusCode, bodySnippet: "Client token rejected", retryAfterSeconds: nil)
            }
            let ttlSec = json.int64("granted_token.refresh_after_seconds")
                ?? json.int64("granted_token.expires_after_seconds")
                ?? 1_209_600
            let expiresAtMs = Int64(Date().timeIntervalSince1970 * 1000) + ttlSec * 1000
            return StoredClientToken(
                token: token,
                expiresAtMs: expiresAtMs,
                clientID: clientID,
                appVersion: appVersion
            )
        }
        inFlightClientTokenTask = task
        defer { inFlightClientTokenTask = nil }

        let fresh = try await task.value
        cachedClientToken = fresh
        if var account = await keychain.activeAccount() {
            account.clientToken = fresh
            try? await keychain.saveAccount(account, makeActive: false)
        }
        return fresh
    }

    private func buildHeaders(
        from auth: SpotifyAuthHeaders,
        accept: String,
        contentType: String?,
        extra: [String: String]
    ) -> [String: String] {
        var out: [String: String] = [
            "Authorization": auth.authorization,
            "client-token": auth.clientToken,
            "Accept": accept,
            "app-platform": "WebPlayer",
            "spotify-app-version": auth.appVersion,
            "Accept-Language": Locale.preferredLanguages.first ?? "en-US"
        ]
        if let contentType {
            out["Content-Type"] = contentType
        }
        for (k, v) in extra { out[k] = v }
        return out
    }
}

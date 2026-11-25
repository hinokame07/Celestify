//
//  KeychainStore.swift
//  Celestify
//
//  Secure Apple Keychain storage for Spotify session cookies, tokens, device ID,
//  and multi-account switching. Zero credentials are ever written to UserDefaults.
//  Built on Myspoti (https://github.com/kota-zo/myspoti), GPL-3.0.
//

import Foundation
import Security

public struct StoredSessionCookie: Codable, Sendable, Equatable, Hashable {
    public let name: String
    public let value: String
    public let domain: String
    public let path: String
    public let expiresDate: Date?
    public let isSecure: Bool
    public let isHTTPOnly: Bool

    public init(
        name: String,
        value: String,
        domain: String,
        path: String = "/",
        expiresDate: Date? = nil,
        isSecure: Bool = true,
        isHTTPOnly: Bool = true
    ) {
        self.name = name
        self.value = value
        self.domain = domain
        self.path = path
        self.expiresDate = expiresDate
        self.isSecure = isSecure
        self.isHTTPOnly = isHTTPOnly
    }

    public func toHTTPCookie() -> HTTPCookie? {
        var props: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: domain,
            .path: path
        ]
        if isSecure { props[.secure] = "TRUE" }
        if isHTTPOnly { props[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
        if let expiresDate { props[.expires] = expiresDate }
        return HTTPCookie(properties: props)
    }

    public static func from(_ cookie: HTTPCookie) -> StoredSessionCookie {
        StoredSessionCookie(
            name: cookie.name,
            value: cookie.value,
            domain: cookie.domain,
            path: cookie.path,
            expiresDate: cookie.expiresDate,
            isSecure: cookie.isSecure,
            isHTTPOnly: cookie.isHTTPOnly
        )
    }
}

public struct StoredWebToken: Codable, Sendable, Equatable {
    public let accessToken: String
    public let expiresAtMs: Int64
    public let clientID: String
    public let appVersion: String

    public init(accessToken: String, expiresAtMs: Int64, clientID: String, appVersion: String) {
        self.accessToken = accessToken
        self.expiresAtMs = expiresAtMs
        self.clientID = clientID
        self.appVersion = appVersion
    }

    public func isValid(nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000), safetyMarginMs: Int64 = 60_000) -> Bool {
        !accessToken.isEmpty && expiresAtMs - safetyMarginMs > nowMs
    }
}

public struct StoredClientToken: Codable, Sendable, Equatable {
    public let token: String
    public let expiresAtMs: Int64
    public let clientID: String
    public let appVersion: String

    public init(token: String, expiresAtMs: Int64, clientID: String, appVersion: String) {
        self.token = token
        self.expiresAtMs = expiresAtMs
        self.clientID = clientID
        self.appVersion = appVersion
    }

    public func isValid(
        forClientID expectedClientID: String,
        appVersion expectedVersion: String,
        nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        safetyMarginMs: Int64 = 60_000
    ) -> Bool {
        !token.isEmpty
            && clientID == expectedClientID
            && appVersion == expectedVersion
            && expiresAtMs - safetyMarginMs > nowMs
    }
}

public struct StoredAccountSession: Codable, Sendable, Equatable, Identifiable {
    public let id: String          // Spotify username or stable session UUID
    public var displayName: String
    public var avatarURL: String?
    public var product: String?
    public var localizedPlayerURL: String?
    public var cookies: [StoredSessionCookie]
    public var webToken: StoredWebToken?
    public var clientToken: StoredClientToken?
    public var updatedAt: Date

    public init(
        id: String,
        displayName: String,
        avatarURL: String? = nil,
        product: String? = nil,
        localizedPlayerURL: String? = nil,
        cookies: [StoredSessionCookie],
        webToken: StoredWebToken? = nil,
        clientToken: StoredClientToken? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.product = product
        self.localizedPlayerURL = localizedPlayerURL
        self.cookies = cookies
        self.webToken = webToken
        self.clientToken = clientToken
        self.updatedAt = updatedAt
    }

    public var hasValidAuthCookie: Bool {
        let now = Date()
        return cookies.contains { cookie in
            cookie.name == "sp_dc"
                && !cookie.value.isEmpty
                && (cookie.expiresDate == nil || cookie.expiresDate! > now)
        }
    }
}

public enum KeychainError: Error, LocalizedError, Sendable {
    case unexpectedStatus(OSStatus)
    case encodingFailed
    case decodingFailed

    public var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status): return "Keychain status \(status)"
        case .encodingFailed: return "Failed to encode Keychain payload"
        case .decodingFailed: return "Failed to decode Keychain payload"
        }
    }
}

/// Thread-safe Apple Keychain store with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
public actor KeychainStore {
    public static let shared = KeychainStore()

    private let service: String
    private let inMemoryForTesting: Bool
    private var memoryVault: [String: Data] = [:]
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(service: String = "app.celestify.ios.keychain", inMemoryForTesting: Bool = false) {
        self.service = service
        self.inMemoryForTesting = inMemoryForTesting
    }

    // MARK: - Generic Raw Operations

    public func writeData(_ data: Data, forKey key: String) throws {
        if inMemoryForTesting {
            memoryVault[key] = data
            return
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess {
            let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(updateStatus)
            }
        } else if status == errSecItemNotFound {
            var insert = query
            for (k, v) in attributes { insert[k] = v }
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(addStatus)
            }
        } else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    public func readData(forKey key: String) throws -> Data? {
        if inMemoryForTesting {
            return memoryVault[key]
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
        return item as? Data
    }

    public func delete(forKey key: String) throws {
        if inMemoryForTesting {
            memoryVault.removeValue(forKey: key)
            return
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    public func writeCodable<T: Codable>(_ value: T, forKey key: String) throws {
        guard let data = try? encoder.encode(value) else {
            throw KeychainError.encodingFailed
        }
        try writeData(data, forKey: key)
    }

    public func readCodable<T: Codable>(_ type: T.Type, forKey key: String) throws -> T? {
        guard let data = try readData(forKey: key) else { return nil }
        guard let decoded = try? decoder.decode(type, from: data) else {
            throw KeychainError.decodingFailed
        }
        return decoded
    }

    // MARK: - Device ID & Multi-Account Session Helpers

    private enum Keys {
        static let deviceID = "spotify.device_id"
        static let activeAccountID = "spotify.active_account_id"
        static let accountsList = "spotify.accounts.v1"
        static let offlineMasterKey = "offline.aes_master_key.v1"
    }

    public func deviceID() throws -> String {
        if let existing = try readData(forKey: Keys.deviceID),
           let str = String(data: existing, encoding: .utf8),
           str.count == 32 {
            return str
        }
        let fresh = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        try writeData(Data(fresh.utf8), forKey: Keys.deviceID)
        return fresh
    }

    public func loadAllAccounts() -> [StoredAccountSession] {
        (try? readCodable([StoredAccountSession].self, forKey: Keys.accountsList)) ?? []
    }

    public func activeAccount() -> StoredAccountSession? {
        let all = loadAllAccounts()
        if let activeData = try? readData(forKey: Keys.activeAccountID),
           let activeID = String(data: activeData, encoding: .utf8),
           let matched = all.first(where: { $0.id == activeID }) {
            return matched
        }
        return all.first
    }

    public func saveAccount(_ session: StoredAccountSession, makeActive: Bool = true) throws {
        var all = loadAllAccounts()
        if let index = all.firstIndex(where: { $0.id == session.id }) {
            all[index] = session
        } else {
            all.append(session)
        }
        try writeCodable(all, forKey: Keys.accountsList)
        if makeActive {
            try writeData(Data(session.id.utf8), forKey: Keys.activeAccountID)
        }
    }

    public func setActiveAccountID(_ id: String) throws {
        try writeData(Data(id.utf8), forKey: Keys.activeAccountID)
    }

    public func removeAccount(id: String) throws {
        var all = loadAllAccounts()
        all.removeAll { $0.id == id }
        try writeCodable(all, forKey: Keys.accountsList)
        if let next = all.first {
            try writeData(Data(next.id.utf8), forKey: Keys.activeAccountID)
        } else {
            try delete(forKey: Keys.activeAccountID)
        }
    }

    public func clearAllSessions() throws {
        try delete(forKey: Keys.accountsList)
        try delete(forKey: Keys.activeAccountID)
    }

    public func loadOrCreateOfflineMasterKey() throws -> Data {
        if let existing = try readData(forKey: Keys.offlineMasterKey), existing.count == 32 {
            return existing
        }
        var keyBytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, keyBytes.count, &keyBytes)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
        let data = Data(keyBytes)
        try writeData(data, forKey: Keys.offlineMasterKey)
        return data
    }
}

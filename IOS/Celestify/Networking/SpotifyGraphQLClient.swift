//
//  SpotifyGraphQLClient.swift
//  Celestify
//
//  Spotify Pathfinder v2 persisted GraphQL client with bundled gql-ops.json,
//  live bundle hash updater (port of GqlOpsUpdater.kt), and BridgeGql read fallback.
//  Built on Myspoti (https://github.com/kota-zo/myspoti), GPL-3.0.
//

import CryptoKit
import Foundation

public enum GraphQLError: Error, LocalizedError, Sendable {
    case unknownOperation(String)
    case serverErrors(operation: String, message: String)
    case entityNotFound(operation: String, path: String)

    public var errorDescription: String? {
        switch self {
        case .unknownOperation(let op): return "Unknown GraphQL operation '\(op)'"
        case .serverErrors(let op, let msg): return "\(op): \(msg)"
        case .entityNotFound(let op, let path): return "\(op): missing \(path)"
        }
    }
}

public struct PersistedOperation: Codable, Sendable {
    public let name: String
    public let kind: String
    public let hash: String
}

public actor SpotifyGraphQLClient {
    private static let endpoint = URL(string: "https://api-partner.spotify.com/pathfinder/v2/query")!

    private let tokens: SpotifyTokenCoordinator
    private let http: HTTPClient
    private var operations: [String: PersistedOperation] = [:]
    private var bridgeFallback: SpotifyWebPlayerBridge?
    private var attemptedHashRefresh = false

    public init(tokens: SpotifyTokenCoordinator, http: HTTPClient = .shared) {
        self.tokens = tokens
        self.http = http
        self.operations = Self.loadOperationsTable()
    }

    public func attachBridge(_ bridge: SpotifyWebPlayerBridge) {
        self.bridgeFallback = bridge
    }

    public func query(_ operationName: String, variables: [String: JSONValue] = [:]) async throws -> JSONValue {
        guard let op = operations[operationName] else {
            DiagnosticLogbook.shared.log("gql", "Operation unavailable: \(operationName)")
            throw GraphQLError.unknownOperation(operationName)
        }
        let isMutation = op.kind == "mutation"
        DiagnosticLogbook.shared.log("gql", "Starting \(operationName)")

        do {
            let result = try await executeHTTP(op: op, variables: variables)
            DiagnosticLogbook.shared.log("gql", "Completed \(operationName)")
            return result
        } catch let error as HTTPError {
            // If Spotify rotated a persisted query hash, refresh once from open.spotify.com bundles
            if case .badStatus(let code, let snippet, _) = error {
                if (snippet.contains("PersistedQueryNotFound") || code == 400) && !attemptedHashRefresh {
                    attemptedHashRefresh = true
                    DiagnosticLogbook.shared.log("gql", "\(operationName) persisted query may be stale; checking bundled hashes")
                    if let updated = try? await refreshOperationHashesFromWebBundles(),
                       let refreshedOp = updated[operationName] {
                        self.operations = updated
                        do {
                            let result = try await executeHTTP(op: refreshedOp, variables: variables)
                            DiagnosticLogbook.shared.log("gql", "Completed \(operationName) with refreshed persisted-query hash")
                            return result
                        } catch {
                            DiagnosticLogbook.shared.log(
                                "gql",
                                "\(operationName) retry with refreshed hash failed (\(String(describing: type(of: error))))"
                            )
                            throw error
                        }
                    }
                    DiagnosticLogbook.shared.log("gql", "No refreshed hash available for \(operationName)")
                }
                // Non-mutation read queries may safely fall back to the page's GraphQL loader
                if !isMutation, (400..<500).contains(code), let bridge = bridgeFallback {
                    DiagnosticLogbook.shared.log("gql", "\(operationName) HTTP \(code); trying Web Player GraphQL fallback")
                    do {
                        let result = try await executeViaBridge(bridge: bridge, op: op, variables: variables)
                        DiagnosticLogbook.shared.log("gql", "Completed \(operationName) through Web Player fallback")
                        return result
                    } catch {
                        DiagnosticLogbook.shared.log("gql", "\(operationName) fallback failed (\(String(describing: type(of: error))))")
                        throw error
                    }
                }
                DiagnosticLogbook.shared.log("gql", "\(operationName) HTTP request failed with status \(code)")
            }
            throw error
        } catch {
            DiagnosticLogbook.shared.log("gql", "\(operationName) failed (\(String(describing: type(of: error))))")
            throw error
        }
    }

    private func executeHTTP(op: PersistedOperation, variables: [String: JSONValue]) async throws -> JSONValue {
        let body: JSONValue = .object([
            "variables": .object(variables),
            "operationName": .string(op.name),
            "extensions": .object([
                "persistedQuery": .object([
                    "version": .int(1),
                    "sha256Hash": .string(op.hash)
                ])
            ])
        ])
        let res = try await tokens.sendAuthenticated(
            method: "POST",
            url: Self.endpoint,
            body: body.serializedData(),
            allowRetryOnAuthFailure: !op.kind.elementsEqual("mutation")
        )
        guard (200...299).contains(res.statusCode) else {
            throw HTTPError.badStatus(
                code: res.statusCode,
                bodySnippet: String(res.text.prefix(200)),
                retryAfterSeconds: res.retryAfterSeconds
            )
        }
        guard let json = JSONValue.parse(res.data) else {
            throw GraphQLError.serverErrors(operation: op.name, message: "Invalid JSON")
        }
        if json.at("data") == nil, let firstErr = json.list("errors").first?.str("message") {
            if firstErr.contains("PersistedQueryNotFound") {
                throw HTTPError.badStatus(code: 400, bodySnippet: firstErr, retryAfterSeconds: nil)
            }
            throw GraphQLError.serverErrors(operation: op.name, message: firstErr)
        }
        return json
    }

    private func executeViaBridge(
        bridge: SpotifyWebPlayerBridge,
        op: PersistedOperation,
        variables: [String: JSONValue]
    ) async throws -> JSONValue {
        let args: JSONValue = .object([
            "name": .string(op.name),
            "operation": .string(op.kind),
            "hash": .string(op.hash),
            "variables": .object(variables)
        ])
        let raw = try await bridge.call("gql.query", args: args)
        if raw.at("data") != nil {
            return raw
        }
        return .object(["data": raw])
    }

    // MARK: - Bundled & Cached Operation Table

    public static func loadOperationsTable() -> [String: PersistedOperation] {
        if let cacheURL = cachedOpsFileURL(),
           let data = try? Data(contentsOf: cacheURL),
           let parsed = parseOpsJSON(data),
           !parsed.isEmpty {
            return parsed
        }
        let bundleURL = Bundle.main.url(forResource: "gql-ops", withExtension: "json", subdirectory: "Spotify")
            ?? Bundle.main.url(forResource: "gql-ops", withExtension: "json")
        if let bundleURL,
           let data = try? Data(contentsOf: bundleURL),
           let parsed = parseOpsJSON(data) {
            return parsed
        }
        return [:]
    }

    public static func parseOpsJSON(_ data: Data) -> [String: PersistedOperation]? {
        guard let root = JSONValue.parse(data),
              let opsDict = root.obj("operations") else { return nil }
        var table: [String: PersistedOperation] = [:]
        for (name, val) in opsDict {
            if let hash = val.str("hash"), !hash.isEmpty {
                let kind = val.str("kind") ?? "query"
                table[name] = PersistedOperation(name: name, kind: kind, hash: hash)
            }
        }
        return table
    }

    private static func cachedOpsFileURL() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("spotify-gql-ops-cache.json")
    }

    // MARK: - Live Bundle Hash Updater (Port of GqlOpsUpdater.kt)

    private func refreshOperationHashesFromWebBundles() async throws -> [String: PersistedOperation]? {
        DiagnosticLogbook.shared.log("gql", "Checking open.spotify.com JS bundles for updated persisted query hashes")
        let htmlRes = try await http.send(url: SpotifyAuthManager.defaultPlayerURL)
        let html = htmlRes.text
        let bundlePattern = #"https://open\.spotifycdn\.com/cdn/build/web-player/[^"']+?\.js"#
        guard let bundleRegex = try? NSRegularExpression(pattern: bundlePattern) else { return nil }
        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
        var urls: [URL] = []
        var seen = Set<String>()
        for match in bundleRegex.matches(in: html, range: nsRange) {
            if let r = Range(match.range, in: html) {
                let str = String(html[r])
                if seen.insert(str).inserted, let url = URL(string: str) {
                    urls.append(url)
                }
            }
        }
        guard !urls.isEmpty else { return nil }

        let opPattern = #"new [\w$]+(?:\.[\w$]+)?\("(\w+)","(query|mutation|subscription)","([0-9a-f]{64})"\)"#
        guard let opRegex = try? NSRegularExpression(pattern: opPattern) else { return nil }

        var merged = operations
        var discoveredCount = 0
        for url in urls.prefix(28) {
            guard let jsRes = try? await http.send(url: url, maxBytes: 6 * 1024 * 1024) else { continue }
            let js = jsRes.text
            let jsRange = NSRange(js.startIndex..<js.endIndex, in: js)
            for m in opRegex.matches(in: js, range: jsRange) {
                guard let nameR = Range(m.range(at: 1), in: js),
                      let kindR = Range(m.range(at: 2), in: js),
                      let hashR = Range(m.range(at: 3), in: js) else { continue }
                let name = String(js[nameR])
                let kind = String(js[kindR])
                let hash = String(js[hashR])
                merged[name] = PersistedOperation(name: name, kind: kind, hash: hash)
                discoveredCount += 1
            }
        }

        guard discoveredCount > 10 else { return nil }
        if let cacheURL = Self.cachedOpsFileURL() {
            var opsObj: [String: JSONValue] = [:]
            for (k, v) in merged {
                opsObj[k] = .object(["kind": .string(v.kind), "hash": .string(v.hash)])
            }
            let payload: JSONValue = .object(["operations": .object(opsObj)])
            try? payload.serializedData()?.write(to: cacheURL, options: .atomic)
        }
        DiagnosticLogbook.shared.log("gql", "Updated \(discoveredCount) GraphQL operation hashes from web bundles")
        return merged
    }
}

public extension JSONValue {
    func entity(_ path: String, operation: String) throws -> JSONValue {
        guard let node = at(path) else {
            throw GraphQLError.entityNotFound(operation: operation, path: path)
        }
        if node.typename() == "NotFound" {
            throw GraphQLError.entityNotFound(operation: operation, path: path)
        }
        return node
    }
}

//
//  HTTPClient.swift
//  Celestify
//
//  Async/await URLSession HTTP transport with byte-size limits, rate-limit
//  Retry-After extraction, and structured error reporting.
//  Built on Myspoti (https://github.com/kota-zo/myspoti), GPL-3.0.
//

import Foundation

public enum HTTPError: Error, LocalizedError, Sendable, Equatable {
    case invalidURL(String)
    case badStatus(code: Int, bodySnippet: String, retryAfterSeconds: Int?)
    case payloadTooLarge(limitBytes: Int)
    case transportError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let raw):
            return "Invalid URL: \(raw)"
        case .badStatus(let code, let snippet, _):
            return snippet.isEmpty ? "HTTP \(code)" : "HTTP \(code): \(snippet)"
        case .payloadTooLarge(let limit):
            return "Response exceeded \(limit) bytes limit"
        case .transportError(let msg):
            return msg
        }
    }
}

public struct HTTPResponse: Sendable {
    public let statusCode: Int
    public let data: Data
    public let headers: [String: String]

    public var text: String {
        String(data: data, encoding: .utf8) ?? ""
    }

    public var retryAfterSeconds: Int? {
        guard let raw = headers.first(where: { $0.key.lowercased() == "retry-after" })?.value else {
            return nil
        }
        return Int(raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

public actor HTTPClient {
    public static let shared = HTTPClient()

    private let session: URLSession
    public static let webPlayerUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    public init(timeoutSeconds: TimeInterval = 20) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeoutSeconds
        config.timeoutIntervalForResource = timeoutSeconds * 1.5
        config.httpShouldSetCookies = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: config)
    }

    public func send(
        method: String = "GET",
        url: URL,
        headers: [String: String] = [:],
        body: Data? = nil,
        maxBytes: Int = 8 * 1024 * 1024
    ) async throws -> HTTPResponse {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        for (k, v) in headers {
            request.setValue(v, forHTTPHeaderField: k)
        }
        if request.value(forHTTPHeaderField: "User-Agent") == nil {
            request.setValue(Self.webPlayerUserAgent, forHTTPHeaderField: "User-Agent")
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw HTTPError.transportError(error.localizedDescription)
        }

        guard data.count <= maxBytes else {
            throw HTTPError.payloadTooLarge(limitBytes: maxBytes)
        }

        guard let http = response as? HTTPURLResponse else {
            throw HTTPError.transportError("Non-HTTP response")
        }

        var normalizedHeaders: [String: String] = [:]
        for (k, v) in http.allHeaderFields {
            normalizedHeaders[String(describing: k)] = String(describing: v)
        }

        return HTTPResponse(statusCode: http.statusCode, data: data, headers: normalizedHeaders)
    }

    public func getJSON(
        url: URL,
        headers: [String: String] = [:],
        maxBytes: Int = 4 * 1024 * 1024
    ) async throws -> JSONValue {
        let res = try await send(method: "GET", url: url, headers: headers, maxBytes: maxBytes)
        guard (200...299).contains(res.statusCode) else {
            throw HTTPError.badStatus(
                code: res.statusCode,
                bodySnippet: String(res.text.prefix(180)),
                retryAfterSeconds: res.retryAfterSeconds
            )
        }
        return JSONValue.parse(res.data) ?? .null
    }
}

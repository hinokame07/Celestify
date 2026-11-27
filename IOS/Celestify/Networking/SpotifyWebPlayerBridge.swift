//
//  SpotifyWebPlayerBridge.swift
//  Celestify
//
//  Hidden WKWebView host loading open.spotify.com and running player-bridge.js
//  to connect Celestify to Spotify's official React service registry (PlayerAPI,
//  PlaybackAPI, LibraryAPI, RootlistAPI, ConnectDevicesAPI, SocialConnectAPI, TokenProvider).
//  Built on Myspoti (https://github.com/kota-zo/myspoti), GPL-3.0.
//

import Foundation
import Observation
import UIKit
import WebKit

public enum BridgeError: Error, LocalizedError, Sendable {
    case notReady
    case timeout(method: String)
    case remoteError(method: String, message: String)
    case malformedPayload

    public var errorDescription: String? {
        switch self {
        case .notReady: return "Spotify Web Player engine is still warming up."
        case .timeout(let method): return "Timed out waiting for \(method)."
        case .remoteError(let method, let msg): return "\(method): \(msg)"
        case .malformedPayload: return "Malformed bridge message."
        }
    }
}

@Observable
@MainActor
public final class SpotifyWebPlayerBridge: NSObject, WebTokenBridgeSource {
    public private(set) var isReady: Bool = false
    public private(set) var latestState: PlayerStateSnapshot?
    public private(set) var latestQueue: PlaybackQueue = PlaybackQueue()
    public private(set) var adPlaying: Bool = false
    public private(set) var drmUnavailable: Bool = false

    public var onStateChanged: ((PlayerStateSnapshot) -> Void)?
    public var onQueueChanged: ((PlaybackQueue) -> Void)?
    public var onAdChanged: ((Bool) -> Void)?

    private var webView: WKWebView?
    private var nextCallID: Int = 1
    private var pendingCalls: [Int: CheckedContinuation<JSONValue, Error>] = [:]
    private var pendingCallTimeouts: [Int: Task<Void, Never>] = [:]
    private var playerURL: URL = SpotifyAuthManager.defaultPlayerURL

    public override init() {
        super.init()
    }

    // MARK: - Lifecycle

    public func start(localizedPlayerURL: String? = nil) {
        if let raw = localizedPlayerURL, let parsed = URL(string: raw) {
            playerURL = parsed
        } else {
            playerURL = SpotifyAuthManager.defaultPlayerURL
        }

        if webView == nil {
            setupHiddenWebView()
        }
        isReady = false
        DiagnosticLogbook.shared.log("bridge", "Loading Web Player host at \(playerURL.absoluteString)")
        webView?.load(URLRequest(url: playerURL))
    }

    public func reload() {
        DiagnosticLogbook.shared.log("bridge", "Reloading Web Player host")
        isReady = false
        if webView == nil {
            setupHiddenWebView()
        }
        webView?.load(URLRequest(url: playerURL))
    }

    public func stopAndReset() {
        DiagnosticLogbook.shared.log("bridge", "Stopping Web Player host and clearing pending RPCs")
        isReady = false
        latestState = nil
        latestQueue = PlaybackQueue()
        adPlaying = false
        webView?.stopLoading()
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "celestifyBridge")
        webView?.removeFromSuperview()
        webView = nil

        let fail = BridgeError.notReady
        for (callID, cont) in pendingCalls {
            pendingCallTimeouts.removeValue(forKey: callID)?.cancel()
            cont.resume(throwing: fail)
        }
        pendingCalls.removeAll()
        pendingCallTimeouts.removeAll()
    }

    public func waitUntilReady(timeoutSeconds: TimeInterval = 25) async throws {
        let deadline = Date().addingTimeInterval(max(0, timeoutSeconds))
        while !isReady {
            try Task.checkCancellation()
            guard Date() < deadline else {
                DiagnosticLogbook.shared.log("bridge", "Timed out waiting for Web Player readiness")
                throw BridgeError.timeout(method: "bridge.ready")
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    // MARK: - RPC Invocation

    @discardableResult
    public func call(_ method: String, args: JSONValue = .object([:]), timeoutSeconds: TimeInterval = 15) async throws -> JSONValue {
        if !isReady {
            try await waitUntilReady(timeoutSeconds: min(timeoutSeconds, 20))
        }
        guard let webView else { throw BridgeError.notReady }

        let callID = nextCallID
        nextCallID += 1
        let serializedArgs = args.serializedString() ?? "{}"
        let escapedMethod = method.replacingOccurrences(of: "'", with: "\\'")
        let js = "window.Myspoti && window.Myspoti.call(\(callID), '\(escapedMethod)', \(serializedArgs)); true;"

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<JSONValue, Error>) in
                guard !Task.isCancelled else {
                    cont.resume(throwing: CancellationError())
                    return
                }
                pendingCalls[callID] = cont
                pendingCallTimeouts[callID] = Task { @MainActor [weak self] in
                    do {
                        try await Task.sleep(nanoseconds: UInt64(max(0, timeoutSeconds) * 1_000_000_000))
                    } catch {
                        return
                    }
                    self?.finishPendingCall(
                        callID,
                        with: .failure(BridgeError.timeout(method: method))
                    )
                }
                webView.evaluateJavaScript(js) { _, error in
                    guard let error else { return }
                    Task { @MainActor in
                        self.finishPendingCall(
                            callID,
                            with: .failure(BridgeError.remoteError(method: method, message: error.localizedDescription))
                        )
                    }
                }
            }
        } onCancel: {
            Task { @MainActor in
                self.finishPendingCall(callID, with: .failure(CancellationError()))
            }
        }
    }

    private func finishPendingCall(_ callID: Int, with result: Result<JSONValue, Error>) {
        guard let continuation = pendingCalls.removeValue(forKey: callID) else { return }
        pendingCallTimeouts.removeValue(forKey: callID)?.cancel()
        continuation.resume(with: result)
    }

    @discardableResult
    public func service(_ serviceName: String, method: String, args: [JSONValue] = []) async throws -> JSONValue {
        try await call(
            "service.call",
            args: .object([
                "service": .string(serviceName),
                "method": .string(method),
                "args": .array(args)
            ])
        )
    }

    // MARK: - WebTokenBridgeSource Conformance

    nonisolated public func fetchBridgeWebToken() async throws -> StoredWebToken {
        let res = try await call("token.get", args: .object([:]), timeoutSeconds: 12)
        guard let token = res.str("accessToken"), !token.isEmpty else {
            throw BridgeError.remoteError(method: "token.get", message: "Empty accessToken from TokenProvider")
        }
        let clientID = res.str("clientId") ?? SpotifyTokenCoordinator.defaultWebClientID
        let appVersion = res.str("appVersion") ?? SpotifyTokenCoordinator.fallbackAppVersion
        let expiresAt = res.int64("expiresAtMs") ?? res.int64("expiresAt")
            ?? Int64(Date().addingTimeInterval(3000).timeIntervalSince1970 * 1000)
        return StoredWebToken(
            accessToken: token,
            expiresAtMs: expiresAt,
            clientID: clientID,
            appVersion: appVersion
        )
    }

    // MARK: - Private Setup & Script Injection

    private func setupHiddenWebView() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.defaultWebpagePreferences.preferredContentMode = .desktop
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let controller = WKUserContentController()
        let handler = WeakScriptMessageProxy(target: self)
        controller.add(handler, name: "celestifyBridge")

        if let bridgeScript = Self.loadBridgeScript() {
            let userScript = WKUserScript(
                source: bridgeScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
            controller.addUserScript(userScript)
        }

        config.userContentController = controller
        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 1280, height: 800), configuration: config)
        wv.customUserAgent = HTTPClient.webPlayerUserAgent
        wv.navigationDelegate = self
        wv.isHidden = true
        wv.alpha = 0.01

        // Attach to key window hierarchy off-screen so WebKit keeps media & RAF timers alive
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = scene.windows.first {
            wv.frame = CGRect(x: -2000, y: -2000, width: 320, height: 240)
            window.insertSubview(wv, at: 0)
        }
        self.webView = wv
    }

    private static func loadBridgeScript() -> String? {
        if let url = Bundle.main.url(forResource: "player-bridge", withExtension: "js", subdirectory: "Spotify")
            ?? Bundle.main.url(forResource: "player-bridge", withExtension: "js") {
            return try? String(contentsOf: url, encoding: .utf8)
        }
        return nil
    }

    fileprivate func handleBridgeMessage(_ body: Any) {
        guard let raw = body as? String, let json = JSONValue.parse(raw) else { return }
        let msgType = json.str("type") ?? ""

        switch msgType {
        case "ready":
            isReady = true
            drmUnavailable = json.bool("drmMissing") ?? false
            DiagnosticLogbook.shared.log("bridge", "Web Player service registry ready (drmMissing=\(drmUnavailable))")

        case "state":
            if let rawState = json.at("state"), let mapped = SpotifyMappers.playerState(rawState) {
                let isAd = mapped.item?.kind == .ad
                if adPlaying != isAd {
                    adPlaying = isAd
                    onAdChanged?(isAd)
                }
                if !isAd {
                    latestState = mapped
                    onStateChanged?(mapped)
                }
            }

        case "queue":
            if let rawQueue = json.at("queue") {
                let mapped = SpotifyMappers.queue(rawQueue)
                latestQueue = mapped
                onQueueChanged?(mapped)
            }

        case "result":
            guard let id = json.int("id") else { return }
            if json.bool("ok") == true {
                finishPendingCall(id, with: .success(json.at("value") ?? .null))
            } else {
                let errText = json.str("error") ?? "Bridge RPC failed"
                finishPendingCall(
                    id,
                    with: .failure(BridgeError.remoteError(method: "rpc#\(id)", message: errText))
                )
            }

        case "error":
            DiagnosticLogbook.shared.log("bridge", "Bridge error: \(json.str("error") ?? "unknown")")

        default:
            break
        }
    }
}

extension SpotifyWebPlayerBridge: WKNavigationDelegate {
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if !isReady, let script = Self.loadBridgeScript() {
            webView.evaluateJavaScript("window.__mspReannounce = true;") { _, _ in }
            webView.evaluateJavaScript(script) { _, _ in }
        }
    }
}

private final class WeakScriptMessageProxy: NSObject, WKScriptMessageHandler {
    weak var target: SpotifyWebPlayerBridge?

    init(target: SpotifyWebPlayerBridge) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        let body = message.body
        Task { @MainActor [weak target] in
            target?.handleBridgeMessage(body)
        }
    }
}

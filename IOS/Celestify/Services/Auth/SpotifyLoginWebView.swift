//
//  SpotifyLoginWebView.swift
//  Celestify
//
//  Coherent WebKit login view fixing Android's CAPTCHA bot-fingerprint mismatch,
//  supporting OAuth/challenge child popup windows via WKUIDelegate, and observing
//  WKHTTPCookieStore directly for `sp_dc` arrival without resetting OTP flows on resume.
//  Built on Myspoti (https://github.com/kota-zo/myspoti), GPL-3.0.
//

import SwiftUI
import UIKit
import WebKit

public struct SpotifyLoginWebView: UIViewRepresentable {
    public let initialURL: URL
    public var callbackURL: URL?
    public let onAuthenticated: ([HTTPCookie], URL?) -> Void
    public let onLoadingChanged: (Bool) -> Void

    public init(
        initialURL: URL = SpotifyAuthManager.loginEntryURL,
        callbackURL: URL? = nil,
        onAuthenticated: @escaping ([HTTPCookie], URL?) -> Void,
        onLoadingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.initialURL = initialURL
        self.callbackURL = callbackURL
        self.onAuthenticated = onAuthenticated
        self.onLoadingChanged = onLoadingChanged
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    public func makeUIView(context: Context) -> UIView {
        let container = UIView(frame: .zero)
        container.backgroundColor = .black

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        // Coherent mobile/tablet content mode matching Apple's genuine WebKit TLS/HTTP2 stack
        // so Arkose/reCAPTCHA never flags a fake Linux desktop User-Agent mismatch.
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: container.bounds, configuration: config)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = .black

        container.addSubview(webView)
        context.coordinator.attach(webView: webView, in: container)
        webView.load(URLRequest(url: initialURL))
        return container
    }

    public func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
        if let callback = callbackURL, callback != context.coordinator.lastHandledCallbackURL {
            context.coordinator.lastHandledCallbackURL = callback
            context.coordinator.webView?.load(URLRequest(url: callback))
        }
    }

    public static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor
    public final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKHTTPCookieStoreObserver {
        var parent: SpotifyLoginWebView
        weak var webView: WKWebView?
        weak var containerView: UIView?
        private var popupWebViews: [WKWebView] = []
        private var completed = false
        var lastHandledCallbackURL: URL?

        init(parent: SpotifyLoginWebView) {
            self.parent = parent
        }

        func attach(webView: WKWebView, in container: UIView) {
            self.webView = webView
            self.containerView = container
            WKWebsiteDataStore.default().httpCookieStore.add(self)
        }

        func detach() {
            WKWebsiteDataStore.default().httpCookieStore.remove(self)
            popupWebViews.forEach { $0.removeFromSuperview() }
            popupWebViews.removeAll()
        }

        // MARK: - WKHTTPCookieStoreObserver

        nonisolated public func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            Task { @MainActor [weak self] in
                await self?.inspectCookiesForCompletion()
            }
        }

        private func inspectCookiesForCompletion() async {
            guard !completed else { return }
            let cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
            let hasSpDc = cookies.contains {
                $0.domain.contains("spotify.com") && $0.name == "sp_dc" && !$0.value.isEmpty
            }
            guard hasSpDc else { return }
            let currentURL = webView?.url
            // Wait until redirect lands on open.spotify.com or auth cookies are settled
            if let host = currentURL?.host, host == "open.spotify.com" {
                completed = true
                parent.onAuthenticated(cookies, currentURL)
            }
        }

        // MARK: - WKNavigationDelegate

        public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.onLoadingChanged(true)
        }

        public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.onLoadingChanged(false)
            Task { await inspectCookiesForCompletion() }
        }

        public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.onLoadingChanged(false)
        }

        public func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if let url = navigationAction.request.url,
               let scheme = url.scheme?.lowercased(),
               scheme != "https" && scheme != "http" && scheme != "about" {
                // Prevent external Spotify app hijack during web login so session cookies stay in Celestify
                if scheme == "spotify" {
                    decisionHandler(.cancel)
                    return
                }
            }
            decisionHandler(.allow)
        }

        // MARK: - WKUIDelegate (OAuth & CAPTCHA Child Window Support)

        public func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            guard let container = containerView else { return nil }
            let popup = WKWebView(frame: container.bounds, configuration: configuration)
            popup.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            popup.navigationDelegate = self
            popup.uiDelegate = self
            popup.allowsBackForwardNavigationGestures = true
            popup.backgroundColor = .black
            container.addSubview(popup)
            popupWebViews.append(popup)
            DiagnosticLogbook.shared.log("auth", "Opened child OAuth/challenge window for \(navigationAction.request.url?.host ?? "popup")")
            return popup
        }

        public func webViewDidClose(_ webView: WKWebView) {
            if let idx = popupWebViews.firstIndex(of: webView) {
                popupWebViews.remove(at: idx)
                webView.removeFromSuperview()
                Task { await inspectCookiesForCompletion() }
            }
        }
    }
}

//
//  CelestifyApp.swift
//  Celestify
//
//  Native iOS entry point for Celestify.
//  Built on Myspoti (https://github.com/kota-zo/myspoti), GPL-3.0.
//  spicetify-glassify compatibility profile licensed under AGPL-3.0.
//

import SwiftUI

@main
public struct CelestifyApp: App {
    @State private var dependencies = AppDependencies()
    @State private var incomingMagicLinkURL: URL?

    public init() {}

    public var body: some Scene {
        WindowGroup {
            RootShellView()
                .environment(dependencies)
                .task {
                    await dependencies.authManager.restoreSessionOnLaunch()
                }
                .onOpenURL { url in
                    if let magic = dependencies.authManager.normalizeMagicLink(url) {
                        incomingMagicLinkURL = magic
                    } else {
                        _ = dependencies.router.handleIncomingURL(url)
                    }
                }
                .sheet(
                    isPresented: Binding(
                        get: { incomingMagicLinkURL != nil },
                        set: { if !$0 { incomingMagicLinkURL = nil } }
                    )
                ) {
                    if let magicURL = incomingMagicLinkURL {
                        SpotifyLoginSheetContainer(initialURL: magicURL)
                            .environment(dependencies)
                    }
                }
        }
    }
}

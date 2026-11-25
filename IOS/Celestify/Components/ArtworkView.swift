//
//  ArtworkView.swift
//  Celestify
//
//  Memory + disk cached artwork loader (`ArtworkCache`) and SwiftUI `ArtworkView`
//  with specular Liquid Glass rim, SF Symbol fallback, and circular artist mode.
//

import SwiftUI
import UIKit

public actor ArtworkCache {
    public static let shared = ArtworkCache()

    private let memory = NSCache<NSURL, UIImage>()
    private let session: URLSession

    public init() {
        memory.countLimit = 240
        memory.totalCostLimit = 96 * 1024 * 1024
        let cfg = URLSessionConfiguration.default
        cfg.urlCache = URLCache(
            memoryCapacity: 32 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024,
            diskPath: "app.celestify.ios.artwork-cache"
        )
        cfg.requestCachePolicy = .returnCacheDataElseLoad
        self.session = URLSession(configuration: cfg)
    }

    public func image(for url: URL) async -> UIImage? {
        let nsURL = url as NSURL
        if let hit = memory.object(forKey: nsURL) {
            return hit
        }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  let decoded = UIImage(data: data) else {
                return nil
            }
            memory.setObject(decoded, forKey: nsURL, cost: data.count)
            return decoded
        } catch {
            return nil
        }
    }

    public func clear() {
        memory.removeAllObjects()
        session.configuration.urlCache?.removeAllCachedResponses()
    }
}

public struct ArtworkView: View {
    public let urlString: String?
    public let size: CGFloat
    public let cornerRadius: CGFloat
    public let isCircular: Bool
    public let fallbackSystemImage: String

    @State private var loadedImage: UIImage?

    public init(
        urlString: String?,
        size: CGFloat = 52,
        cornerRadius: CGFloat = 10,
        isCircular: Bool = false,
        fallbackSystemImage: String = "music.note"
    ) {
        self.urlString = urlString
        self.size = size
        self.cornerRadius = cornerRadius
        self.isCircular = isCircular
        self.fallbackSystemImage = fallbackSystemImage
    }

    public var body: some View {
        ZStack {
            if let loadedImage {
                Image(uiImage: loadedImage)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity.animation(.easeOut(duration: 0.2)))
            } else {
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.10),
                        Color.white.opacity(0.04)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: fallbackSystemImage)
                    .font(.system(size: max(14, size * 0.34), weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 0.6)
        }
        .task(id: urlString) {
            guard let raw = urlString, let url = URL(string: raw) else {
                loadedImage = nil
                return
            }
            loadedImage = await ArtworkCache.shared.image(for: url)
        }
    }

    private var shape: AnyShape {
        if isCircular {
            AnyShape(Circle())
        } else {
            AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

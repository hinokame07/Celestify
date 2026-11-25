//
//  ArtworkPaletteExtractor.swift
//  Celestify
//
//  Built on Myspoti (https://github.com/kota-zo/myspoti), GPL-3.0.
//

import CoreGraphics
import Foundation
import SwiftUI
import UIKit

public struct ArtworkPalette: Sendable, Equatable {
    public let accentHex: UInt32
    public let meshStopsHex: [UInt32]

    public init(accentHex: UInt32, meshStopsHex: [UInt32]) {
        self.accentHex = accentHex
        self.meshStopsHex = meshStopsHex
    }

    public var accentColor: Color { Color(argb: accentHex) }
    public var meshColors: [Color] { meshStopsHex.map { Color(argb: $0) } }
    public var dominantARGB: UInt32 { meshStopsHex.first ?? accentHex }
    public var vibrantARGB: UInt32 { accentHex }

    public static let celestialDefault = ArtworkPalette(
        accentHex: 0xFFFF5C74,
        meshStopsHex: [
            0xFF0B132B, 0xFF1C2541, 0xFF3A0CA3,
            0xFF070B19, 0xFF240046, 0xFF7209B7,
            0xFF03040A, 0xFF10002B, 0xFF3C096C
        ]
    )

    public static let midnightDefault = ArtworkPalette(
        accentHex: 0xFF0A84FF,
        meshStopsHex: [
            0xFF020612, 0xFF071A3E, 0xFF0A3A7E,
            0xFF01040B, 0xFF0B2559, 0xFF0A84FF,
            0xFF000000, 0xFF041028, 0xFF082046
        ]
    )

    public static let goldenDefault = ArtworkPalette(
        accentHex: 0xFFFFD60A,
        meshStopsHex: [
            0xFF0B0802, 0xFF281E08, 0xFF4A350B,
            0xFF050402, 0xFF382909, 0xFF8A6512,
            0xFF020201, 0xFF1C1506, 0xFF332407
        ]
    )
}

public enum ArtworkPaletteExtractor {
    /// Extracts a vibrant UI accent and a 9-stop atmospheric mesh palette from a `UIImage`.
    public static func extract(from image: UIImage) -> ArtworkPalette {
        guard let cgImage = image.cgImage else { return .celestialDefault }
        let sampleSide = 24
        var pixels = [UInt8](repeating: 0, count: sampleSide * sampleSide * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &pixels,
            width: sampleSide,
            height: sampleSide,
            bitsPerComponent: 8,
            bytesPerRow: sampleSide * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return .celestialDefault
        }
        ctx.interpolationQuality = .medium
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: sampleSide, height: sampleSide))

        var bestScore: Double = -1
        var bestRGB: (Double, Double, Double) = (1.0, 0.36, 0.45)

        var regionStops: [UInt32] = []
        let gridSteps = [4, 12, 20]

        for gy in gridSteps {
            for gx in gridSteps {
                let idx = (gy * sampleSide + gx) * 4
                let r = Double(pixels[idx]) / 255.0
                let g = Double(pixels[idx + 1]) / 255.0
                let b = Double(pixels[idx + 2]) / 255.0
                // Deepen stop for atmospheric readability under white/ivory lyrics
                let dr = r * 0.48
                let dg = g * 0.48
                let db = b * 0.52
                regionStops.append(packARGB(r: dr, g: dg, b: db))
            }
        }

        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = Double(pixels[i]) / 255.0
            let g = Double(pixels[i + 1]) / 255.0
            let b = Double(pixels[i + 2]) / 255.0
            let maxC = max(r, max(g, b))
            let minC = min(r, min(g, b))
            let chroma = maxC - minC
            let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
            // Prefer vibrant mid-to-bright hues that read cleanly on obsidian glass
            let lumPenalty = 1.0 - min(abs(lum - 0.52) * 1.35, 0.85)
            let score = (chroma * 1.8 + 0.12) * lumPenalty
            if score > bestScore {
                bestScore = score
                bestRGB = (r, g, b)
            }
        }

        let readableAccent = ensureAccentReadability(r: bestRGB.0, g: bestRGB.1, b: bestRGB.2)
        return ArtworkPalette(
            accentHex: readableAccent,
            meshStopsHex: regionStops.count == 9 ? regionStops : ArtworkPalette.celestialDefault.meshStopsHex
        )
    }

    private static func ensureAccentReadability(r: Double, g: Double, b: Double) -> UInt32 {
        var nr = r
        var ng = g
        var nb = b
        let lum = 0.2126 * nr + 0.7152 * ng + 0.0722 * nb
        if lum < 0.22 {
            let boost = (0.28 - lum)
            nr = min(1.0, nr + boost)
            ng = min(1.0, ng + boost)
            nb = min(1.0, nb + boost)
        }
        return packARGB(r: nr, g: ng, b: nb)
    }

    public static func packARGB(r: Double, g: Double, b: Double, a: Double = 1.0) -> UInt32 {
        let ai = UInt32(min(max(a * 255.0, 0), 255))
        let ri = UInt32(min(max(r * 255.0, 0), 255))
        let gi = UInt32(min(max(g * 255.0, 0), 255))
        let bi = UInt32(min(max(b * 255.0, 0), 255))
        return (ai << 24) | (ri << 16) | (gi << 8) | bi
    }
}

public extension Color {
    init(argb: UInt32) {
        let a = Double((argb >> 24) & 0xFF) / 255.0
        let r = Double((argb >> 16) & 0xFF) / 255.0
        let g = Double((argb >> 8) & 0xFF) / 255.0
        let b = Double(argb & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a == 0 ? 1.0 : a)
    }

    init?(hexString: String?) {
        guard let raw = hexString?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        let cleaned = raw.hasPrefix("#") ? String(raw.dropFirst()) : raw
        guard let val = UInt32(cleaned, radix: 16) else { return nil }
        if cleaned.count == 6 {
            self.init(argb: 0xFF000000 | val)
        } else if cleaned.count == 8 {
            self.init(argb: val)
        } else {
            return nil
        }
    }
}

//
//  NativeDynamicBackground.swift
//  Celestify
//
//  Artwork-driven Metal background for the immersive lyrics stage.
//  Kawarp-inspired warp and color treatment; see THIRD_PARTY_NOTICES.md.
//

import Foundation
import MetalKit
import QuartzCore
import SwiftUI
import UIKit

public struct NativeDynamicBackground: View {
    public let artwork: UIImage?
    public let palette: ArtworkPalette
    public let isAnimating: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    private var preferences: PreferencesStore { PreferencesStore.shared }

    public init(artwork: UIImage?, palette: ArtworkPalette, isAnimating: Bool) {
        self.artwork = artwork
        self.palette = palette
        self.isAnimating = isAnimating
    }

    public var body: some View {
        let motionAllowed = !reduceMotion
            && !preferences.reduceAnimations
            && !preferences.energySaverEnabled
        ZStack {
            AtmosphericBackdrop(
                palette: palette,
                isAnimating: isAnimating && motionAllowed && scenePhase == .active
            )
            MetalArtworkBackgroundView(
                artwork: artwork,
                isAnimating: isAnimating,
                allowsMotion: motionAllowed,
                isSceneActive: scenePhase == .active
            )
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.18), location: 0),
                        .init(color: .black.opacity(0.34), location: 0.52),
                        .init(color: .black.opacity(0.48), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

private struct MetalArtworkBackgroundView: UIViewRepresentable {
    let artwork: UIImage?
    let isAnimating: Bool
    let allowsMotion: Bool
    let isSceneActive: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MTKView {
        let view = CappedMetalView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColorMake(0, 0, 0, 0)
        view.framebufferOnly = true
        view.isOpaque = false
        view.layer.isOpaque = false
        view.enableSetNeedsDisplay = true
        view.isPaused = true
        context.coordinator.attach(to: view)
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.update(
            artwork: artwork,
            isAnimating: isAnimating,
            allowsMotion: allowsMotion,
            isSceneActive: isSceneActive,
            view: view
        )
    }

    static func dismantleUIView(_ view: MTKView, coordinator: Coordinator) {
        view.delegate = nil
        coordinator.stop()
    }

    final class Coordinator {
        private var renderer: MetalArtworkRenderer?

        func attach(to view: MTKView) {
            guard let device = view.device else { return }
            renderer = MetalArtworkRenderer(device: device)
            view.delegate = renderer
            renderer?.setNeedsDraw = { [weak view] in view?.setNeedsDisplay() }
        }

        func update(
            artwork: UIImage?,
            isAnimating: Bool,
            allowsMotion: Bool,
            isSceneActive: Bool,
            view: MTKView
        ) {
            renderer?.allowsTransitions = allowsMotion && isSceneActive
            renderer?.setArtwork(artwork)
            guard let renderer else { return }

            if !isSceneActive || !allowsMotion {
                view.enableSetNeedsDisplay = true
                view.isPaused = true
                view.setNeedsDisplay()
                return
            }

            renderer.animationSpeed = isAnimating ? 1 : 0.035
            view.enableSetNeedsDisplay = false
            view.preferredFramesPerSecond = isAnimating ? 30 : 4
            view.isPaused = false
        }

        func stop() {
            renderer?.stop()
            renderer = nil
        }
    }
}

private final class CappedMetalView: MTKView {
    override func layoutSubviews() {
        super.layoutSubviews()
        let longestSide = max(bounds.width, bounds.height)
        guard longestSide > 0 else { return }
        let screenScale = window?.screen.scale ?? contentScaleFactor
        let scale = min(screenScale, 960 / longestSide)
        let targetSize = CGSize(
            width: max(1, (bounds.width * scale).rounded()),
            height: max(1, (bounds.height * scale).rounded())
        )
        if drawableSize != targetSize {
            drawableSize = targetSize
        }
    }
}

private final class MetalArtworkRenderer: NSObject, MTKViewDelegate {
    private struct BlurUniforms {
        var texelOffset: SIMD2<Float>
    }

    private struct BackgroundUniforms {
        var viewport: SIMD2<Float>
        var time: Float
        var intensity: Float
        var blend: Float
        var saturation: Float
        var brightness: Float
        var padding: Float
    }

    private final class PreparedArtwork {
        let texture: MTLTexture

        init(texture: MTLTexture) {
            self.texture = texture
        }
    }

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue?
    private let textureLoader: MTKTextureLoader
    private let sampler: MTLSamplerState?
    private let blurPipeline: MTLRenderPipelineState?
    private let backgroundPipeline: MTLRenderPipelineState?
    private var currentArtwork: PreparedArtwork?
    private var previousArtwork: PreparedArtwork?
    private var requestedImage: UIImage?
    private var requestRevision: UInt64 = 0
    private var transitionStart: CFTimeInterval = 0
    private var animationStart = CACurrentMediaTime()
    private var isStopped = false
    var allowsTransitions = true
    var animationSpeed: Float = 1
    var setNeedsDraw: (() -> Void)?

    init(device: MTLDevice) {
        self.device = device
        commandQueue = device.makeCommandQueue()
        textureLoader = MTKTextureLoader(device: device)

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        sampler = device.makeSamplerState(descriptor: samplerDescriptor)

        let library = try? device.makeLibrary(source: Self.shaderSource, options: nil)
        let blurDescriptor = MTLRenderPipelineDescriptor()
        blurDescriptor.vertexFunction = library?.makeFunction(name: "backgroundVertex")
        blurDescriptor.fragmentFunction = library?.makeFunction(name: "blurFragment")
        blurDescriptor.colorAttachments[0].pixelFormat = .rgba8Unorm
        blurPipeline = try? device.makeRenderPipelineState(descriptor: blurDescriptor)

        let backgroundDescriptor = MTLRenderPipelineDescriptor()
        backgroundDescriptor.vertexFunction = library?.makeFunction(name: "backgroundVertex")
        backgroundDescriptor.fragmentFunction = library?.makeFunction(name: "backgroundFragment")
        backgroundDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        backgroundPipeline = try? device.makeRenderPipelineState(descriptor: backgroundDescriptor)
        super.init()
    }

    func setArtwork(_ image: UIImage?) {
        guard !isStopped else { return }
        if let image, image === requestedImage { return }
        if image == nil, requestedImage == nil { return }

        requestedImage = image
        requestRevision &+= 1
        let revision = requestRevision
        guard let image else {
            currentArtwork = nil
            previousArtwork = nil
            setNeedsDraw?()
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let thumbnail = image.preparingThumbnail(of: CGSize(width: 768, height: 768)) ?? image
            guard let cgImage = thumbnail.cgImage else { return }
            self?.textureLoader.newTexture(
                cgImage: cgImage,
                options: [.SRGB: false],
                completionHandler: { [weak self] texture, _ in
                    DispatchQueue.main.async {
                        guard let self,
                              !self.isStopped,
                              self.requestRevision == revision,
                              let texture else { return }
                        self.install(texture)
                    }
                }
            )
        }
    }

    private func install(_ source: MTLTexture) {
        guard let queue = commandQueue,
              let blurPipeline,
              let sampler else { return }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: source.width,
            height: source.height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        guard let horizontal = device.makeTexture(descriptor: descriptor),
              let blurred = device.makeTexture(descriptor: descriptor),
              let commandBuffer = queue.makeCommandBuffer() else { return }

        let horizontalOffset = BlurUniforms(texelOffset: SIMD2(2.2 / Float(source.width), 0))
        let verticalOffset = BlurUniforms(texelOffset: SIMD2(0, 2.2 / Float(source.height)))
        guard encodeBlur(
            commandBuffer: commandBuffer,
            pipeline: blurPipeline,
            source: source,
            destination: horizontal,
            uniforms: horizontalOffset,
            sampler: sampler
        ), encodeBlur(
            commandBuffer: commandBuffer,
            pipeline: blurPipeline,
            source: horizontal,
            destination: blurred,
            uniforms: verticalOffset,
            sampler: sampler
        ) else { return }

        let prepared = PreparedArtwork(texture: blurred)
        if currentArtwork == nil || !allowsTransitions {
            previousArtwork = prepared
            currentArtwork = prepared
        } else {
            previousArtwork = currentArtwork
            currentArtwork = prepared
        }
        transitionStart = CACurrentMediaTime()
        commandBuffer.commit()
        setNeedsDraw?()
    }

    private func encodeBlur(
        commandBuffer: MTLCommandBuffer,
        pipeline: MTLRenderPipelineState,
        source: MTLTexture,
        destination: MTLTexture,
        uniforms: BlurUniforms,
        sampler: MTLSamplerState
    ) -> Bool {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = destination
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return false }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(source, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        var uniforms = uniforms
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<BlurUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        return true
    }

    func draw(in view: MTKView) {
        guard !isStopped,
              let commandQueue,
              let drawable = view.currentDrawable,
              let pass = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        guard let currentArtwork else {
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
            guard let clearEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
            clearEncoder.endEncoding()
            commandBuffer.present(drawable)
            commandBuffer.commit()
            return
        }
        guard let backgroundPipeline,
              let sampler,
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }

        let now = CACurrentMediaTime()
        let previous = previousArtwork ?? currentArtwork
        let blend = previous === currentArtwork
            ? 1
            : min(max(Float((now - transitionStart) / 0.9), 0), 1)
        let time = Float(now - animationStart) * animationSpeed
        var uniforms = BackgroundUniforms(
            viewport: SIMD2(Float(view.drawableSize.width), Float(view.drawableSize.height)),
            time: time,
            intensity: 0.11,
            blend: blend,
            saturation: 1.38,
            brightness: 0.78,
            padding: 0
        )
        encoder.setRenderPipelineState(backgroundPipeline)
        encoder.setFragmentTexture(previous.texture, index: 0)
        encoder.setFragmentTexture(currentArtwork.texture, index: 1)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.setFragmentBytes(
            &uniforms,
            length: MemoryLayout<BackgroundUniforms>.stride,
            index: 0
        )
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()

        if blend >= 1, previous !== currentArtwork {
            self.previousArtwork = currentArtwork
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func stop() {
        isStopped = true
        requestRevision &+= 1
        currentArtwork = nil
        previousArtwork = nil
        requestedImage = nil
        setNeedsDraw = nil
    }

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct VertexOut {
        float4 position [[position]];
        float2 uv;
    };

    struct BlurUniforms {
        float2 texelOffset;
    };

    struct BackgroundUniforms {
        float2 viewport;
        float time;
        float intensity;
        float blend;
        float saturation;
        float brightness;
        float padding;
    };

    vertex VertexOut backgroundVertex(uint vertexID [[vertex_id]]) {
        const float2 positions[3] = {
            float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0)
        };
        VertexOut out;
        float2 point = positions[vertexID];
        out.position = float4(point, 0.0, 1.0);
        out.uv = float2((point.x + 1.0) * 0.5, (1.0 - point.y) * 0.5);
        return out;
    }

    fragment float4 blurFragment(
        VertexOut in [[stage_in]],
        texture2d<float> image [[texture(0)]],
        sampler imageSampler [[sampler(0)]],
        constant BlurUniforms &uniforms [[buffer(0)]]
    ) {
        float2 step = uniforms.texelOffset;
        float4 color = image.sample(imageSampler, in.uv) * 0.227027;
        color += image.sample(imageSampler, in.uv + step * 1.384615) * 0.316216;
        color += image.sample(imageSampler, in.uv - step * 1.384615) * 0.316216;
        color += image.sample(imageSampler, in.uv + step * 3.230769) * 0.070270;
        color += image.sample(imageSampler, in.uv - step * 3.230769) * 0.070270;
        return color;
    }

    float3 mod289(float3 value) {
        return value - floor(value * (1.0 / 289.0)) * 289.0;
    }

    float2 mod289(float2 value) {
        return value - floor(value * (1.0 / 289.0)) * 289.0;
    }

    float3 permute(float3 value) {
        return mod289(((value * 34.0) + 1.0) * value);
    }

    float simplexNoise(float2 value) {
        const float4 C = float4(
            0.211324865405187, 0.366025403784439,
            -0.577350269189626, 0.024390243902439
        );
        float2 cell = floor(value + dot(value, C.yy));
        float2 offset = value - cell + dot(cell, C.xx);
        float2 corner = offset.x > offset.y ? float2(1.0, 0.0) : float2(0.0, 1.0);
        float4 pair = offset.xyxy + C.xxzz;
        pair.xy -= corner;
        cell = mod289(cell);
        float3 gradients = permute(
            permute(cell.y + float3(0.0, corner.y, 1.0))
            + cell.x + float3(0.0, corner.x, 1.0)
        );
        float3 weight = max(
            0.5 - float3(dot(offset, offset), dot(pair.xy, pair.xy), dot(pair.zw, pair.zw)),
            0.0
        );
        weight *= weight;
        weight *= weight;
        float3 x = 2.0 * fract(gradients * C.www) - 1.0;
        float3 h = abs(x) - 0.5;
        float3 ox = floor(x + 0.5);
        float3 a0 = x - ox;
        weight *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h * h);
        float3 g;
        g.x = a0.x * offset.x + h.x * offset.y;
        g.yz = a0.yz * pair.xz + h.yz * pair.yw;
        return 130.0 * dot(weight, g);
    }

    float2 coverCoordinate(float2 uv, float2 viewport, uint width, uint height) {
        float sourceAspect = float(width) / max(float(height), 1.0);
        float viewAspect = viewport.x / max(viewport.y, 1.0);
        if (sourceAspect > viewAspect) {
            uv.x = 0.5 + (uv.x - 0.5) * (viewAspect / sourceAspect);
        } else {
            uv.y = 0.5 + (uv.y - 0.5) * (sourceAspect / viewAspect);
        }
        return uv;
    }

    fragment float4 backgroundFragment(
        VertexOut in [[stage_in]],
        texture2d<float> previousImage [[texture(0)]],
        texture2d<float> currentImage [[texture(1)]],
        sampler imageSampler [[sampler(0)]],
        constant BackgroundUniforms &uniforms [[buffer(0)]]
    ) {
        float2 uv = in.uv;
        float time = uniforms.time * 0.05;
        float2 center = uv - 0.5;
        float centerWeight = 1.0 - smoothstep(0.0, 0.7, length(center));
        float n1 = simplexNoise(uv * 0.35 + float2(time, time * 0.7));
        float n2 = simplexNoise(uv * 0.35 + float2(-time * 0.8, time * 0.5) + 50.0);
        float n3 = simplexNoise(uv * 0.9 + float2(time * 1.2, -time) + float2(100.0, 0.0));
        float n4 = simplexNoise(uv * 0.9 + float2(-time, time * 1.1) + float2(0.0, 100.0));
        float2 warp = float2(n1 * 0.65 + n3 * 0.35, n2 * 0.65 + n4 * 0.35);
        warp *= centerWeight * uniforms.intensity;
        float2 displaced = clamp(uv + warp, 0.0, 1.0);
        float2 previousUV = coverCoordinate(
            displaced, uniforms.viewport, previousImage.get_width(), previousImage.get_height()
        );
        float2 currentUV = coverCoordinate(
            displaced, uniforms.viewport, currentImage.get_width(), currentImage.get_height()
        );
        float3 previousColor = previousImage.sample(imageSampler, previousUV).rgb;
        float3 currentColor = currentImage.sample(imageSampler, currentUV).rgb;
        float3 color = mix(previousColor, currentColor, uniforms.blend);
        float vignette = 1.0 - dot(center, center) * 0.3;
        color *= vignette;
        float luminance = dot(color, float3(0.299, 0.587, 0.114));
        color = mix(float3(luminance), color, uniforms.saturation) * uniforms.brightness;
        float2 pixel = in.position.xy;
        float noise = fract(sin(dot(pixel + uniforms.time, float2(12.9898, 78.233))) * 43758.5453);
        color = clamp(color + (noise - 0.5) * 0.008, 0.0, 1.0);
        return float4(color, 1.0);
    }
    """
}

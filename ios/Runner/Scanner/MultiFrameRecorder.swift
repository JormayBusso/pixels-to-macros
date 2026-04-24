import ARKit
import CoreVideo
import Foundation

/// Samples AR frames from the running session at ~10 fps during a video sweep.
///
/// Memory strategy:
///   - The **first** frame is kept as a full `CapturedFrame` (RGB + depth) and
///     used as the "top" reference for plate detection and segmentation.
///   - Every subsequent sampled frame stores only **depth + pose** (no RGB),
///     keeping peak memory well under 20 MB for a 2-second sweep.
///
/// IMPORTANT: ARKit recycles pixel-buffer memory between frames.
///   We deep-copy every CVPixelBuffer before storing it.
final class MultiFrameRecorder {

    // MARK: – Stored frame types

    /// Lightweight per-frame record: depth data + camera pose only.
    struct LightFrame {
        let depthBuffer:     CVPixelBuffer   // deep copy — owned by us
        let cameraTransform: simd_float4x4
        let cameraIntrinsics: simd_float3x3
        let imageWidth:  Int
        let imageHeight: Int
    }

    // MARK: – Public state

    /// Full first frame (RGB + optional depth) used for segmentation.
    private(set) var topFrame: FrameCaptureService.CapturedFrame?

    /// All sampled frames that had depth data available.
    private(set) var lightFrames: [LightFrame] = []

    var frameCount: Int { lightFrames.count }
    var hasDepthData: Bool { !lightFrames.isEmpty }

    /// Current phone pitch angle in radians. Updated every sample.
    /// -π/2 = pointing straight down (top-view), 0 = horizontal (side-view).
    private(set) var currentPitch: Float = 0

    // MARK: – Private

    private var timer:    Timer?
    private var isActive: Bool = false

    /// 10 fps sample rate — enough for reconstruction without excessive memory use.
    private let sampleInterval: TimeInterval = 0.1
    /// 20 frames == 2 seconds at 10 fps.
    private let maxFrames = 20

    // MARK: – Control

    /// Start sampling from the running ARKit session.
    /// Must be called on the main thread (Timer requires a RunLoop).
    func startRecording(sessionManager: ARSessionManager) {
        guard !isActive else { return }
        topFrame    = nil
        lightFrames = []
        isActive    = true

        timer = Timer.scheduledTimer(
            withTimeInterval: sampleInterval,
            repeats: true
        ) { [weak self] _ in
            self?.sampleFrame(from: sessionManager)
        }
    }

    /// Stop sampling. Call before `runVideoScan`.
    func stopRecording() {
        isActive = false
        timer?.invalidate()
        timer = nil
    }

    /// Release all stored pixel buffers and reset state.
    func releaseAll() {
        stopRecording()
        topFrame    = nil
        lightFrames = []
    }

    // MARK: – Orientation query

    /// Read the current pitch from the latest AR frame without recording.
    /// Returns pitch in radians: -π/2 = top-view, 0 = horizontal.
    func updatePitch(from sessionManager: ARSessionManager) {
        guard let frame = sessionManager.latestFrame else { return }
        currentPitch = frame.camera.eulerAngles.x
    }

    // MARK: – Private

    private func sampleFrame(from sessionManager: ARSessionManager) {
        guard isActive, let arFrame = sessionManager.latestFrame else { return }

        // Always update pitch for orientation tracking.
        currentPitch = arFrame.camera.eulerAngles.x

        autoreleasepool {
            let pixBuf    = arFrame.capturedImage
            let depthBuf  = arFrame.sceneDepth?.depthMap
            let transform = arFrame.camera.transform
            let intrinsics = arFrame.camera.intrinsics
            let w = CVPixelBufferGetWidth(pixBuf)
            let h = CVPixelBufferGetHeight(pixBuf)

            // First frame → full top frame (RGB + depth).
            // Deep-copy pixel buffers so ARKit can reuse its internal pool.
            if topFrame == nil {
                topFrame = FrameCaptureService.CapturedFrame(
                    pixelBuffer:     MultiFrameRecorder.copyPixelBuffer(pixBuf),
                    depthBuffer:     depthBuf.flatMap { MultiFrameRecorder.copyPixelBuffer($0) },
                    cameraTransform: transform,
                    cameraIntrinsics: intrinsics,
                    timestamp:       arFrame.timestamp
                )
            }

            // All frames with depth → lightweight record (deep-copy depth).
            if let depth = depthBuf, lightFrames.count < maxFrames {
                lightFrames.append(LightFrame(
                    depthBuffer:      MultiFrameRecorder.copyPixelBuffer(depth),
                    cameraTransform:  transform,
                    cameraIntrinsics: intrinsics,
                    imageWidth:  w,
                    imageHeight: h
                ))
            }
        }
    }

    // MARK: – Pixel buffer deep copy

    /// Create an independent deep copy of a CVPixelBuffer.
    /// This is essential because ARKit recycles its pixel buffer pool
    /// between frames — references become invalid after the next delegate call.
    static func copyPixelBuffer(_ src: CVPixelBuffer) -> CVPixelBuffer {
        let width  = CVPixelBufferGetWidth(src)
        let height = CVPixelBufferGetHeight(src)
        let format = CVPixelBufferGetPixelFormatType(src)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(src)

        var dst: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any],
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width, height, format,
            attrs as CFDictionary,
            &dst
        )
        guard status == kCVReturnSuccess, let dst else {
            // Allocation failed – return the original; ARC keeps it alive.
            return src
        }

        CVPixelBufferLockBaseAddress(src, .readOnly)
        CVPixelBufferLockBaseAddress(dst, [])
        defer {
            CVPixelBufferUnlockBaseAddress(src, .readOnly)
            CVPixelBufferUnlockBaseAddress(dst, [])
        }

        let planeCount = CVPixelBufferGetPlaneCount(src)
        if planeCount > 0 {
            // Multi-planar (e.g. YCbCr 420)
            for plane in 0..<planeCount {
                guard let srcBase = CVPixelBufferGetBaseAddressOfPlane(src, plane),
                      let dstBase = CVPixelBufferGetBaseAddressOfPlane(dst, plane)
                else { continue }
                let srcRowBytes = CVPixelBufferGetBytesPerRowOfPlane(src, plane)
                let dstRowBytes = CVPixelBufferGetBytesPerRowOfPlane(dst, plane)
                let planeH = CVPixelBufferGetHeightOfPlane(src, plane)
                let copyBytes = min(srcRowBytes, dstRowBytes)
                for row in 0..<planeH {
                    memcpy(
                        dstBase.advanced(by: row * dstRowBytes),
                        srcBase.advanced(by: row * srcRowBytes),
                        copyBytes
                    )
                }
            }
        } else {
            // Single plane (e.g. Float32 depth, BGRA)
            guard let srcBase = CVPixelBufferGetBaseAddress(src),
                  let dstBase = CVPixelBufferGetBaseAddress(dst)
            else { return dst }
            let dstRowBytes = CVPixelBufferGetBytesPerRow(dst)
            let copyBytes = min(bytesPerRow, dstRowBytes)
            for row in 0..<height {
                memcpy(
                    dstBase.advanced(by: row * dstRowBytes),
                    srcBase.advanced(by: row * bytesPerRow),
                    copyBytes
                )
            }
        }

        return dst
    }
}

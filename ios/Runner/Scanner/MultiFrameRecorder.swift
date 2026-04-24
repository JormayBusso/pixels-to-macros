import ARKit
import CoreVideo
import Foundation

/// Samples AR frames from the running session at ~10 fps during a video sweep.
///
/// Memory strategy:
///   - The **first** frame is kept as a full `CapturedFrame` (RGB + depth) and
///     used as the "top" reference for plate detection and segmentation.
///   - Every subsequent sampled frame stores only **depth + pose** (no RGB),
///     keeping peak memory well under 20 MB for a 5-second sweep.
final class MultiFrameRecorder {

    // MARK: – Stored frame types

    /// Lightweight per-frame record: depth data + camera pose only.
    struct LightFrame {
        let depthBuffer:     CVPixelBuffer
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

    // MARK: – Private

    private var timer:    Timer?
    private var isActive: Bool = false

    /// 10 fps sample rate — enough for reconstruction without excessive memory use.
    private let sampleInterval: TimeInterval = 0.1
    /// 50 frames == 5 seconds at 10 fps.
    private let maxFrames = 50

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

    // MARK: – Private

    private func sampleFrame(from sessionManager: ARSessionManager) {
        guard isActive, let arFrame = sessionManager.latestFrame else { return }

        autoreleasepool {
            let pixBuf    = arFrame.capturedImage
            let depthBuf  = arFrame.sceneDepth?.depthMap
            let transform = arFrame.camera.transform
            let intrinsics = arFrame.camera.intrinsics
            let w = CVPixelBufferGetWidth(pixBuf)
            let h = CVPixelBufferGetHeight(pixBuf)

            // First frame → full top frame (RGB + depth)
            if topFrame == nil {
                topFrame = FrameCaptureService.CapturedFrame(
                    pixelBuffer:     pixBuf,
                    depthBuffer:     depthBuf,
                    cameraTransform: transform,
                    cameraIntrinsics: intrinsics,
                    timestamp:       arFrame.timestamp
                )
            }

            // All frames with depth → lightweight record
            if let depth = depthBuf, lightFrames.count < maxFrames {
                lightFrames.append(LightFrame(
                    depthBuffer:      depth,
                    cameraTransform:  transform,
                    cameraIntrinsics: intrinsics,
                    imageWidth:  w,
                    imageHeight: h
                ))
            }
        }
    }
}

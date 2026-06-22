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

    /// RGB side/reference frame captured after the top frame. Used by the
    /// non-LiDAR monocular estimator as an optional height/quality cue.
    private(set) var sideFrame: FrameCaptureService.CapturedFrame?

    /// All sampled frames that had depth data available.
    private(set) var lightFrames: [LightFrame] = []

    /// First few top-view depth frames, captured before the phone moves to a side view.
    private(set) var topViewFrames: [LightFrame] = []

    var frameCount: Int { topViewFrames.count + lightFrames.count }
    var hasDepthData: Bool { !topViewFrames.isEmpty || !lightFrames.isEmpty }

    /// Current phone pitch angle in radians. Updated every sample.
    /// -π/2 = pointing straight down (top-view), 0 = horizontal (side-view).
    private(set) var currentPitch: Float = 0

    /// Device roll about the camera viewing axis, in radians, or the sentinel
    /// 999 when the camera points (near-)straight down/up and roll is
    /// ambiguous. 0 ≈ portrait-upright, ±π/2 ≈ landscape, ±π ≈ upside-down.
    private(set) var currentRoll: Float = 999

    // MARK: – Private

    private var timer:    Timer?
    private var isActive: Bool = false

    /// 10 fps sample rate — enough for reconstruction without excessive memory use.
    private let sampleInterval: TimeInterval = 0.1
    /// 40 frames == 4 seconds at 10 fps — the HARD upper bound. The sweep
    /// normally finishes earlier: the controller stops recording the moment the
    /// top-to-side arc completes (scan_screen pitch early-stop), so a steady
    /// user uses far fewer frames and only a slow sweep reaches this cap.
    private let maxFrames = 40
    /// Keep a short stable top-view lock before side-view depth is allowed to influence volume.
    private let maxTopViewFrames = 4

    // MARK: – Control

    /// Start sampling from the running ARKit session.
    /// Must be called on the main thread (Timer requires a RunLoop).
    func startRecording(sessionManager: ARSessionManager) {
        guard !isActive else { return }
        topFrame    = nil
        sideFrame   = nil
        topViewFrames = []
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
        sideFrame   = nil
        topViewFrames = []
        lightFrames = []
    }

    // MARK: – Orientation query

    /// Read the current pitch from the latest AR frame without recording.
    /// Returns pitch in radians: -π/2 = top-view, 0 = horizontal.
    func updatePitch(from sessionManager: ARSessionManager) {
        guard let frame = sessionManager.latestFrame else { return }
        currentPitch = frame.camera.eulerAngles.x
    }

    /// Read the device's roll about its viewing axis from the latest AR frame.
    ///
    /// ARKit's world is gravity-aligned (world up = +Y), so projecting world-up
    /// onto the camera's image plane (right = column 0, up = column 1) yields the
    /// screen rotation directly: roll = atan2(rightY, upY). This stays
    /// well-defined across the full top-view↔side-view tilt, unlike
    /// `eulerAngles` which is unstable near pitch = ±90°. When the camera is
    /// near-vertical (phone flat) the in-plane gravity component vanishes and
    /// orientation is ambiguous, so the sentinel 999 is returned and callers
    /// hold the last known orientation.
    func updateRoll(from sessionManager: ARSessionManager) {
        guard let frame = sessionManager.latestFrame else { currentRoll = 999; return }
        let t = frame.camera.transform
        // ARKit camera space is LANDSCAPE-native (Apple docs): +x runs along the
        // device long axis from the front camera toward the home button (= the
        // device's DOWN edge in portrait), and +y is "up" relative to
        // landscapeRight (= the device's portrait LEFT edge). So the portrait
        // device-up axis is -column0 and device-right is -column1. Projecting
        // both onto world-up (+y) yields the screen roll directly — without this
        // landscape offset the overlay rotates 90° the wrong way.
        let upY = -t.columns.0.y    // deviceUp · worldUp
        let rightY = -t.columns.1.y // deviceRight · worldUp
        let mag = (upY * upY + rightY * rightY).squareRoot()
        if mag < 0.25 {
            currentRoll = 999
        } else {
            // Negate so a clockwise physical turn maps to a clockwise overlay
            // counter-rotation — otherwise landscape lands 180° off (upside-down).
            currentRoll = -atan2(rightY, upY)
        }
    }

    // MARK: – Private

    private func sampleFrame(from sessionManager: ARSessionManager) {
        guard isActive, let arFrame = sessionManager.latestFrame else { return }

        // Always update pitch for orientation tracking.
        currentPitch = arFrame.camera.eulerAngles.x

        autoreleasepool {
            let pixBuf    = arFrame.capturedImage
            let depthBuf  = FrameCaptureService.preferredDepthMap(from: arFrame)
            let transform = arFrame.camera.transform
            let intrinsics = arFrame.camera.intrinsics
            let w = CVPixelBufferGetWidth(pixBuf)
            let h = CVPixelBufferGetHeight(pixBuf)
            let isTopView = MultiFrameRecorder.isLikelyTopView(pitch: currentPitch)

            // First frame → full top frame (RGB + depth).
            // Deep-copy pixel buffers so ARKit can reuse its internal pool.
            if topFrame == nil && isTopView {
                print("[SCAN] sampleFrame topFrame: pitch=\(String(format: "%.2f", currentPitch)), sceneDepth=\(arFrame.sceneDepth != nil), depthMap=\(depthBuf != nil)")
                topFrame = FrameCaptureService.CapturedFrame(
                    pixelBuffer:     MultiFrameRecorder.copyPixelBuffer(pixBuf),
                    depthBuffer:     depthBuf.flatMap { MultiFrameRecorder.copyPixelBuffer($0) },
                    cameraTransform: transform,
                    cameraIntrinsics: intrinsics,
                    timestamp:       arFrame.timestamp
                )
            }

            // Keep one RGB side/reference frame for non-LiDAR volume fallback.
            // We do not need every RGB frame; one frame is enough for future
            // side-height refinement while keeping memory bounded.
            if topFrame != nil && sideFrame == nil && !isTopView {
                sideFrame = FrameCaptureService.CapturedFrame(
                    pixelBuffer:     MultiFrameRecorder.copyPixelBuffer(pixBuf),
                    depthBuffer:     depthBuf.flatMap { MultiFrameRecorder.copyPixelBuffer($0) },
                    cameraTransform: transform,
                    cameraIntrinsics: intrinsics,
                    timestamp:       arFrame.timestamp
                )
            }

            // All frames with depth → lightweight record (deep-copy depth).
            if let depth = depthBuf, lightFrames.count < maxFrames {
                let frame = LightFrame(
                    depthBuffer:      MultiFrameRecorder.copyPixelBuffer(depth),
                    cameraTransform:  transform,
                    cameraIntrinsics: intrinsics,
                    imageWidth:  w,
                    imageHeight: h
                )
                if isTopView && topViewFrames.count < maxTopViewFrames {
                    topViewFrames.append(frame)
                } else if topFrame != nil {
                    lightFrames.append(frame)
                }
            }
        }
    }

    private static func isLikelyTopView(pitch: Float) -> Bool {
        abs(Double(pitch) + Double.pi / 2.0) < 0.55
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

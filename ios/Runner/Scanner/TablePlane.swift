import ARKit
import Foundation
import simd

/// The reference surface the food rests on (table / plate top).
///
/// Volume in both tiers is computed as the integral of the food's **height
/// above this plane**, so a single, well-defined plane is the shared anchor
/// for the LiDAR and camera strategies alike.
///
/// Geometry is expressed in **ARKit world space** (metres). `normal` always
/// points from the table *up toward the camera*, so a food surface sample that
/// sits above the table yields a positive height.
struct TablePlane {

    /// Where the plane datum came from — used for confidence + diagnostics.
    enum Source: String {
        /// Detected `ARPlaneAnchor` (LiDAR / world tracking).
        case arPlaneAnchor = "ar_plane"
        /// Virtual plane synthesised at the assumed hold distance (camera tier).
        case assumedDistance = "assumed_distance"
        /// LiDAR device but no plane anchor yet — virtual fallback.
        case lidarFallback = "lidar_fallback"
    }

    /// A point that lies on the plane (world space, metres).
    let point: simd_float3
    /// Unit normal pointing toward the camera (world space).
    let normal: simd_float3
    let source: Source
    /// 0…1 confidence in the plane estimate.
    let confidence: Float

    /// Signed height (metres) of a world-space point above the plane.
    /// Positive means "between the table and the camera" (i.e. food).
    @inline(__always)
    func heightAboveM(_ worldPoint: simd_float3) -> Float {
        simd_dot(worldPoint - point, normal)
    }

    /// Build a virtual plane at `distanceM` straight ahead of the camera.
    ///
    /// ARKit cameras look along their local **−Z** axis, so for a top-down
    /// scan the forward ray points down at the table.
    static func virtual(
        cameraTransform: simd_float4x4,
        distanceM: Float,
        source: Source,
        confidence: Float
    ) -> TablePlane {
        let camPos = simd_float3(cameraTransform.columns.3.x,
                                 cameraTransform.columns.3.y,
                                 cameraTransform.columns.3.z)
        // Camera forward = −Z column.
        let zAxis = simd_float3(cameraTransform.columns.2.x,
                                cameraTransform.columns.2.y,
                                cameraTransform.columns.2.z)
        let forward = simd_normalize(-zAxis)
        let planePoint = camPos + forward * distanceM
        // Normal points back toward the camera.
        let normal = -forward
        return TablePlane(point: planePoint, normal: normal,
                          source: source, confidence: confidence)
    }
}

/// Locates the reference [TablePlane] for a captured frame.
///
/// • LiDAR tier → largest horizontal `ARPlaneAnchor` beneath the camera,
///   falling back to a virtual plane if none has been detected yet.
/// • Camera tier → virtual plane at the pre-programmed hold distance (30 cm).
final class PlaneDetector {

    /// Pick the table plane for the given frame and tier.
    ///
    /// - Parameters:
    ///   - frame:            The AR frame whose anchors / camera pose are used.
    ///   - tier:             Selected scan tier.
    ///   - assumedDistanceM: Hold distance (metres) for the virtual plane.
    func detectTablePlane(
        in frame: ARFrame,
        tier: DepthModeDetector.ScanTier,
        assumedDistanceM: Float
    ) -> TablePlane {
        let camTransform = frame.camera.transform

        guard tier == .lidar else {
            // Camera tier: always the assumed-distance virtual plane.
            return TablePlane.virtual(
                cameraTransform: camTransform,
                distanceM: assumedDistanceM,
                source: .assumedDistance,
                confidence: 0.5
            )
        }

        // LiDAR tier: prefer the largest horizontal plane anchor.
        let camPos = simd_float3(camTransform.columns.3.x,
                                 camTransform.columns.3.y,
                                 camTransform.columns.3.z)

        var best: ARPlaneAnchor?
        var bestArea: Float = 0
        for anchor in frame.anchors {
            guard let plane = anchor as? ARPlaneAnchor,
                  plane.alignment == .horizontal else { continue }
            let area = plane.planeExtent.width * plane.planeExtent.height
            if area > bestArea {
                bestArea = area
                best = plane
            }
        }

        if let plane = best {
            // Plane centre in world space.
            let centerLocal = simd_float4(plane.center.x, plane.center.y,
                                          plane.center.z, 1)
            let centerWorld4 = plane.transform * centerLocal
            let pointW = simd_float3(centerWorld4.x, centerWorld4.y, centerWorld4.z)

            // The plane's local +Y is its up axis.
            var n = simd_normalize(simd_float3(plane.transform.columns.1.x,
                                               plane.transform.columns.1.y,
                                               plane.transform.columns.1.z))
            // Ensure the normal points toward the camera.
            if simd_dot(n, camPos - pointW) < 0 { n = -n }

            return TablePlane(point: pointW, normal: n,
                              source: .arPlaneAnchor, confidence: 0.9)
        }

        // No anchor yet — virtual plane, but flagged as LiDAR fallback.
        return TablePlane.virtual(
            cameraTransform: camTransform,
            distanceM: assumedDistanceM,
            source: .lidarFallback,
            confidence: 0.6
        )
    }
}

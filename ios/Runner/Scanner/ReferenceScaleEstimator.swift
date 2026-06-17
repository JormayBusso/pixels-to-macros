import CoreGraphics
import Foundation
import simd

/// Refines the camera-tier hold distance using a known reference object.
///
/// The camera tier has no depth sensor, so it assumes the user holds the phone
/// at a pre-programmed distance (30 cm). When a reference object of known real
/// size is visible — most reliably a **dinner plate** — its apparent pixel size
/// lets us *recover the true distance* and correct the assumption:
///
///     distance = realSizeMetres × focalLengthPx / apparentSizePx
///
/// This keeps scale accurate even when the user holds the phone closer or
/// farther than 30 cm. Cutlery (fork/knife) is supported as an additional
/// reference via `refine(referenceSizeM:apparentSizePx:)` once a detector is
/// available; until then the plate is the primary cue.
final class ReferenceScaleEstimator {

    /// Plausible hold-distance band (metres). Anything outside is treated as a
    /// bad reference measurement and ignored in favour of the assumption.
    private let minDistanceM: Float = 0.15
    private let maxDistanceM: Float = 0.60

    /// Known real-world reference sizes (metres).
    enum Reference {
        /// Standard dinner-plate diameter.
        static let plateDiameterM: Float = 0.26
        /// Typical table-fork length.
        static let forkLengthM: Float = 0.20
        /// Typical table-knife length.
        static let knifeLengthM: Float = 0.21
    }

    /// Result of a distance refinement.
    struct Estimate {
        /// Best-estimate hold distance (metres).
        let distanceM: Float
        /// Whether a real reference object drove the estimate (vs the default).
        let fromReference: Bool
        /// 0…1 confidence in the scale.
        let confidence: Float
    }

    // MARK: – Public

    /// Refine the hold distance from a detected plate.
    ///
    /// - Parameters:
    ///   - plate:        Result from `PlateDetector`.
    ///   - intrinsics:   Camera intrinsics for the full-resolution frame.
    ///   - defaultDistanceM: The pre-programmed assumption (30 cm).
    func refineFromPlate(
        plate: PlateDetector.PlateResult,
        intrinsics: simd_float3x3,
        defaultDistanceM: Float
    ) -> Estimate {
        guard plate.detected, plate.diameterPx > 1 else {
            return Estimate(distanceM: defaultDistanceM,
                            fromReference: false, confidence: 0.4)
        }
        let fx = intrinsics.columns.0.x
        let fy = intrinsics.columns.1.y
        let focalPx = (fx + fy) * 0.5
        return refine(
            referenceSizeM: Reference.plateDiameterM,
            apparentSizePx: Float(plate.diameterPx),
            focalLengthPx: focalPx,
            defaultDistanceM: defaultDistanceM
        )
    }

    /// Generic refinement from any reference object of known real size.
    func refine(
        referenceSizeM: Float,
        apparentSizePx: Float,
        focalLengthPx: Float,
        defaultDistanceM: Float
    ) -> Estimate {
        guard apparentSizePx > 1, focalLengthPx > 1 else {
            return Estimate(distanceM: defaultDistanceM,
                            fromReference: false, confidence: 0.4)
        }

        let distance = referenceSizeM * focalLengthPx / apparentSizePx

        guard distance >= minDistanceM && distance <= maxDistanceM else {
            // Implausible — reference likely mis-detected; keep the assumption.
            return Estimate(distanceM: defaultDistanceM,
                            fromReference: false, confidence: 0.4)
        }

        // Confidence grows the closer the measurement is to the expected hold.
        let delta = abs(distance - defaultDistanceM)
        let confidence = max(0.5, 1.0 - delta / 0.30)
        return Estimate(distanceM: distance,
                        fromReference: true, confidence: confidence)
    }
}

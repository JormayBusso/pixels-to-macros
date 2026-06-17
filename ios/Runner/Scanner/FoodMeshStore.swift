import Foundation

/// Holds the most recent scan's renderable food surfaces so the 3-D model
/// platform view can build geometry without re-running the pipeline.
///
/// Written by `InferencePipeline` at the end of a scan; read by
/// `FoodModelView`. Access is serialised with a lock because the writer runs
/// on a background queue and the reader on the main thread.
final class FoodMeshStore {

    static let shared = FoodMeshStore()
    private init() {}

    /// One renderable food surface plus its label.
    struct Surface {
        let label: String
        let grid: FoodSurfaceGrid
    }

    private let lock = NSLock()
    private var _surfaces: [Surface] = []

    var surfaces: [Surface] {
        lock.lock(); defer { lock.unlock() }
        return _surfaces
    }

    func update(_ estimates: [FoodVolumeEstimate]) {
        lock.lock(); defer { lock.unlock() }
        _surfaces = estimates.compactMap { est in
            guard let grid = est.surface else { return nil }
            return Surface(label: est.label, grid: grid)
        }
    }

    func clear() {
        lock.lock(); defer { lock.unlock() }
        _surfaces = []
    }
}

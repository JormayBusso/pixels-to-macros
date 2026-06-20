import Foundation
import ModelIO
import simd

/// Writes a list of `DepthFusion.Food3DObject` to a single 3-D scene file on
/// disk.
///
/// Contract (enforced):
///   • This exporter is a strict CONSUMER of `DepthFusion.Food3DObject`. It
///     MUST NEVER recompute voxels, merge clusters, or re-sample colours.
///   • Each `Food3DObject` becomes ONE `MDLMesh` with its OWN `MDLMaterial`,
///     named after the object's stable id (e.g. `rice_0`, `chicken_0`).
///     The 3-D scene preserves the per-food hierarchy so downstream viewers
///     (and AR Quick Look) can toggle / hit-test individual foods.
///
/// Output strategy (Stage 1):
///   1. Try `.usdz` via `MDLAsset.export(to:)` — best for iOS AR Quick Look and
///      the SceneKit viewer planned for Stage 2.
///   2. Fall back to `.obj` (+ `.mtl`) when USDZ export is not supported by
///      the current Model I/O build.
final class Food3DExporter {

    /// Try to export `objects` to a 3-D scene file in the app's Documents
    /// directory. Returns the URL on success, `nil` on failure (caller logs).
    func export(
        objects: [DepthFusion.Food3DObject],
        baseName: String
    ) -> URL? {
        guard !objects.isEmpty else { return nil }

        let docs = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first!

        // Build the asset once and try multiple file types.
        print("[Food3DExporter] Export request: objects=\(objects.count), " +
              "usdz=\(MDLAsset.canExportFileExtension("usdz")), " +
              "usdc=\(MDLAsset.canExportFileExtension("usdc")), " +
              "obj=\(MDLAsset.canExportFileExtension("obj"))")
        for ext in ["usdz", "usdc", "obj"] where MDLAsset.canExportFileExtension(ext) {
            let url = docs.appendingPathComponent("\(baseName).\(ext)")
            if writeAsset(objects: objects, to: url) {
                // Verify file size
                if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                   let size = attrs[.size] as? Int {
                    print("[Food3DExporter] SUCCESS: \(url.lastPathComponent) size=\(size) bytes")
                }
                return url
            }
        }
        print("[Food3DExporter] No supported export format succeeded")
        return nil
    }

    // MARK: – Asset construction

    private func writeAsset(
        objects: [DepthFusion.Food3DObject],
        to url: URL
    ) -> Bool {
        let allocator = MDLMeshBufferDataAllocator()
        let asset = MDLAsset()

        var added = 0
        for object in objects {
            // INVARIANT: one Food3DObject = one MDLMesh = one MDLMaterial.
            // Never merge clusters here, even if two objects share a label.
            guard let mesh = buildMesh(object: object, allocator: allocator) else {
                continue
            }
            asset.add(mesh)
            added += 1
        }
        guard added > 0 else { return false }

        do {
            try asset.export(to: url)
            let exists = FileManager.default.fileExists(atPath: url.path)
            print("[Food3DExporter] Wrote \(added) mesh(es) to " +
                  "\(url.lastPathComponent), exists=\(exists)")
            return true
        } catch {
            print("[Food3DExporter] export(to: \(url.lastPathComponent)) failed: \(error)")
            // Best-effort cleanup of the partial file.
            try? FileManager.default.removeItem(at: url)
            return false
        }
    }

    private func buildMesh(
        object: DepthFusion.Food3DObject,
        allocator: MDLMeshBufferAllocator
    ) -> MDLMesh? {
        let vertexCount = object.vertices.count
        guard vertexCount > 0, object.faces.count >= 3 else { return nil }

        // Interleaved vertex layout: position (3 × Float32) + RGBA (4 × UInt8).
        // 4 bytes padding for the alpha channel keeps the stride 16 B aligned.
        let stride = MemoryLayout<Float>.size * 3 + 4

        var vertexBytes = Data(count: vertexCount * stride)
        vertexBytes.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) in
            guard let base = raw.baseAddress else { return }
            for i in 0..<vertexCount {
                let pos = object.vertices[i]
                let row = base.advanced(by: i * stride)
                let floats = row.assumingMemoryBound(to: Float.self)
                floats[0] = pos.x
                floats[1] = pos.y
                floats[2] = pos.z

                let bytes = row.advanced(by: 12).assumingMemoryBound(to: UInt8.self)
                let cIdx = i * 3
                bytes[0] = cIdx     < object.colors.count ? object.colors[cIdx]     : 200
                bytes[1] = cIdx + 1 < object.colors.count ? object.colors[cIdx + 1] : 200
                bytes[2] = cIdx + 2 < object.colors.count ? object.colors[cIdx + 2] : 200
                bytes[3] = 255
            }
        }
        let vertexBuffer = allocator.newBuffer(with: vertexBytes, type: .vertex)

        var indexBytes = Data(count: object.faces.count * MemoryLayout<UInt32>.size)
        indexBytes.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt32.self) else { return }
            for (i, face) in object.faces.enumerated() {
                base[i] = UInt32(face)
            }
        }
        let indexBuffer = allocator.newBuffer(with: indexBytes, type: .index)

        let descriptor = MDLVertexDescriptor()
        descriptor.attributes[0] = MDLVertexAttribute(
            name: MDLVertexAttributePosition,
            format: .float3,
            offset: 0,
            bufferIndex: 0
        )
        descriptor.attributes[1] = MDLVertexAttribute(
            name: MDLVertexAttributeColor,
            format: .uChar4Normalized,
            offset: 12,
            bufferIndex: 0
        )
        descriptor.layouts[0] = MDLVertexBufferLayout(stride: stride)

        let submesh = MDLSubmesh(
            indexBuffer: indexBuffer,
            indexCount: object.faces.count,
            indexType: .uInt32,
            geometryType: .triangles,
            material: makeMaterial(label: object.id)
        )

        let mesh = MDLMesh(
            vertexBuffer: vertexBuffer,
            vertexCount: vertexCount,
            descriptor: descriptor,
            submeshes: [submesh]
        )
        // USD object names must be valid identifiers (letters, digits,
        // underscores). The stable cluster id (e.g. `rice_0`) already
        // matches this format, but sanitise defensively in case labels
        // contain spaces or punctuation.
        mesh.name = sanitised(label: object.id)

        // Pre-compute smooth vertex normals so lighting works out-of-the-box
        // in QuickLook + the planned SceneKit viewer. `creaseThreshold = 0`
        // means: average normals everywhere (smooth shading).
        mesh.addNormals(withAttributeNamed: MDLVertexAttributeNormal, creaseThreshold: 0)

        return mesh
    }

    private func makeMaterial(label: String) -> MDLMaterial {
        // PhysicallyPlausible scattering keeps materials sensible in USD/USDZ.
        // One material per food object so per-instance edits stay isolated.
        let scatter = MDLPhysicallyPlausibleScatteringFunction()
        let material = MDLMaterial(name: sanitised(label: label), scatteringFunction: scatter)
        return material
    }

    private func sanitised(label: String) -> String {
        // USD object names must be valid identifiers (letters, digits,
        // underscores). Collapse anything else to "_".
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_")
        let scalars = label.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let cleaned = String(scalars)
        return cleaned.isEmpty ? "food" : cleaned
    }
}

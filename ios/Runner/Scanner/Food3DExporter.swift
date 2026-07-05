import CoreVideo
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
        baseName: String,
        textureSource: CVPixelBuffer? = nil,
        sideTextureSource: CVPixelBuffer? = nil
    ) -> URL? {
        guard !objects.isEmpty else { return nil }

        let docs = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first!

        // Per-vertex colour sidecar. USD/USDZ export via ModelIO silently DROPS
        // the vertex colour source (verified: a round-trip keeps positions and
        // normals but returns colorSources=0), so the exported scene renders as a
        // single dull averaged baseColour instead of the real sampled food
        // colours. The SceneKit viewer rebuilds geometry from this sidecar — an
        // in-process SCNGeometry keeps its colour source — so the inline preview
        // shows the true per-vertex colours. The USD file remains the AR / Quick
        // Look artefact; this sidecar is the colour-accurate source for the viewer.
        writeMeshSidecar(
            objects: objects,
            to: docs.appendingPathComponent("\(baseName).p2mesh")
        )

        // Paste the real captured photo onto the mesh. Earlier builds disabled
        // this because the top+side ATLAS stretched side-image rows into visible
        // stripes; the monocular estimator now emits a single seamless top-down
        // projection UV instead (no atlas, no side strip), so writing the top
        // photo as one continuous baseColor texture renders the food in its true
        // colour with no seams. `textureSource` is the mask-aligned preprocessed
        // top RGB, so its pixels line up exactly with the projected UVs.
        var textureURL: URL? = nil
        if let textureSource {
            let candidate = docs.appendingPathComponent("\(baseName)_texture.png")
            if Food3DTextureBaker.writeTexture(from: textureSource, to: candidate) {
                textureURL = candidate
                print("[Food3DExporter] baked photo texture -> \(candidate.lastPathComponent)")
            } else {
                print("[Food3DExporter] texture bake failed; using sampled colour")
            }
        }

        // Build the asset once and try multiple file types.
        print("[Food3DExporter] Export request: objects=\(objects.count), " +
              "usdz=\(MDLAsset.canExportFileExtension("usdz")), " +
              "usdc=\(MDLAsset.canExportFileExtension("usdc")), " +
              "obj=\(MDLAsset.canExportFileExtension("obj"))")
        for ext in ["usdz", "usdc", "obj"] where MDLAsset.canExportFileExtension(ext) {
            let url = docs.appendingPathComponent("\(baseName).\(ext)")
            if writeAsset(objects: objects, to: url, textureURL: textureURL) {
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

    // MARK: – Per-vertex colour sidecar

    /// Binary layout (little-endian, matches SceneKit's native byte order):
    ///
    ///     magic       : 4 bytes  'P','2','M','1'
    ///     objectCount : UInt32
    ///     per object:
    ///       idLength   : UInt32   + id UTF-8 bytes
    ///       avgColor   : 3 × Float32   (r,g,b in 0…1, fallback tint)
    ///       vertexCount: UInt32
    ///       positions  : vertexCount × 3 × Float32   (x,y,z, same space as USD)
    ///       colors     : vertexCount × 4 × UInt8     (r,g,b,a)
    ///       indexCount : UInt32
    ///       indices    : indexCount × UInt32
    ///
    /// A strict CONSUMER of `Food3DObject`: it copies the pipeline's vertices,
    /// colours and faces verbatim — never re-sampling or re-meshing.
    private func writeMeshSidecar(
        objects: [DepthFusion.Food3DObject],
        to url: URL
    ) {
        var data = Data()
        func append<T>(_ value: T) {
            var v = value
            withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
        }

        data.append(contentsOf: [0x50, 0x32, 0x4D, 0x31]) // 'P','2','M','1'
        append(UInt32(objects.count))

        for object in objects {
            let idBytes = Array(object.id.utf8)
            append(UInt32(idBytes.count))
            data.append(contentsOf: idBytes)

            let avg = Self.averageColor(of: object.colors) ?? SIMD3<Float>(0.78, 0.78, 0.78)
            append(avg.x); append(avg.y); append(avg.z)

            let vertexCount = object.vertices.count
            append(UInt32(vertexCount))
            for v in object.vertices {
                append(v.x); append(v.y); append(v.z)
            }
            for i in 0..<vertexCount {
                let c = i * 3
                data.append(c     < object.colors.count ? object.colors[c]     : 200)
                data.append(c + 1 < object.colors.count ? object.colors[c + 1] : 200)
                data.append(c + 2 < object.colors.count ? object.colors[c + 2] : 200)
                data.append(255)
            }

            append(UInt32(object.faces.count))
            for face in object.faces {
                append(UInt32(face))
            }
        }

        do {
            try data.write(to: url, options: .atomic)
            print("[Food3DExporter] wrote mesh sidecar \(url.lastPathComponent) " +
                  "objects=\(objects.count) bytes=\(data.count)")
        } catch {
            print("[Food3DExporter] mesh sidecar write failed: \(error)")
        }
    }

    // MARK: – Asset construction

    private func writeAsset(
        objects: [DepthFusion.Food3DObject],
        to url: URL,
        textureURL: URL?
    ) -> Bool {
        let allocator = MDLMeshBufferDataAllocator()
        let asset = MDLAsset()

        var added = 0
        for object in objects {
            // INVARIANT: one Food3DObject = one MDLMesh = one MDLMaterial.
            // Never merge clusters here, even if two objects share a label.
            guard let mesh = buildMesh(object: object, allocator: allocator, textureURL: textureURL) else {
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
        allocator: MDLMeshBufferAllocator,
        textureURL: URL?
    ) -> MDLMesh? {
        let vertexCount = object.vertices.count
        guard vertexCount > 0, object.faces.count >= 3 else { return nil }

        // Texture only when explicitly enabled. Current scan UX uses solid
        // per-object sampled colours, so `textureURL` is intentionally nil.
        let hasTexture = textureURL != nil && object.uvs.count == vertexCount

        // Interleaved layout: position (3 × Float32) + RGBA (4 × UInt8), plus a
        // UV (2 × Float32) when textured. RGBA padding keeps positions aligned;
        // the UV is appended after it.
        let uvOffset = MemoryLayout<Float>.size * 3 + 4 // 16
        let stride = hasTexture ? uvOffset + MemoryLayout<Float>.size * 2 : uvOffset

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

                if hasTexture {
                    let uv = row.advanced(by: uvOffset).assumingMemoryBound(to: Float.self)
                    uv[0] = object.uvs[i].x
                    uv[1] = object.uvs[i].y
                }
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
        if hasTexture {
            descriptor.attributes[2] = MDLVertexAttribute(
                name: MDLVertexAttributeTextureCoordinate,
                format: .float2,
                offset: uvOffset,
                bufferIndex: 0
            )
        }
        descriptor.layouts[0] = MDLVertexBufferLayout(stride: stride)

        let averageColor = Self.averageColor(of: object.colors)
        let submesh = MDLSubmesh(
            indexBuffer: indexBuffer,
            indexCount: object.faces.count,
            indexType: .uInt32,
            geometryType: .triangles,
            material: makeMaterial(
                label: object.id,
                textureURL: hasTexture ? textureURL : nil,
                averageColor: averageColor
            )
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

        // Pre-compute normals so lighting works out-of-the-box in QuickLook
        // and SceneKit. Monocular visual-hull meshes preserve creases because
        // averaging every normal made top/side/underside surfaces read as one
        // soft blanket shell over the food.
        mesh.addNormals(
            withAttributeNamed: MDLVertexAttributeNormal,
            // A moderate crease threshold keeps genuine silhouette/rim edges
            // defined while smoothing gentle curvature, so the camera estimate
            // renders as a rounded food surface instead of a hard faceted/cubic
            // block (creaseThreshold 1) or a featureless soft blanket (0).
            creaseThreshold: object.preserveCreases ? 0.45 : 0
        )

        return mesh
    }

    private func makeMaterial(label: String, textureURL: URL?, averageColor: SIMD3<Float>?) -> MDLMaterial {
        // PhysicallyPlausible scattering keeps materials sensible in USD/USDZ.
        // One material per food object so per-instance edits stay isolated.
        let scatter = MDLPhysicallyPlausibleScatteringFunction()
        // Food is matte-to-semi-glossy: a high roughness with zero metalness
        // reads as natural and appetising instead of a shiny plastic surface,
        // in both the SceneKit and RealityKit PBR viewers.
        scatter.roughness.floatValue = 0.65
        scatter.metallic.floatValue = 0.0
        let material = MDLMaterial(name: sanitised(label: label), scatteringFunction: scatter)

        // Photo projection is intentionally disabled for generated scans; it
        // created visible stripes when the top/side atlas stretched across the
        // reconstructed surface. Prefer the sampled food/object colour.
        if let textureURL {
            let sampler = MDLTextureSampler()
            sampler.texture = MDLURLTexture(
                url: textureURL, name: sanitised(label: label) + "_tex"
            )
            let baseColor = MDLMaterialProperty(name: "baseColor", semantic: .baseColor)
            baseColor.type = .texture
            baseColor.textureSamplerValue = sampler
            material.setProperty(baseColor)
        } else if let averageColor {
            // Use the food's sampled colour as a solid baseColor so it renders
            // in real colour rather than plain white/grey.
            let baseColor = MDLMaterialProperty(name: "baseColor", semantic: .baseColor)
            baseColor.type = .float3
            baseColor.float3Value = averageColor
            material.setProperty(baseColor)
        }
        return material
    }

    /// Mean of the per-vertex RGB triples (0–1 floats), or nil if absent.
    private static func averageColor(of colors: [UInt8]) -> SIMD3<Float>? {
        guard colors.count >= 3 else { return nil }
        var r = 0, g = 0, b = 0, n = 0
        var i = 0
        while i + 2 < colors.count {
            r += Int(colors[i]); g += Int(colors[i + 1]); b += Int(colors[i + 2])
            n += 1
            i += 3
        }
        guard n > 0 else { return nil }
        return SIMD3<Float>(
            Float(r) / Float(n) / 255.0,
            Float(g) / Float(n) / 255.0,
            Float(b) / Float(n) / 255.0
        )
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

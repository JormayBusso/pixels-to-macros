# Scanner Validation Phase

A repeatable, on-device procedure to confirm the AI scanner produces faithful
3-D reconstructions and plausible volumes **before** worrying about production
readiness. Run this after the P1 reconstruction fix and the diagnostics system
land.

> The agent cannot run this — it requires the physical iPhone 16 Plus
> (monocular, no LiDAR) and real food. This is the human-in-the-loop checklist.

## Live food glow checks

LiDAR framing and non-LiDAR TOP/SIDE framing use the same
`com.pixelstomacros/ar_camera` preview and native live glow renderer. Saved
capture segmentation, geometry and texture projection are separate and unchanged
by the live-only gates.

- Check a plate with food, then an empty table, plate, utensils and other objects:
  only recognized food classes should receive a glow. Unknown/generic labels
  are rejected; ML food-class false positives remain possible.
- Pan/rotate the camera, switch TOP to SIDE, close/reopen the scanner and
  background/foreground the app. Old outlines must disappear rather than trail
  the previous image. Check both landscape directions and the guide alignment.
- The current food mask should have a soft fill/edge/core glow without
  historical-mask blending or trails. This live-only blur never alters the
  saved segmentation or reconstructed silhouette.
- Paste `[LiveGlow] backend=`, `infer=`, `drop_stale`, `roi` and any
  `label_map_rejected` logs. Frames older than 350 ms or displaced by more than
  1 cm / 3° are not displayed. A slow model can therefore yield fewer/no live
  glows; it must not fall back to highlighting arbitrary foreground objects.
- Host regression checks: `python3 ios/RunnerTests/run_live_overlay_checks.py`.
  These validate live label gates, reset/backlog handling, freshness, camera
  motion, smooth bounded glow fields and ROI mapping, not on-device ML/render quality.

Scheduling follows Apple's [TN2445](https://developer.apple.com/library/archive/technotes/tn2445/_index.html):
one inference slot, discard busy frames, and promptly release camera buffers.

## Where the data comes from

Every successful scan now captures a full telemetry snapshot. Open it via:

**Settings → Debug → Scanner Diagnostics**

Each scan card expands to show, per food: `scan_mode`, `scale_source`,
`volume_cm3` (and `raw_volume_cm3`), `footprint`/`height`, `weight_g`, whether
the **side** silhouette was applied, whether a **fallback** prior was used, and
whether the **volume guardrail** softened the result. Use **Copy all** to paste
a run into notes.

## Free trained model stack

The current on-device recognition path uses only free, local models:

| Purpose | Model/resource | Notes |
| ------- | -------------- | ----- |
| Food masks | `FoodSegYolo.mlmodelc` | Primary instance segmentation and crop masks. |
| Open-vocabulary labels | `MobileCLIPImage.mlmodelc` + `FoodLabelEmbeddings.json` | Apple MobileCLIP-S2/datacompdr image encoder with a 361-label food table generated from [training/food_vocab.txt](../training/food_vocab.txt). |
| Fine-grained fallback labels | `FoodClassifier.mlmodelc` + `FoodClassifierLabels.json` | Free `nateraw/food` Food-101 ViT classifier. It only overrides when its confidence clears the conservative gate in `InferencePipeline`. |

Refresh the free recognition resources after editing the vocabulary:

```bash
/Users/jormaybusso/pixels-to-macros/.venv/bin/python training/export_mobileclip.py --compile_ios
ruby scripts/add_yolo_model.rb MobileCLIPImage.mlmodelc
ruby scripts/add_yolo_model.rb FoodLabelEmbeddings.json
```

Refresh the optional Food-101 classifier:

```bash
/Users/jormaybusso/pixels-to-macros/.venv/bin/python training/export_food_classifier.py --compile_ios
ruby scripts/add_yolo_model.rb FoodClassifier.mlmodelc
ruby scripts/add_yolo_model.rb FoodClassifierLabels.json
```

## Test items (known, easy to verify)

| Item            | Approx. real volume | Approx. real weight |
| --------------- | ------------------- | ------------------- |
| Medium tomato   | ~90–110 cm³         | ~90–120 g           |
| Medium banana   | ~110–130 cm³        | ~115–135 g          |
| Medium apple    | ~150–180 cm³        | ~150–180 g          |
| Chicken breast  | ~120–160 cm³        | ~150–200 g          |

Place each on a **plate of known diameter** so `scale_source = plate_diameter`.

## Per-item checklist

For each item, capture top + side as guided, then open Scanner Diagnostics:

- [ ] **Reconstruction shape** (in the 3-D viewer): rounded/organic, **not** a
      cube/cylinder. Silhouette and rim follow the real outline.
- [ ] `scan_mode` is `monocular_visual_hull` (preferred) — not stuck on
      `monocular_scale` only.
- [ ] `scale_source` is `plate_diameter` (or `arkit_plane`) — **not**
      `fallback_22cm`.
- [ ] `side=true` and `fallback=false` → `bothViews=true`.
- [ ] `volume_cm3` lands within the item's expected range above.
- [ ] `weight_g` is plausible for the portion.
- [ ] Guardrail **not** engaged for normal portions (`guardrail: softened`
      should be absent). If it fires often, the raw estimate is overshooting.

## Repeatability / stability

- [ ] Scan the **same** tomato 3× without moving it. `volume_cm3` should be
      consistent (spread within ~±15%).
- [ ] Scan two **different-sized** items. Larger item reports larger
      `volume_cm3` and `weight_g` (monotonic — no inversions).

## Performance sanity

- [ ] `inference` time is acceptable on-device (check the chip on each card).
- [ ] `mem` peak does not spike toward an OOM.
- [ ] No dropped frames / UI jank during the AI edge-glow + capture.

## Failure triage (what each signal means)

| Symptom in diagnostics                         | Likely cause / next step                                   |
| ---------------------------------------------- | ---------------------------------------------------------- |
| `scale_source = fallback_22cm`                 | Plate not detected — improve plate framing/contrast.       |
| `side=false`, `fallback=true`                  | Missing capture, unmatched/occluded food, or invalid mask; inspect `[CAPTUREPAIR]` and `[SIDEMATCH]`. Top-only monocular geometry is a zero-thickness sheet, not an inferred portion. |
| Visible horizontal layers                      | Monocular mesh should report `surface_extraction_mode = exact_silhouette_loft`; otherwise an old layered hull path is still being used. |
| Cube/cylinder shape                            | Inspect missing-side input and silhouette association; do not add smoothing, rim taper, or class thickness. |
| `guardrail: softened` on a normal portion      | Raw volume overshoot — review envelope for that label.     |
| `volume_cm3` swings wildly on identical scans  | Unstable scale or silhouette extraction.                   |

## October 2026 dual-photo repeatability regression

The five-piece beef plate (468 g **after trimming**) exposed three code-level
failures, independent of theme: overlapping top spans deliberately shared the
same side-mask slice; a failed **primary** silhouette check discarded every
other valid side profile; and missing side evidence generated an invented
0.4–2.2 cm extrusion. Photo color used local silhouette bounding-box coordinates
rather than the captured camera geometry. Detection count remains an ML result:
the side capture never creates a missing fifth top detection.

### Native contracts

- **Capture:** replacement top capture invalidates previous side RGB/depth and
  calibration. A side must be newer than the top and from the same AR session
  generation. An inference-in-flight gate prevents another scan from replacing
  or releasing the recorder while its background pipeline is reading it.
- **Non-LiDAR:** profiles survive primary-check failure and are validated per
  item. Small/thin/rectangular measured profiles are not rejected merely by
  area, aspect ratio, or fill. Disconnected side masks are separated using their
  original pixels. Pose/intrinsics/crop plus the captured table plane project top
  footprints into the side image; ambiguous overlapping footprints are never
  given identical side slices. With calibration the nearest visible item may
  own an occluding segment; hidden items stay explicitly unmatched.
- **Geometry:** exact top mask intersects the measured side profile and its
  mirrored transverse profile. Empty side samples remain empty; no gap filling,
  top-hole filling, primitive, class dimension/thickness floor, subdivision, or
  smoothing is introduced. Missing monocular height produces an exact top-mask
  sheet with `scan_mode=monocular_top_only`, `volume_measured=false`,
  `side_missing_reason`, and zero display-mesh volume—not an inferred portion.
  The old generic hidden bowl-cavity route is disabled on both sensor paths.
- **Color:** calibrated monocular side vertices and atlas coordinates use the
  captured top/side poses, intrinsics, crops, and table plane. Samples must stay
  inside their matched side mask; off-image projections fall back to top-photo
  color rather than clamping onto another food. If no table plane is available,
  existing mask-bounds correspondence is explicitly logged as
  `projection=uncalibrated_mask_bounds`; its accuracy is not claimed.
- **LiDAR separately:** top-instance ownership survives label assignment;
  separate top masks remain separate even when their same-label depth shells
  touch. Each cluster is carved by its **matched instance mask**, not the union
  of all foods, and also by its mirrored transverse side constraint. Low
  retention never undoes carving. Side-photo colors require the same matched
  mask plus camera visibility/depth tests. Missing side retains observed depth,
  logs degraded geometry explicitly, and never substitutes a class primitive.
  Sub-voxel side carving uses 2.5 mm cells when the mesh-grid size permits it;
  sparse-depth foods use an exact silhouette hull on a measured support plane.
  If neither depth nor side evidence supplies height, LiDAR requests a retake
  rather than dropping the food or inventing geometry. An empty side carve is
  never undone by restoring the uncarved solid.
  Surface Nets remains the existing depth surface extraction; no added
  smoothing/subdivision. The exported mesh remains the volume source.

Reliable references: Apple's [scene-depth point-cloud example](https://developer.apple.com/documentation/arkit/displaying-a-point-cloud-using-scene-depth)
for captured-image intrinsics and ARKit camera/world projection conventions;
Laurentini's visual-hull definition (intersection of silhouette cones, not a
recovery of hidden concavities). The symmetry of the transverse side remains an
explicit observation-limited assumption.

### Deterministic checks and device acceptance

Run `python3 ios/RunnerTests/run_repeatability_checks.py`: existing-target
XCTest regression methods execute against extracted **production** Swift
helpers with fail-fast assertions (no copied algorithm). Covers duplicated
profiles, calibrated occlusion, small mislabeled pieces, missing side, crop/
gravity/photo projection, thin profiles/out-of-image sampling, and sparse-depth
LiDAR hulls. `testMonocularMissingSideExportsUnmeasuredTopMaskSheet` runs in
RunnerTests on the simulator and verifies actual export plus unmeasured metadata.
The host
check is not an iOS typecheck or substitute for release/simulator compilation;
the coordinator must run those builds and deploy.

Re-scan the unchanged five-piece plate at least three times, keeping the side
capture **level** and exposing separated profiles; repeat with LiDAR separately.
Paste `[CAPTUREPAIR]`, `[INSTANCES]`, `[SIDEMATCH]`, `[DUALHULL]`,
`[MonocularEstimator] visual-hull`, `[SIDECOLOR]`, `[ScaleValidation]`,
`[EVAL]`, and `[Scan3DViewer]`/sidecar `avgColor` logs. Check five top instances,
unique appropriate side-mask owners, both scales/crops, missing-side reasons,
side color, and `volume_source=display_mesh`. Render/accuracy acceptance is
**device-only and unconfirmed** until these runs.

**Required UI follow-up (not changed here):** consume `volume_measured=false`
without presenting zero calories/weight as a measured portion; show a localized
(en/nl/es/de/pl) level-side recapture prompt and distinguish missing capture,
occlusion/unmatched masks, and unavailable calibration. Native diagnostics alone
do not provide that user-facing explanation.

## Record results

Use **Copy all** in Scanner Diagnostics and paste the runs (item, expected vs.
reported volume/weight, pass/fail per checkbox) into the validation log. Only
after the checklist passes on the target device should production-readiness work
begin.

## Automated coverage

The diagnostics plumbing itself is covered by
[test/scan_diagnostics_test.dart](../test/scan_diagnostics_test.dart) (payload
parsing, `bothViews` logic, guardrail capture, report formatting). The on-device
checklist above validates the *reconstruction quality* that automated tests
cannot.

# Scanner Validation Phase

A repeatable, on-device procedure to confirm the AI scanner produces faithful
3-D reconstructions and plausible volumes **before** worrying about production
readiness. Run this after the P1 reconstruction fix and the diagnostics system
land.

> The agent cannot run this — it requires the physical iPhone 16 Plus
> (monocular, no LiDAR) and real food. This is the human-in-the-loop checklist.

## Where the data comes from

Every successful scan now captures a full telemetry snapshot. Open it via:

**Settings → Debug → Scanner Diagnostics**

Each scan card expands to show, per food: `scan_mode`, `scale_source`,
`volume_cm3` (and `raw_volume_cm3`), `footprint`/`height`, `weight_g`, whether
the **side** silhouette was applied, whether a **fallback** prior was used, and
whether the **volume guardrail** softened the result. Use **Copy all** to paste
a run into notes.

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
| `side=false`, `fallback=true`                  | Side mask rejected by `usableSideProfile` gates.           |
| Cube/cylinder shape                            | Mesh smoothing/rim taper regression (Food3DExporter).      |
| `guardrail: softened` on a normal portion      | Raw volume overshoot — review envelope for that label.     |
| `volume_cm3` swings wildly on identical scans  | Unstable scale or silhouette extraction.                   |

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

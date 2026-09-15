# Improved reconstruction and comparison window

Implemented 2026-09-15 in PodTrack 0.9.0 (16), then integrated as the default throughout the app in **0.10.0 (17)**. The experimental core version is `0.5.0-constrained-experimental`; **Old** retains `0.4.0-heuristic`.

## What changed

`ImprovedReconstruction` computes a second result from the same saved `RunSession`. It reuses the baseline's sensor, calibration, timestamp and attitude-reference validation. It neither writes to the run store nor changes calibration or saved settings.

1. **Full-vector smoothing.** Form a unit forward direction from the unsmoothed signal, average its XYZ components over the requested time window and normalize. Heading/slope are derived afterwards for display. This avoids the artificial sideways bend caused by averaging heading across a vertical passage. A nearly canceled average falls back to the measured direction and warns.
2. **Supported edge rest and bias.** Only contiguous stable windows at the recording edges can constrain speed to zero. A single supported edge supplies a constant tangential acceleration offset; two supported edges permit linear bias drift. A moving start is not forced to rest. Interior quiet sections never become stop constraints.
3. **Nonnegative speed fit.** Solve a sparse convex quadratic over speed at each sample. Residuals combine tangential acceleration increments, speed smoothness and normal acceleration during turns. Speed is constrained to be nonnegative within the solver. No positive speed floor is added.
4. **Matched circuits.** Detect complete inversions using calibrated car-up relative to gravity. Compare entire inversion-to-inversion direction sequences, resampled at 41 points of accumulated 3D turning angle. A group needs at least two mutually compatible intervals, a turning-arc ratio above 0.8 and an RMS direction difference below 15°. There is no recording-specific time, geometry or lap-count constant.
5. **Return and shared-route constraints.** For enabled matching intervals inside the active motion span, penalize XYZ return error, total-distance differences and distance differences across eight equal turning-angle sections. Each interval retains its measured duration and can have different speeds. A switch disables all of these repeat constraints while retaining the detector's diagnostics.
6. **Existing physical scaling.** Integrate direction times fitted speed, apply the entered H/length through the existing reconstructor, attach metrics and report the scale correction. Unknown H and length remain relative units.

For fixed unit tangent `d`, the path increment is the trapezoidal integral of `v d`. Under the rigid-mount, tangent-alignment and small sensor-offset assumptions, the sensor-frame normal acceleration satisfies approximately:

```text
w = angularVelocity × forwardDevice
a_normal ≈ v w
```

This provides speed evidence during turns. The solver retains explicit acceleration polarity settings; automatic polarity uses consistent turning evidence when available and an early-descent fallback otherwise. Impacts and perpendicular acceleration mismatch are downweighted, and high residual disagreement generates a warning.

The projected accelerated-gradient solver has a 12,000-iteration limit, a projected-gradient convergence check and cancellation support. Its sparse residual rows avoid a dense sample-by-sample matrix. Residual weights are experimental tuning parameters, not calibrated statistical uncertainties. Attitude and mounting are fixed inputs; this implementation does not optimize calibration, attitude drift or a full inertial-navigation state.

The optional `forwardDirection` and `reconstructionDiagnostics` fields preserve decoding of older analysis JSON. The legacy `endpointAccelerationCorrection` field reports the fit's mean acceleration-increment discrepancy; this solver does not apply the baseline's uniform endpoint correction.

## Latest recording

Source: `E7E31364-5AB2-41F6-B402-BA55292EC450`, recorded 2026-09-15 at 15:11:14 Europe/Warsaw. Left AirPod, 680 samples, 13.58 s, H = 58 cm. A copy is the regression fixture in `Tests/PodTrackCoreTests/Fixtures/repeated-circuit.json`.

| Result | Current | Improved |
| --- | ---: | ---: |
| Estimated total distance | 10.97 m | 25.90 m |
| Estimated peak speed | 2.79 m/s | 6.80 m/s |
| Circuit 1, 1.78–4.54 s | 2.00 m | 6.47 m |
| Circuit 2, 4.54–7.74 s | 6.01 m | 6.47 m |
| Circuit 3, 7.74–10.86 s | 1.08 m | 6.47 m |
| Longest near-zero speed during sustained rotation | 1.86 s | None detected |
| Steepest down/up direction | −62.3° / +63.2° | −84.5° / +88.3° |

The detector finds four inversion landmarks and three matching complete intervals. Direction signatures differ from the reference by 5.87° and 8.45° RMS. It does not equate these three intervals with the total number of physical loops or laps outside them.

The improved fit converges in 1,000 iterations, about 0.04 s in an optimized standalone core run on this machine. Return gaps are 0.42, 1.97 and 0.56 cm **after applying return constraints**. Equal lengths and small gaps measure fit consistency, not independent accuracy.

The stable ending supports rest; the start does not. The inferred active interval is 0–13.14 s. The height constraint scales the solution by 2.30×. Pre-scaling tangential acceleration residual RMS is 2.67 m/s² and turning residual RMS is 7.86 m/s². That remaining disagreement and the large scale correction mean that absolute distances and peak speed should not yet be treated as physically validated. A measured circuit length and independent video timing are the useful next checks.

## Separate window

The main Run Analysis, Track Visualization, Saved Runs & Compare and Export screens now share an **Improved / Old** selector. App startup and completion of each new recording select Improved. The selector changes the active geometry, metrics, measurements and exports together. Caches and errors are kept separately for each method; edits and recoverable deletion invalidate both. Canceled calculations cannot publish into a newly selected method or restore a removed recording. The recording-review panel uses the active method's rest diagnostics.

The separate window below continues to show both methods simultaneously.

**Compare algorithms** in the toolbar or **Command-Shift-K** opens the window. It has a recording picker, two orbitable SceneKit roads, common initial/reset camera framing, shared play/pause/restart and time slider, an overlaid speed chart, repeat-constraint and height-plane toggles, and expandable fit details. Chart scrubbing pauses playback.

The launch option `--compare-algorithms` opens it directly without starting the hardware stream. An optional developer argument `--comparison-receipt <path>` writes this process's visible window titles, loaded run ID and point counts after the calculation finishes. This only observes the app's own windows.

## Validation completed

- Built and signed the release app using the installed Command Line Tools and macOS 26.5 SDK.
- Independently constructed a constant-speed vertical circle from analytic position, orientation, angular velocity and acceleration. The improved method reconstructed 7.274 m against a 7.288 m analytic length and 1.524 m/s peak against a 1.518 m/s analytic speed.
- Verified that vector smoothing preserves that circle's plane; the baseline's separate-angle smoothing produced a maximum sideways tangent component of 0.144.
- Ran standalone checks for single-pass rejection of repeat closure, the repeat switch, mismatched direction signatures, relative units, a biased stationary recording and bias correction from a final rest alone.
- Reconstructed the real regression recording through both production methods. Baseline length remains 10.97116518977551 m; all three repeat intervals and the absence of the sustained collapse were verified in the improved output.
- Rendered and visually inspected actual SceneKit scenes and native SwiftUI comparison content at widths 1,120 and 1,420 points. The live app's own receipt confirms both the main and algorithm-comparison windows are visible, with 680 points per result and the latest recording selected.
- Added eight XCTest cases covering the core behaviors, unchanged raw data/baseline output, malformed timestamps and analysis Codable round-tripping. **XCTest execution remains blocked by Xcode's unaccepted license; Command Line Tools alone do not supply XCTest.** The standalone checks above passed and are separate from this pending suite.

After accepting Xcode's license through Xcode, run:

```sh
bash scripts/test.sh
```

The native render/export command is documented in the README. Current development artifacts are under `build/improved-comparison/`, including both JSON results, the native comparison images, analytic checks and the window receipt.

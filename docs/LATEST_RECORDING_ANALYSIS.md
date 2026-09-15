# Latest recording investigation — 15 September 2026

## Conclusion

The recording captures repeatable track motion. The largest reconstruction problem is the speed estimate: it becomes zero during an apparently moving section, so that section contributes no distance. Separately, smoothing heading and slope as independent angles distorts the vertical loop. Repeated visits to the same track section provide useful constraints that the current algorithm does not use.

The recommendations below were implemented as the experimental comparison method in app version 0.9.0. See [IMPROVED_RECONSTRUCTION.md](IMPROVED_RECONSTRUCTION.md) for the implementation, results and remaining validation limits. This document preserves the original investigation of the baseline.

This was an investigation with offline experiments. Application source, saved recordings, mounting calibration and recording settings were not changed.

## Recording and evidence

- **Run:** `E7E31364-5AB2-41F6-B402-BA55292EC450`, “Untitled track · Hot Wheels · Left AirPod.”
- **Recorded:** 15 September 2026, 15:11:14 Europe/Warsaw; `13:11:14Z` in storage.
- **Data:** 680 samples over 13.58 seconds; source timestamps are spaced at 20 ms, or 50 Hz. No source-timestamp gaps appear in this run. This does not measure Bluetooth latency.
- **Calibration:** saved Left AirPod mounting profile captured at 15:08:22.
- **Settings:** H = 58 cm, height-range mode, 100 ms smoothing, automatic acceleration polarity, endpoint-rest enabled, no known length.
- **Pipeline reproduced:** `0.4.0-heuristic`, compiled directly from the current `Sources/PodTrackCore` files.
- **References:** the supplied physical-track photo and reconstruction screenshot. There is no synchronized video or surveyed path in this analysis.

The photo contains one vertical inversion loop. In the recording, the calibrated car-up axis reverses relative to gravity four times. The most inverted sample in each passage occurs at **1.78, 4.54, 7.74 and 10.86 seconds**. Their orientations differ from the first by approximately 0°, 3.4°, 7.6° and 9.7°.

I interpret the three intervals between these four passages as candidate repeated circuits, consistent with the user's description of three loops. A vertical-loop passage is a landmark, not itself a complete circuit. Matching this landmark alone does not establish that every intervening route is identical; branches or different routes must remain possible until the full motion sequence or video confirms the correspondence.

### The same candidate circuit gets very different sizes

| Candidate interval | Duration | Current estimated distance | Separation between the two landmark positions |
| --- | ---: | ---: | ---: |
| A → B, 1.78–4.54 s | 2.76 s | 2.00 m | 0.42 m |
| B → C, 4.54–7.74 s | 3.20 s | 6.01 m | 1.02 m |
| C → D, 7.74–10.86 s | 3.12 s | 1.08 m | 0.17 m |

These distances are outputs of the current height-scaled model, not measurements of the physical track. If these intervals follow the same route, their lengths should agree even when lap times differ. The roughly 5.5-fold distance spread is a direct consistency failure. The candidate common landmark also drops by 6.8, 23.9 and 11.7 cm between visits in the reconstruction.

The full recording currently reconstructs as 10.97 m with a maximum speed of 2.79 m/s. Neither value is validated by this experiment.

## Findings

### 1. Speed integration collapses a moving section

From **8.90 to 10.70 seconds**, the displayed speed is effectively zero. During those 1.80 seconds:

- The processed heading travels approximately **252°** in total.
- The raw gyroscope magnitude averages **2.90 rad/s**, approximately 166°/s.
- The surrounding orientation and slope sequence resembles the preceding circuits.

Given a car continuing around the track, zero travel over that interval is inconsistent with the recorded motion. Rotation alone cannot rule out a car being turned in place, but the repeated sequence and track context strongly favor a collapsed travel estimate here.

The mechanism is explicit in [SpeedEstimator.swift](/Users/andriiliubivyi/Documents/ChatGPT/pod_track/Sources/PodTrackCore/SpeedEstimator.swift:52): subtract one constant acceleration correction across the motion interval, integrate, then apply `max(0, integral)`. The integral can remain negative for many samples; clipping its output keeps position stationary until the integral recovers.

For this recording:

- The constant correction is **0.9879 m/s²**, just below the existing `> 1` warning threshold.
- Before the endpoint correction, the nominal integrated end speed is **13.42 m/s**. After correction, the minimum integral is **−2.87 m/s**. These are intermediate values before the H scale, not physical speed measurements.
- **25.9% of sample values** have a negative corrected integral before clipping; this includes recording edges as well as the interior failure.
- An independent numerical reproduction matches the production speed output to within `8 × 10⁻¹⁴` before height scaling.

A small positive speed floor would conceal the failure while inventing distance. Instead, fit a nonnegative speed profile jointly with the available physical constraints and report when those constraints cannot explain the data.

### 2. Independent angle smoothing flattens vertical motion

[SignalProcessor.swift](/Users/andriiliubivyi/Documents/ChatGPT/pod_track/Sources/PodTrackCore/SignalProcessor.swift:105) smooths heading and slope separately. When the car approaches vertical, its horizontal forward projection becomes tiny and heading becomes ill-conditioned. It can flip by approximately 180° as the car passes through vertical. Averaging that angle independently from the folded slope can create an artificial sideways direction.

I tested an isolated alternative offline: construct the full unit forward direction from the unsmoothed production signals, average its XYZ components with the same elapsed-time window, normalize, and retain the existing speed estimate.

| Direction processing | Steepest descent | Steepest ascent |
| --- | ---: | ---: |
| Unsmooth recorded orientation | −85.59° | +89.20° |
| Current 100 ms angle smoothing | −62.27° | +63.23° |
| 100 ms vector smoothing prototype | −84.46° | +88.28° |

The two smoothing approaches differ by up to **31.3°** in estimated direction. The vector prototype changes the estimated total length to 10.55 m, but preserves the zero-speed interval because speed was held fixed. This demonstrates two separate problems; it does not establish ground-truth geometry accuracy.

In production, store and integrate the full direction, or a suitably filtered quaternion. Derive display angles afterward. Handle a near-zero averaged vector explicitly. Suppress horizontal-heading interpretations near vertical, and distinguish genuine fast loop rotation from a reference reset using the existing quaternion/gyro continuity evidence. This run reaches 27.4 rad/s of reported rotation, so a generic “abrupt heading change” warning is not sufficient to identify a reset.

### 3. Endpoint detection is too brittle for this trace

The current quiet-sample test requires both acceleration below 0.035 g and rotation below 0.15 rad/s. The longest contiguous quiet span is only **0.06 seconds**, so the inferred motion interval consumes the entire recording. The final approximately 0.70 seconds have low rotation, but acceleration after 13 seconds has a median magnitude of **0.101 g**.

This could reflect residual acceleration error or continued straight travel; low rotation alone cannot distinguish those cases. It does show why the current threshold fails to identify a supported end-rest interval.

Use sustained windows, signal variation, attitude stability and a robust local offset estimate, together with the user's rest assumption. Retain a manual release/finish selection when rest is not established. Do not silently treat quiet interior travel as a stop.

### 4. Height scaling and rendering cannot enforce repeatability

[TrackReconstructor.swift](/Users/andriiliubivyi/Documents/ChatGPT/pod_track/Sources/PodTrackCore/TrackReconstructor.swift:33) integrates direction times speed and then scales the whole path to H. It has no return-to-landmark or repeated-route constraints. Fitting 58 cm guarantees the displayed total height range, even when accumulated vertical drift contributes to that range.

Consequently, repeated visits are drawn as different pieces of road at different positions and sizes. This is primarily an estimation issue. A later display improvement should show one fitted common route, with separate lap timing and playback, once repeated-route correspondence is established.

## Parameter experiments

Ten variants of the latest recording were run through the production pipeline, alongside six recent saved recordings for context. Other recordings were not assumed to be ground truth or identical routes.

| Latest-run experiment | Estimated total length | What it shows |
| --- | ---: | --- |
| Current defaults | 10.97 m | Baseline |
| Smoothing 0 / 40 / 200 / 400 ms | 11.92 / 11.61 / 10.92 / 13.21 m | More smoothing is not a systematic fix |
| Gravity-model weight zero | 11.01 m | The rolling-gravity prior is not the principal cause here |
| Endpoint-rest disabled | 12.03 m | Large scale change; removing the constraint does not establish correct speed |
| Acceleration explicitly “As reported” | 5.47 m | Strong sensitivity; flipping polarity is not a validated correction |
| Candidate crop approximately 0.80–12.90 s | 10.96 m | A zero-speed interval of about 1.78 s still remains |

The explicit “Inverted” polarity reproduces the automatic baseline. No default settings were changed.

## Proposed implementation order

### First: diagnostics and direction handling

1. Add a specific quality finding when a sustained zero-speed interval overlaps significant rotation or matched moving track features. Preserve and export the unclipped speed integral, clipped duration and timing.
2. Integrate a full 3D unit direction; move heading and slope derivation to display/diagnostics. Use separate smoothing settings for orientation and noisy acceleration.
3. Improve endpoint selection with windowed evidence and an editable active interval.

These are bounded improvements that can be evaluated before replacing the speed solver.

### Next: an experimental mode for repeated circuits

1. Detect candidate repeat landmarks from a sequence of gravity, orientation, angular motion and acceleration features. Align surrounding sequences in time to accommodate differing speeds. Do not count laps from accumulated heading: vertical loops make that quantity ambiguous.
2. For confirmed returns to the same landmark, apply a soft position-return constraint. Only apply equal-route-length or shared-shape constraints when the intervening routes also match.
3. Fit speed, slowly varying acceleration bias and small orientation corrections together over the whole recording. Use nonnegative speed and supported rest endpoints; downweight unexplained impact outliers without deleting real booster impulses. The observed acceleration reaches 8.30 g, which calls for explicit residual handling but does not by itself prove sensor saturation.
4. Fit a common route with individual timing for each lap. Preserve partial laps and distinct branches. Apply H or a measured route length consistently after establishing correspondence.

For fixed directions, a return constraint is the time integral of `speed × direction` between the two matched visits being near zero. This directly addresses the accumulated displacement visible here. A batch least-squares solver may be enough initially; adopting a full SLAM library is not required. Factor graphs provide an established framework for combining motion and return constraints. [GTSAM introduction, including loop closure](https://gtsam.org/tutorials/intro.html).

Keep this mode optional for open tracks, jumps, ambiguous repeated patterns and recordings where the car is picked up. Report closure residuals and data disagreement rather than a fabricated confidence percentage. A forced closed curve can look correct while being wrong.

### Scale and validation

A measured full-route length or an independently measured vertical-loop diameter would add a useful physical check. H alone cannot recover a unique path. For a recording with multiple laps, distinguish **one-circuit length** from **total traveled distance**; the existing known-length field fits the total reconstructed recording, including partial laps.

Validate changes against this saved run plus: a single pass, several repeated laps at different speeds, a stationary capture, real stops, an open route, a vertical loop and a handling/impact capture. Use synchronized phone video to label release, finish and landmark passes, and compare at least one independently measured dimension. Success means better agreement with those independent observations, not merely making loop-return residuals zero by construction.

Apple describes `CMDeviceMotion` as fused attitude, rotation, gravity and user acceleration; these are the available observations, not a surveyed trajectory. [Apple CMDeviceMotion documentation](https://developer.apple.com/documentation/coremotion/cmdevicemotion).

## Reproduction and artifacts

The analysis files are under [build/recording-investigation-2026-09-15](/Users/andriiliubivyi/Documents/ChatGPT/pod_track/build/recording-investigation-2026-09-15):

- [main.swift](/Users/andriiliubivyi/Documents/ChatGPT/pod_track/build/recording-investigation-2026-09-15/main.swift): compiles with the production core and exports recent-run and variant results. It selects the newest saved AirPods run at execution time.
- [diagnose_recording.py](/Users/andriiliubivyi/Documents/ChatGPT/pod_track/build/recording-investigation-2026-09-15/diagnose_recording.py): NumPy diagnostics, independent speed reproduction and vector-direction experiment for the exported baseline.
- [diagnostics.json](/Users/andriiliubivyi/Documents/ChatGPT/pod_track/build/recording-investigation-2026-09-15/diagnostics.json): measurements, landmark candidates and the original recording's SHA-256.
- [variant-summary.json](/Users/andriiliubivyi/Documents/ChatGPT/pod_track/build/recording-investigation-2026-09-15/variant-summary.json): all ten production-pipeline variants.

The core compiled and all ten variants produced analyses. The chart uses the exported production speed and original gyro values. Its script syntax and data were checked; browser preview of the local HTML file was blocked by browser URL policy, so browser interaction and layout were not verified. No application implementation was changed or rebuilt for use.

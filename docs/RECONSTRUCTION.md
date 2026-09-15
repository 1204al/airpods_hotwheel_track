# Reconstruction notes (algorithm 0.4.0-heuristic)

This document describes the **Old** method. PodTrack 0.10.0 defaults to **Improved**; see [IMPROVED_RECONSTRUCTION.md](IMPROVED_RECONSTRUCTION.md). The app provides a shared Improved / Old selector.

The pipeline is intentionally an experimental, constrained model. Raw values are never replaced by model outputs, and a failed reconstruction remains a raw-only run.

## Frame and mounting

Vectors use right-handed coordinates. The output has X in the initial horizontal forward direction, Y to the left, and Z up. SceneKit maps `(x,y,z)` to `(x,z,-y)` so its Y-up scene preserves handedness. Heading is relative, never geographic.

Let `g0` and `g1` be normalized gravity vectors from stationary level and nose-up poses, expressed in the same device frame. The mounting axes are:

```text
up_device = -g0
forward_device = -normalize(g1 - dot(g1, g0) * g0)
```

Capture uses only samples after the button click and requires at least 10 samples over 0.5 s, strictly increasing timestamps, a maximum inter-sample gap of 120 ms, and one sensor. Rotation magnitude must be below 0.22 rad/s, user acceleration below 0.10 g, and gravity variation below 0.04. The mean gravity directions of the first and last thirds may differ by at most 1°; this catches slowly settling fused data. Pose means are time-weighted. A tilt between poses of 10–65° is required. The user is instructed to lift the nose by 15–45° with no sideways roll. A wrongly performed pose can still produce a mathematical axis; this is not an automatic mounting truth detector.

Instantaneous slope is `asin(dot(forward_device, -normalize(gravity)))`. Banking compares the calibrated up axis with gravity-up projected perpendicular to forward. Vertical and tangential **user-acceleration** signals are dot products with gravity-up and calibrated forward, multiplied by 9.80665. They preserve the reported acceleration polarity.

For heading, both active and inverse quaternion mappings are scored using transformed-gravity consistency and the sign of the gyro's gravity-axis rotation. This avoids relying blindly on a passive/active convention or a headphone reference-frame setter that does not exist. The chosen frame is aligned using the first sample's gravity and forward projection. The heading is unwrapped before time-window smoothing. Gravity disagreement above 0.15 rejects the run; above 0.035 creates a warning. Sudden heading rates above 12 rad/s are flagged. Before that scoring, each full quaternion step is checked against `max(|gyro_previous|, |gyro_current|) × dt + 20°`. A larger step rejects the trace as a possible reference reset or missing motion. Quaternion sign flips are handled as the same orientation. Abrupt pure-yaw resets can therefore be rejected even with consistent gravity; smaller or gradual resets can still evade these checks.

## Smoothing over elapsed time

For each output time, integrate the piecewise-linear input signal over the centered smoothing window and divide by its observed duration. Clip the window at the first/last measurement; do not extrapolate. Subtract a constant baseline before accumulating the integral to reduce numerical cancellation, then restore it in the output. Moving integration bounds make the operation O(n). This replaces a sample-count average, which could overweight densely sampled intervals. The offline reconstruction may use future samples in its centered window; the live calibration picture uses the latest delivered sample directly.

## Acceleration sign and speed

[Core Motion defines total acceleration as gravity plus userAcceleration](https://developer.apple.com/documentation/coremotion/cmdevicemotion/useracceleration). Its accelerometer convention must not be confused with a mathematical world-space acceleration. In the simulator, raw total acceleration is `gravity - a_inertial/g`, so free fall has `userAcceleration = -gravity` and a near-zero total. Exported API values are retained unchanged.

The automatic speed-estimation sign chooses the sign consistent with positive acceleration during the first downhill release: samples from the first 1.2 s with slope below −0.08 rad and tangential magnitude above 0.1 m/s² contribute. Weak evidence generates a warning; it does not establish a universal Core Motion sign convention. Users can select **As reported** or **Inverted** in setup or saved-run editing. Validate sign using a physically known ramp, rather than trusting simulation alone.

Quiet initial/final samples use thresholds of 0.035 g and 0.15 rad/s. With endpoint-rest enabled, the integration window is the first through last nonquiet region, including one sample of padding. Interior quiet intervals are preserved as possible constant-speed travel. A run needs more than 0.25 s of activity. Endpoint quiet periods shorter than 0.2 s trigger a warning. These thresholds cannot distinguish steady motion from rest.

Initial quiet samples estimate the tangential offset. The model blends signed tangential acceleration `a_sensor` with `a_slope = -g*sin(slope) - rollingResistance`. The default maximum model weight is 0.20, reduced by `exp(-abs(a_sensor-a_slope)/2)`. Rolling resistance defaults to 0.15 m/s². Possible free-fall samples disable this contact model. These parameters are priors, not measured physical properties of the car.

With endpoint-rest enabled, the mean integrated impulse divided by motion duration is subtracted from acceleration. This supplies a zero-velocity endpoint correction. Its magnitude is exported and values above 1 m/s² trigger a warning. The corrected acceleration is integrated with trapezoidal steps; speed is clipped nonnegative and smoothed, with explicit zeros at the assumed rest edges. Clipping and smoothing can violate the original acceleration equations, so the result is a regularized estimate rather than an exact solution. When endpoint-rest is off, end speed is unconstrained and start speed still defaults to zero because initial speed is unobserved.

## Geometry and global constraints

```text
direction = (cos(slope)*cos(heading), cos(slope)*sin(heading), sin(slope))
p[i] = p[i-1] + 0.5 * (direction[i-1]*v[i-1] + direction[i]*v[i]) * dt
raw_height = max(p.z) - min(p.z)
height_scale = entered_H / raw_height
estimated_p = p * height_scale
estimated_p.z -= min(p.z) * height_scale
estimated_speed = speed * height_scale
```

New recordings with a measured height use the full height range, so the lowest centerline point has Z=0 and the highest Z=H. The start and finish need not be extrema, and can even have the same height. The user must record a pass through both extrema of the physical track. Raw height must exceed 5 mm and 0.5% of the integrated length; otherwise a flat/noisy trace could be amplified into fabricated geometry. Scale factors outside 0.05–20 reject the result, and factors outside 0.5–2 warn. All coordinates and speeds get the same scale; the datum translation changes neither speed nor distance. Fitting H does not independently verify the height or uniquely recover the shape.

For compatibility, recordings without the optional `metadata.heightConstraint` retain the original `endpointDrop` mode. It scales using `raw_drop = -p[last].z`, requiring a net descent, with start Z=0 and finish Z=−H. Exceeding these endpoint levels by 5% of H warns. New recordings explicitly store `heightRange`; **Apply height** in the 3D view deliberately selects that mode. The old `verticalDrop` field name remains the storage key for H. Both unscaled endpoint drop and unscaled height range are exported with the interpretation and coordinate convention. The scene and ruler display ground-relative heights in either mode; a legacy upper plane is labeled “Ground + H” since it need not coincide with the actual maximum.

An optional known total along-track length is fitted by a separate horizontal scale, found by bisection while leaving Z unchanged. It is feasible only when at least the vertical total variation can fit within that length. Incompatible constraints retain the height solution and report that length was not applied. This anisotropic fitting changes path slope relative to orientation-derived slope. Speed is adjusted by the same local tangent transform. No endpoint position is forced horizontally.

Curvature uses `abs(heading_rate)/estimated_speed`, with zero below 0.05 m/s to avoid a numerical singularity. This is planar turning intensity per distance, not full spatial Frenet curvature.

### Unknown height and relative units

A missing/null `metadata.verticalDrop` means H is unknown; it is never replaced by the default height during reconstruction. With no known length either, divide all raw centerline coordinates, cumulative distances and speeds by the integrated centerline length. The whole path then has length **1 u**, speed uses **u/s**, and curvature uses **1/u**. Translate the lowest point to Z=0. This is a convention for displaying approximate shape, not a recovered physical size. Flat paths are allowed; absent calibration, stationary input and negligible/nonfinite integrated paths remain errors.

If only along-track length is measured, use `scale = knownLength / rawLength` uniformly in XYZ and speed. The height remains estimated. With H present, retain the existing height fit and optional horizontal length fit. Analyses and exports record `scaleBasis` as `relative`, `trackLength` or `height`; older analyses without that field resolve to `height`. CSV coordinate/speed headers change from `_m`/`_m_s` to `_u`/`_u_s` for relative output. Sensor signals retain their original units.

Adding H later reconstructs from the same stored samples and calibration. A comparison containing any relative run normalizes every displayed path to length 1 u, including speed graphs and comparison metrics, without changing the saved analyses.

In relative mode, the curvature low-speed cutoff is applied to the original, unscaled velocity estimate, then curvature is divided by the normalization factor. It does not use a fixed cutoff in arbitrary u/s.

## 3D road and measurements

The orange deck and two raised rails are extruded along the reconstructed centerline using parallel-transport frames. This avoids an up-vector singularity on vertical sections. Consecutive duplicate positions are removed for meshing and at most 1,200 frames are drawn. Cross-section width (6 cm), thickness, rail height, frame roll, and support posts are illustrative; none is recovered from an AirPod. No texture, asset or track template is used. Speed-color mode adds vertex colors to the same mesh.

Picking filters SceneKit hits to the deck/rails, excluding planes, labels, event markers and ruler graphics. A hit maps back from SceneKit coordinates to the nearest point on the full, unthinned centerline. Linear interpolation supplies position, time and cumulative distance within a segment. Exact crossings and stationary duplicates prefer the current inspection time; cursor buttons allow explicit selection of an overlapping segment. Selecting by time survives height changes and ensures measurements use the current reconstruction.

For points A and B, straight distance is `|B-A|`, horizontal is `hypot(B.x-A.x, B.y-A.y)`, height change is `B.z-A.z`, and along-track distance is `abs(distance_B-distance_A)`. The last value follows the recorded route between those times, including turns and revisits; it is not the shortest route around a closed circuit. None of these distances is inferred from decorative mesh edges. Readouts in cm are estimates, not statements of centimeter accuracy.

## Segmentation and quality

Slope candidates use ±0.07 rad, turns use signed heading-rate thresholds of ±0.30 rad/s, and a minimum 0.12 s duration. Possible airtime requires `|gravity + userAcceleration| < 0.22 g` for at least 0.06 s. This is a **total-acceleration proxy**, not a measured support force. Bump candidates exceed either 0.70 g user-acceleration magnitude or 0.20 g smoothed vertical user acceleration for at least 0.015 s, excluding near-zero support. A magnitude peak above 0.70 g within 0.3 s of airtime end is a possible landing. Strong braking or vertical track transitions may also trigger bump candidates. Start/release/finish are endpoint heuristics. Raw sample frequency controls which events are observable.

Slope, turns and impact layers overlap. Segment lengths use cumulative reconstructed distance; average segment speed uses that length divided by its duration. Run average speed uses the inferred active interval. All warnings and algorithm settings are exported with results. No confidence percentage is invented without empirical calibration.

Testing compares synthetic sensor input with independently retained reference paths, and includes an analytic fixed-slope sine-speed pass. Synthetic self-consistency is necessary but does not validate real AirPods metrology, single-bud availability, ear-detection behavior, latency, saturation, or mount dynamics.

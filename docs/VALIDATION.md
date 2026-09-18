# Prototype validation

Development verification: **2026-09-14**, macOS 26.6.2, Xcode 26.6, Swift 6.3.3. Deployment target: macOS 14.0.

## 2026-09-18 · Play line with candidate events, a selectable range, and partial export

- The time slider under the 3D view became a play line carrying the detected candidates: point events (release, bump, possible airtime, possible landing, finish) as coloured ticks, continuous slope and turn candidates as lane bands, with a legend of the kinds actually present. The white playhead stays the shared cursor for the 3D car, charts and readouts.
- Two handles select part of the run. Dragging snaps to nearby candidate boundaries, and per-handle step buttons move exactly one boundary at a time. The 3D view, top-down XY and side profile then draw only that range, and playback runs inside it. Ground, H, the grid and the height bracket keep the whole recording's datum, and the ends of a partial road are labelled FROM and TO instead of START and FINISH, so a range cannot relabel the construction's height or imply a different run.
- A range never refits a reconstruction: it selects rows of the existing whole-run result. Points, speeds and cumulative distance are unchanged and distance keeps counting from the start of the run; only per-window totals (duration, path length, top and average speed, height range, candidate airtime, peak acceleration) are recomputed from the selected rows. Candidates overlapping the edges are clipped. The trimmed analysis carries a warning saying the fit, its scale and its endpoint assumptions come from the complete recording.
- Export of a range reuses the existing format and dataset choices. Raw `elapsed_s` still counts from the recording's first sample, so a row is byte-identical in the full and the partial file; the filename carries the range, raw JSON records it in the recording notes together with the source run ID, and an empty range is refused rather than exported as an empty file.
- Added 14 XCTest cases: window rows equal to the whole-run rows, per-window metrics, candidate clipping, trimmed recording identity and note, identical raw rows across full and partial exports, refusal of an empty range, window clamping and minimum span, timeline markers/snapping/stepping against real detected candidates, window reset when another run is selected, windowed points, and a scene whose road follows the window while its height planes do not.
- New `--render-timeline` command renders the play line for a synthetic jump run at whole-run and windowed state and writes all six windowed export files for inspection. A 3.76–5.28 s window of a 6.80 s run kept 77 of 341 points and 9 of 17 candidates, and reported 2.435 m of path against 8.041 m for the whole run. Inspected both renders and the exported files.

## 2026-09-18 · Saved-run library information, filtering and bulk export

- The **Runs** list now identifies each recording before it is opened: car and track, the AirPod side taken from the saved samples, date, duration, sample count, entered H, and a status line. A reconstructed run shows its estimated path length, top speed and average speed in that run's own units (m/m·s⁻¹, or u/u·s⁻¹ when the scale is unknown). Runs without a path show the reconstruction's own reason, and recording-quality notes appear on the row. No path is invented for a raw-only or failed recording.
- Search matches car, track, side, date and run ID, with tokens combined in any order. Sorting by estimated path length or top speed ranks runs without a reconstruction last. Filters cover source and status; a run still being analysed is excluded from both *with* and *without a 3D path* rather than being labelled unusable early. Per-row actions (open 3D/analysis, add to comparison, edit, recalculate, copy ID, reveal file, delete) are available from the row and by right-click.
- **Export N runs…** applies the existing per-run dataset and format choices to every listed recording and writes one ZIP. An optional `PodTrack-runs-index.csv` carries one row per run with identity, recording facts and the already-computed estimates of the selected algorithm; runs without a reconstruction keep empty estimate columns instead of substituted values. A recording that cannot produce a selected dataset no longer cancels the export: it is skipped, listed in `export-report.txt` inside the archive, and reported in the dialog. Single-run export keeps its all-or-nothing behaviour.
- Rows carry checkboxes. A selection bar offers select all, export of the selection, and **Delete N…** behind a confirmation. Shift-click extends from the last clicked checkbox. Bulk removal moves each recording separately: a recording that cannot be moved stays active and is named in the reported error while the others are still removed, and only the recordings actually removed form the Undo group. Undo restores that whole group; Recently Deleted gained **Restore all**.
- Added 15 XCTest cases: library search/sort/filter rules including the in-progress case, raw-only state and file location, CSV index units/escaping/identity, library export with a skipped recording, the unchanged strict single-run refusal, group deletion with undo and restart persistence, a blocked removal that keeps its recording, and comparison/selection/cache cleanup after a bulk delete. The full suite runs 63 tests; the 8 failures in `ComparisonTests` and `TrackSceneTests` reproduce identically at the previous commit and are unrelated to this change.
- New `--render-run-library` command writes four synthetic recordings (measured, unknown scale, second height, no calibration) into an isolated library and renders the list at the 840 pt minimum content width and wider, with two rows selected, plus the export dialog and a sample index. No hardware, no access to the user's library. Inspected all three renders and the generated index.

## 2026-09-15 · 0.10.3 Red cars in every 3D replay

- Reused the existing sports-car model with a red body. Run Analysis, Track Visualization and the separate algorithm-comparison window share it. Saved Runs & Compare now also uses cars, with stripes matching each trajectory's colour, in place of its spherical replay markers. Cars use the road's scale and orientation, including vertical and inverted sections; wheels follow the recorded distance when playing, pausing or seeking.
- Release build, packaging and signature verification passed with Command Line Tools and the macOS 26.5 SDK. `--render-replay-car build/red-car/verification` passed analytic loop orientation, wheel rotation/pause/rewind, relative scale, model components and road measurement picking. Added comparison checks cover release alignment, matching road scale, inverted road contact, rewind and finish clamping in both metric and relative units. Updated the existing shared-replay XCTest for car placement and finish clamping; full XCTest remains unavailable in the selected toolchain.
- Visually inspected the red car closeup, comparison scene and vertical/inverted loop frames. The command also produced a 64-frame animation. Reports and renders are under `build/red-car/verification/`. The app's window receipt confirms version 0.10.3 is open on Track Visualization with Improved selected. Computer Use inspection timed out, so the native scene checks and animation render provide verification; an automated click on the live Play button is not claimed.

## 2026-09-15 · 0.10.1 Unknown height by default

- New recording metadata defaults to no measured height. The recording screen starts on Unknown; the 58 cm numeric prefill is used only after selecting Measured. Saved recordings retain their own height, independently of the setup for the next recording.
- Track height controls use the selected draft mode for their explanation and label unapplied edits. Unknown recordings show Unknown in Run Analysis, Track Visualization, Saved Runs & Compare and the saved-run editor. Apply height / Apply unknown persists the change and rebuilds estimates with the selected algorithm.
- Release build, packaging and signature verification passed with Command Line Tools and the macOS 26.5 SDK. The extended isolated `--verify-library` acceptance command recorded all 341 samples through the real simulation callback, persisted Unknown, reopened the recording with Improved and relative units, and verified that a different next-recording height does not affect it. Adding 42 cm and returning to Unknown updated both method caches, retained comparison selection and preserved all raw samples and calibration. A measured length alone set scale while the height remained Unknown.
- Inspected native renders of the recording setup at minimum width, analysis, track visualization, saved comparison, editor, measured-height controls and Unknown with a measured length. Artifacts and acceptance JSON are in `build/unknown-default/verification/`. Full XCTest execution remains blocked by Xcode's unaccepted license; the acceptance command runs independently of XCTest. Four existing app test cases were updated for the default and height-edit behavior.
- The opened app's own window receipt confirms version 0.10.1 is visible on Record Run with Unknown and Improved selected. No real sensor capture or automated mouse/keyboard interaction was performed. The existing 680-sample user recording still matches its regression fixture byte for byte.

## 2026-09-15 · 0.10.0 default method and recoverable deletion

- Run Analysis, Track Visualization, Saved Runs & Compare and Export share the Improved / Old selector. Improved is selected at startup and after each completed recording. A failed reconstruction keeps its own error instead of substituting another method. The separate algorithm-comparison window still shows both methods.
- Method-specific caches, cancellation tokens and revision checks prevent stale results after rapid switches, edits or deletion. Playback and ruler selections reset when changing methods. Endpoint advice now uses the chosen method's diagnostics. Export filenames identify the selected method.
- Removing a recording moves its current revision to `Runs/RecentlyDeleted/`, clears its analysis and comparison selection, and offers Undo. Restore works after restart and does not overwrite a recording with the same ID. Removal failures keep the active recording and its selection intact. No automatic permanent purge is implemented.
- Release build, packaging and signature verification passed using the installed Command Line Tools and macOS 26.5 SDK. The app's isolated `--verify-library` command passed method-default/switching checks, comparison consistency, exported algorithm identity, both-cache invalidation after height edits, rapid-switch cancellation, deletion during analysis, restart restoration and a filesystem-obstruction failure case. A real 6.8-second simulation through the source callback, recorder and store confirmed that a prior Old selection becomes Improved after recording, preserving all 341 samples.
- The real-recording fixture produces 25.9013 m with Improved and 10.9712 m with Old. These remain estimated distances; promoting the existing method to the default adds no new physical accuracy claim.
- Added five XCTest cases for method selection and recoverable storage, and extended the existing post-recording test. Full XCTest execution remains blocked by Xcode's unaccepted license; the isolated acceptance command runs independently of XCTest. No user recording was removed during verification.
- Reproduction and artifacts: README's `--verify-library` command; `build/default-improved/` contains acceptance JSON, logs and native renders.
- Visually inspected the native method controls at 860 pt width, the analysis and track screens, the saved-run comparison and Recently Deleted. The final app's own receipt confirms version 0.10.0 is visible on Track Visualization with the latest 680-sample recording and Improved selected. Computer Use window inspection timed out, so automated mouse/keyboard interaction was not exercised. The original recording still matches the regression fixture byte for byte.

## 2026-09-15 · 0.8.5 motion session recovery and diagnostics

- Retry now replaces the Core Motion manager and invalidates old motion deliveries and delegate callbacks. A later availability transition can start motion without another connection event; a disconnect waits at least one second before another request. Explicit Stop and denied permission prevent restart.
- Ten seconds without a valid sample after authorization produces a no-data state instead of an indefinite spinner. The session continues listening for late recovery. Core Motion errors are visible, invalid samples cannot establish readiness, and Capture requires fresh motion from the selected side.
- Copy diagnostics includes authorization, connection/availability/API flags, accepted and rejected sample counts, timing, error details, and recent events. It is available on a failed connection card and in Diagnostics.
- All **100 tests passed**, including nine new session/connection tests for stale-manager retry, old callbacks, delayed availability, timeout recovery, invalid samples, error recovery, Stop, disconnect backoff, and permission changes. Tests inject sessions and a clock; they do not request real headphone access.
- SwiftPM Release packaging/signature verification and native Xcode Release (arm64) builds passed. Native renders of connected-without-data, unavailable-device, and motion-error cards were inspected at 480 pt width. Text and buttons fit. Artifacts, fixture reports, and build/test logs: `build/verification-connection/`.
- Hardware remains unverified after this change. The user's left AirPod still reported Stream — / 0 Hz with the right in its case before this build. Read-only checks showed motion permission granted, the intended AirPods Pro as the Mac's audio route, and an idle microphone at the time of the check. These findings do not identify why macOS supplied no motion. The new session must be tried through the normally launched app; fixture renders are not hardware evidence.

## 2026-09-15 · 0.8.4 setup reminder and Mac screenshot

- Setup guide opens a compact popover attached to the button's bottom edge, showing the selected Microphone side and Automatic Ear Detection → OFF. The screenshot button opens the full guide with Mac/iPhone tabs; Mac is the default. The examples explicitly show Right even when the requested recording side is Left.
- Added the user's Mac settings screenshot with two red arrows using built-in image_gen. The image and prompt are saved in the project. Both PNGs are included in SwiftPM packaging and the generated Xcode resource phase.
- Release packaging and signature verification passed for 0.8.4 (14). Rendered and inspected reminder content, both platform tabs, and both recording sides through the isolated native preview command. Both screenshots loaded from the packaged app. Artifacts: `build/verification-mac-setup/`.
- A live desktop interaction check timed out in Computer Use. Popover placement and the transition to the full guide were reviewed in code but were not exercised by clicking the running app. No sensor or reconstruction algorithm changed.

## 2026-09-15 · 0.8.3 microphone setup guide

- Added a visible Microphone → Always Right/Left instruction and a Setup guide in both connection panels. The guide follows the selected side, identifies the iPhone screenshot as a right-side example, and keeps the actual motion Stream check explicit.
- Annotated the user-supplied screenshot using the built-in image_gen tool, then added the requested second arrow: Automatic Ear Detection → Off and Microphone → Always Right. The PNG, Ukrainian instructions, and generation prompts are saved in the project; see `docs/AIRPODS_SETUP.md`.
- SwiftPM Release packaging and the native Xcode Release build passed for 0.8.3 (13). Both include the screenshot. The SwiftPM app was copied to a temporary location and verified to load its own embedded resource; the Xcode app also loaded its embedded PNG.
- Rendered the setup sheet and compact connection panel for both Left and Right, and inspected the screenshot, arrow, text wrapping, and side-specific hint. Artifacts and build logs are in `build/verification-airpods-setup/`. Preview commands do not connect to AirPods or use the user's run library. This change adds setup guidance; it does not change sensor capture or reconstruction.

## 2026-09-15 · 0.8.2 stability / algorithm 0.4.0

- **91 XCTest cases passed.** New regression tests cover excluding pre-click pose data, timeout commitment, minimum pose duration, missing/duplicate timestamps, mixed-sensor poses, slow gravity settling, and acceptance of small stationary noise.
- The time-weighted smoother matches an analytic linear signal at irregular timestamps and is invariant to inserting samples on the same piecewise-linear signal. Existing independent ramp, quaternion convention, quiet-middle, height/length scaling, and simulated track tests still pass.
- A synthetic 90° yaw reset with unchanged gravity and zero gyro is rejected before reconstruction. Real gyro-supported rotation and quaternion sign flips remain accepted. The 20° excess-step threshold is a conservative consistency rule; it does not detect every small/gradual reset.
- Release app 0.8.2 (12) packaged successfully. A separate command-line simulation verification recorded, persisted, reconstructed, and exported all 341 generated samples. Output reports ground Z=0, maximum Z=0.42 m, and algorithmVersion 0.4.0-heuristic. Artifacts: `build/verification-stability/`.
- Rendered and inspected the native calibration panel using isolated synthetic input. The newest sample shows 30°, while the capture window containing both old and new poses remains unsteady. Raw user-library files were not used or rewritten by these checks.
- Physical calibration repeatability, position/velocity error, and the new gravity-settling threshold remain to be assessed on hardware. No empirical accuracy percentage is claimed.

## 2026-09-15 · 0.8.1 live-motion latency

- User reported a right AirPods Pro 3 continuing to change the calibration visualization for more than three seconds after stopping.
- Before the change, the running 0.8.0 process reported 100.2% CPU in a point-in-time `ps` reading. A two-second stack sample showed substantial main-thread SwiftUI layout work. Core Motion callbacks also used the main operation queue; the live gravity view averaged the preceding 0.6 seconds. These are confirmed app-side latency risks, not a measured allocation of the full physical delay.
- 0.8.1 receives on a separate serial operation queue, preserves samples through a coalesced handoff, draws only the latest sample without an app moving average, and distinguishes callback timing from source cadence. Whole-window telemetry is limited to 10 Hz; the small live view updates up to 30 Hz. Duplicate/backwards timestamps cannot refresh freshness. App start/stop recording boundaries flush pending callbacks.
- **81 XCTest cases passed**, including immediate tilt steps/return to level, independent source and receipt clocks, delayed 50 Hz input, old timestamps, lossless batch recording, recording boundaries, and sensor changes within a batch. Debug tests and release packaging succeeded.
- Native synthetic calibration and diagnostics screens rendered successfully outside the sandbox. The 30° step image and recording screen at minimum content width were visually inspected. Artifacts are under `build/verification-calibration/`; test/build logs and the original stack sample are under `build/verification-latency/`.
- Opened the updated 0.8.1 app and restarted the connection. A subsequent point-in-time CPU reading was 35.4%; conditions were not identical, so this is not a controlled benchmark. Computer Use stopped responding before hardware timing fields could be read. End-to-end physical response and remaining upstream sensor-fusion/transport delay require the user's movement check.

## Completed checks

| Check | Result |
| --- | --- |
| SwiftPM Debug build | Passed |
| SwiftPM Release build and `.app` packaging | Passed |
| Native Xcode Debug build, arm64 | Passed |
| Native Xcode Release build, generic macOS | Passed; universal x86_64 + arm64 executable |
| XCTest | **59 tests, 0 failures** |
| Real-time simulated MotionSource → AppModel → recorder → store → background analysis | Passed; 341 samples in approximately 6.8 s |
| Plot pause/clear while recording | Passed; recording retains all received samples |
| Sensor-switch handling | Passed with an injected test source; prefix saved, unfinished poses cleared, completed per-side profiles retained |
| Raw CSV, reconstructed CSV, processed JSON | Generated and validated |
| JSON persistence/reload | Passed; unchanged motion sample values |
| SceneKit Metal render | Passed outside execution sandbox |
| SwiftUI chart/report render | Passed and visually inspected |
| Orange road, rails, height planes, A/B pins and ruler | Native SceneKit render inspected |
| Road hit-testing | Passed; height planes and ruler nodes excluded |
| H edit → background analysis → updated ruler → persistence | Passed; selected times and raw samples retained |
| New default height and saved-run compatibility | New setup and simulation use 58 cm; a saved 42 cm run reloads with unchanged samples, height and reconstructed points |
| Multiple saved runs and shared 3D replay | Passed; four-run selection limit, selection retained across navigation preparation, per-run scale preserved, legacy ground normalized, release offsets aligned and shorter runs clamped at the finish |
| Explicit comparison selection | Passed; no silent selection, Latest 2 skips raw/failed paths, four selected runs retain distinct stable colours, current-run entry point respects the limit, and failed reanalysis removes invisible selection without losing raw samples |
| Endpoint recording guidance | Passed; a complete synthetic run has no endpoint warning, a clipped finish gets a still-finish instruction, and disabling endpoint-rest assumptions does not falsely report that check |
| 3D comparison presentation | `comparison-3d.png` renders three synthetic colored roads with 58 cm height planes, legend and shared playback controls; visually inspected |
| Distinct shapes with one H, including an elevated finish | Curved circuit, S-bends and raised-finish tests passed |
| Legacy saved metadata without height mode | Endpoint-drop behavior preserved; new runs use full height range |
| Default Right / optional Left recording requirement | Passed; other-bud and unknown-side samples cannot start a recording or calibration |
| Connection states and retry | Passed with injected source; request-only, confirmed connection, fresh motion, mismatched bud, stale and denied states remain distinct |
| Automatic connection on launch | Uses an existing motion permission once; never restarts after explicit Stop |
| Height/connection setup screen | Native control rendering inspected; `setup-screen.png` clearly labels the connection state as an interface fixture, not real headphone evidence |
| Real headphone stream shown by user | Screenshot supplied at 15:12 shows **Right AirPod connected · receiving motion**, **Stream: right**, **50.0 Hz**; raw data values and outside-ear streaming were not independently checked |
| App signature | Ad-hoc signature passes `codesign --verify --deep --strict` |
| Bundle replacement after rebuild | Fresh staged bundle signed and verified before replacement; Finder modification date now reflects packaging time; build output includes version, path and quit/reopen instructions |
| Info.plist and Xcode project plist | `plutil -lint` passed |

The final explicit verification fixture produced these **simulation-only** results:

- 341 samples, 50 Hz, 6.80 s recorded duration.
- Entered height H: 0.42 m; ground Z: 0; highest Z: 0.42 m; finish Z: 0.0113 m.
- Estimated length: 5.51 m; estimated maximum speed: 1.30 m/s.
- Ruler A at 1.60 s / B at 4.30 s: straight distance 272.3 cm, along-track distance 330.1 cm, horizontal 272.1 cm, height change −10.2 cm.
- Candidate airtime: 0.12 s; both turn directions, the small bump, uphill/downhill, and possible landing were detected.
- Native images and exports: `build/verification/`.

The test suite includes an independently defined analytic straight-ramp pass, not just the simulator used by the app. It verifies length/direction and speed with explicit tolerances, gravity/attitude convention resolution, degenerate flat/stationary rejection, sample-gap rejection, optional length constraints, and that a quiet mid-run interval does not impose a false stop. New tests cover equal-height endpoints, full height-range scaling, ruler interpolation and signed height, crossing/repeated-point selection, finite ribbon geometry through verticals/loops, and saved-run height changes. SceneKit geometry hit-tests commit the scene transaction before ray queries; no screen or hardware interaction is inferred from that check.

## 0.5.0 comparison UX checks

- Inspected the running 0.4.0 app with native accessibility controls and saved screenshots: single-track page, the automatic selection containing an unusable recording, and a successful two-trajectory comparison. Findings and evidence are in [UX_REVIEW.md](UX_REVIEW.md).
- Rendered the actual updated SwiftUI library with no selection and three selected synthetic runs, including the shared SceneKit image, at 1200-point width. Also inspected a stacked 780-point layout. Artifacts: `build/verification-ux/saved-runs-empty.png`, `saved-runs-comparison.png`, and `saved-runs-narrow.png`.
- Inspected the native setup screen, fixed clipping of the large 58 cm input and long pose instructions, then rendered again. The one-centimetre arrows remain next to the input.
- Inspected both normal and clipped-finish recording-review panels. Synthetic fixtures are visibly labelled. Image capture uses NSHostingView plus SCNRenderer and does not imply a click-through test of the running app.
- SHA-256 comparison confirmed all six user-library JSON files were unchanged by this work. No real recordings were replaced with test data.
- The Mac locked before restarting the app into 0.5.0. Updated-window mouse/keyboard checks and camera gestures remain pending manual unlock; a request to unlock was sent. The packaged app can be opened after quitting the old running process.

The algorithm remains `0.2.0-heuristic`. This UX update does not claim improved measurement accuracy.

## 0.6.0 AirPod identity and saved mounting profiles

- All **59 XCTest cases passed** (`build/tests-bud-profiles.log`). New coverage captures different forward axes for Left and Right, persists both, creates a new AppModel to simulate relaunch, records each side with its matching calibration snapshot, and verifies that recalibrating a side does not rewrite historical runs.
- Tested reconnect preservation, wrong/unknown streaming-side guards, prevention of side changes during recording, incomplete calibration across a handover, and disk-save failure with an explicit retry. Corrupt/misfiled profiles do not disable the valid opposite side. Synthetic, unknown, and invalid axes cannot be saved as reusable physical profiles.
- Older raw recordings derive Left/Right from actual stored samples; calibration and current UI selection cannot invent their source. Unknown/mixed inputs stay explicit, simulations stay labelled, and processed CSV/JSON plus filename helpers preserve provenance. Live CSV does not apply the other side’s calibration to diagnostic samples.
- Rebuilt and signed **PodTrack 0.6.0 (6)** at `build/PodTrack.app`. SwiftPM Release packaging and the native Xcode Release build passed; the latter produced both Mac architectures (`build/release-bud-profiles.log`, `build/xcode-bud-profiles.log`).
- Restarted the actual app from 0.4.0 into 0.6.0 and checked native controls: the selector beside Record updates the top selector, calibration side, button title and next-run source together. Right is selected after relaunch and H remains 58 cm. With no fresh motion, capture/record stay disabled.
- Opened the six real saved runs in the new library. All reported Right from their stored samples, including raw-only recordings. **Latest 2 ready** selected two reconstructable runs and displayed two 3D tracks with Right AirPod labels. Searching **Left** correctly found none; clearing search restored the library. These UI operations did not record new motion or change saved data.
- Native screenshots: `build/verification-bud-profiles/native-recording-controls.png` and `native-comparison.png`. Separately rendered and inspected `calibration-left.png` and `recording-left.png` with visibly labelled synthetic fixtures and an isolated library, verifying the ready/saved and recording/disabled-switch layouts. These fixtures never use the real calibration directory.
- SHA-256 verification confirmed that all six original run files remain unchanged and no additional user-library runs were created (`build/verification-bud-profiles/library-preservation.json`).

The initial reusable profile must be captured once for each side. Old run calibrations remain attached to those runs; they are not silently adopted as the current physical mounting. Recalibrate after moving the mount or changing AirPods pairs. Physical left/right calibration and recordings on two cars were not performed during this verification.

## 0.6.1 compact recording screen

- Rebuilt and signed **PodTrack 0.6.1 (7)** at `build/PodTrack.app` (`build/release-compact.log`). The existing **59 XCTest cases passed** (`build/tests-compact.log`). This update changes layout and guidance, not reconstruction or calibration persistence.
- Moved Record and its Left/Right selector to the upper left, with height and compact Track/Car fields below. Connection and calibration occupy the right column. Notes and reconstruction settings open in a separate sheet; full recording/calibration/connection guidance uses popovers.
- Rendered the final SwiftUI recording page at **840 × 740 pt**, allowing for the sidebar at the supported minimum window width. Waiting, raw-only with an invalid height, saved Left calibration, active Left recording and simulation fixtures all fit. Fixtures are visibly labelled, use isolated storage and do not request real headphone motion (`build/verification-compact/setup-minimum-*.png`).
- Native navigation initially exposed a blank-window layout regression with the non-scrolling root stack. Restoring a naturally sized scroll viewport fixed it; the compact content fits without needing to scroll. Restarted the final bundle and visually checked the complete main page (`build/verification-compact/native-record-screen.png`).
- Clicked Left beside Record and confirmed the recording button, next-run label, required source and mounting profile all changed to Left. Tested **58 → 59 → 58 cm**, returned to Right, opened and closed the settings sheet and calibration help. Record and Capture remain disabled without fresh motion. No physical recording was started.
- All six existing run JSON files retained their original SHA-256 hashes; no user-library runs were added (`build/verification-compact/library-preservation.json`).

## 0.7.0 bilingual interactive guide

Development verification: **2026-09-15**.

- Added **How It Works** to the sidebar and Help menu. The native page has five steps, full English/Ukrainian copy, persistent page-language selection, accessible diagram descriptions and native controls.
- The speed/path fixture runs the existing reconstruction pipeline with synthetic raised-finish motion. Height examples apply the same uniform coordinate/speed scaling, retain a fixed camera and show a dashed 58 cm reference. The guide does not construct a motion source or access the run library.
- SwiftPM Debug and Release builds passed; the packaged **PodTrack 0.7.0 (8)** passed ad-hoc signing verification. The final **59 XCTest cases passed** with zero failures (see the guide build/test logs in build/).
- The explicit render-guide developer command rendered **15 native previews**: every step in both languages at 1100 × 940 pt; H = 29 and 87 cm in both languages at 840 × 740 pt; and Ukrainian direction in light appearance at 840 × 900 pt. Inspected diagrams, text wrapping, chart polarity, scaling, contrast and narrow-window layout. The page scrolls vertically at smaller window heights. Preview images are in build/verification-guide/.
- Opened the actual packaged app and verified sidebar navigation, switching all page copy to English and back, mounting-angle adjustment, time scrubbing with updated speed, expanded mathematics, scale changes with updated length/speed, expanded limitations and the return-to-recording action. Recording height remained 58 cm after changing the educational H. Confirmed Ukrainian selection survived relaunch.
- Final visual refinements fit the projected path to its actual bounds, attach H to the highest point and its ground projection, increase light-theme text contrast and use whole-degree/centimetre slider steps.

These checks validate the guide and its synthetic examples. The reconstruction algorithm and physical-accuracy status are unchanged.

## 0.7.1 sensor explanation

- Added **Sensors / Датчики** as the first of six guide steps. The visual flow connects the accelerometer and gyroscope to Core Motion, then separates gravity and motion acceleration. The details identify the actual API fields, unit conversion and forward projection, with a link to Apple documentation.
- The three educational states cover rest, straight motion at constant speed, and straight-line acceleration. Magnitudes are explicitly illustrative: gravity stays near 1 g; motion acceleration is near zero for the first two states and 0.20 g for the acceleration example. These controls do not read or modify recordings.
- Release packaging and signing passed for **0.7.1 (9)**. All **59 XCTest cases passed**, with zero failures. The Xcode project includes the new native view, and its plist/project validation passed.
- Rendered 24 native previews in build/verification-sensors/: all six steps in both languages, both scale extremes at minimum width, all three sensor states in each language at 840 pt, and light appearance. Visually checked the new flow, English/Ukrainian copy, six-step navigation labels and the light-theme sensor state.
- Verified the packaged app interactively: all three sensor states update the values and explanation, both languages switch correctly, the data disclosure opens, and navigation returns from Mount to Sensors. Left the Ukrainian Sensors step open.

## Unknown height · 0.8.0 (10)

- All **69 XCTest cases passed**. New coverage checks relative normalization, an independent flat-path fixture, later height scaling with unchanged shape and timing, length-only scaling, invalid inputs, legacy decoding, persistence, units in exports and the SceneKit ruler, and normalized comparisons.
- An app-state test loads an unknown-height run, saves a measured height, returns to Unknown, and checks that raw samples, calibration and ruler times survive both changes.
- Release packaging, plist validation and ad-hoc signature verification passed. The generated Xcode project uses version 0.8.0 (10).
- Rendered eight native previews in build/verification-unknown-height: measured/unknown setup at minimum width, relative analysis, dark/light ruler controls, mixed-scale comparison, and the English/Ukrainian scale guide. Visual inspection caught and fixed a wrapped picker label; the final render shows relative units, legible controls and the approximate path.
- Opened the packaged 0.8.0 app and selected **Record Run → Track height H → Unknown**. Verified that the height input disappears and the relative-shape explanation appears. The app is left on that screen. This UI check did not create or modify saved user recordings.
- These checks use synthetic fixtures and verify behavior, not physical trajectory accuracy. Removing H does not eliminate drift or mounting/flight uncertainty.

## Not verified

**No physical track reconstruction has been checked against measured ground truth.** Read-only inspection of six saved sessions labelled AirPods found 20 ms sample intervals: two recordings lack calibration, one calibrated recording has no sustained motion, and three produce geometry with weak finish-rest evidence. The running app showed the corresponding saved paths. This validates library handling and identifies recording issues; it does not establish outside-ear stream reliability or a numerical position/speed accuracy. Native render fixtures use an inert, explicitly labelled interface source. Camera gestures, live playback and interactive 3D clicks still need the manual UI check below; geometric picking, shared replay positions and measurement calculations are tested separately.

Attempts to probe Core Motion by directly executing the application binary from the agent host were terminated by macOS TCC for a missing usage description in that launch context, despite the app bundle containing the motion usage key. A sandboxed attempt also failed inside Core Motion. The app includes a usage description and starts connection monitoring on Connect AirPods, or once when opening the window with an existing motion permission. Real capture must be verified by launching the normal `.app` from Finder or Xcode. The direct command-line hardware probe was removed. No permission setting was bypassed or changed, and no simulation was substituted as hardware evidence.

macOS 14 runtime behavior, physical single-bud streaming outside the ear, Automatic Ear Detection, real latency/filtering/saturation, and a loose/high-impact mount remain unverified. The Intel binary was compiled but not executed on Intel hardware.

## Exact hardware test to perform

1. Open `build/PodTrack.app` from Finder, or run the PodTrack scheme in Xcode. Connect compatible AirPods to **this Mac**.
2. The app opens **Record Run**. Choose **Right AirPod** (default) or **Left AirPod**, then **Connect AirPods** if it has not started automatically. Grant the motion permission if macOS presents it. **Diagnostics** exposes all received sample values.
3. Over approximately five seconds, move only the bud you intend to mount. Check that the sample count increases and the quaternion, gravity and acceleration respond. The selected **Required** side must match the reported **Stream** before calibration or recording is enabled. Watch the reported side before and after mounting outside the ear. Selecting Left/Right does not force Core Motion to switch its sensor.
4. In **Record Run**, enter a track name, car name, and **42** in Height H if the lowest-to-highest difference is 42 cm. Capture the level and nose-up mounting poses. Put the car at the start.
5. Click **Start recording**, hold still for 1 second, release, let the car traverse both height levels and settle at the finish (which can be elevated), then record another 1 second still before **Stop & save run**. Save before picking up the car. Inspect the synchronized analysis and export raw samples plus analysis JSON.

Report back:

```text
macOS version:
AirPods model:
Compatible headphones connected: YES/NO
Motion available: YES/NO
Authorization:
Motion streaming active: YES/NO
Sensor location before/after mounting:
Sample count after ~5 seconds:
Observed Hz and interval jitter:
Latest sample age:
Any event-log errors / disconnects / sensor switches:
Measured highest-to-lowest H in cm:
Reconstruction result or failure message:
```

If capture fails, report the exact diagnostic status and event log. If the app is terminated, report that it terminated and the macOS diagnostic message; do not treat an empty stream as proof that a particular AirPods model lacks all motion support.

For a hardware-free functional check, select **Simulation → Record Run**, set **H = 42**, choose **Raised finish**, and **Simulate & record a full run**. It should automatically open Run Analysis after about seven seconds. The finish should sit above the 0 plane while the highest point sits at 42 cm. Open **Track Visualization**, orbit/zoom, toggle planes/speed colors and reset the camera. **Play run** should advance the cursor; **Pause** should stop it. **Measure A–B**, click the road twice, then check the four distances. Try cursor-based endpoint selection, Swap and Clear. Set H to 70 and Apply height: the selected times should stay the same and distances should scale by 70/42. Create an S-bends run, compare both, and try all three exports. Simulation is always explicitly labeled.

For the comparison check, keep the new **58 cm** default and record two named simulation runs. Quit and reopen PodTrack, open **Compare Runs**, and select both. Check the shared colored 3D roads and legend, rotate/zoom, **Fit all**, **Play together**, **Pause**, **Restart**, and the time slider. Add two further runs and confirm a fifth selection is disabled. Deselect a run and verify its road/marker disappears; open another page and return to confirm the remaining selection is retained. The automated SceneKit checks verify marker positions and scene membership; actual mouse gestures and two physical-car recordings remain a manual check.

## Reproduce automated checks

```sh
bash scripts/test.sh
bash scripts/build.sh release
build/PodTrack.app/Contents/MacOS/PodTrack --verify-simulation build/verification --render
xcodebuild -project PodTrack.xcodeproj -scheme PodTrack -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath build/Xcode \
  CODE_SIGNING_ALLOWED=NO build
```

The app scheme builds the native application; the XCTest targets live in the Swift package. Expected build-environment notes: a restricted sandbox may disable SwiftPM user caches and block Metal; Xcode may warn that App Intents metadata extraction was skipped because this app does not use AppIntents. Neither note is a test failure.
## 2026-09-15 — Sports-car replay

Replaced the single-track cursor sphere with a procedural blue sports car, rear wing, four rotating wheels, and a roof-mounted white AirPod. Playback and scrubbing use the existing recorded cursor; wheel angle is derived from distance. Cached parallel-transport road frames align the model through turns, vertical sections, and inverted loops. The model remains schematic and does not change reconstruction, timing, measurements, or saved runs.

The app compiled and was packaged as 0.10.2 (19), with a verified local code signature. This Mac's selected Xcode requires its license agreement, and the installed command-line tools' newest SDK lacks SwiftUI macro support. The build succeeded with the already-installed command-line tools and macOS 26.5 SDK:

```sh
DEVELOPER_DIR=/Library/Developer/CommandLineTools \
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk \
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swift-module-cache" \
swift build --disable-sandbox --build-system native \
  --sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk --cache-path .build/cache
```

`--render-replay-car OUTPUT_DIRECTORY` passed checks for analytic circular-loop alignment (including vertical and inverted poses), distance-driven wheel rotation, repeated paused frames, rewind, relative-unit scale, model components, and road-only measurement picking. It rendered the car closeup, a synthetic track, and a 64-frame GIF. The closeup and vertical/inverted loop frames were visually inspected. Results are in `build/verification-sports-car/`.

New XCTest coverage is in `ReplayCarTests`; the existing picking test now places the car at the picked point. XCTest did not run because its framework is unavailable in the selected command-line-tools installation. The standalone scene checks above ran successfully with graphics access. They never connect to headphones or read the user's run library. Opening the interactive app was blocked by automatic approval review pending explicit user authorization, so no interactive playback check is claimed.

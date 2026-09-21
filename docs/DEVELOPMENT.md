# Development

Run these commands from the project folder. For the tested Mac and Xcode versions, test results, and known issues, see [Validation](VALIDATION.md).

## Build and test

```sh
bash scripts/build.sh
bash scripts/test.sh
```

For a release build:

```sh
bash scripts/build.sh release
```

The build script creates and signs `build/PodTrack.app` for local use. This is a prototype, not a notarized release for distribution. Quit the running app with **⌘Q**, then open the new bundle:

```sh
open build/PodTrack.app
```

Use the app bundle when testing AirPods access. macOS may assign motion permission differently when the executable runs directly from a terminal.

After adding or moving app source files, update the Xcode project:

```sh
python3 scripts/generate-xcode-project.py
```

Python is only needed for this script. The app itself uses Swift and Apple's frameworks.

## Preview with sample data

These commands render real app views with sample data. They save files in their output folders and do not read the user's recording library. Rendering needs a macOS desktop session; 3D images also need Metal.

Record, save, and analyse a sample run, then render its results:

```sh
build/PodTrack.app/Contents/MacOS/PodTrack --verify-simulation build/verification --render
```

Leave out `--render` to run those checks without a graphics device.

Render the 3D view and timeline, saved-run library, and bilingual guide:

```sh
build/PodTrack.app/Contents/MacOS/PodTrack --render-timeline build/verification-timeline
build/PodTrack.app/Contents/MacOS/PodTrack --render-run-library build/verification-run-library
build/PodTrack.app/Contents/MacOS/PodTrack --render-guide build/verification-guide
```

Render calibration and connection examples:

```sh
build/PodTrack.app/Contents/MacOS/PodTrack --render-calibration build/verification-calibration
build/PodTrack.app/Contents/MacOS/PodTrack --render-connection-states build/verification-connection
build/PodTrack.app/Contents/MacOS/PodTrack --render-airpods-setup build/verification-airpods-setup
```

Compare both methods using the included recording:

```sh
build/PodTrack.app/Contents/MacOS/PodTrack --render-algorithm-comparison \
  Tests/PodTrackCoreTests/Fixtures/repeated-circuit.json build/improved-comparison/rendered
```

Check recording, saved runs, method switching, exports, edits, deletion, and restore using a separate test library:

```sh
build/PodTrack.app/Contents/MacOS/PodTrack --verify-library \
  Tests/PodTrackCoreTests/Fixtures/repeated-circuit.json build/library-verification --render
```

Passing these checks does not prove accuracy on a real track.

## README images

The README uses these app images without image edits:

| Image | Source |
| --- | --- |
| `images/podtrack-3d-track.png` | The looped-track image from the original README, reused unchanged |
| `images/podtrack-motion-guide.png` | PodTrack 0.10.4, `--render-guide`, output `en-2.png`; the interactive direction example |

Keep sample images clearly labelled. Do not present generated examples as measurements from a real car.

## Code and saved files

- `Sources/PodTrackCore/` holds recording, calibration, storage, exports, and track calculations.
- `Sources/PodTrack/` holds the Mac app, motion connection, views, and 3D display.
- `Tests/` holds the core and app tests.

Each saved run keeps its original motion samples and a copy of its mounting calibration. Left and right mounting profiles are also saved separately under `Runs/Calibrations/`.

Calculated results are cached under `Runs/AnalysisCache/`, separately for Improved and Old. Missing or unreadable cache files are rebuilt. Increase `AnalysisDiskCache.revision` when changing calculation behaviour or the saved result format. Cached results must never replace the original recording.

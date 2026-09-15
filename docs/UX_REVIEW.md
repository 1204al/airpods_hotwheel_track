# Saved-run comparison UX review · 14 September 2026

Scope: the existing native PodTrack 0.4.0 flow from a single reconstructed track to comparison of saved recordings. Captured in the running macOS app using Computer Use. The same app, colours, controls and SceneKit renderer are the implementation target for 0.5.0.

1. **Open a single track — comparison entry is hard to find.** The main screen has a single-selection Run picker, but no nearby comparison action. The user must discover a separate sidebar destination. [Captured screen](../build/ux-review/01-track-before.png).
2. **Choose saved runs — misleading selection count.** The two newest records are selected automatically. In the captured library, the newest recording has no sustained motion: the selection says two while the scene contains one trajectory. All six records have the same default car/track names; timestamps are shown only to the minute. The list pushes the 3D scene below the initial viewport. [Captured screen](../build/ux-review/02-compare-before.png).
3. **View two trajectories — works, but selection is offscreen.** Unticking the stationary recording and ticking another reconstructed run displays both paths. The user must scroll between selection and the scene. Playback and ground alignment exist; the view provides no convenient removal action beside each scene label. [Captured screen](../build/ux-review/03-two-tracks-before.png).

The screenshots were saved and reopened for inspection. Native accessibility inspection confirmed labelled checkboxes and replay controls. It also showed the distinction between two selected recordings and one rendered trajectory. This is a scoped UX review, not a full accessibility compliance audit.

## Implemented changes

- **Saved Runs & Compare** is immediately below Record Run in the sidebar. **Compare runs in 3D** appears beside the single-run picker; it brings the current reconstructed run into the comparison.
- The library and 3D view share one row at normal window widths. The library has its own scrolling area, date/time including seconds, search, edit/open actions, selected borders, matching colours and explicit checkbox instructions. A narrower view stacks the panels.
- Opening the library does not select records silently. **Latest 2 ready** is a deliberate shortcut that skips records without a reconstructed path. Raw-only, processing and failure states explain why a record is unavailable for 3D while keeping its raw data accessible.
- Selected tracks retain their colours when another is removed. Each scene label offers removal. The four-run limit remains explicit; advanced comparison charts are collapsed initially.
- Single-track and analysis views show recording checks and an action to review height and known track length. The calibration and recording instructions now say to hold each pose for one second before Capture, and to record one second of rest at each endpoint.

## Accuracy evidence and limits

Read-only inspection of the six existing saved JSON sessions found evenly spaced source timestamps (largest gap 20 ms). Three calibrated runs that produced geometry had no quiet tail under the processor's acceleration/rotation thresholds. A fourth calibrated recording had no sustained motion; two earlier recordings had no mounting calibration. This explains a failed default comparison and weak endpoint assumptions, but does not establish the true path or a numerical accuracy rate.

The reconstruction algorithm is unchanged. New recording advice reuses the endpoint-rest interpretation used by the speed estimator; it does not score accuracy or claim that the physical car was certainly moving. Known length is an additional scale constraint, not evidence that the reconstructed shape is correct.

## Verification

Automated checks and current native UI captures are recorded in [VALIDATION.md](VALIDATION.md). Reconstructed sample data is not regenerated or overwritten by browsing the library, changing comparison selections, or replaying trajectories.

The redesigned view is also available as an explicitly synthetic [native interface render](../build/verification-ux/saved-runs-comparison.png). The empty-selection and narrow-window renders are in the same directory. The Mac locked before the new build could be tested in its running window; these renders must not be presented as completed mouse/keyboard verification.

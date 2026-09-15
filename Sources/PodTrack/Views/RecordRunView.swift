import SwiftUI
import PodTrackCore

struct RecordRunView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        ScrollView {
            recordingContent
        }
    }
    private var recordingContent: some View {
        VStack(alignment:.leading,spacing:14) {
            VStack(alignment:.leading,spacing:4) {
                Text("Record a run").font(.system(size:24,weight:.semibold,design:.rounded))
                Text(model.sourceKind == .simulation ? "Choose a shape and height, then simulate a saved run." : "Enter a height or choose Unknown. Connect your AirPod, calibrate and record.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            HStack(alignment:.top,spacing:14) {
                VStack(spacing:12) {
                    RecordingControlsPanel()
                    RunHeightSetupView()
                    RunSetupView()
                }.frame(maxWidth:.infinity)
                VStack(spacing:12) {
                    HeadphoneConnectionPanel(compact:true)
                    MountingCalibrationPanel()
                }.frame(maxWidth:.infinity)
            }
            Text("Track shape, speed and distances are estimates. Record cars one at a time; compare saved runs afterward.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }.padding(20).frame(maxWidth:.infinity,alignment:.topLeading)
    }
}

struct MountingCalibrationPanel: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Panel(title:"Mounting calibration",subtitle:model.recordingSourceLabel,spacing:10,padding:14) {
            if model.sourceKind == .airPods {
                HStack(spacing:8) {
                    ForEach(RecordingBud.allCases,id:\.self) { bud in
                        let profile = model.calibrationProfiles[bud.location]
                        let selected = model.selectedBud == bud
                        let unsaved = model.unsavedCalibrationSides.contains(bud.location)
                        Button { model.selectBud(bud) } label: {
                            VStack(alignment:.leading,spacing:4) {
                                Label("\(bud.rawValue) AirPod",systemImage:selected ? "checkmark.circle.fill" : "circle")
                                    .font(.callout.bold()).foregroundStyle(selected ? PodTheme.teal : .primary)
                                Text(profile == nil ? "Not calibrated" : unsaved ? "Not saved" : "Saved on this Mac")
                                    .font(.caption).foregroundStyle(profile == nil || unsaved ? PodTheme.amber : .secondary)
                            }.padding(9).frame(maxWidth:.infinity,alignment:.leading)
                                .background(selected ? PodTheme.teal.opacity(0.08) : Color.primary.opacity(0.025),in:RoundedRectangle(cornerRadius:8))
                                .overlay(RoundedRectangle(cornerRadius:8).strokeBorder(selected ? PodTheme.teal.opacity(0.5) : .clear))
                        }.buttonStyle(.plain).disabled(model.recording)
                            .accessibilityLabel("\(bud.rawValue) AirPod calibration, \(profile == nil ? "not calibrated" : unsaved ? "not saved" : "saved")")
                            .accessibilityAddTraits(selected ? [.isSelected] : [])
                    }
                }
                Text("Saved separately for each side. Recalibrate if the mount changes.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }
            if let calibration = model.calibration, model.hasMatchingCalibration {
                let unsaved = model.unsavedCalibrationSides.contains(calibration.sensorLocation) && model.sourceKind == .airPods
                Label("\(model.recordingSourceLabel) calibration ready",systemImage:"checkmark.circle.fill")
                    .font(.callout.bold()).foregroundStyle(PodTheme.teal)
                Text("Captured \(calibration.capturedAt.formatted(date:.abbreviated,time:.shortened))\(unsaved ? " · not saved yet" : "")")
                    .font(.caption).foregroundStyle(unsaved ? PodTheme.amber : .secondary)
                if model.sourceKind == .airPods {
                    HStack {
                        Button("Recalibrate \(model.selectedBud.rawValue)") { model.recalibrateSelectedBud() }
                            .disabled(model.recording)
                        if unsaved {
                            Button("Retry saving calibration") { model.saveCalibration(for:model.selectedBud.location) }
                        }
                    }.controlSize(.small)
                }
            } else if model.sourceKind == .airPods {
                if !model.hasFreshSelectedMotion {
                    Label("Waiting for fresh \(model.selectedBud.rawValue) AirPod motion to enable Capture.",systemImage:"airpodspro")
                        .font(.caption).foregroundStyle(PodTheme.amber).fixedSize(horizontal:false,vertical:true)
                }
                HStack(alignment:.center,spacing:10) {
                    Image(systemName:model.hasLevelPose ? "checkmark.circle.fill" : "1.circle")
                        .foregroundStyle(model.hasLevelPose ? PodTheme.teal : .secondary)
                    VStack(alignment:.leading,spacing:3) {
                        Text(model.hasLevelPose ? "Level pose captured" : "All four wheels level").font(.callout.weight(.medium))
                        Text("Click Capture, then hold still. Collects a new pose for at least 0.5 s.").font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth:.infinity,alignment:.leading)
                    Button(model.hasLevelPose ? "Recapture" : "Capture level") { model.captureLevelPose() }
                        .disabled(!model.hasFreshSelectedMotion || model.recording || model.captureStatus != nil)
                        .accessibilityLabel("Capture \(model.selectedBud.rawValue) AirPod level pose")
                }
                Divider()
                HStack(alignment:.center,spacing:10) {
                    Image(systemName:"2.circle").foregroundStyle(.secondary)
                    VStack(alignment:.leading,spacing:3) {
                        Text("Raise the nose 15–45°").font(.callout.weight(.medium))
                        Text("No sideways tilt. Click Capture and keep holding still.").font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth:.infinity,alignment:.leading)
                    Button("Capture & save") { model.captureNosePose() }
                        .disabled(!model.hasLevelPose || !model.hasFreshSelectedMotion || model.recording || model.captureStatus != nil)
                        .accessibilityLabel("Capture \(model.selectedBud.rawValue) AirPod nose-up pose and save calibration")
                }
            } else {
                Label("Synthetic calibration is supplied for each run.",systemImage:"checkmark.circle")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if model.sourceKind == .airPods && !model.hasMatchingCalibration {
                CalibrationPosePreview(display:model.liveMotion)
                Text(model.calibrationFeedback)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal:false,vertical:true)
            }
            if let status = model.captureStatus {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(status).font(.caption).fixedSize(horizontal:false,vertical:true)
                    Button("Cancel") { model.cancelCapture() }
                }
            }
            HStack(alignment:.center) {
                if model.sourceKind == .airPods {
                    Toggle("Raw only · no 3D",isOn:$model.recordRawOnly).font(.caption).disabled(model.recording)
                        .accessibilityLabel("Raw-only recording, skip reconstruction")
                }
                Spacer(minLength:4)
                RecordingHelpButton(title:"Calibration help",topic:.calibration)
            }
            if model.recordRawOnly && model.sourceKind == .airPods {
                Text("Raw-only saves sensor data. Turn it off to reconstruct and compare 3D tracks.")
                    .font(.caption).foregroundStyle(PodTheme.amber).fixedSize(horizontal:false,vertical:true)
            }
        }
    }
}

struct RecordingControlsPanel: View {
    @EnvironmentObject var model: AppModel
    private var isSimulation: Bool { model.sourceKind == .simulation }
    private var blocked: Bool {
        !model.recording && !isSimulation && (!model.hasFreshSelectedMotion || (!model.hasMatchingCalibration && !model.recordRawOnly))
    }
    private var readiness: String {
        if isSimulation { return "Synthetic motion · no AirPods readings" }
        if !model.hasFreshSelectedMotion { return "Waiting for \(model.recordingSourceLabel) motion" }
        if model.recordRawOnly { return "Raw only · no 3D trajectory" }
        return model.hasMatchingCalibration ? "Using \(model.recordingSourceLabel) calibration" : "Calibrate \(model.recordingSourceLabel) to enable recording"
    }
    var body: some View {
        Panel(title:model.recording ? "Recording · \(model.recordingSourceLabel)" : "Record",spacing:10,padding:14) {
            if !isSimulation { RecordingBudPicker().labelsHidden() }
            else {
                Picker("Track shape",selection:$model.simulationProfile) {
                    ForEach(SimulationProfile.allCases,id:\.self) { Text($0.rawValue).tag($0) }
                }.disabled(model.recording)
                Toggle("Include a short jump",isOn:$model.simulationIncludesJump).font(.caption).disabled(model.recording)
            }
            HStack(spacing:12) {
                VStack(alignment:.leading,spacing:2) {
                    HStack(spacing:6) {
                        Circle().fill(model.recording ? .red : .secondary).frame(width:7,height:7)
                        Text("\(formatted(model.recording ? model.recordingDuration : 0)) s")
                            .font(.system(size:26,weight:.medium,design:.monospaced)).fixedSize()
                    }
                    Text("\(model.recording ? model.recordedCount : 0) samples").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength:0)
                Button(model.recording ? "Stop & save" : isSimulation ? "Simulate & record" : "Record \(model.recordingSourceLabel)",systemImage:model.recording ? "stop.fill" : "record.circle") {
                    if model.recording { model.finishRecording() }
                    else if isSimulation { model.recordSimulation() }
                    else { model.startRecording() }
                }.buttonStyle(.borderedProminent).controlSize(.large).tint(model.recording ? .red : PodTheme.teal)
                    .disabled(blocked).accessibilityLabel(model.recording ? "Stop and save \(model.recordingSourceLabel) run" : isSimulation ? "Simulate and record a full run" : "Record \(model.recordingSourceLabel)")
            }
            Text(readiness).font(.caption).foregroundStyle(blocked || (model.recordRawOnly && !isSimulation) ? PodTheme.amber : PodTheme.teal)
                .fixedSize(horizontal:false,vertical:true)
            Text("\(model.recording ? "Run" : "Next run"): \(model.setup.carName) · \(model.recordingSourceLabel)")
                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            Divider()
            Text(isSimulation ? "Generates a 6.8-second run and saves it automatically." : "Still for 1 s → release → still for 1 s at the finish → save.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            HStack {
                if model.recording { Text("Stop and save before switching sides.").font(.caption).foregroundStyle(.secondary) }
                Spacer(minLength:0)
                RecordingHelpButton(title:"Recording help",topic:.recording)
            }
        }
    }
}

struct RunSetupView: View {
    @EnvironmentObject var model: AppModel
    @State private var showOptions = false
    var body: some View {
        Panel(title:"Run details",spacing:10,padding:14) {
            Grid(alignment:.leading,horizontalSpacing:10,verticalSpacing:8) {
                GridRow { Text("Track").foregroundStyle(.secondary); TextField("Track name",text:$model.setup.trackName).accessibilityLabel("Track name") }
                GridRow { Text("Car").foregroundStyle(.secondary); TextField("Car name",text:$model.setup.carName).accessibilityLabel("Car name") }
            }.textFieldStyle(.roundedBorder).font(.callout)
            HStack {
                if !model.setup.notes.isEmpty { Text(model.setup.notes).lineLimit(1).font(.caption).foregroundStyle(.secondary) }
                Spacer(minLength:0)
                Button("Notes & advanced settings…",systemImage:"slider.horizontal.3") { showOptions = true }
                    .font(.caption)
            }
        }.disabled(model.recording)
            .sheet(isPresented:$showOptions) { RunOptionsSheet().environmentObject(model) }
    }
}

struct RunOptionsSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            Text("Notes & advanced settings").font(.title2.bold())
            TextField("Notes for this run",text:$model.setup.notes,axis:.vertical).lineLimit(3...5)
                .accessibilityLabel("Notes for this run")
            Divider()
            Picker("Height meaning",selection:Binding(get:{model.setup.resolvedHeightConstraint},set:{model.setup.heightConstraint = $0})) {
                ForEach(HeightConstraint.allCases,id:\.self) { Text($0.label).tag($0) }
            }.disabled(!model.heightIsKnown)
            LabeledContent("Known track length (cm)") { TextField("Optional",text:$model.knownLengthCentimeters).frame(width:120) }
            Text("Measure along the whole track, from start to finish. If height is unknown, this length sets scale. With neither measurement, the path uses relative units.")
                .font(.caption).foregroundStyle(.secondary)
            LabeledContent("Smoothing",value:"\(formatted(model.setup.settings.smoothingSeconds*1000,0)) ms")
            Slider(value:$model.setup.settings.smoothingSeconds,in:0...0.5,step:0.02)
            LabeledContent("Slope model weight",value:formatted(model.setup.settings.gravityModelWeight))
            Slider(value:$model.setup.settings.gravityModelWeight,in:0...0.6,step:0.05)
            Picker("Acceleration sign",selection:$model.setup.settings.accelerationPolarity) {
                ForEach(AccelerationPolarity.allCases,id:\.self) { Text($0.rawValue).tag($0) }
            }
            Toggle("Start and end at rest",isOn:$model.setup.settings.startsAndEndsAtRest)
            Text("Turn off endpoint rest if recording stops while the car is moving.").font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent) }
        }.textFieldStyle(.roundedBorder).padding(24).frame(width:510)
    }
}

enum RecordingHelpTopic { case recording, calibration }

struct RecordingHelpButton: View {
    let title: String
    let topic: RecordingHelpTopic
    @State private var showing = false
    var body: some View {
        Button(title,systemImage:"questionmark.circle") { showing = true }
            .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
            .popover(isPresented:$showing) {
                VStack(alignment:.leading,spacing:12) {
                    Text(title).font(.headline)
                    if topic == .calibration {
                        Text("Calibration teaches PodTrack which way the car points. Keep the selected AirPod rigidly fixed to the car for both poses.")
                        Text("1. Put all four wheels on a level surface. Hold still for 1 second, then Capture level.")
                        Text("2. Raise only the front wheels by 15–45°, with no sideways tilt. Hold for 1 second, then Capture & save.")
                        Text("Each side saves independently and reloads when selected. Recalibrate that side after moving the mount or using a different AirPods pair. Older runs keep their original calibration.")
                    } else {
                        Text("Start recording while the car is held still. Wait 1 second, release it, then keep recording for 1 second after it stops.")
                        Text("Stop and save before picking the car up. Maximum recording: 180 seconds. Stop and save before switching AirPods.")
                        Text("Record cars one at a time. Select two or more runs in Saved Runs & Compare to see their estimated trajectories together.")
                        Text("Inertial sensing cannot measure absolute position or distinguish rest from perfectly steady straight-line motion. Mounting and endpoint rest are experimental assumptions.")
                    }
                    Button("Got it") { showing = false }.frame(maxWidth:.infinity,alignment:.trailing)
                }.font(.callout).padding(20).frame(width:360).fixedSize(horizontal:false,vertical:true)
            }
    }
}


// Before the second pose, only unsigned gravity-relative tilt is observable.
// These cars illustrate that magnitude, not a solved pitch or heading.
private struct CalibrationPosePreview: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var display: LiveMotionPresentation
    private var tilt: Double? { model.calibrationTiltDegrees }

    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            Text("Saved pose → latest sensor tilt").font(.callout.bold())
            Text("Live view uses the newest sample. Capture waits for fresh, steady data after your click (up to 6 s).")
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing:12) {
                poseCard(title:"1 · Saved level",angle:model.hasLevelPose ? 0 : nil,
                         gravity:model.savedLevelGravity,live:false)
                poseCard(title:"2 · Latest sample",angle:tilt,
                         gravity:model.liveCalibrationGravity,live:true)
            }
            if let tilt {
                GeometryReader { proxy in
                    ZStack(alignment:.leading) {
                        Capsule().fill(Color.secondary.opacity(0.15))
                        Rectangle().fill(PodTheme.teal.opacity(0.35))
                            .frame(width:proxy.size.width * 30 / 90)
                            .offset(x:proxy.size.width * 15 / 90)
                        Circle().fill(PodTheme.teal).frame(width:12,height:12)
                            .offset(x:(proxy.size.width-12)*min(tilt,90)/90)
                    }.clipShape(Capsule())
                }.frame(height:12)
                HStack {
                    Text("0°")
                    Spacer()
                    Text("Target 15–45°").foregroundStyle(PodTheme.teal)
                    Spacer()
                    Text("90°+")
                }.font(.caption.monospacedDigit())
                if tilt < 2 {
                    Text("Almost no tilt change detected. Raise the mounted AirPod with the car. If it is already raised, check the selected bud and recapture level on a flat surface.")
                        .font(.caption).foregroundStyle(PodTheme.amber)
                }
            }
            if model.hasFreshSelectedMotion, let sample = display.sample {
                Text(String(format:"Turning now: %.1f°/s · acceleration: %.3f g",sample.rotationRate.length*180 / .pi,sample.userAcceleration.length))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                if let rotation = model.calibrationAttitudeChangeDegrees {
                    Text(String(format:"Total orientation change: %.1f° (includes turning on the spot)",rotation))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            Text(model.motionTimingSummary).font(.caption.monospacedDigit())
                .foregroundStyle(model.hasDeliveryBacklog ? PodTheme.amber : .secondary)
            Text("This car shows unsigned tilt, not position or a complete car pose. Level means your saved reference. Core Motion’s own filtering is still present; PodTrack adds no smoothing to this live view.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06),in:RoundedRectangle(cornerRadius:12))
    }

    private func poseCard(title: String, angle: Double?, gravity: Vector3?, live: Bool) -> some View {
        VStack(alignment:.leading,spacing:6) {
            Text(title).font(.caption.bold())
            ZStack {
                RoundedRectangle(cornerRadius:1).fill(Color.secondary.opacity(0.25))
                    .frame(height:2).offset(y:31)
                car
                    .foregroundStyle(live ? PodTheme.teal : Color.secondary)
                    .rotationEffect(.degrees(-(angle ?? 0)))
                    .transaction { $0.animation = nil }
                    .opacity(angle == nil ? 0.25 : 1)
            }.frame(height:105).frame(maxWidth:.infinity).clipped()
            Text(angle.map { String(format:"%.1f°", $0) } ?? (live ? "Waiting for pose" : "Not captured"))
                .font(.title3.monospacedDigit().bold())
            if let gravity {
                Text(String(format:"g  x %+.2f  y %+.2f  z %+.2f",gravity.x,gravity.y,gravity.z))
                    .font(.caption2.monospacedDigit())
            } else {
                Text(live ? "No fresh reference comparison" : "Capture all four wheels level")
                    .font(.caption2)
            }
        }.frame(maxWidth:.infinity,alignment:.leading)
        .accessibilityElement(children:.combine)
    }

    private var car: some View {
        ZStack {
            RoundedRectangle(cornerRadius:8).frame(width:104,height:25)
            RoundedRectangle(cornerRadius:6).frame(width:52,height:21).offset(x:-7,y:-17)
            RoundedRectangle(cornerRadius:3).fill(Color.black.opacity(0.4))
                .frame(width:20,height:12).offset(x:5,y:-18)
            Circle().fill(Color.primary).frame(width:20,height:20).offset(x:-32,y:15)
            Circle().fill(Color.primary).frame(width:20,height:20).offset(x:32,y:15)
            Image(systemName:"arrow.right").font(.caption.bold()).offset(x:34,y:-3)
        }.frame(width:120,height:64)
    }
}

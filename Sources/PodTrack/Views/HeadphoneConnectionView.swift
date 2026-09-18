import SwiftUI
import PodTrackCore

struct HeadphoneConnectionPanel: View {
    @EnvironmentObject var model: AppModel
    var compact = false
    @State private var showingHelp = false
    @State private var showingChecklist = false
    var body: some View {
        Group {
            if compact { compactPanel }
            else { fullPanel }
        }
        .sheet(isPresented:$showingHelp) { AirPodsSetupSheet(bud:model.selectedBud) }
    }
    private var microphoneHint: some View {
        ViewThatFits(in:.horizontal) {
            HStack(spacing:12) { airPodsSettingsButtons }
            VStack(alignment:.leading,spacing:8) { airPodsSettingsButtons }
        }
    }
    @ViewBuilder private var airPodsSettingsButtons: some View {
        SystemSettingsShortcut(title:"Microphone → Always \(model.selectedBud.rawValue)",icon:"mic",destination:.airPods)
        SystemSettingsShortcut(title:"Automatic Ear Detection → Off",icon:"ear",destination:.airPods)
    }
    private var setupHelpButton: some View {
        Button("Setup guide",systemImage:"questionmark.circle") { showingChecklist = true }
            .buttonStyle(.plain).font(.caption).foregroundStyle(PodTheme.teal)
            .accessibilityLabel("AirPods connection and microphone setup guide")
            .help("Choose the microphone side and turn Automatic Ear Detection OFF.")
            .popover(isPresented:$showingChecklist,arrowEdge:.bottom) {
                AirPodsSetupReminder(bud:model.selectedBud) {
                    showingChecklist = false
                    showingHelp = true
                }
            }
    }
    private var compactPanel: some View {
        Panel(title:"Connection",subtitle:model.sourceKind.rawValue,spacing:10,padding:14) {
            HeadphoneStatusSummary(compact:true,showDetail:[.wrongBud,.unidentified,.permissionBlocked,.noMotion,.motionError].contains(model.headphoneLinkState),showTelemetry:true)
            if model.sourceKind == .airPods {
                if [.searching,.waitingForMotion,.stale].contains(model.headphoneLinkState) {
                    Label("No motion? Put AirPods in your ears, then turn off Automatic Ear Detection in their System Settings.",systemImage:"ear")
                        .font(.caption).foregroundStyle(PodTheme.amber).fixedSize(horizontal:false,vertical:true)
                }
                HStack(spacing:8) {
                    Button(model.status.requested ? "Retry connection" : "Connect AirPods",systemImage:"airpodspro") {
                        if model.status.requested { model.retryMotion() } else { model.startMotion() }
                    }.buttonStyle(.borderedProminent).disabled(model.recording)
                    Button("Stop",systemImage:"stop.fill") { model.stopMotion() }
                        .disabled(!model.status.requested && !model.status.active)
                    Spacer(minLength:0)
                }
                if [.noMotion,.motionError].contains(model.headphoneLinkState) { ConnectionDiagnosticsButton() }
                microphoneHint
            } else {
                Button("Use real AirPods") { model.selectSource(.airPods) }.disabled(model.recording)
            }
            HStack {
                Text(model.sourceKind == .airPods ? "macOS chooses which AirPod streams motion." : "Switch to AirPods to record a physical car.").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength:4)
                if model.sourceKind == .airPods { setupHelpButton }
            }
        }
    }
    private var fullPanel: some View {
        Panel(title:"AirPod on the car",subtitle:model.sourceKind == .airPods ? "Right is the default" : "Simulation") {
            if model.sourceKind == .airPods {
                RecordingBudPicker()
                HeadphoneStatusSummary()
                if [.noMotion,.motionError].contains(model.headphoneLinkState) { ConnectionDiagnosticsButton() }
                if [.searching,.waitingForMotion,.stale].contains(model.headphoneLinkState) {
                    Label {
                        Text("Automatic Ear Detection may be stopping motion. Put your AirPods in your ears, turn it off in System Settings → your AirPods, then retry.")
                            .fixedSize(horizontal:false,vertical:true)
                    } icon: {
                        Image(systemName:"ear")
                    }
                    .font(.caption).foregroundStyle(PodTheme.amber)
                    .padding(12).frame(maxWidth:.infinity,alignment:.leading)
                    .background(PodTheme.amber.opacity(0.08),in:RoundedRectangle(cornerRadius:10))
                }
                HStack(spacing:10) {
                    Button(model.status.requested ? "Retry connection" : "Connect AirPods",systemImage:"airpodspro") {
                        if model.status.requested { model.retryMotion() } else { model.startMotion() }
                    }.buttonStyle(.borderedProminent).disabled(model.recording)
                    Button("Stop",systemImage:"stop.fill") { model.stopMotion() }
                        .disabled(!model.status.requested && !model.status.active)
                    Spacer(minLength:0)
                }
                HStack(alignment:.top) {
                    microphoneHint
                    Spacer(minLength:4)
                    setupHelpButton
                }
                if model.recording {
                    Text("Stop and save the run before changing AirPods.").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Records only the selected AirPod. macOS chooses which bud sends motion; the selector does not force a sensor handover.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                }
            } else {
                HeadphoneStatusSummary()
                Text("The Right / Left selector applies to real AirPods. Synthetic recordings use their own supplied calibration.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Use real AirPods") { model.selectSource(.airPods) }.disabled(model.recording)
            }
        }
    }
}

struct ConnectionDiagnosticsButton: View {
    @EnvironmentObject var model: AppModel
    @State private var copied = false
    var body: some View {
        Button(copied ? "Diagnostics copied" : "Copy diagnostics",systemImage:"doc.on.doc") {
            NSPasteboard.general.clearContents()
            copied = NSPasteboard.general.setString(model.connectionDiagnosticReport,forType:.string)
        }.font(.caption)
    }
}

enum AirPodsSetupImage: String, CaseIterable, Identifiable {
    case mac = "Mac", iPhone = "iPhone"
    var id: String { rawValue }
    private static let bundle: Bundle = {
        #if SWIFT_PACKAGE
        let bundle = Bundle.main.url(forResource:"airpods-hotwheels-track_PodTrack",withExtension:"bundle")
            .flatMap { Bundle(url:$0) } ?? Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        return bundle
    }()
    var url: URL? {
        Self.bundle.url(forResource:self == .mac ? "airpods-mac-setup" : "airpods-microphone-setup",withExtension:"png")
    }
    var image: NSImage? { url.flatMap { NSImage(contentsOf:$0) } }
}

struct AirPodsSetupReminder: View {
    let bud: RecordingBud
    var openGuide: () -> Void
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            Text("Before recording").font(.headline)
            SystemSettingsShortcut(title:"Microphone → Always \(bud.rawValue)",icon:"mic",destination:.airPods)
            SystemSettingsShortcut(title:"Automatic Ear Detection → Off",icon:"ear",destination:.airPods)
            Text("Check both settings in your AirPods settings.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Show Mac & iPhone screenshots",action:openGuide)
                .buttonStyle(.borderedProminent).tint(PodTheme.teal)
        }.font(.callout).padding(18).frame(width:330,alignment:.leading)
            .fixedSize(horizontal:false,vertical:true)
    }
}

struct AirPodsSetupSheet: View {
    let bud: RecordingBud
    @Environment(\.dismiss) private var dismiss
    @State private var platform: AirPodsSetupImage
    init(bud: RecordingBud, platform: AirPodsSetupImage = .mac) {
        self.bud = bud
        _platform = State(initialValue:platform)
    }
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            Text("Set up the \(bud.rawValue) AirPod").font(.title2.bold())
            SystemSettingsShortcut(title:"Open AirPods settings",icon:"airpodspro",destination:.airPods)
            HStack(alignment:.top,spacing:24) {
                VStack(spacing:8) {
                    Picker("Screenshot",selection:$platform) {
                        ForEach(AirPodsSetupImage.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented).frame(width:platform == .mac ? 330 : 245)
                    if let image = platform.image {
                        Image(nsImage:image).resizable().scaledToFit().frame(width:platform == .mac ? 330 : 245,height:480,alignment:.top)
                            .clipShape(RoundedRectangle(cornerRadius:12))
                            .accessibilityLabel("\(platform.rawValue) AirPods settings. Two red arrows point to Automatic Ear Detection, off, and Microphone, Always Right.")
                    }
                    Text("\(platform.rawValue) example · Always Right").font(.caption).foregroundStyle(.secondary)
                    Button("Open full-size screenshot",systemImage:"arrow.up.left.and.arrow.down.right") {
                        if let url = platform.url { NSWorkspace.shared.open(url) }
                    }.font(.caption).disabled(platform.url == nil)
                }
                ScrollView {
                    VStack(alignment:.leading,spacing:16) {
                        step("1. Open your AirPods settings", "Connect and wear your AirPods. On iPhone: Settings → your AirPods. On Mac: System Settings → your AirPods. If needed, open Audio & Routing.")
                        step("2. Microphone → Always \(bud.rawValue)", "Choose Always \(bud.rawValue) for the \(bud.rawValue.lowercased()) AirPod selected in PodTrack. The screenshot shows the right-side example.")
                        step("3. Turn off Automatic Ear Detection", "Do this before mounting the AirPod on the car, so taking it out of your ear does not interrupt the setup. Recheck motion after mounting.")
                        step("4. Retry and check the stream", "Return to PodTrack on this Mac and click Retry connection. Confirm Required: \(bud.rawValue.lowercased()) and Stream: \(bud.rawValue.lowercased()). Move only that AirPod and check the live tilt responds.")
                        Text("Microphone selects audio input. macOS still chooses the motion sensor, so always check Stream. If the other bud is streaming, try keeping it in its case and reconnecting. Stop and save before switching sides.")
                            .font(.caption).foregroundStyle(.secondary)
                        Link("Apple: AirPods settings",destination:URL(string:"https://support.apple.com/108764")!)
                            .font(.caption)
                    }.frame(maxWidth:.infinity,alignment:.leading).padding(.trailing,6)
                }
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }.padding(24).frame(width:760,height:690).tint(PodTheme.teal)
    }
    private func step(_ title: String, _ detail: String) -> some View {
        VStack(alignment:.leading,spacing:5) {
            Text(title).font(.callout.bold())
            Text(detail).font(.callout).foregroundStyle(.secondary)
        }.fixedSize(horizontal:false,vertical:true)
    }
}

struct RecordingBudPicker: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Picker("Use for recording",selection:Binding(get:{model.selectedBud},set:{model.selectBud($0)})) {
            ForEach(RecordingBud.allCases,id:\.self) { bud in Text("\(bud.rawValue) AirPod").tag(bud) }
        }.pickerStyle(.segmented).disabled(model.recording)
            .accessibilityLabel("AirPod required for recording")
            .help("Switch the recording side and load its mounting calibration. macOS chooses the streaming sensor.")
    }
}

struct HeadphoneStatusSummary: View {
    @EnvironmentObject var model: AppModel
    var compact = false
    var showDetail = false
    var showTelemetry = false
    private var state: HeadphoneLinkState { model.headphoneLinkState }
    private var selected: String { model.selectedBud.rawValue.lowercased() }
    private var actual: String { model.latest?.sensorLocation.rawValue ?? "unknown" }
    private var color: Color {
        switch state {
        case .receiving: return PodTheme.teal
        case .permissionBlocked,.wrongBud,.unidentified,.stale,.noMotion,.motionError: return PodTheme.amber
        case .simulation: return .purple
        default: return .secondary
        }
    }
    private var title: String {
        switch state {
        case .simulation: return "Simulation · no hardware connection"
        case .permissionBlocked: return "Motion permission is blocked"
        case .idle: return "AirPods motion is stopped"
        case .searching: return "Waiting for headphone motion…"
        case .waitingForMotion: return "Headphones connected · waiting for motion"
        case .noMotion: return model.status.connected ? "Headphones connected · no motion data" : "No headphone motion data received"
        case .motionError: return "Headphone motion error"
        case .receiving: return "\(model.selectedBud.rawValue) AirPod connected · receiving motion"
        case .wrongBud: return "Waiting for the \(selected) AirPod"
        case .unidentified: return "Motion received · side unknown"
        case .stale: return model.hasDeliveryBacklog ? "Connected · motion is delayed" : "Connected · motion stopped arriving"
        }
    }
    private var detail: String {
        switch state {
        case .simulation: return model.status.active ? "Synthetic motion is playing." : "Choose a track shape and simulate a run."
        case .permissionBlocked: return "Allow PodTrack in System Settings → Privacy & Security → Motion & Fitness."
        case .idle: return "Choose Right or Left, then connect."
        case .searching: return "AirPods can be connected over Bluetooth without sending motion."
        case .waitingForMotion: return "The connection is confirmed, but no motion samples have arrived."
        case .noMotion: return "No valid motion samples after \(model.status.waitingSeconds) s. Retry starts a fresh session. If it stays empty, copy diagnostics."
        case .motionError: return model.status.motionError ?? model.status.detail
        case .receiving: return "Ready to calibrate and record the \(selected) AirPod."
        case .wrongBud: return "macOS is sending the \(actual) AirPod. That bud will not be recorded with the current selection."
        case .unidentified: return "The selected side cannot be confirmed. Recording requires a reported left/right source."
        case .stale:
            if model.hasDeliveryBacklog { return "Old motion is arriving. Retry connection, then capture level again." }
            return "No fresh motion for \(model.sampleAge.map { formatted($0,1) } ?? "—") s. Check the connection and ear detection."
        }
    }
    var body: some View {
        VStack(alignment:.leading,spacing:compact ? 5 : 8) {
            HStack(alignment:.top,spacing:8) {
                if [.searching,.waitingForMotion].contains(state) {
                    ProgressView().controlSize(.small).frame(width:12,height:14)
                } else {
                    Circle().fill(color).frame(width:8,height:8).padding(.top,compact ? 3 : 4)
                }
                Text(title).font(compact ? .caption.weight(.semibold) : .callout.weight(.semibold))
                    .foregroundStyle(color).fixedSize(horizontal:false,vertical:true)
            }
            if !compact || showDetail {
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }
            if state == .permissionBlocked {
                SystemSettingsShortcut(title:"Open Motion & Fitness",icon:"hand.raised",destination:.motion)
            }
            if !compact || showTelemetry {
                if model.sourceKind == .airPods {
                    HStack(spacing:12) {
                        Text("Required: \(selected)")
                        Text("Stream: \(model.hasFreshMotion ? actual : "—")")
                        Text("Source: \(formatted(model.hasFreshMotion ? model.statistics.frequencyHz : 0,1)) Hz")
                    }.font(.system(.caption,design:.monospaced)).foregroundStyle(.secondary)
                    if model.latest != nil {
                        Text(model.motionTimingSummary).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
        }.accessibilityElement(children:.combine)
    }
}

/// System Settings owns these controls; opening a page never changes a preference.
private enum SettingsDestination {
    case motion, airPods
    var url: URL {
        switch self {
        case .motion: return URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Motion")!
        case .airPods: return URL(string:"x-apple.systempreferences:com.apple.HeadphoneSettings")!
        }
    }
}

private struct SystemSettingsShortcut: View {
    let title: String
    let icon: String
    let destination: SettingsDestination
    @State private var failed = false
    var body: some View {
        Button {
            failed = !NSWorkspace.shared.open(destination.url)
        } label: {
            Label(title,systemImage:icon)
        }
        .font(.caption).buttonStyle(.bordered)
        .help("Open the corresponding page in System Settings. Change the setting there, then return and retry the connection.")
        .alert("Could not open System Settings",isPresented:$failed) {
            Button("OK",role:.cancel) {}
        } message: {
            Text("Open System Settings and select your AirPods, or Privacy & Security → Motion & Fitness for motion permission.")
        }
    }
}

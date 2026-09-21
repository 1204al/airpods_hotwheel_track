import SwiftUI
import PodTrackCore

enum AppArea: String, CaseIterable, Identifiable {
    case record = "Record Run", compare = "Saved Runs & Compare", track = "Track Visualization", analysis = "Run Analysis", dashboard = "Live Dashboard", diagnostics = "Diagnostics", export = "Export", howItWorks = "How It Works"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .diagnostics: return "waveform.path.ecg"
        case .dashboard: return "gauge.with.dots.needle.50percent"
        case .record: return "record.circle"
        case .export: return "square.and.arrow.up"
        case .analysis: return "chart.xyaxis.line"
        case .track: return "cube.transparent"
        case .compare: return "square.stack.3d.up"
        case .howItWorks: return "lightbulb"
        }
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    private var navigationSelection: Binding<AppArea?> {
        Binding(get: {
            switch model.area ?? .record {
            case .track, .analysis, .export, .compare: return .compare
            case .dashboard, .diagnostics: return .dashboard
            default: return model.area
            }
        }, set: { model.area = $0 })
    }
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    var body: some View {
        NavigationSplitView(columnVisibility:$columnVisibility) {
            VStack(alignment:.leading,spacing:0) {
                HStack(spacing:10) {
                    Image(systemName:"point.3.connected.trianglepath.dotted").font(.title).foregroundStyle(PodTheme.teal)
                    VStack(alignment:.leading,spacing:3) {
                        Text("PodTrack").font(.title2.bold())
                        Text("MOTION LAB").font(.system(size:9,weight:.semibold,design:.monospaced)).tracking(2).foregroundStyle(.secondary)
                        Text("v\(Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "dev")")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }.padding(22)
                List(selection:navigationSelection) {
                    Section {
                        Label("Record",systemImage:"record.circle").tag(AppArea.record)
                        Label("Runs",systemImage:"square.stack.3d.up").tag(AppArea.compare)
                        Label("Device",systemImage:"airpodspro").tag(AppArea.dashboard)
                    }
                    Section("Learn") {
                        Label("How It Works",systemImage:"questionmark.circle").tag(AppArea.howItWorks)
                            .accessibilityIdentifier("sidebar-how-it-works")
                            .help("Understand PodTrack, prepare a run, and explore the motion examples.")
                    }
                }
                VStack(alignment:.leading,spacing:8) {
                    Picker("Motion source",selection:Binding(get:{ model.selectedSource },set:{ model.selectSource($0) })) {
                        ForEach(SourceKind.allCases,id:\.self) { Text($0.rawValue).tag($0) }
                    }.labelsHidden().disabled(model.recording)
                    Label(model.sourceKind.rawValue,systemImage:"airpodspro").font(.headline)
                    HeadphoneStatusSummary(compact:true)
                    Text("Experimental telemetry\nGeometry & speed are estimates.").font(.caption2).foregroundStyle(.secondary)
                }.padding(20)
            }.navigationSplitViewColumnWidth(min:205,ideal:220,max:260)
        } detail: {
            Group {
                switch model.area ?? .record {
                case .diagnostics, .dashboard: DeviceWorkspace()
                case .record: RecordRunView()
                case .export, .analysis, .track, .compare: RunsWorkspace()
                case .howItWorks: HowItWorksView()
                }
            }.background(Color(nsColor:.windowBackgroundColor))
        }.tint(PodTheme.teal)
            .task {
                if ProcessInfo.processInfo.arguments.contains("--compare-algorithms") { openWindow(id:"algorithm-comparison") }
                if ProcessInfo.processInfo.arguments.contains("--open-latest-track"), let run = model.selectedRun { model.openRun(run) }
                if ProcessInfo.processInfo.arguments.contains("--open-recording-setup") {
                    model.area = .record
                    try? await Task.sleep(nanoseconds:200_000_000)
                    PrototypeVerification.reportLibraryWindowIfRequested(model:model)
                }
            }
            .alert("PodTrack",isPresented:Binding(get:{ model.errorMessage != nil },set:{ if !$0 { model.errorMessage = nil } })) {
                Button("OK") { model.errorMessage = nil }
            } message: { Text(model.errorMessage ?? "") }
    }
}

struct DeviceWorkspace: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(spacing:0) {
            Picker("Device view",selection:Binding(get:{ model.area == .diagnostics },set:{ model.area = $0 ? .diagnostics : .dashboard })) {
                Text("Live signals").tag(false)
                Text("Diagnostics").tag(true)
            }.pickerStyle(.segmented).frame(width:320).padding(20)
            if model.area == .diagnostics { DiagnosticsView() } else { DashboardView() }
        }
    }
}

struct RunsWorkspace: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var comparing = false
    var body: some View {
        VStack(spacing:0) {
            if model.area == .track || model.area == .analysis {
                HStack {
                    Button("All runs",systemImage:"chevron.left") { model.area = .compare; comparing = false }
                    Spacer()
                    Picker("Run view",selection:Binding(get:{ model.area == .analysis },set:{ model.area = $0 ? .analysis : .track })) {
                        Text("3D Track").tag(false)
                        Text("Analysis").tag(true)
                    }.pickerStyle(.segmented).frame(width:240)
                    Spacer()
                    if let run = model.selectedRun {
                        RunExportButton(run:run)
                    }
                    Menu("Advanced") {
                        Button("Compare algorithms") { openWindow(id:"algorithm-comparison") }
                    }
                }.padding(20)
                if model.area == .track { TrackVisualizationView() } else { AnalysisView() }
            } else if comparing || !model.comparedRunIDs.isEmpty {
                HStack {
                    Button("All runs",systemImage:"chevron.left") { comparing = false; model.clearComparison() }
                    Spacer()
                }.padding(20)
                CompareRunsView()
            } else {
                RunLibraryView(startComparison:{ comparing = true })
            }
        }
    }
}

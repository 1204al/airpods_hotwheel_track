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
                List(AppArea.allCases,selection:$model.area) { area in Label(area.rawValue,systemImage:area.icon).tag(area) }
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
                case .diagnostics: DiagnosticsView()
                case .dashboard: DashboardView()
                case .record: RecordRunView()
                case .export: ExportView()
                case .analysis: AnalysisView()
                case .track: TrackVisualizationView()
                case .compare: CompareRunsView()
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
            .toolbar {
                ToolbarItem(placement:.primaryAction) {
                    Button("Compare algorithms",systemImage:"rectangle.split.2x1") { openWindow(id:"algorithm-comparison") }
                        .disabled(model.runs.isEmpty)
                }
                ToolbarItem(placement:.primaryAction) {
                    Button("Saved runs",systemImage:"square.stack.3d.up") { columnVisibility = .all; model.openComparison() }
                }
                ToolbarItem(placement:.primaryAction) {
                    Button("Height & record",systemImage:"ruler") { columnVisibility = .all; model.area = .record }
                }
            }
            .alert("PodTrack",isPresented:Binding(get:{ model.errorMessage != nil },set:{ if !$0 { model.errorMessage = nil } })) {
                Button("OK") { model.errorMessage = nil }
            } message: { Text(model.errorMessage ?? "") }
    }
}

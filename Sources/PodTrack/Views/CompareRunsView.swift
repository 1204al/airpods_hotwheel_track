import SwiftUI
import Charts
import PodTrackCore

struct CompareRunsView: View {
    @EnvironmentObject var model: AppModel
    // Developer rendering supplies the image of this same scene without touching
    // the user's windows or starting a hardware source.
    var renderedScene: NSImage? = nil
    @State private var byDistance = false
    @State private var search = ""
    @State private var editRun: RunSession?
    private var runs: [RunSession] { model.comparisonRuns }
    private var colors: [Color] { runs.map(color) }
    private var isRelativeComparison: Bool { runs.contains { model.analyses[$0.id]?.isRelative == true } }
    private var distanceUnit: String { isRelativeComparison ? "u" : "m" }
    private var speedUnit: String { isRelativeComparison ? "u/s" : "m/s" }
    private var entries: [ComparisonEntry] {
        runs.compactMap { run in
            model.analyses[run.id].map { ComparisonEntry(run:run,result:$0,colorIndex:model.comparisonColors[run.id] ?? 0,normalizeToUnitLength:isRelativeComparison) }
        }
    }
    private var filteredRuns: [RunSession] {
        let query = search.trimmingCharacters(in:.whitespacesAndNewlines)
        return model.runs.filter { query.isEmpty || "\($0.displayName) \($0.createdAt.formatted()) \($0.id.uuidString)".localizedCaseInsensitiveContains(query) }
    }
    private func color(_ run: RunSession) -> Color { Color(nsColor:ComparisonScene.color(model.comparisonColors[run.id] ?? 0)) }
    private func name(_ run: RunSession) -> String { run.comparisonDisplayName }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment:.leading,spacing:20) {
                    PageHeader(eyebrow:"Saved runs & compare",title:"Pick your runs. See them together.",detail:"Tick 2–4 saved runs to compare their estimated tracks in one 3D view. Each selected run gets its own colour.")
                    HStack { ReconstructionMethodPicker(); Spacer(); RecentlyDeletedButton() }
                    DeletedRecordingNotice()
                    if model.runs.isEmpty {
                        ContentUnavailableView("Your saved runs will appear here",systemImage:"square.stack.3d.up",description:Text("Calibrate the mounted AirPod, record a run, then press Stop & save run."))
                        Button("Record your first run",systemImage:"record.circle") { model.area = .record }.buttonStyle(.borderedProminent)
                    } else {
                        if let notice = model.comparisonNotice { Notice(text:notice) }
                        if geometry.size.width >= 850 {
                            HStack(alignment:.top,spacing:16) {
                                library.frame(width:310)
                                viewer.frame(maxWidth:.infinity)
                            }
                        } else {
                            library
                            viewer
                        }
                        if !entries.isEmpty {
                            DisclosureGroup("Speed, distances & segment timings") {
                                comparisonDetails.padding(.top,14)
                            }.font(.headline)
                        }
                    }
                }.padding(24)
            }
        }.onAppear { model.prepareComparison() }
            .onChange(of:model.runs.map(\.id)) { _,_ in model.prepareComparison() }
            .sheet(item:$editRun) { RunEditSheet(run:$0).environmentObject(model) }
    }

    private var library: some View {
        Panel(title:"1 · Choose runs",subtitle:"\(model.comparedRunIDs.count) of 4 selected") {
            HStack {
                Button("Latest 2 ready",systemImage:"checkmark.circle") { model.compareLatestRuns() }
                    .disabled(model.readyComparisonRuns.count<2 || !model.analysingIDs.isEmpty)
                    .help("Select the two most recent runs that have a reconstructed 3D path.")
                Spacer(minLength:0)
                Button("Clear") { model.clearComparison() }.disabled(model.comparedRunIDs.isEmpty)
            }.controlSize(.small)
            TextField("Search runs or AirPod side",text:$search).textFieldStyle(.roundedBorder)
                .accessibilityLabel("Search saved runs")
            Text("\(model.runs.count) saved · \(model.readyComparisonRuns.count) with a 3D path")
                .font(.caption).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(alignment:.leading,spacing:10) {
                    ForEach(filteredRuns) { run in runRow(run) }
                    if filteredRuns.isEmpty { Text("No runs match this search.").font(.callout).foregroundStyle(.secondary).padding(.vertical,20) }
                }.padding(.trailing,4)
            }.frame(height:440)
            if model.comparedRunIDs.count == 4 {
                Text("Four selected. Untick a run to choose another.").font(.caption).foregroundStyle(PodTheme.amber)
            } else {
                Text("Click a checkbox or run name to add it. The 3D view updates immediately.").font(.caption).foregroundStyle(.secondary)
            }
            Label("Saved on this Mac after Stop & save run",systemImage:"internaldrive").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func runRow(_ run: RunSession) -> some View {
        let isSelected = model.comparedRunIDs.contains(run.id)
        let result = model.analyses[run.id]
        let isReady = result != nil
        return VStack(alignment:.leading,spacing:8) {
            Toggle(isOn:Binding(get:{isSelected},set:{model.setCompared(run,selected:$0)})) {
                VStack(alignment:.leading,spacing:3) {
                    HStack(spacing:5) {
                        if isSelected { Text("\((model.comparisonColors[run.id] ?? 0)+1) ·").foregroundStyle(color(run)) }
                        Text(run.metadata.carName).lineLimit(2)
                    }.font(.callout.bold())
                    Text(run.recordedOrigin.label).font(.caption.bold()).foregroundStyle(isSelected ? color(run) : .primary)
                    Text(run.createdAt,format:.dateTime.month(.abbreviated).day().hour().minute().second()).font(.caption).foregroundStyle(.secondary)
                }
            }.toggleStyle(.checkbox).disabled(!isReady || (!isSelected && model.comparedRunIDs.count>=4))
                .accessibilityLabel("Compare \(name(run))")
            Text("\(run.metadata.trackName) · H \(run.metadata.heightLabel)")
                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            if let result {
                Label(result.isRelative ? "Relative 3D shape · scale unknown" : "3D estimate · \(formatted(result.metrics.estimatedPathLength)) m",systemImage:"cube.transparent")
                    .font(.caption).foregroundStyle(isSelected ? color(run) : .secondary)
                if let advice = RecordingReview(run:run,result:result).endpointAdvice {
                    Label(advice.title,systemImage:"exclamationmark.triangle").font(.caption2).foregroundStyle(PodTheme.amber)
                }
            } else if model.analysingIDs.contains(run.id) {
                ProgressView("Checking 3D path…").controlSize(.small).font(.caption)
            } else {
                Label(run.calibration == nil ? "Raw only · no calibration" : "No 3D trajectory",systemImage:"info.circle")
                    .font(.caption).foregroundStyle(PodTheme.amber)
                DisclosureGroup("Why can't I select this?") {
                    Text(model.analysisErrors[run.id] ?? "The path could not be reconstructed.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                }.font(.caption)
            }
            HStack(spacing:12) {
                Button(isReady ? "Open 3D" : "View recording") { model.openRun(run,in:isReady ? .track : .analysis) }
                Button("Edit name & height") { editRun = run }
                Spacer(minLength:0)
                DeleteRecordingButton(run:run,compact:true)
            }.font(.caption).buttonStyle(.link)
            if model.unsavedIDs.contains(run.id) {
                Button("Not saved yet · retry save") { model.persist(run) }.font(.caption).tint(PodTheme.amber)
            }
        }.padding(12).frame(maxWidth:.infinity,alignment:.leading)
            .background(isSelected ? color(run).opacity(0.07) : Color.primary.opacity(0.025),in:RoundedRectangle(cornerRadius:9))
            .overlay(RoundedRectangle(cornerRadius:9).strokeBorder(isSelected ? color(run).opacity(0.65) : Color.primary.opacity(0.08),lineWidth:isSelected ? 1.5 : 1))
    }

    private var viewer: some View {
        VStack(alignment:.leading,spacing:12) {
            if entries.isEmpty {
                Panel(title:"2 · Compare in 3D") {
                    VStack(spacing:18) {
                        Image(systemName:"square.stack.3d.up").font(.system(size:42)).foregroundStyle(PodTheme.teal)
                        Text("Choose two runs to begin").font(.title2.bold())
                        Text("Use the checkboxes in the saved-run list, or choose Latest 2 ready.")
                            .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Text("Only recordings with a reconstructed path can be selected. Your raw recordings remain in the list.")
                            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.frame(maxWidth:.infinity).frame(height:445).padding(.horizontal,20)
                }
            } else {
                if entries.count == 1 {
                    Label("One run selected — tick another run to compare.",systemImage:"plus.circle")
                        .font(.callout).foregroundStyle(PodTheme.teal)
                }
                ComparisonExplorerView(entries:entries,renderedScene:renderedScene,onRemove:{ id in
                    if let run = model.runs.first(where:{$0.id == id}) { model.setCompared(run,selected:false) }
                }).id(model.reconstructionMethod)
                ForEach(runs) { run in
                    if let result = model.analyses[run.id], let advice = RecordingReview(run:run,result:result).endpointAdvice {
                        HStack(alignment:.top) {
                            Image(systemName:"exclamationmark.triangle").foregroundStyle(PodTheme.amber)
                            VStack(alignment:.leading,spacing:3) {
                                Text("\(name(run)): \(advice.title)").font(.caption.bold())
                                Text(advice.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength:0)
                            Button("Review") { model.openRun(run,in:.analysis) }.font(.caption)
                        }.padding(10).background(PodTheme.amber.opacity(0.06),in:RoundedRectangle(cornerRadius:8))
                    }
                }
            }
            Text("Record one car at a time. Replay aligns the detected release of each run; the AirPods pair provides one motion stream.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }
    }

    private var comparisonDetails: some View {
        VStack(spacing:16) {
                    HStack(spacing:16) {
                        Panel(title:"Estimated track overlays",subtitle:isRelativeComparison ? "XY · each path = 1 u" : "XY · equal scale") { overlay.frame(height:260) }
                        Panel(title:"Estimated speed profiles",subtitle:byDistance ? "Path distance" : "Time since release") {
                            Chart {
                                ForEach(runs) { run in
                                    if let entry = entries.first(where:{$0.id == run.id}) {
                                        ForEach(thinned(entry.points)) { p in
                                            LineMark(x:.value("Progress",byDistance ? p.distance : p.time-entry.releaseTime),y:.value("Speed",p.speed),series:.value("Run",run.id.uuidString))
                                                .foregroundStyle(by:.value("Run",run.id.uuidString))
                                        }
                                    }
                                }
                            }.chartForegroundStyleScale(domain:runs.map { $0.id.uuidString },range:colors).chartLegend(.hidden)
                                .chartXAxisLabel(byDistance ? "Estimated distance (\(distanceUnit))" : "Time since candidate release (s)")
                                .chartYAxisLabel("Estimated speed (\(speedUnit))").frame(height:225)
                            ForEach(runs) { run in Text(name(run)).font(.caption2).foregroundStyle(color(run)) }
                            Toggle("Compare along path distance",isOn:$byDistance).font(.caption)
                        }
                    }
                    Panel(title:"Run comparison",subtitle:isRelativeComparison ? "Relative · each path = 1 u" : "Speed & geometry are estimates") {
                        Grid(alignment:.leading,horizontalSpacing:24,verticalSpacing:12) {
                            GridRow { Text("Run"); Text("Recorded"); Text("Est. length"); Text("Est. max speed"); Text("Est. avg speed") }.font(.caption.bold())
                            ForEach(runs) { run in
                                if let m = model.analyses[run.id]?.metrics, let entry = entries.first(where:{$0.id == run.id}) {
                                    let length = entry.points.last?.distance ?? 0
                                    GridRow { Text(name(run)); Text("\(formatted(m.recordingDuration)) s"); Text("\(formatted(length)) \(distanceUnit)"); Text("\(formatted(entry.points.map(\.speed).max() ?? 0)) \(speedUnit)"); Text("\(formatted(length/max(0.001,m.motionDuration))) \(speedUnit)") }.font(.callout).monospacedDigit()
                                } else { GridRow { Text(name(run)); Text(model.analysingIDs.contains(run.id) ? "Processing…" : "Raw data only") } }
                            }
                        }
                    }
                    Panel(title:"Candidate segment timings",subtitle:"Total time per type; layers overlap") {
                        Grid(alignment:.leading,horizontalSpacing:24,verticalSpacing:10) {
                            GridRow { Text("Segment type"); ForEach(runs) { Text(name($0)) } }.font(.caption.bold())
                            ForEach(SegmentKind.allCases,id:\.self) { kind in
                                GridRow {
                                    Text(kind.rawValue)
                                    ForEach(runs) { run in
                                        if let result = model.analyses[run.id] {
                                            let sections = result.segments.filter { $0.kind == kind }
                                            Text(sections.isEmpty ? "—" : "\(formatted(sections.map(\.duration).reduce(0,+))) s")
                                        } else { Text("—") }
                                    }
                                }.font(.caption).monospacedDigit()
                            }
                        }
                    }
        }
    }
    private var overlay: some View {
        VStack(alignment:.leading,spacing:12) {
            Canvas { context,size in
                let all = entries.flatMap(\.points)
                let xs = all.map { $0.position.x }, ys = all.map { $0.position.y }
                let xmin = xs.min() ?? 0, xmax = xs.max() ?? 1, ymin = ys.min() ?? 0, ymax = ys.max() ?? 1
                let scale = min((size.width-30)/max(0.1,xmax-xmin),(size.height-30)/max(0.1,ymax-ymin))
                for (index,run) in runs.enumerated() {
                    let points = entries.first(where:{$0.id == run.id})?.points ?? []
                    var path = Path()
                    for (i,p) in points.enumerated() {
                        let point = CGPoint(x:size.width/2+(p.position.x-(xmin+xmax)/2)*scale,y:size.height/2-(p.position.y-(ymin+ymax)/2)*scale)
                        if i == 0 { path.move(to:point) } else { path.addLine(to:point) }
                    }
                    context.stroke(path,with:.color(colors[index]),style:.init(lineWidth:2.5,lineCap:.round,lineJoin:.round))
                }
            }
            HStack { ForEach(Array(runs.enumerated()),id:\.element.id) { i,run in Text(name(run)).font(.caption2).foregroundStyle(colors[i]) } }
        }
    }
}

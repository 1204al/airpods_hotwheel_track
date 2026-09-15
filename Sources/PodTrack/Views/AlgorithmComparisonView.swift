import SwiftUI
import Charts
import PodTrackCore

struct AlgorithmComparisonResults: Sendable {
    var baseline: AnalysisResult?
    var improved: AnalysisResult?
    var baselineError: String?
    var improvedError: String?
    var baselineCollapsed: [MotionQualityInterval] = []
    var framing: [TrackPoint] { (baseline?.points ?? [])+(improved?.points ?? []) }

    static func calculate(run: RunSession, useRepeatedCircuits: Bool) -> Self {
        var value = Self()
        do {
            let result = try AnalysisPipeline.analyze(run)
            value.baseline = result
            value.baselineCollapsed = ImprovedReconstruction.collapsedMotion(samples:run.samples,signals:result.signals,
                points:result.points,speedScale:result.heightScale)
        } catch { value.baselineError = error.localizedDescription }
        do { value.improved = try ImprovedReconstruction.analyze(run,useRepeatedCircuits:useRepeatedCircuits) }
        catch { value.improvedError = error.localizedDescription }
        return value
    }
}

struct AlgorithmComparisonView: View {
    @EnvironmentObject private var model: AppModel
    @State private var runID: UUID?
    @State private var useRepeatedCircuits = true
    @State private var results: AlgorithmComparisonResults?
    @State private var selectedTime = 0.0
    @State private var playing = false
    @State private var cameraReset = 0
    @State private var showPlanes = true
    private var run: RunSession? { model.runs.first(where:{$0.id == (runID ?? model.selectedRunID)}) ?? model.runs.first }
    private struct Request: Hashable {
        var id: UUID; var metadata: RunMetadata; var calibration: MountCalibration?
        var count: Int; var lastTimestamp: Double?; var repeats: Bool
    }
    private var request: Request? {
        run.map { .init(id:$0.id,metadata:$0.metadata,calibration:$0.calibration,count:$0.samples.count,lastTimestamp:$0.samples.last?.timestamp,repeats:useRepeatedCircuits) }
    }
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            HStack(alignment:.top) {
                VStack(alignment:.leading,spacing:4) {
                    Text("Compare reconstruction methods").font(.title2.bold())
                    Text("Same recording · same measured scale · shared playback").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Fit both views",systemImage:"arrow.up.left.and.arrow.down.right") { cameraReset += 1 }
            }
            HStack(spacing:18) {
                Picker("Recording",selection:Binding<UUID?>(get:{run?.id},set:{runID = $0})) {
                    ForEach(model.runs) { item in
                        Text("\(item.carDisplayName) · \(item.createdAt.formatted(date:.abbreviated,time:.standard))").tag(Optional(item.id))
                    }
                }.frame(maxWidth:620)
                Toggle("Use matching repeat circuits",isOn:$useRepeatedCircuits)
                    .help("Use return and shared-route constraints only when complete inversion-to-inversion motion sequences match.")
                Toggle("Height planes",isOn:$showPlanes)
            }.font(.callout)
            if let run {
                if let results {
                    AlgorithmComparisonContent(run:run,results:results,selectedTime:$selectedTime,showPlanes:showPlanes,cameraReset:cameraReset,onScrub:{ playing = false })
                    HStack(spacing:12) {
                        Button(playing ? "Pause" : "Play both",systemImage:playing ? "pause.fill" : "play.fill") {
                            if !playing && selectedTime>=run.duration { selectedTime = 0 }
                            playing.toggle()
                        }
                        Button("Restart",systemImage:"backward.end.fill") { playing = false; selectedTime = 0 }
                        Slider(value:$selectedTime,in:0...max(0.01,run.duration),onEditingChanged:{ if $0 { playing = false } })
                            .accessibilityLabel("Shared comparison time")
                        Text("\(formatted(selectedTime)) / \(formatted(run.duration)) s").font(.callout.monospacedDigit()).frame(width:125)
                    }
                    DisclosureGroup("Fit details and limitations") {
                        ScrollView {
                            VStack(alignment:.leading,spacing:8) {
                                ForEach(results.improved?.warnings ?? [],id:\.self) { Text($0).font(.caption).fixedSize(horizontal:false,vertical:true) }
                                if let d = results.improved?.reconstructionDiagnostics {
                                    Text("Solver: \(d.speedFitConverged ? "converged" : "iteration limit") · \(d.speedFitIterations) iterations · acceleration residual \(formatted(d.accelerationResidualRMS)) m/s² · turning residual \(formatted(d.normalAccelerationRMS)) m/s²").font(.caption.monospacedDigit())
                                }
                            }.frame(maxWidth:.infinity,alignment:.leading)
                        }.frame(maxHeight:130)
                    }.font(.caption)
                } else {
                    HStack { ProgressView().controlSize(.small); Text("Reconstructing both methods…") }.frame(maxWidth:.infinity,minHeight:620)
                }
            } else {
                ContentUnavailableView("No saved recordings",systemImage:"waveform",description:Text("Record a run before comparing the methods."))
            }
        }.padding(20).frame(minWidth:1120,minHeight:860).background(Color(nsColor:.windowBackgroundColor))
            .task(id:request) {
                guard let run else { return }
                results = nil; playing = false; selectedTime = 0
                let repeats = useRepeatedCircuits
                let task = Task.detached(priority:.userInitiated) { AlgorithmComparisonResults.calculate(run:run,useRepeatedCircuits:repeats) }
                let value = await withTaskCancellationHandler(operation:{ await task.value },onCancel:{ task.cancel() })
                guard !Task.isCancelled else { return }
                results = value; cameraReset += 1
                PrototypeVerification.reportComparisonWindowIfRequested(run:run,results:value)
            }
            .task(id:playing) {
                guard playing, let run else { return }
                let started = ProcessInfo.processInfo.systemUptime, initial = selectedTime
                while !Task.isCancelled {
                    selectedTime = min(run.duration,initial+ProcessInfo.processInfo.systemUptime-started)
                    if selectedTime>=run.duration { playing = false; break }
                    do { try await Task.sleep(nanoseconds:33_000_000) } catch { break }
                }
            }
    }
}

struct AlgorithmComparisonContent: View {
    let run: RunSession
    let results: AlgorithmComparisonResults
    @Binding var selectedTime: Double
    var showPlanes = true
    var cameraReset = 0
    var renderedScenes: [NSImage]? = nil
    var onScrub: () -> Void = {}
    private var circuits: [RepeatCircuit] { results.improved?.reconstructionDiagnostics?.repeatCircuits ?? [] }
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack(alignment:.top,spacing:16) {
                panel("Current method",subtitle:"Baseline · 0.4.0",result:results.baseline,error:results.baselineError,
                      collapsed:results.baselineCollapsed,rendered:renderedScenes?.first)
                panel("Improved method",subtitle:"Experimental · 0.5.0",result:results.improved,error:results.improvedError,
                      collapsed:results.improved?.reconstructionDiagnostics?.collapsedMotion ?? [],rendered:renderedScenes?.last)
            }
            HStack {
                Text(run.metadata.verticalDrop.map { "Measured H: \(formatted($0*100,0)) cm" } ?? run.metadata.knownTrackLength.map { "Measured total distance: \(formatted($0)) m" } ?? "Scale unknown · each path = 1 u")
                Spacer()
                Text("Drag each view to orbit · Fit both views restores the same camera scale")
            }.font(.caption).foregroundStyle(.secondary)
            speedChart
            if !circuits.isEmpty {
                HStack(alignment:.top,spacing:20) {
                    VStack(alignment:.leading,spacing:5) {
                        Text("\(circuits.count) matching circuit intervals").font(.callout.bold())
                        Text(results.improved?.reconstructionDiagnostics?.repeatConstraintsApplied == true ? "Return constraints applied" : "Return constraints disabled")
                        Text("Return gaps describe the fit, not accuracy.")
                        if circuits.count>4 { Text("Showing the first four intervals.") }
                    }.font(.caption).foregroundStyle(.secondary).frame(width:240,alignment:.leading)
                    ForEach(Array(circuits.prefix(4).enumerated()),id:\.element.id) { index,circuit in
                        VStack(alignment:.leading,spacing:5) {
                            Text("Circuit \(index+1) · \(formatted(circuit.duration)) s").fontWeight(.semibold)
                            if let baseline = results.baseline,
                               let a = TrackSampling.point(at:circuit.startTime,in:baseline.points), let b = TrackSampling.point(at:circuit.endTime,in:baseline.points) {
                                Text("Current: \(formatted(b.distance-a.distance)) \(run.metadata.scaleBasis.distanceUnit)")
                            }
                            Text("Improved: \(formatted(circuit.estimatedLength)) \(run.metadata.scaleBasis.distanceUnit)")
                            Text("Return gap: \(formatted(circuit.closureDistance*(run.metadata.scaleBasis.isRelative ? 1 : 100))) \(run.metadata.scaleBasis.isRelative ? "u" : "cm")").foregroundStyle(.secondary)
                        }.font(.caption.monospacedDigit()).frame(maxWidth:.infinity,alignment:.leading)
                    }
                }
            } else {
                Text("No matching repeated circuits detected. Direction and acceleration evidence are used without closing the route.").font(.caption).foregroundStyle(.secondary)
            }
            Text("Experimental estimates · absolute distance and speed need independent validation. Original samples and saved settings are preserved.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private func panel(_ title: String, subtitle: String, result: AnalysisResult?, error: String?, collapsed: [MotionQualityInterval], rendered: NSImage?) -> some View {
        VStack(alignment:.leading,spacing:8) {
            HStack { Text(title).font(.headline); Spacer(); Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            if let result {
                if let rendered {
                    Image(nsImage:rendered).resizable().aspectRatio(contentMode:.fit).frame(height:330).frame(maxWidth:.infinity)
                } else {
                    Track3DView(result:result,selectedTime:selectedTime,options:.init(showPlanes:showPlanes),cameraReset:cameraReset,cameraPoints:results.framing)
                        .frame(height:330).clipShape(RoundedRectangle(cornerRadius:8))
                }
                HStack(spacing:18) {
                    metric("Total distance",formatted(result.metrics.estimatedPathLength)+" "+result.distanceUnit)
                    metric("Peak speed",formatted(result.metrics.estimatedMaximumSpeed)+" "+result.speedUnit)
                    metric("Speed at cursor",formatted(TrackSampling.point(at:selectedTime,in:result.points)?.speed ?? 0)+" "+result.speedUnit)
                }
                let longest = collapsed.map(\.duration).max() ?? 0
                Label(longest>0 ? "Near-zero speed during rotation: \(formatted(longest)) s" : "No sustained zero-speed / rotation mismatch",systemImage:longest>0 ? "exclamationmark.triangle" : "waveform.path")
                    .font(.caption).foregroundStyle(longest>0 ? Color.orange : Color.secondary)
            } else {
                ContentUnavailableView("Reconstruction unavailable",systemImage:"exclamationmark.triangle",description:Text(error ?? "Waiting for analysis")).frame(height:405)
            }
        }.frame(maxWidth:.infinity,alignment:.topLeading)
    }
    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment:.leading,spacing:3) { Text(label).font(.caption).foregroundStyle(.secondary); Text(value).font(.callout.bold().monospacedDigit()) }
            .frame(maxWidth:.infinity,alignment:.leading)
    }
    private var speedChart: some View {
        Chart {
            ForEach(thinned(results.baseline?.points ?? [])) { p in
                LineMark(x:.value("Time",p.time),y:.value("Speed",p.speed),series:.value("Method","Current")).foregroundStyle(by:.value("Method","Current"))
            }
            ForEach(thinned(results.improved?.points ?? [])) { p in
                LineMark(x:.value("Time",p.time),y:.value("Speed",p.speed),series:.value("Method","Improved")).foregroundStyle(by:.value("Method","Improved"))
            }
            RuleMark(x:.value("Cursor",selectedTime)).foregroundStyle(.secondary).lineStyle(.init(dash:[3,3]))
        }.chartForegroundStyleScale(["Current":Color.orange,"Improved":PodTheme.teal])
            .chartXScale(domain:0...max(0.01,run.duration)).chartXAxisLabel("Original recording time (s)")
            .chartYAxisLabel("Estimated speed (\(run.metadata.scaleBasis.speedUnit))")
            .chartXSelection(value:Binding<Double?>(get:{selectedTime},set:{ if let value = $0 { onScrub(); selectedTime = clamp(value,0,run.duration) } }))
            .frame(height:155)
    }
}

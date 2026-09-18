import SwiftUI
import PodTrackCore

struct RunPicker: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
          HStack(spacing:16) {
            Picker("Run",selection:$model.selectedRunID) {
                Text("Select a run").tag(UUID?.none)
                ForEach(model.runs) { run in
                    Text("\(run.displayName) · \(run.createdAt.formatted(date:.omitted,time:.standard))").tag(Optional(run.id))
                }
            }
            Spacer(minLength:0)
            Button("Compare runs in 3D",systemImage:"square.stack.3d.up") { model.openComparison(including:model.selectedRun) }
                .buttonStyle(.borderedProminent).disabled(model.runs.isEmpty)
            if let run = model.selectedRun { DeleteRecordingButton(run:run) }
          }
          HStack { ReconstructionMethodPicker(); Spacer(); RecentlyDeletedButton() }
          DeletedRecordingNotice()
        }.onChange(of:model.selectedRunID) { _,_ in
            model.cursorTime = 0; model.timeWindow = nil
            if let run = model.selectedRun { model.ensureAnalysis(run) }
        }.onAppear { if let run = model.selectedRun { model.ensureAnalysis(run) } }
    }
}

struct AnalysisView: View {
    @EnvironmentObject var model: AppModel
    @State private var speedByDistance = false
    @State private var editRun: RunSession?
    var renderedScene: NSImage? = nil
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                PageHeader(eyebrow:"Run analysis",title:model.selectedRun?.displayName ?? "From motion to a hypothesis.",detail:"Explore an estimated path from recorded motion. A measured height or track length sets its physical scale.")
                RunPicker()
                if let run = model.selectedRun {
                    if run.source == .simulation { Notice(text:"SIMULATED RUN — this analysis uses synthetic motion, not hardware measurements.") }
                    if let result = model.selectedAnalysis {
                        HStack(spacing:12) {
                            MetricTile(title:result.isRelative ? "Relative path length" : "Path length",value:formatted(result.metrics.estimatedPathLength),unit:result.distanceUnit,estimated:true)
                            MetricTile(title:result.isRelative ? "Relative max speed" : "Maximum speed",value:formatted(result.metrics.estimatedMaximumSpeed),unit:result.speedUnit,estimated:true)
                            MetricTile(title:result.isRelative ? "Relative avg speed" : "Average speed",value:formatted(result.metrics.estimatedAverageSpeed),unit:result.speedUnit,estimated:true)
                            MetricTile(title:"Recording duration",value:formatted(run.duration),unit:"s")
                        }
                        EstimateReviewPanel(run:run,result:result) { editRun = run }
                        HStack(alignment:.top,spacing:16) {
                            VStack(spacing:16) {
                                Panel(title:"Run details") {
                                    Text(run.carDisplayName).font(.headline)
                                    Text(run.createdAt.formatted()).font(.caption).foregroundStyle(.secondary)
                                    LabeledContent("Height H",value:run.metadata.heightLabel)
                                    LabeledContent("Recorded with",value:run.recordedOrigin.label)
                                    LabeledContent("Samples",value:"\(run.samples.count)")
                                    LabeledContent("Motion interval",value:"\(formatted(result.metrics.motionDuration)) s")
                                    if !run.metadata.notes.isEmpty { Text(run.metadata.notes).font(.caption).foregroundStyle(.secondary) }
                                    Button("Edit constraints & notes") { editRun = run }
                                    if model.unsavedIDs.contains(run.id) { Button("Retry saving run") { model.persist(run) }.tint(.orange) }
                                }
                                Panel(title:"Candidate segments",subtitle:"Heuristics") {
                                    ScrollView {
                                        VStack(alignment:.leading,spacing:10) {
                                            ForEach(result.segments) { s in
                                                Button { model.cursorTime = s.startTime } label: {
                                                    VStack(alignment:.leading,spacing:3) {
                                                        Text(s.kind.rawValue).font(.callout.weight(.medium))
                                                        Text("\(formatted(s.startTime))–\(formatted(s.endTime)) s · \(formatted(s.estimatedLength)) \(result.distanceUnit)")
                                                            .font(.caption2).foregroundStyle(.secondary)
                                                    }.frame(maxWidth:.infinity,alignment:.leading)
                                                }.buttonStyle(.plain)
                                            }
                                        }
                                    }.frame(maxHeight:260)
                                }
                            }.frame(width:225)
                            VStack(spacing:16) {
                                TrackExplorerView(run:run,result:result,sceneHeight:350,renderedScene:renderedScene).id("\(run.id)-\(result.algorithmVersion)")
                                HStack(spacing:16) {
                                    Panel(title:"Top-down XY") { TrackTopDownView(points:model.windowedPoints(result),selectedTime:model.cursorTime,isRelative:result.isRelative) }
                                    Panel(title:"Side profile") { TrackSideProfileView(points:model.windowedPoints(result),selectedTime:model.cursorTime,unit:result.distanceUnit) }
                                }
                            }.frame(maxWidth:.infinity)
                        }
                        scrubber(result)
                        Panel(title:"Detected segments",subtitle:"Overlapping candidates; click or drag to inspect") {
                            SegmentTimelineView(segments:result.segments,duration:run.duration,selectedTime:$model.cursorTime)
                        }
                        HStack(alignment:.top,spacing:16) {
                            Panel(title:"Estimated speed",subtitle:speedByDistance ? "Along path" : "Over time") {
                                SpeedChartView(points:result.points,selectedTime:$model.cursorTime,byDistance:speedByDistance,distanceUnit:result.distanceUnit,speedUnit:result.speedUnit)
                                Toggle("Use path distance",isOn:$speedByDistance).font(.caption)
                            }
                            Panel(title:"Orientation-derived slope",subtitle:"Degrees") {
                                DerivedSignalChart(signals:result.signals,field:\.slope,units:"°",multiplier:180 / .pi,cursor:model.cursorTime)
                            }
                            Panel(title:"Turning intensity",subtitle:result.reconstructionDiagnostics == nil ? "Signed heading rate" : "Rotation about gravity") {
                                DerivedSignalChart(signals:result.signals,field:\.turnRate,units:"rad/s",cursor:model.cursorTime,color:.blue)
                            }
                        }
                        Panel(title:"Raw signal evidence",subtitle:run.source == .simulation ? "SIMULATED · g" : "MEASURED · g") {
                            SignalChartView(samples:run.samples,signal:.acceleration,cursor:model.cursorTime)
                        }
                        AnalysisMetricsView(result:result)
                        Panel(title:"Reconstruction assumptions & quality",subtitle:"Experimental") {
                            Text("\(result.resolvedScaleBasis.label) · coordinate factor \(formatted(result.heightScale)) · horizontal factor \(formatted(result.horizontalScale)) · endpoint acceleration correction \(formatted(result.endpointAccelerationCorrection)) m/s²")
                                .font(.system(.caption,design:.monospaced))
                            Text(result.attitudeMapping).font(.caption).foregroundStyle(.secondary)
                            ForEach(Array(result.warnings.enumerated()),id:\.offset) { _,warning in Label(warning,systemImage:"info.circle").font(.callout).foregroundStyle(PodTheme.amber) }
                        }
                    } else { AnalysisUnavailableView(run:run) }
                } else {
                    ContentUnavailableView("No run selected",systemImage:"point.topleft.down.curvedto.point.bottomright.up",description:Text("Record a run to inspect its raw signals, then reconstruct a calibrated path."))
                    Button("Set up a run") { model.area = .record }.buttonStyle(.borderedProminent)
                }
            }.padding(24)
        }.sheet(item:$editRun) { RunEditSheet(run:$0).environmentObject(model) }
    }
    private func scrubber(_ result: AnalysisResult) -> some View {
        Panel(title:"Synchronized inspection",subtitle:"\(formatted(model.cursorTime)) s") {
            Text("The play line under the 3D view moves this cursor and selects the shown range.")
                .font(.caption).foregroundStyle(.secondary)
            if let point = result.points.min(by:{abs($0.time-model.cursorTime)<abs($1.time-model.cursorTime)}) {
                HStack {
                    Text("Est. speed \(formatted(point.speed)) \(result.speedUnit)")
                    Text("Distance \(formatted(point.distance)) \(result.distanceUnit)")
                    Text("Above ground \(formatted(point.position.z-result.groundZ)) \(result.distanceUnit)")
                    Spacer()
                    Text(point.segmentLabel)
                }.font(.system(.caption,design:.monospaced)).foregroundStyle(.secondary)
            }
        }
    }
}

struct SpeedLegend: View {
    let maximum: Double
    var unit = "m/s"
    var body: some View {
        HStack(spacing:8) {
            Text("0")
            LinearGradient(colors:(0...10).map { Color(nsColor:TrackScene.speedColor(Double($0)/10)) },startPoint:.leading,endPoint:.trailing).frame(width:110,height:5).clipShape(Capsule())
            Text("\(formatted(maximum)) \(unit) · estimated speed")
        }.font(.system(size:10,design:.monospaced)).foregroundStyle(.secondary)
    }
}

struct AnalysisUnavailableView: View {
    @EnvironmentObject var model: AppModel
    let run: RunSession
    var body: some View {
        VStack(alignment:.leading,spacing:20) {
            if model.analysingIDs.contains(run.id) { ProgressView("Reconstructing the run…") }
            else { Notice(text:model.analysisErrors[run.id] ?? "Analysis is waiting to start.") }
            Panel(title:"Raw motion is retained",subtitle:run.recordedOrigin.label) {
                SignalChartView(samples:run.samples,signal:.acceleration)
                Button("Export raw samples CSV") { model.exportRaw(run) }
            }
        }
    }
}

struct AnalysisMetricsView: View {
    let result: AnalysisResult
    var body: some View {
        Panel(title:"Telemetry metrics",subtitle:"Derived unless labeled observed") {
            LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible()),GridItem(.flexible())],alignment:.leading,spacing:14) {
                metric("Peak user acceleration · observed magnitude","\(formatted(result.metrics.observedPeakUserAcceleration)) m/s²")
                metric("Maximum turn intensity","\(formatted(result.metrics.estimatedMaximumTurnRate)) rad/s")
                metric("Total absolute heading change","\(formatted(result.metrics.estimatedTotalHeadingChangeDegrees,1))°")
                metric("Steepest downhill","\(formatted(result.metrics.estimatedSteepestDownhillDegrees,1))°")
                metric("Steepest uphill","\(formatted(result.metrics.estimatedSteepestUphillDegrees,1))°")
                metric("Reconstructed height range","\(formatted(result.metrics.reconstructedHeightRange)) \(result.distanceUnit)")
                metric("Possible airtime","\(formatted(result.metrics.candidateAirtime)) s")
                metric("Possible landing peak",result.metrics.candidateLandingPeakAcceleration.map { "\(formatted($0)) m/s²" } ?? "No candidate")
            }
            Divider()
            Grid(alignment:.leading,horizontalSpacing:20,verticalSpacing:8) {
                GridRow { Text("Candidate"); Text("Duration"); Text("Est. length"); Text("Est. mean speed"); Text("Entry → exit") }.font(.caption.bold())
                ForEach(result.segments) { s in
                    GridRow {
                        Text(s.kind.rawValue); Text("\(formatted(s.duration)) s"); Text("\(formatted(s.estimatedLength)) \(result.distanceUnit)")
                        Text("\(formatted(s.estimatedAverageSpeed)) \(result.speedUnit)"); Text("\(formatted(s.entrySpeed)) → \(formatted(s.exitSpeed)) \(result.speedUnit)")
                    }.font(.caption).monospacedDigit()
                }
            }
            Text("Segments overlap across slope, turn, and event layers; their lengths must not be summed.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment:.leading,spacing:5) { Text(label).font(.caption).foregroundStyle(.secondary); Text(value).font(.callout.monospacedDigit()) }
    }
}

struct TrackVisualizationView: View {
    @EnvironmentObject var model: AppModel
    @State private var editRun: RunSession?
    var renderedScene: NSImage? = nil
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                PageHeader(eyebrow:"Spatial reconstruction",title:"Your track, in three dimensions.",detail:"Explore the estimated shape and measure between points. With height unknown, distances are relative until you add a measured height or length.")
                RunPicker()
                if let run = model.selectedRun, let result = model.selectedAnalysis {
                    if run.source == .simulation { Notice(text:"SIMULATED RUN — all source motion was generated.") }
                    EstimateReviewPanel(run:run,result:result) { editRun = run }
                    TrackExplorerView(run:run,result:result,sceneHeight:460,renderedScene:renderedScene).id("\(run.id)-\(result.algorithmVersion)")
                    Text("\(formatted(model.cursorTime)) s · drag the 3D view to orbit; scroll to zoom").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing:16) {
                        Panel(title:"Top-down XY") { TrackTopDownView(points:model.windowedPoints(result),selectedTime:model.cursorTime,isRelative:result.isRelative).frame(height:230) }
                        Panel(title:"Distance vs height") { TrackSideProfileView(points:model.windowedPoints(result),selectedTime:model.cursorTime,unit:result.distanceUnit) }
                    }
                } else if let run = model.selectedRun { AnalysisUnavailableView(run:run) }
                else { ContentUnavailableView("Record a calibrated run first",systemImage:"cube.transparent") }
            }.padding(24)
        }.sheet(item:$editRun) { RunEditSheet(run:$0).environmentObject(model) }
    }
}

struct RecordingReview {
    let run: RunSession
    let result: AnalysisResult
    struct Advice {
        let title: String
        let detail: String
    }
    var endpointAdvice: Advice? {
        guard run.metadata.settings.startsAndEndsAtRest else { return nil }
        if let diagnostics = result.reconstructionDiagnostics {
            return advice(startSupported:diagnostics.startRestSupported,endSupported:diagnostics.endRestSupported)
        }
        guard
              let first = result.signals.firstIndex(where:{ !$0.isQuiet }),
              let last = result.signals.lastIndex(where:{ !$0.isQuiet }),
              let beginning = result.signals.first, let finish = result.signals.last else { return nil }
        // Match the edge-rest intervals used by SpeedEstimator. These are signal
        // checks, not measurements of positional accuracy or proof of physical rest.
        let startRest = result.signals[max(0,first-1)].time-beginning.time
        let endRest = finish.time-result.signals[min(result.signals.count-1,last+1)].time
        return advice(startSupported:startRest>=0.2,endSupported:endRest>=0.2)
    }
    private func advice(startSupported: Bool, endSupported: Bool) -> Advice? {
        if !startSupported && !endSupported {
            return .init(title:"No still start or finish detected",detail:"For the next run, record 1 second still before release and 1 second after the car stops, before picking it up.")
        }
        if !endSupported {
            return .init(title:"No still finish detected",detail:"Keep recording for 1 second after the car stops. Press Stop & save run before picking it up.")
        }
        if !startSupported {
            return .init(title:"No still start detected",detail:"Start recording while the car is held still at the start. Wait 1 second, then release it.")
        }
        return nil
    }
}

struct EstimateReviewPanel: View {
    let run: RunSession
    let result: AnalysisResult
    var onEdit: () -> Void
    private var advice: RecordingReview.Advice? { RecordingReview(run:run,result:result).endpointAdvice }
    var body: some View {
        VStack(alignment:.leading,spacing:9) {
            if result.isRelative {
                Label("Relative shape · scale unknown",systemImage:"ruler").font(.callout.bold()).foregroundStyle(PodTheme.teal)
                Text("The whole path = 1 relative unit (u). Distances use u; speeds use u/s. Add a measured height or length to estimate metres and m/s. The shape itself remains approximate.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            } else if result.resolvedScaleBasis == .trackLength {
                Label("Height unknown · scale from measured track length",systemImage:"ruler").font(.callout.bold()).foregroundStyle(PodTheme.teal)
            }
            HStack {
                Label(advice?.title ?? "Estimated shape · accuracy has not been measured",systemImage:advice == nil ? "info.circle" : "exclamationmark.triangle")
                    .font(.callout.bold()).foregroundStyle(PodTheme.amber)
                Spacer(minLength:0)
                Button("Check height & track length",action:onEdit).font(.caption)
            }
            Text(advice?.detail ?? "Mounting, motion and drift affect the shape. A measured height or length sets scale; it does not verify the reconstructed shape.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            DisclosureGroup("Recording checks & estimate limitations") {
                let statistics = SampleStatistics(samples:run.samples)
                Text("\(run.samples.count) samples · \(formatted(statistics.frequencyHz,1)) Hz · largest gap \(formatted(statistics.largestGap*1000,0)) ms")
                    .font(.caption.monospacedDigit())
                Text("H = \(run.metadata.heightLabel) · measured track length: \(run.metadata.knownTrackLength.map { "\(formatted($0)) m" } ?? "not provided")")
                    .font(.caption)
                Text("Sampling frequency describes updates per second. It does not establish position accuracy. Height fixes one scale constraint; multiple shapes can fit the same motion.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(Array(result.warnings.enumerated()),id:\.offset) { _,warning in
                    Label(warning,systemImage:"info.circle").font(.caption).foregroundStyle(PodTheme.amber)
                }
            }.font(.caption)
        }.padding(14).frame(maxWidth:.infinity,alignment:.leading)
            .background(PodTheme.amber.opacity(0.065),in:RoundedRectangle(cornerRadius:10))
    }
}

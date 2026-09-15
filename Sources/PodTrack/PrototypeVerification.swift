import AppKit
import Darwin
import Metal
import SceneKit
import SwiftUI
import PodTrackCore

/// Explicit developer commands. Normal app startup never generates simulation data.
@MainActor enum PrototypeVerification {
    static func reportLibraryWindowIfRequested(model: AppModel) {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of:"--library-window-receipt"), arguments.count>index+1 else { return }
        let report: [String:Any] = ["runID":model.selectedRun?.id.uuidString ?? "","method":model.reconstructionMethod.rawValue,
            "recordingHeight":model.heightIsKnown ? "Measured" : "Unknown",
            "selectedRunHeight":model.selectedRun?.metadata.verticalDrop.map { "\($0) m" } ?? "Unknown",
            "algorithmVersion":model.selectedAnalysis?.algorithmVersion ?? "",
            "pointCount":model.selectedAnalysis?.points.count ?? 0,
            "area":model.area?.rawValue ?? "","version":Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "",
            "windows":NSApplication.shared.windows.map { ["title":$0.title,"visible":$0.isVisible] as [String:Any] }]
        do {
            try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys])
                .write(to:URL(fileURLWithPath:arguments[index+1]),options:.atomic)
        } catch { FileHandle.standardError.write(Data("Library window receipt failed: \(error.localizedDescription)\n".utf8)) }
    }

    /// Optional receipt from the running app itself, after the comparison finishes loading.
    /// This observes only this process's windows; it neither starts hardware nor changes data.
    static func reportComparisonWindowIfRequested(run: RunSession, results: AlgorithmComparisonResults) {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of:"--comparison-receipt"), arguments.count>index+1 else { return }
        let windows = NSApplication.shared.windows.map { ["title":$0.title,"visible":$0.isVisible] as [String:Any] }
        let receipt: [String:Any] = [
            "runID":run.id.uuidString,
            "windows":windows,
            "baselinePointCount":results.baseline?.points.count ?? 0,
            "improvedPointCount":results.improved?.points.count ?? 0,
            "repeatCircuits":results.improved?.reconstructionDiagnostics?.repeatCircuits.count ?? 0
        ]
        do {
            try JSONSerialization.data(withJSONObject:receipt,options:[.prettyPrinted,.sortedKeys])
                .write(to:URL(fileURLWithPath:arguments[index+1]),options:.atomic)
        } catch { FileHandle.standardError.write(Data("Comparison receipt failed: \(error.localizedDescription)\n".utf8)) }
    }

    static func runIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of:"--render-replay-car") {
            do {
                guard arguments.count>index+1 else { throw PodTrackError.invalid("Provide an output directory for the replay preview.") }
                try ReplayCarVerification.run(output:URL(fileURLWithPath:arguments[index+1],isDirectory:true))
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("Replay car verification failed: \(error.localizedDescription)\n".utf8)); exit(1)
            }
        }
        if let index = arguments.firstIndex(of:"--verify-library") {
            guard arguments.count>index+2 else { FileHandle.standardError.write(Data("Provide a recording path and output directory.\n".utf8)); exit(1) }
            Task {
                do {
                    try await RunLibraryVerification.run(recording:URL(fileURLWithPath:arguments[index+1]),
                        output:URL(fileURLWithPath:arguments[index+2],isDirectory:true),render:arguments.contains("--render"))
                    exit(0)
                } catch { FileHandle.standardError.write(Data("Library verification failed: \(error.localizedDescription)\n".utf8)); exit(1) }
            }
            return
        }
        if let index = arguments.firstIndex(of:"--render-algorithm-comparison") {
            do {
                guard arguments.count>index+2 else { throw PodTrackError.invalid("Provide a saved recording path and an output directory.") }
                let output = URL(fileURLWithPath:arguments[index+2],isDirectory:true)
                try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
                let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
                let run = try decoder.decode(RunSession.self,from:Data(contentsOf:URL(fileURLWithPath:arguments[index+1])))
                let results = AlgorithmComparisonResults.calculate(run:run,useRepeatedCircuits:true)
                guard let baseline = results.baseline, let improved = results.improved else {
                    throw PodTrackError.invalid([results.baselineError,results.improvedError].compactMap{$0}.joined(separator:"\n"))
                }
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
                try encoder.encode(baseline).write(to:output.appendingPathComponent("baseline.json"))
                try encoder.encode(improved).write(to:output.appendingPathComponent("improved.json"))
                guard let device = MTLCreateSystemDefaultDevice() else { throw PodTrackError.invalid("No Metal device available for comparison rendering.") }
                let renderer = SCNRenderer(device:device,options:nil)
                var images: [NSImage] = []
                for (name,result) in [("baseline",baseline),("improved",improved)] {
                    let scene = TrackScene.make(result:result)
                    TrackScene.fitCamera(in:scene,points:results.framing)
                    TrackScene.updateCursor(in:scene,points:result.points,time:min(9.6,run.duration),isRelative:result.isRelative)
                    renderer.scene = scene; renderer.pointOfView = scene.rootNode.childNode(withName:"camera",recursively:false)
                    let image = renderer.snapshot(atTime:0,with:.init(width:1200,height:760),antialiasingMode:.multisampling4X)
                    images.append(image)
                    guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data:tiff), let png = bitmap.representation(using:.png,properties:[:]) else {
                        throw PodTrackError.invalid("Could not render the \(name) scene.")
                    }
                    try png.write(to:output.appendingPathComponent("\(name)-3d.png"))
                }
                for width in [1120.0,1420.0] {
                    let view = VStack(alignment:.leading,spacing:14) {
                        Text("PodTrack · Reconstruction comparison").font(.title2.bold())
                        Text("\(run.carDisplayName) · \(run.createdAt.formatted())").font(.callout)
                        AlgorithmComparisonContent(run:run,results:results,selectedTime:.constant(min(9.6,run.duration)),renderedScenes:images)
                    }.padding(20).frame(width:width).background(Color(nsColor:.windowBackgroundColor)).environment(\.colorScheme,.dark)
                    try renderView(view,to:output.appendingPathComponent("comparison-\(Int(width)).png"))
                }
                print("Rendered both methods from the same saved recording. Original library unchanged. \(output.path)")
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("Comparison render failed: \(error.localizedDescription)\n".utf8)); exit(1)
            }
        }
        if let index = arguments.firstIndex(of:"--render-connection-states") {
            do {
                let output = URL(fileURLWithPath:arguments.count>index+1 ? arguments[index+1] : "build/verification-connection",isDirectory:true)
                try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
                let states: [(String,MotionSourceStatus)] = [
                    ("no-data-connected",.init(connected:true,available:true,active:true,requested:true,authorization:"Authorized",detail:"Fixture: connected, no valid samples.",waitingSeconds:12,noMotionTimedOut:true)),
                    ("no-device",.init(available:false,requested:true,authorization:"Authorized",detail:"Fixture: no available device.",waitingSeconds:12,noMotionTimedOut:true)),
                    ("motion-error",.init(connected:true,available:true,active:true,requested:true,authorization:"Authorized",detail:"Fixture: an error from Core Motion.",motionError:"CMErrorDomain (101): Motion is unavailable in this test fixture."))
                ]
                for (name,status) in states {
                    let source = InterfacePreviewMotionSource()
                    source.status = status
                    let model = AppModel(motionSource:source,store:RunStore(directory:output.appendingPathComponent("PreviewLibrary-\(name)")))
                    defer { model.shutdown() }
                    model.selectBud(.left)
                    let panel = VStack(alignment:.leading,spacing:10) {
                        Text("INTERFACE FIXTURE · no hardware access").font(.caption).foregroundStyle(.orange)
                        HeadphoneConnectionPanel(compact:true)
                    }.environmentObject(model).padding(20).frame(width:480)
                        .background(Color(nsColor:.windowBackgroundColor)).environment(\.colorScheme,.dark)
                    try renderView(panel,to:output.appendingPathComponent("\(name).png"))
                    try model.connectionDiagnosticReport.write(to:output.appendingPathComponent("\(name).txt"),atomically:true,encoding:.utf8)
                }
                print("Rendered no-data and error connection states using isolated fixtures. No hardware was accessed.")
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("Connection preview failed: \(error.localizedDescription)\n".utf8)); exit(1)
            }
        }
        if let index = arguments.firstIndex(of:"--render-airpods-setup") {
            do {
                let output = URL(fileURLWithPath:arguments.count>index+1 ? arguments[index+1] : "build/verification-airpods-setup",isDirectory:true)
                try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
                guard AirPodsSetupImage.allCases.allSatisfy({ $0.image != nil }) else { throw PodTrackError.invalid("Bundled setup screenshot is missing.") }
                for bud in RecordingBud.allCases {
                    for platform in AirPodsSetupImage.allCases {
                        try renderView(AirPodsSetupSheet(bud:bud,platform:platform).background(Color(nsColor:.windowBackgroundColor))
                            .environment(\.colorScheme,.dark),to:output.appendingPathComponent("setup-\(platform.rawValue)-\(bud.rawValue.lowercased()).png"))
                    }
                    try renderView(AirPodsSetupReminder(bud:bud,openGuide:{}).background(Color(nsColor:.windowBackgroundColor))
                        .environment(\.colorScheme,.dark),to:output.appendingPathComponent("reminder-\(bud.rawValue.lowercased()).png"))
                }
                let model = AppModel(motionSource:InterfacePreviewMotionSource(),store:RunStore(directory:output.appendingPathComponent("PreviewLibrary")))
                defer { model.shutdown() }
                for bud in RecordingBud.allCases {
                    model.selectBud(bud)
                    let panel = HeadphoneConnectionPanel(compact:true).environmentObject(model)
                        .padding(20).frame(width:480).background(Color(nsColor:.windowBackgroundColor))
                        .environment(\.colorScheme,.dark)
                    try renderView(panel,to:output.appendingPathComponent("connection-\(bud.rawValue.lowercased()).png"))
                }
                print("Rendered setup guide and microphone hints for both sides. No hardware or user library access.")
                for platform in AirPodsSetupImage.allCases { print("Bundled screenshot: \(platform.url!.path)") }
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("AirPods setup render failed: \(error.localizedDescription)\n".utf8)); exit(1)
            }
        }
        if let index = arguments.firstIndex(of:"--render-calibration") {
            do {
                let output = URL(fileURLWithPath:arguments.count>index+1 ? arguments[index+1] : "build/verification-calibration",isDirectory:true)
                try renderCalibration(output:output)
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("Calibration render failed: \(error.localizedDescription)\n".utf8)); exit(1)
            }
        }
        if let index = arguments.firstIndex(of:"--render-unknown-height") {
            do {
                let output = URL(fileURLWithPath:arguments.count>index+1 ? arguments[index+1] : "build/verification-unknown-height",isDirectory:true)
                try renderUnknownHeight(output:output)
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("Unknown-height render failed: \(error.localizedDescription)\n".utf8)); exit(1)
            }
        }
        if let index = arguments.firstIndex(of:"--render-guide") {
            do {
                let output = URL(fileURLWithPath:arguments.count>index+1 ? arguments[index+1] : "build/verification-guide",isDirectory:true)
                try renderGuide(output:output)
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("Guide render failed: \(error.localizedDescription)\n".utf8)); exit(1)
            }
        }
        guard let index = arguments.firstIndex(of:"--verify-simulation") else { return }
        do {
            let output = URL(fileURLWithPath:arguments.count>index+1 ? arguments[index+1] : "build/verification",isDirectory:true)
            try verify(output:output,render:arguments.contains("--render"))
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("Verification failed: \(error.localizedDescription)\n".utf8)); exit(1)
        }
    }
    private static func verify(output: URL, render: Bool) throws {
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        let fixture = SimulatedTrack.generate(drop:0.42)
        var recorder = RunRecorder()
        try recorder.start(metadata:.init(trackName:"Verification circuit",carName:"Synthetic car",verticalDrop:0.42),source:.simulation,calibration:fixture.calibration)
        for sample in fixture.samples { try recorder.append(sample) }
        guard let run = recorder.finish() else { throw PodTrackError.invalid("Recorder returned no run") }
        let store = RunStore(directory:output.appendingPathComponent("Runs"))
        try store.save(run)
        guard let loaded = try store.load().runs.first(where:{$0.id == run.id}), loaded.samples == run.samples else {
            throw PodTrackError.invalid("Saved samples changed during persistence")
        }
        let result = try AnalysisPipeline.analyze(loaded)
        guard abs(result.groundZ)<1e-6, abs(result.metrics.reconstructedHeightRange-0.42)<1e-6 else { throw PodTrackError.invalid("Height constraint failed") }
        try CSVExporter.rawRun(run).write(to:output.appendingPathComponent("raw-samples.csv"),atomically:true,encoding:.utf8)
        try CSVExporter.reconstructedTrack(result).write(to:output.appendingPathComponent("estimated-track.csv"),atomically:true,encoding:.utf8)
        try CSVExporter.processedJSON(run:run,result:result).write(to:output.appendingPathComponent("analysis.json"),atomically:true,encoding:.utf8)
        if render {
            guard let device = MTLCreateSystemDefaultDevice() else { throw PodTrackError.invalid("No Metal device for render verification") }
            let renderer = SCNRenderer(device:device,options:nil)
            let scene = TrackScene.make(result:result)
            TrackScene.updateCursor(in:scene,points:result.points,time:2.9)
            TrackScene.updateMeasurement(in:scene,points:result.points,selection:.init(aTime:1.6,bTime:4.3))
            renderer.scene = scene; renderer.pointOfView = scene.rootNode.childNode(withName:"camera",recursively:false)
            renderer.autoenablesDefaultLighting = true
            scene.background.contents = NSColor(calibratedRed:0.045,green:0.065,blue:0.085,alpha:1)
            let sceneImage = renderer.snapshot(atTime:0,with:.init(width:1200,height:800),antialiasingMode:.multisampling4X)
            guard let tiff = sceneImage.tiffRepresentation,let bitmap = NSBitmapImageRep(data:tiff),let png = bitmap.representation(using:.png,properties:[:]) else {
                throw PodTrackError.invalid("SceneKit did not produce an image")
            }
            try png.write(to:output.appendingPathComponent("track-3d.png"))
            let report = VerificationReport(run:run,result:result,sceneImage:sceneImage).frame(width:1280).padding(28)
                .background(Color(red:0.06,green:0.07,blue:0.085)).environment(\.colorScheme,.dark)
            try renderView(report,to:output.appendingPathComponent("native-report.png"))
            // An inert source exercises the connection UI without requesting Core Motion
            // from this developer command. The image explicitly labels it as a UI preview.
            let previewModel = AppModel(motionSource:InterfacePreviewMotionSource(),store:RunStore(directory:output.appendingPathComponent("InterfacePreviewRuns")))
            let setup = VStack(spacing:0) {
                Text("INTERFACE PREVIEW · illustrative connection state · no AirPods readings")
                    .font(.system(.caption,design:.monospaced)).foregroundStyle(.orange).padding(10)
                RecordRunView().environmentObject(previewModel)
            }.frame(width:1180,height:760)
                .background(Color(red:0.075,green:0.08,blue:0.085)).environment(\.colorScheme,.dark)
            try renderView(setup,to:output.appendingPathComponent("setup-screen.png"))
            try renderCompactRecording(previewModel,name:"setup-minimum-waiting",output:output)
            previewModel.recordRawOnly = true; previewModel.dropCentimeters = "0"
            try renderCompactRecording(previewModel,name:"setup-minimum-raw-invalid-height",output:output)
            previewModel.recordRawOnly = false; previewModel.dropCentimeters = "58"
            previewModel.shutdown()
            // Isolated synthetic profile fixtures exercise the two real-side UI
            // states. They never read or write the user's run/profile library.
            let profileStore = RunStore(directory:output.appendingPathComponent("BudProfilePreviewRuns"))
            let mounts = CalibrationStore(directory:profileStore.directory.appendingPathComponent("Calibrations"))
            try mounts.save(.init(forwardDevice:.unitX,upDevice:.unitZ,sensorLocation:.right,source:.airPods,capturedAt:Date(timeIntervalSince1970:1789401600)))
            try mounts.save(.init(forwardDevice:.unitY,upDevice:.unitZ,sensorLocation:.left,source:.airPods,capturedAt:Date(timeIntervalSince1970:1789401720)))
            let profileSource = InterfacePreviewMotionSource()
            profileSource.status.connected = true
            let profileModel = AppModel(motionSource:profileSource,store:profileStore)
            for side in RecordingBud.allCases {
                profileModel.selectBud(side)
                profileSource.onSamples?([.init(sample:.init(timestamp:side == .right ? 1 : 2,sensorLocation:side.location))])
                let profiles = VStack(alignment:.leading,spacing:16) {
                    Text("INTERFACE FIXTURE · synthetic Left/Right samples · no AirPods readings")
                        .font(.caption.monospaced()).foregroundStyle(.orange)
                    HStack(alignment:.top,spacing:20) {
                        RecordingControlsPanel()
                        MountingCalibrationPanel()
                    }
                }.padding(24).frame(width:1100).background(Color(nsColor:.windowBackgroundColor))
                    .tint(PodTheme.teal).environment(\.colorScheme,.dark).environmentObject(profileModel)
                try renderView(profiles,to:output.appendingPathComponent("calibration-\(side.rawValue.lowercased()).png"))
            }
            try renderCompactRecording(profileModel,name:"setup-minimum-calibrated-left",output:output)
            profileModel.startRecording()
            try renderCompactRecording(profileModel,name:"setup-minimum-recording-left",output:output)
            let activeRecording = VStack(spacing:16) {
                Text("INTERFACE FIXTURE · synthetic recording state · no AirPods readings")
                    .font(.caption.monospaced()).foregroundStyle(.orange)
                RecordingControlsPanel()
            }.padding(24).frame(width:600).background(Color(nsColor:.windowBackgroundColor))
                .tint(PodTheme.teal).environment(\.colorScheme,.dark).environmentObject(profileModel)
            try renderView(activeRecording,to:output.appendingPathComponent("recording-left.png"))
            profileModel.shutdown()
            let simulationModel = AppModel(motionSource:SimulatedTrackMotionSource(),store:RunStore(directory:output.appendingPathComponent("SimulationSetupPreview")))
            try renderCompactRecording(simulationModel,name:"setup-minimum-simulation",output:output)
            simulationModel.shutdown()
            var comparison: [ComparisonEntry] = []
            var comparisonRuns: [RunSession] = []
            var comparisonResults: [UUID:AnalysisResult] = [:]
            for (index,profile) in SimulationProfile.allCases.enumerated() {
                let input = SimulatedTrack.generate(drop:RunMetadata.defaultHeightMeters,includeJump:false,profile:profile)
                let saved = RunSession(createdAt:Date(timeIntervalSince1970:1789401600-Double(index)*80),source:.simulation,metadata:.init(trackName:"Orange track",carName:"Car \(index+1)"),calibration:input.calibration,samples:input.samples)
                let analysis = try AnalysisPipeline.analyze(saved)
                comparisonRuns.append(saved); comparisonResults[saved.id] = analysis
                comparison.append(.init(run:saved,result:analysis,colorIndex:index))
            }
            let comparisonScene = ComparisonScene.make(entries:comparison)
            ComparisonScene.updateCursors(in:comparisonScene,entries:comparison,elapsed:2)
            renderer.scene = comparisonScene
            renderer.pointOfView = comparisonScene.rootNode.childNode(withName:"camera",recursively:false)
            let comparisonImage = renderer.snapshot(atTime:0,with:.init(width:1400,height:650),antialiasingMode:.multisampling4X)
            let comparisonReport = VStack(alignment:.leading,spacing:16) {
                Text("SIMULATED RUNS · 3D comparison preview · no simultaneous AirPods capture")
                    .font(.caption.monospaced()).foregroundStyle(.orange)
                ComparisonExplorerView(entries:comparison,renderedScene:comparisonImage,initialElapsed:2)
            }.padding(24).frame(width:1280).background(Color(red:0.075,green:0.08,blue:0.085)).environment(\.colorScheme,.dark)
            try renderView(comparisonReport,to:output.appendingPathComponent("comparison-3d.png"))
            ComparisonScene.updateCursors(in:comparisonScene,entries:comparison,elapsed:0)
            let libraryImage = renderer.snapshot(atTime:0,with:.init(width:1400,height:650),antialiasingMode:.multisampling4X)
            let rawPreview = RunSession(source:.simulation,metadata:.init(trackName:"Calibration practice",carName:"Raw recording"),calibration:nil,samples:fixture.samples)
            previewModel.runs = comparisonRuns+[rawPreview]
            previewModel.analyses = comparisonResults
            previewModel.analysisErrors[rawPreview.id] = "This recording has no mounting calibration. Its raw samples are saved, but it has no 3D trajectory."
            let banner = Text("SIMULATED DATA · native saved-run interface preview · no AirPods readings")
                .font(.caption.monospaced()).foregroundStyle(.orange).padding(10)
            let emptyComparison = VStack(spacing:0) {
                banner
                CompareRunsView().environmentObject(previewModel)
            }.frame(width:1200,height:900).background(Color(nsColor:.windowBackgroundColor)).tint(PodTheme.teal).environment(\.colorScheme,.dark)
            try renderView(emptyComparison,to:output.appendingPathComponent("saved-runs-empty.png"))
            comparisonRuns.forEach { previewModel.setCompared($0,selected:true) }
            let libraryComparison = VStack(spacing:0) {
                banner
                CompareRunsView(renderedScene:libraryImage).environmentObject(previewModel)
            }.frame(width:1200,height:930).background(Color(nsColor:.windowBackgroundColor)).tint(PodTheme.teal).environment(\.colorScheme,.dark)
            try renderView(libraryComparison,to:output.appendingPathComponent("saved-runs-comparison.png"))
            let narrowComparison = VStack(spacing:0) {
                banner
                CompareRunsView(renderedScene:libraryImage).environmentObject(previewModel)
            }.frame(width:780,height:1600).background(Color(nsColor:.windowBackgroundColor)).tint(PodTheme.teal).environment(\.colorScheme,.dark)
            try renderView(narrowComparison,to:output.appendingPathComponent("saved-runs-narrow.png"))
            let review = VStack(alignment:.leading,spacing:16) {
                banner
                EstimateReviewPanel(run:run,result:result,onEdit:{})
            }.padding(24).frame(width:1050).background(Color(nsColor:.windowBackgroundColor)).tint(PodTheme.teal).environment(\.colorScheme,.dark)
            try renderView(review,to:output.appendingPathComponent("estimate-review.png"))
            var clippedRun = run
            let lastActiveTime = result.signals.last(where:{ !$0.isQuiet })?.time ?? run.duration
            clippedRun.samples = run.samples.filter { $0.timestamp-run.samples[0].timestamp <= lastActiveTime }
            let clippedResult = try AnalysisPipeline.analyze(clippedRun)
            let clippedReview = VStack(alignment:.leading,spacing:16) {
                banner
                EstimateReviewPanel(run:clippedRun,result:clippedResult,onEdit:{})
            }.padding(24).frame(width:1050).background(Color(nsColor:.windowBackgroundColor)).tint(PodTheme.teal).environment(\.colorScheme,.dark)
            try renderView(clippedReview,to:output.appendingPathComponent("estimate-review-clipped.png"))
        }
        let summary: [String:Any] = ["source":"EXPLICIT SIMULATION","samples":run.samples.count,"duration_s":run.duration,
            "estimated_length_m":result.metrics.estimatedPathLength,"estimated_max_speed_m_s":result.metrics.estimatedMaximumSpeed,
            "end_z_m":result.points.last!.position.z,"ground_z_m":result.groundZ,"highest_z_m":result.points.map { $0.position.z }.max()!,"candidate_airtime_s":result.metrics.candidateAirtime,
            "segments":result.segments.map { $0.kind.rawValue },"hardware_verified":false,"native_render_verified":render,
            "exports_verified":true,"persistence_verified":true]
        let summaryData = try JSONSerialization.data(withJSONObject:summary,options:[.prettyPrinted,.sortedKeys])
        try summaryData.write(to:output.appendingPathComponent("verification.json"))
        print(String(decoding:summaryData,as:UTF8.self))
        print("Artifacts: \(output.path)")
    }
    private static func renderCalibration(output: URL) throws {
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        let source = InterfacePreviewMotionSource()
        let model = AppModel(motionSource:source,store:RunStore(directory:output.appendingPathComponent("SyntheticPreviewLibrary")))
        defer { model.shutdown() }
        model.captureLevelPose()
        for i in 0...30 {
            source.onSamples?([.init(sample:.init(timestamp:1+Double(i)/50,sensorLocation:.right))])
        }
        model.retryCapture()
        source.onSamples?([.init(sample:.init(timestamp:1.62,
            attitude:.init(axis:.unitY,angle: -.pi/6),
            gravity:.init(-0.5,0,-sqrt(0.75)),sensorLocation:.right))])
        let panel = VStack(alignment:.leading,spacing:14) {
            Text("SYNTHETIC UI CHECK · 30° step in the newest sample").font(.caption.bold())
            MountingCalibrationPanel().environmentObject(model)
        }.padding(20).frame(width:630)
        try renderView(panel,to:output.appendingPathComponent("latest-sample-30-degrees.png"))
        let record = RecordRunView().environmentObject(model).frame(width:872,height:960)
        try renderView(record,to:output.appendingPathComponent("recording-minimum-width.png"))
        let diagnostics = DiagnosticsView().environmentObject(model).frame(width:1000,height:1050)
        try renderView(diagnostics,to:output.appendingPathComponent("delivery-diagnostics.png"))
    }

    private static func renderCompactRecording(_ model: AppModel, name: String, output: URL) throws {
        // 840 pt is the available width at the app's 1100 pt minimum with its
        // sidebar at the widest 260 pt. The banner leaves less than 740 pt tall.
        let screen = VStack(spacing:0) {
            Text("INTERFACE FIXTURE · synthetic state · no AirPods readings")
                .font(.caption.monospaced()).foregroundStyle(.orange).padding(8)
            RecordRunView().environmentObject(model)
        }.frame(width:840,height:740).background(Color(nsColor:.windowBackgroundColor))
            .tint(PodTheme.teal).environment(\.colorScheme,.dark)
        try renderView(screen,to:output.appendingPathComponent(name+".png"))
    }
    private static func renderUnknownHeight(output: URL) throws {
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        let fixture = SimulatedTrack.generate(includeJump:false,profile:.raisedFinish)
        let run = RunSession(source:.simulation,metadata:.init(trackName:"Unknown height preview",verticalDrop:nil),
                             calibration:fixture.calibration,samples:fixture.samples)
        let result = try AnalysisPipeline.analyze(run)
        let model = AppModel(motionSource:InterfacePreviewMotionSource(),store:RunStore(directory:output.appendingPathComponent("PreviewLibrary")))
        defer { model.shutdown() }
        model.heightIsKnown = false
        try renderCompactRecording(model,name:"setup-unknown-minimum",output:output)
        model.heightIsKnown = true
        try renderCompactRecording(model,name:"setup-measured-minimum",output:output)
        guard let device = MTLCreateSystemDefaultDevice() else { throw PodTrackError.invalid("No Metal renderer") }
        let renderer = SCNRenderer(device:device,options:nil)
        let scene = TrackScene.make(result:result)
        TrackScene.updateCursor(in:scene,points:result.points,time:2.9,isRelative:true)
        TrackScene.updateMeasurement(in:scene,points:result.points,selection:.init(aTime:1.6,bTime:4.3),isRelative:true)
        renderer.scene = scene; renderer.pointOfView = scene.rootNode.childNode(withName:"camera",recursively:false)
        let sceneImage = renderer.snapshot(atTime:0,with:.init(width:1200,height:800),antialiasingMode:.multisampling4X)
        let report = VerificationReport(run:run,result:result,sceneImage:sceneImage).frame(width:1280).padding(28)
            .background(Color(nsColor:.windowBackgroundColor)).environment(\.colorScheme,.dark)
        try renderView(report,to:output.appendingPathComponent("relative-report.png"))
        for scheme in [ColorScheme.dark,.light] {
            let controls = VStack(alignment:.leading,spacing:20) {
                Text("SIMULATED PREVIEW · unknown height").font(.caption).foregroundStyle(.orange)
                TrackHeightControl(run:run,onChange:{_ in})
                TrackRulerControls(points:result.points,groundZ:result.groundZ,selection:.constant(.init(aTime:1.6,bTime:4.3)),
                                   cursorTime:.constant(2.9),isRelative:true)
            }.padding(20).frame(width:520).background(Color(nsColor:.windowBackgroundColor)).environment(\.colorScheme,scheme)
            try renderView(controls,to:output.appendingPathComponent("relative-controls-\(scheme == .dark ? "dark" : "light").png"),colorScheme:scheme)
        }
        var known = run; known.id = UUID(); known.metadata.verticalDrop = 0.58
        let measured = try AnalysisPipeline.analyze(known)
        let entries = [ComparisonEntry(run:run,result:result,colorIndex:0,normalizeToUnitLength:true),
                       ComparisonEntry(run:known,result:measured,colorIndex:1,normalizeToUnitLength:true)]
        let comparison = ComparisonScene.make(entries:entries)
        renderer.scene = comparison; renderer.pointOfView = comparison.rootNode.childNode(withName:"camera",recursively:false)
        let comparisonImage = renderer.snapshot(atTime:0,with:.init(width:1200,height:650),antialiasingMode:.multisampling4X)
        let comparisonView = ComparisonExplorerView(entries:entries,renderedScene:comparisonImage).padding(20).frame(width:840)
            .background(Color(nsColor:.windowBackgroundColor)).environment(\.colorScheme,.dark)
        try renderView(comparisonView,to:output.appendingPathComponent("relative-comparison.png"))
        for language in GuideLanguage.allCases {
            let guide = HowItWorksPage(language:.constant(language),initialStep:.scale)
                .frame(width:840,height:740).background(Color(nsColor:.windowBackgroundColor)).environment(\.colorScheme,.dark)
            try renderView(guide,to:output.appendingPathComponent("guide-scale-\(language.rawValue).png"))
        }
        print("Rendered unknown-height setup, relative analysis, ruler, comparison and bilingual scale guide. Synthetic fixtures; no hardware or user library access.")
    }
    private static func renderGuide(output: URL) throws {
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        guard GuideExample.result != nil else { throw PodTrackError.invalid("Educational simulation failed to reconstruct.") }
        for language in GuideLanguage.allCases {
            for step in GuideStep.allCases {
                let page = HowItWorksPage(language:.constant(language),initialStep:step)
                    .frame(width:1100,height:940).background(Color(nsColor:.windowBackgroundColor))
                    .environment(\.colorScheme,.dark)
                try renderView(page,to:output.appendingPathComponent("\(language.rawValue)-\(step.rawValue).png"))
            }
            for height in [29.0,87.0] {
                let page = HowItWorksPage(language:.constant(language),initialStep:.scale,initialHeight:height)
                    .frame(width:840,height:740).background(Color(nsColor:.windowBackgroundColor))
                    .environment(\.colorScheme,.dark)
                try renderView(page,to:output.appendingPathComponent("\(language.rawValue)-minimum-\(Int(height)).png"))
            }
            for motion in GuideSensorMotion.allCases {
                let page = HowItWorksPage(language:.constant(language),initialStep:.sensors,initialSensorMotion:motion)
                    .frame(width:840,height:940).background(Color(nsColor:.windowBackgroundColor))
                    .environment(\.colorScheme,.dark)
                try renderView(page,to:output.appendingPathComponent("\(language.rawValue)-sensors-\(motion.rawValue).png"))
            }
        }
        let light = HowItWorksPage(language:.constant(.ukrainian),initialStep:.direction)
            .frame(width:840,height:900).background(Color(nsColor:.windowBackgroundColor))
            .environment(\.colorScheme,.light)
        try renderView(light,to:output.appendingPathComponent("uk-light.png"),colorScheme:.light)
        let sensorLight = HowItWorksPage(language:.constant(.ukrainian),initialStep:.sensors,initialSensorMotion:.accelerating)
            .frame(width:840,height:940).background(Color(nsColor:.windowBackgroundColor))
            .environment(\.colorScheme,.light)
        try renderView(sensorLight,to:output.appendingPathComponent("uk-sensors-light.png"),colorScheme:.light)
        print("Rendered all \(GuideStep.allCases.count) guide steps in English and Ukrainian, the three sensor states, minimum-width scale extremes, and light appearance. Educational examples only; no run library accessed.")
    }
    static func renderView<Content: View>(_ content: Content, to url: URL, colorScheme: ColorScheme = .dark) throws {
        // NSHostingView includes the native backing views of text fields and sliders.
        let hosting = NSHostingView(rootView:content.background(Color(nsColor:.windowBackgroundColor))
            .environment(\.colorScheme,colorScheme).tint(PodTheme.teal))
        hosting.appearance = NSAppearance(named:colorScheme == .dark ? .darkAqua : .aqua)
        hosting.frame = .init(origin:.zero,size:hosting.fittingSize)
        let window = NSWindow(contentRect:hosting.frame,styleMask:.borderless,backing:.buffered,defer:false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in:hosting.bounds) else {
            throw PodTrackError.invalid("Native view bitmap unavailable")
        }
        hosting.cacheDisplay(in:hosting.bounds,to:bitmap)
        guard let data = bitmap.representation(using:.png,properties:[:]) else { throw PodTrackError.invalid("Native view did not render") }
        try data.write(to:url)
    }
}

/// Presentation-only fixture, reachable exclusively from --verify-simulation --render.
@MainActor private final class InterfacePreviewMotionSource: MotionSource {
    let kind: SourceKind = .airPods
    var status = MotionSourceStatus(connected:false,available:true,active:true,requested:true,authorization:"Authorized",detail:"UI preview only. No hardware is accessed.")
    var onSamples: (([MotionDelivery]) -> Void)?
    var onStatus: ((MotionSourceStatus) -> Void)?
    var onEvent: ((String) -> Void)?
    func start() {}
    func stop() { status.active = false; status.requested = false; refreshStatus() }
    func refreshStatus() { onStatus?(status) }
}

private struct VerificationReport: View {
    let run: RunSession
    let result: AnalysisResult
    let sceneImage: NSImage
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            PageHeader(eyebrow:"PodTrack · native render verification",title:"Your track, in three dimensions.",detail:"SIMULATED INPUT · \(result.resolvedScaleBasis.label) · A–B measurements from the estimated centerline.")
            HStack {
                MetricTile(title:"Estimated path",value:formatted(result.metrics.estimatedPathLength),unit:result.distanceUnit,estimated:true)
                MetricTile(title:"Estimated max speed",value:formatted(result.metrics.estimatedMaximumSpeed),unit:result.speedUnit,estimated:true)
                VStack(alignment:.leading,spacing:8) {
                    Text("Height H").font(.caption).foregroundStyle(.secondary)
                    Text(run.metadata.heightLabel).font(.title2.bold())
                }.frame(maxWidth:.infinity,alignment:.leading)
                MetricTile(title:"Recorded duration",value:"6.80",unit:"s")
            }
            HStack(alignment:.top,spacing:18) {
                Panel(title:"Estimated track in 3D",subtitle:"Orange track · height planes") {
                    TrackHeightControl(run:run,onChange:{_ in})
                    Image(nsImage:sceneImage).resizable().aspectRatio(contentMode:.fit).frame(maxWidth:.infinity)
                    TrackRulerControls(points:result.points,groundZ:result.groundZ,selection:.constant(.init(aTime:1.6,bTime:4.3)),cursorTime:.constant(2.9),isRelative:result.isRelative)
                }
                VStack(spacing:18) {
                    Panel(title:"Top-down XY") { TrackTopDownView(points:result.points,selectedTime:2.9,isRelative:result.isRelative).frame(height:175) }
                    Panel(title:"Height along path") { TrackSideProfileView(points:result.points,selectedTime:2.9,unit:result.distanceUnit) }
                }.frame(width:350)
            }
            HStack(alignment:.top,spacing:18) {
                Panel(title:"Estimated speed") { SpeedChartView(points:result.points,selectedTime:.constant(2.9),distanceUnit:result.distanceUnit,speedUnit:result.speedUnit) }
                Panel(title:"Orientation-derived slope") { DerivedSignalChart(signals:result.signals,field:\.slope,units:"°",multiplier:180 / .pi,cursor:2.9) }
                Panel(title:"Turning intensity") { DerivedSignalChart(signals:result.signals,field:\.turnRate,units:"rad/s",cursor:2.9,color:.blue) }
            }
            Panel(title:"Candidate event timeline",subtitle:"Heuristic layers overlap") { SegmentTimelineView(segments:result.segments,duration:6.8,selectedTime:.constant(2.9)) }
            Notice(text:result.isRelative
                   ? "Height unknown · whole path = 1 u. Add a measured height or length later to set physical scale. Shape remains approximate."
                   : "The entered height constrains scale, not uniqueness. No true position or speed is measured. Airborne path estimates are especially uncertain.")
        }
    }
}

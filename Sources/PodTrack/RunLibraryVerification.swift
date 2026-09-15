import AppKit
import Metal
import SceneKit
import SwiftUI
import PodTrackCore

/// Explicit acceptance checks against isolated copies. No XCTest dependency or hardware.
@MainActor enum RunLibraryVerification {
    static func run(recording: URL, output: URL, render: Bool) async throws {
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let original = try decoder.decode(RunSession.self,from:Data(contentsOf:recording))
        let store = RunStore(directory:output.appendingPathComponent("Library-\(UUID().uuidString)"))
        try store.save(original)
        let model = AppModel(motionSource:VerificationMotionSource(),store:store)
        defer { model.shutdown() }
        guard var run = model.selectedRun else { throw PodTrackError.invalid("Fixture did not load.") }
        try check(!model.heightIsKnown && model.setup.verticalDrop == nil,"New recording setup must default to Unknown")
        try check(run.metadata == original.metadata,"Unknown default changed an existing recording")
        try check(model.reconstructionMethod == .improved,"Improved must be the default")
        model.openRun(run); try await wait(model)
        guard let improved = model.selectedAnalysis else { throw PodTrackError.invalid(model.analysisErrors[run.id] ?? "Missing Improved analysis") }
        try check(improved.algorithmVersion == ImprovedReconstruction.version,"Wrong default algorithm")
        try check(RecordingReview(run:run,result:improved).endpointAdvice?.title == "No still start detected","Review must use improved endpoint diagnostics")
        let json = try CSVExporter.processedJSON(run:run,result:improved)
        try check(json.contains(ImprovedReconstruction.version),"Export does not identify the active method")
        try json.write(to:output.appendingPathComponent("improved-analysis.json"),atomically:true,encoding:.utf8)
        if render {
            let image = try sceneImage(TrackScene.make(result:improved))
            try PrototypeVerification.renderView(TrackVisualizationView(renderedScene:image).environmentObject(model).frame(width:1060,height:1150),to:output.appendingPathComponent("track-improved.png"))
            try PrototypeVerification.renderView(AnalysisView(renderedScene:image).environmentObject(model).frame(width:1240,height:1200),to:output.appendingPathComponent("analysis-improved.png"))
            try PrototypeVerification.renderView(RunPicker().environmentObject(model).padding(20).frame(width:860),to:output.appendingPathComponent("controls-minimum.png"))
        }
        model.setCompared(run,selected:true)
        let second = RunSession(source:run.source,metadata:run.metadata,calibration:run.calibration,samples:run.samples)
        model.runs.insert(second,at:0); model.persist(second); model.ensureAnalysis(second); try await wait(model)
        model.setCompared(second,selected:true)
        if render {
            let entries = model.comparisonRuns.compactMap { r in model.analyses[r.id].map { ComparisonEntry(run:r,result:$0,colorIndex:model.comparisonColors[r.id] ?? 0) } }
            let image = try sceneImage(ComparisonScene.make(entries:entries))
            try PrototypeVerification.renderView(CompareRunsView(renderedScene:image).environmentObject(model).frame(width:1280,height:1080),to:output.appendingPathComponent("saved-runs-improved.png"))
        }
        model.selectReconstructionMethod(.old); try await wait(model)
        guard let old = model.selectedAnalysis else { throw PodTrackError.invalid("Missing Old analysis") }
        try check(old.algorithmVersion == "0.4.0-heuristic","Old switch selected wrong algorithm")
        try check(old.points == AnalysisPipeline.analyze(run).points,"Old no longer matches the original pipeline")
        try check(model.comparedRunIDs.count == 2 && model.analyses.values.allSatisfy { $0.algorithmVersion == old.algorithmVersion },"Comparison mixed methods or lost selections")
        if render {
            let image = try sceneImage(TrackScene.make(result:old))
            try PrototypeVerification.renderView(TrackVisualizationView(renderedScene:image).environmentObject(model).frame(width:1060,height:1150),to:output.appendingPathComponent("track-old.png"))
        }
        model.selectReconstructionMethod(.improved)
        try check(model.selectedAnalysis?.algorithmVersion == ImprovedReconstruction.version,"Switch did not use the correct cache")
        run.metadata.verticalDrop = 0.87
        model.updateRun(run)
        for _ in 0..<3 { model.selectReconstructionMethod(.old); model.selectReconstructionMethod(.improved) }
        try await wait(model)
        try check(abs((model.selectedAnalysis?.metrics.reconstructedHeightRange ?? 0)-0.87)<1e-8,"Rapid switches used a stale result")
        model.selectReconstructionMethod(.old); try await wait(model)
        try check(abs((model.selectedAnalysis?.metrics.reconstructedHeightRange ?? 0)-0.87)<1e-8,"Editing did not invalidate the other method")
        run.metadata.notes = "Deletion must retain the newest edit"
        model.updateRun(run) // Delete before its asynchronous analysis can finish.
        model.deleteRecording(run)
        try await wait(model)
        try await Task.sleep(nanoseconds:100_000_000)
        try check(model.analyses[run.id] == nil && model.analysisErrors[run.id] == nil && !model.comparedRunIDs.contains(run.id),"Deleted run returned from an in-flight task")
        try check(!model.runs.contains { $0.id == run.id } && model.selectedRunID == second.id,"Deletion did not update selection")
        if render {
            try PrototypeVerification.renderView(RecentlyDeletedView().environmentObject(model),to:output.appendingPathComponent("recently-deleted.png"))
            try PrototypeVerification.renderView(DeletedRecordingNotice().environmentObject(model).padding(20).frame(width:860),to:output.appendingPathComponent("undo.png"))
        }
        let restarted = AppModel(motionSource:VerificationMotionSource(),store:store)
        defer { restarted.shutdown() }
        guard let deleted = restarted.deletedRuns.first(where:{$0.id == run.id}) else { throw PodTrackError.invalid("Deleted recording did not survive restart") }
        try check(deleted.samples == original.samples && deleted.metadata == run.metadata,"Removed recording lost raw data or edits")
        restarted.restoreRecording(deleted); try await wait(restarted)
        try check(restarted.deletedRuns.isEmpty && restarted.analyses[run.id]?.algorithmVersion == ImprovedReconstruction.version,"Restore failed to reconstruct with the default method")
        try check(try store.load().runs.first(where:{$0.id == run.id})?.samples == original.samples,"Restore lost samples")

        // Filesystem failure must leave the visible run, selection and cached result intact.
        let failureStore = RunStore(directory:output.appendingPathComponent("FailureLibrary-\(UUID().uuidString)"))
        try failureStore.save(original)
        let failure = AppModel(motionSource:VerificationMotionSource(),store:failureStore)
        defer { failure.shutdown() }
        guard let failureRun = failure.selectedRun else { throw PodTrackError.invalid("Failure fixture did not load") }
        failure.ensureAnalysis(failureRun); try await wait(failure); failure.setCompared(failureRun,selected:true)
        try Data("Filesystem obstruction".utf8).write(to:failureStore.recentlyDeletedDirectory)
        failure.deleteRecording(failureRun)
        try check(failure.runs.count == 1 && failure.selectedAnalysis != nil && failure.comparedRunIDs.contains(failureRun.id) && failure.errorMessage != nil,"Failed deletion changed the active library")

        // Exercise the real recorder callback, save and post-recording navigation.
        let recordingStore = RunStore(directory:output.appendingPathComponent("RecordingLibrary-\(UUID().uuidString)"))
        let recordingModel = AppModel(motionSource:SimulatedTrackMotionSource(),store:recordingStore)
        defer { recordingModel.shutdown() }
        try check(try recordingModel.preparedMetadata().verticalDrop == nil,"Recorder setup invented a measured height")
        if render {
            try PrototypeVerification.renderView(RecordRunView().environmentObject(recordingModel).frame(width:840,height:740),to:output.appendingPathComponent("record-default-unknown.png"))
        }
        recordingModel.selectReconstructionMethod(.old)
        recordingModel.recordSimulation()
        try check(recordingModel.recording,"Simulation recording did not start")
        let deadline = Date().addingTimeInterval(15)
        while recordingModel.recording && Date()<deadline { try await Task.sleep(nanoseconds:50_000_000) }
        try check(!recordingModel.recording,"Simulation did not stop")
        try await wait(recordingModel)
        try check(recordingModel.area == .analysis && recordingModel.reconstructionMethod == .improved,"Post-recording default/navigation is wrong")
        try check(recordingModel.selectedAnalysis?.algorithmVersion == ImprovedReconstruction.version,"New recording was not analyzed with Improved")
        try check(recordingModel.selectedRun?.samples.count == 341,"Recorder lost samples")
        try check(recordingModel.selectedRun?.metadata.verticalDrop == nil && recordingModel.selectedAnalysis?.isRelative == true,"Unknown recording acquired a height or metric scale")

        // Reopen the actual saved recording, then edit its height with both methods cached.
        let reopened = AppModel(motionSource:VerificationMotionSource(),store:recordingStore)
        defer { reopened.shutdown() }
        guard var editable = reopened.selectedRun else { throw PodTrackError.invalid("New recording did not persist") }
        let rawSamples = editable.samples
        try check(editable.metadata.verticalDrop == nil,"Unknown height did not survive restart")
        reopened.heightIsKnown = true; reopened.dropCentimeters = "72"
        reopened.openRun(editable); try await wait(reopened)
        guard let relative = reopened.selectedAnalysis else { throw PodTrackError.invalid("Reopened recording has no analysis") }
        try check(relative.isRelative && abs(relative.metrics.estimatedPathLength-1)<1e-8,"Setup height leaked into the saved recording")
        try check(CSVExporter.reconstructedTrack(relative).contains("estimated_x_u"),"Unknown export used metric units")
        reopened.setCompared(editable,selected:true)
        if render {
            let image = try sceneImage(TrackScene.make(result:relative))
            try PrototypeVerification.renderView(TrackVisualizationView(renderedScene:image).environmentObject(reopened).frame(width:1060,height:1150),to:output.appendingPathComponent("track-unknown.png"))
            try PrototypeVerification.renderView(AnalysisView(renderedScene:image).environmentObject(reopened).frame(width:1240,height:1200),to:output.appendingPathComponent("analysis-unknown.png"))
            let entries = [ComparisonEntry(run:editable,result:relative,colorIndex:0)]
            let comparisonImage = try sceneImage(ComparisonScene.make(entries:entries))
            try PrototypeVerification.renderView(CompareRunsView(renderedScene:comparisonImage).environmentObject(reopened).frame(width:1280,height:1080),to:output.appendingPathComponent("saved-runs-unknown.png"))
            try PrototypeVerification.renderView(RunEditSheet(run:editable).environmentObject(reopened),to:output.appendingPathComponent("edit-unknown.png"))
        }
        for height in [Double?(0.42),nil] {
            editable.metadata.verticalDrop = height
            reopened.updateRun(editable)
            for method in ReconstructionMethod.allCases {
                reopened.selectReconstructionMethod(method); try await wait(reopened)
                guard let result = reopened.selectedAnalysis else { throw PodTrackError.invalid("Height edit lost the analysis") }
                try check(result.isRelative == (height == nil),"Height edit reused an incompatible cached scale")
                let dimension = height == nil ? result.metrics.estimatedPathLength : result.metrics.reconstructedHeightRange
                try check(abs(dimension-(height ?? 1))<1e-8,"Edited height did not update the reconstruction")
                try check(reopened.comparedRunIDs.contains(editable.id),"Height edit lost comparison selection")
            }
            guard let saved = try recordingStore.load().runs.first else { throw PodTrackError.invalid("Height edit lost the saved recording") }
            try check(saved.metadata.verticalDrop == height && saved.samples == rawSamples && saved.calibration == editable.calibration,"Height edit did not persist or changed raw data")
            if render, height != nil {
                try PrototypeVerification.renderView(TrackHeightControl(run:saved,onChange:{_ in}).padding(20).frame(width:800),to:output.appendingPathComponent("height-edited.png"))
            }
        }
        editable.metadata.knownTrackLength = 3.2
        reopened.updateRun(editable)
        for method in ReconstructionMethod.allCases {
            reopened.selectReconstructionMethod(method); try await wait(reopened)
            try check(reopened.selectedRun?.metadata.verticalDrop == nil && reopened.selectedAnalysis?.resolvedScaleBasis == .trackLength,"Known length invented a measured height")
            try check(abs((reopened.selectedAnalysis?.metrics.estimatedPathLength ?? 0)-3.2)<1e-8,"Known length did not set scale")
        }
        if render {
            try PrototypeVerification.renderView(TrackHeightControl(run:editable,onChange:{_ in}).padding(20).frame(width:800),to:output.appendingPathComponent("height-unknown-known-length.png"))
        }

        let report: [String:Any] = ["defaultMethod":"Improved","oldVersion":old.algorithmVersion,
            "improvedVersion":improved.algorithmVersion,"fixtureSamples":original.samples.count,
            "improvedDistance":improved.metrics.estimatedPathLength,"oldDistance":old.metrics.estimatedPathLength,
            "comparisonUsesOneMethod":true,"rapidSwitchAndEdit":true,"deleteDuringAnalysis":true,
            "restoreAfterRestart":true,"failedDeleteRetainsRun":true,"postRecordingImproved":true,
            "postRecordingUnknown":true,"unknownSurvivesRestart":true,"savedHeightIndependentOfSetup":true,
            "heightEditsBothMethods":true,"unknownWithKnownLength":true,
            "scope":"Isolated fixture libraries; no user recording was deleted"]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:output.appendingPathComponent("verification.json"))
        print("Library acceptance checks passed: defaults, both methods, comparison, exports, editing, cancellation, recoverable deletion, restart restoration, failure handling, recording completion, Unknown persistence and height edits.")
    }

    private static func check(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !value() { throw PodTrackError.invalid(message) }
    }
    private static func wait(_ model: AppModel) async throws {
        let deadline = Date().addingTimeInterval(15)
        while !model.analysingIDs.isEmpty && Date()<deadline { try await Task.sleep(nanoseconds:10_000_000) }
        try check(model.analysingIDs.isEmpty,"Analysis did not finish")
    }
    private static func sceneImage(_ scene: SCNScene) throws -> NSImage {
        guard let device = MTLCreateSystemDefaultDevice() else { throw PodTrackError.invalid("No Metal device for rendering") }
        let renderer = SCNRenderer(device:device,options:nil)
        renderer.scene = scene; renderer.pointOfView = scene.rootNode.childNode(withName:"camera",recursively:false)
        return renderer.snapshot(atTime:0,with:.init(width:1300,height:850),antialiasingMode:.multisampling4X)
    }
}

@MainActor private final class VerificationMotionSource: MotionSource {
    let kind: SourceKind = .airPods
    var status = MotionSourceStatus(detail:"Verification fixture; hardware is not accessed.")
    var onSamples: (([MotionDelivery]) -> Void)?
    var onStatus: ((MotionSourceStatus) -> Void)?
    var onEvent: ((String) -> Void)?
    func start() {}
    func stop() {}
    func refreshStatus() { onStatus?(status) }
}

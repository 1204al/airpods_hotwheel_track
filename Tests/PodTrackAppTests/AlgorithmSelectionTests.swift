import XCTest
import PodTrackCore
@testable import PodTrack

@MainActor final class AlgorithmSelectionTests: XCTestCase {
    func testImprovedDefaultSwitchingAndEditsUseTheSelectedMethod() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let fixture = SimulatedTrack.generate(drop:0.58,includeJump:false)
        var run = RunSession(source:.simulation,metadata:.init(),calibration:fixture.calibration,samples:fixture.samples)
        let store = RunStore(directory:directory); try store.save(run)
        let model = AppModel(motionSource:SimulatedTrackMotionSource(),store:store)
        defer { model.shutdown() }
        run = try XCTUnwrap(model.selectedRun)
        XCTAssertEqual(model.reconstructionMethod,.improved)
        model.ensureAnalysis(run); try await wait(model)
        XCTAssertEqual(model.selectedAnalysis?.algorithmVersion,ImprovedReconstruction.version)
        model.setCompared(run,selected:true)
        model.selectReconstructionMethod(.old); try await wait(model)
        XCTAssertEqual(model.selectedAnalysis?.algorithmVersion,"0.4.0-heuristic")
        XCTAssertEqual(model.selectedAnalysis?.points,try AnalysisPipeline.analyze(run).points)
        XCTAssertTrue(model.comparedRunIDs.contains(run.id))
        model.selectReconstructionMethod(.improved)
        XCTAssertEqual(model.selectedAnalysis?.algorithmVersion,ImprovedReconstruction.version)
        run.metadata.verticalDrop = 0.87
        model.updateRun(run); try await wait(model)
        XCTAssertEqual(try XCTUnwrap(model.selectedAnalysis?.metrics.reconstructedHeightRange),0.87,accuracy:1e-8)
        model.selectReconstructionMethod(.old); try await wait(model)
        XCTAssertEqual(try XCTUnwrap(model.selectedAnalysis?.metrics.reconstructedHeightRange),0.87,accuracy:1e-8)
        XCTAssertEqual(try store.load().runs.first?.samples,run.samples)
    }

    func testDeleteDuringAnalysisCannotResurrectRunAndUndoRebuildsIt() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let fixture = SimulatedTrack.generate(drop:0.58,includeJump:false)
        let run = RunSession(source:.simulation,metadata:.init(),calibration:fixture.calibration,samples:fixture.samples)
        let store = RunStore(directory:directory); try store.save(run)
        let model = AppModel(motionSource:SimulatedTrackMotionSource(),store:store)
        defer { model.shutdown() }
        let saved = try XCTUnwrap(model.selectedRun)
        model.ensureAnalysis(saved)
        model.selectReconstructionMethod(.old)
        model.deleteRecording(saved)
        try await Task.sleep(nanoseconds:150_000_000)
        XCTAssertTrue(model.runs.isEmpty); XCTAssertTrue(model.analyses.isEmpty)
        XCTAssertTrue(model.analysisErrors.isEmpty); XCTAssertTrue(model.analysingIDs.isEmpty)
        XCTAssertNil(model.selectedRunID); XCTAssertTrue(model.comparedRunIDs.isEmpty)
        model.restoreRecording(saved); try await wait(model)
        XCTAssertEqual(model.runs.first?.samples,saved.samples)
        XCTAssertEqual(model.selectedAnalysis?.algorithmVersion,"0.4.0-heuristic")
        model.selectReconstructionMethod(.improved); try await wait(model)
        XCTAssertEqual(model.selectedAnalysis?.algorithmVersion,ImprovedReconstruction.version)
    }

    func testFailedDeletionKeepsSelectionAndAnalysis() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let fixture = SimulatedTrack.generate(drop:0.58,includeJump:false)
        let run = RunSession(source:.simulation,metadata:.init(),calibration:fixture.calibration,samples:fixture.samples)
        let store = RunStore(directory:directory); try store.save(run)
        let model = AppModel(motionSource:SimulatedTrackMotionSource(),store:store)
        defer { model.shutdown() }
        let saved = try XCTUnwrap(model.selectedRun)
        model.ensureAnalysis(saved); try await wait(model); model.setCompared(saved,selected:true)
        try Data("Directory obstruction".utf8).write(to:store.recentlyDeletedDirectory)
        model.deleteRecording(saved)
        XCTAssertEqual(model.selectedRunID,saved.id)
        XCTAssertEqual(model.comparedRunIDs,[saved.id])
        XCTAssertNotNil(model.selectedAnalysis); XCTAssertTrue(model.deletedRuns.isEmpty)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(try store.load().runs.first?.samples,saved.samples)
    }

    private func wait(_ model: AppModel) async throws {
        let deadline = Date().addingTimeInterval(10)
        while !model.analysingIDs.isEmpty && Date()<deadline { try await Task.sleep(nanoseconds:10_000_000) }
        XCTAssertTrue(model.analysingIDs.isEmpty,"Analysis did not finish")
    }
}

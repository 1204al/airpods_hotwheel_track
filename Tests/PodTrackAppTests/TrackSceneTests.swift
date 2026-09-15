import XCTest
import SceneKit
import PodTrackCore
@testable import PodTrack

@MainActor final class TrackSceneTests: XCTestCase {
    func testPickingTargetsRoadAndIgnoresHeightPlanesAndRuler() throws {
        let fixture = SimulatedTrack.generate(includeJump:false)
        let result = try AnalysisPipeline.analyze(.init(source:.simulation,metadata:.init(verticalDrop:0.42),calibration:fixture.calibration,samples:fixture.samples))
        let scene = TrackScene.make(result:result)
        let target = try XCTUnwrap(TrackSampling.point(at:2.45,in:result.points))
        TrackScene.updateCursor(in:scene,points:result.points,time:target.time)
        TrackScene.updateMeasurement(in:scene,points:result.points,selection:.init(aTime:2.45,bTime:4.4))
        // Commit the new nodes without requiring a renderer/window in this unit test.
        SCNTransaction.flush()
        let hits = scene.rootNode.hitTestWithSegment(from:TrackScene.position(target.position+Vector3(0,0,1)),
                                                    to:TrackScene.position(target.position-Vector3(0,0,1)),
                                                    options:[SCNHitTestOption.categoryBitMask.rawValue:TrackScene.trackCategory,SCNHitTestOption.backFaceCulling.rawValue:false])
        XCTAssertFalse(hits.isEmpty)
        XCTAssertTrue(hits.allSatisfy { $0.node.name == "track-deck" || $0.node.name == "track-rails" })
        let hit = try XCTUnwrap(hits.first)
        let snapped = try XCTUnwrap(TrackSampling.nearest(to:TrackScene.dataPosition(hit.worldCoordinates),in:result.points,preferredTime:target.time))
        XCTAssertEqual(snapped.time,target.time,accuracy:0.01)
        XCTAssertEqual((snapped.position-target.position).length,0,accuracy:0.001)
    }

    func testHeightEditRecalculatesSameRulerTimesAndPersists() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PodTrackHeight-"+UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let fixture = SimulatedTrack.generate(profile:.raisedFinish)
        var run = RunSession(source:.simulation,metadata:.init(verticalDrop:0.42),calibration:fixture.calibration,samples:fixture.samples)
        let model = AppModel(motionSource:SimulatedTrackMotionSource(),store:RunStore(directory:directory))
        defer { model.shutdown() }
        model.runs = [run]; model.selectedRunID = run.id
        model.analyses[run.id] = try AnalysisPipeline.analyze(run)
        model.rulerEnabled = true; model.rulerSelection = .init(aTime:1.6,bTime:5.2)
        let original = model.selectedAnalysis!
        run.metadata.verticalDrop = 0.7
        model.updateRun(run)
        let deadline = Date().addingTimeInterval(4)
        while model.selectedAnalysis == nil && Date()<deadline { try await Task.sleep(nanoseconds:10_000_000) }
        let updated = try XCTUnwrap(model.selectedAnalysis)
        XCTAssertEqual(updated.metrics.reconstructedHeightRange,0.7,accuracy:1e-8)
        XCTAssertEqual(model.rulerSelection.aTime,1.6)
        XCTAssertEqual(model.rulerSelection.bTime,5.2)
        XCTAssertTrue(model.rulerEnabled)
        let before = TrackMeasurement(a:TrackSampling.point(at:1.6,in:original.points)!,b:TrackSampling.point(at:5.2,in:original.points)!)
        let after = TrackMeasurement(a:TrackSampling.point(at:1.6,in:updated.points)!,b:TrackSampling.point(at:5.2,in:updated.points)!)
        XCTAssertEqual(after.alongTrack,before.alongTrack*0.7/0.42,accuracy:1e-8)
        XCTAssertEqual(try model.store.load().runs.first?.metadata.verticalDrop,0.7)
        XCTAssertEqual(try model.store.load().runs.first?.samples,fixture.samples)
        model.selectedRunID = UUID()
        XCTAssertNil(model.rulerSelection.aTime)
        XCTAssertNil(model.rulerSelection.bTime)
    }
}

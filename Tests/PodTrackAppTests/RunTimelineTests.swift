import XCTest
import SceneKit
import PodTrackCore
@testable import PodTrack

@MainActor final class RunTimelineTests: XCTestCase {
    /// Real detected candidates, so the timeline is exercised against the same events the
    /// app draws rather than hand-written segment values.
    private func fixture() throws -> (run: RunSession, result: AnalysisResult) {
        let input = SimulatedTrack.generate(drop:0.58,includeJump:true,profile:.circuit)
        let run = RunSession(source:.simulation,metadata:.init(verticalDrop:0.58),calibration:input.calibration,samples:input.samples)
        return (run,try AnalysisPipeline.analyze(run))
    }

    func testEveryCandidateBoundaryBecomesASnapPointInsideTheRecording() throws {
        let (run,result) = try fixture()
        let markers = RunTimeline.markers(segments:result.segments,duration:run.duration)
        XCTAssertEqual(markers.map(\.time),markers.map(\.time).sorted())
        XCTAssertTrue(markers.allSatisfy { $0.time >= 0 && $0.time <= run.duration })
        for segment in result.segments where segment.endTime <= run.duration {
            XCTAssertTrue(markers.contains { $0.kind == segment.kind && $0.isStart && $0.time == segment.startTime },segment.kind.rawValue)
            XCTAssertTrue(markers.contains { $0.kind == segment.kind && !$0.isStart && $0.time == segment.endTime },segment.kind.rawValue)
        }
        // Boundaries beyond the recording are not offered, so a handle cannot leave the run.
        XCTAssertTrue(RunTimeline.markers(segments:result.segments,duration:1).allSatisfy { $0.time <= 1 })
    }

    func testSnapPointsCollapseNearDuplicatesAndIncludeBothEnds() throws {
        let (run,result) = try fixture()
        let times = RunTimeline.snapTimes(RunTimeline.markers(segments:result.segments,duration:run.duration),duration:run.duration)
        XCTAssertEqual(times.first,0)
        XCTAssertEqual(times.last,run.duration)
        XCTAssertEqual(times,times.sorted())
        // Two candidates that meet produce one snap point, so a handle does not stutter.
        for (a,b) in zip(times,times.dropFirst()) { XCTAssertGreaterThan(b-a,0.004) }
        XCTAssertLessThan(times.count,result.segments.count*2+2)
    }

    func testDraggingSnapsOnlyWithinToleranceAndOtherwiseKeepsTheExactTime() throws {
        let (run,result) = try fixture()
        let times = RunTimeline.snapTimes(RunTimeline.markers(segments:result.segments,duration:run.duration),duration:run.duration)
        // A candidate with room around it, so the nearest snap point is unambiguous.
        let index = try XCTUnwrap((1..<times.count-1).first { times[$0]-times[$0-1] > 0.2 && times[$0+1]-times[$0] > 0.2 })
        let target = times[index]
        XCTAssertEqual(RunTimeline.snapped(target-0.05,to:times,tolerance:0.08),target)
        XCTAssertEqual(RunTimeline.snapped(target+0.05,to:times,tolerance:0.08),target)
        // Outside the tolerance the dragged time is kept exactly, so a free position is possible.
        XCTAssertEqual(RunTimeline.snapped(target-0.05,to:times,tolerance:0.001),target-0.05)
        XCTAssertEqual(RunTimeline.snapped(-2,to:times,tolerance:0.05),-2)
    }

    func testStepButtonsMoveOneCandidateAtATimeAndStopAtTheEnds() throws {
        let (run,result) = try fixture()
        let times = RunTimeline.snapTimes(RunTimeline.markers(segments:result.segments,duration:run.duration),duration:run.duration)
        XCTAssertGreaterThan(times.count,3)
        XCTAssertEqual(RunTimeline.neighbour(of:times[2],in:times,forward:true),times[3])
        XCTAssertEqual(RunTimeline.neighbour(of:times[2],in:times,forward:false),times[1])
        XCTAssertNil(RunTimeline.neighbour(of:try XCTUnwrap(times.last),in:times,forward:true))
        XCTAssertNil(RunTimeline.neighbour(of:0,in:times,forward:false))
    }

    func testSelectingAnotherRunClearsTheWindowSoItCannotLeakBetweenRecordings() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let store = RunStore(directory:directory)
        let input = SimulatedTrack.generate(drop:0.58,includeJump:false,profile:.raisedFinish)
        let runs = (0..<2).map { index in
            RunSession(createdAt:Date(timeIntervalSince1970:1_789_401_600-Double(index)*60),source:.simulation,
                       metadata:.init(carName:"Car \(index)",verticalDrop:0.58),calibration:input.calibration,samples:input.samples)
        }
        try runs.forEach { try store.save($0) }
        let model = AppModel(motionSource:SimulatedTrackMotionSource(),store:store)
        defer { model.shutdown() }
        model.timeWindow = .init(start:1,end:3)
        model.cursorTime = 2
        model.selectedRunID = model.runs.last?.id
        XCTAssertNil(model.timeWindow)
        XCTAssertEqual(model.cursorTime,0)
    }

    func testWindowedPointsFollowTheSelectedRangeAndFallBackToTheWholeRun() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let input = SimulatedTrack.generate(drop:0.58,includeJump:false,profile:.raisedFinish)
        let run = RunSession(source:.simulation,metadata:.init(verticalDrop:0.58),calibration:input.calibration,samples:input.samples)
        let result = try AnalysisPipeline.analyze(run)
        let model = AppModel(motionSource:SimulatedTrackMotionSource(),store:RunStore(directory:directory))
        defer { model.shutdown() }
        XCTAssertEqual(model.windowedPoints(result).count,result.points.count)
        model.timeWindow = .init(start:2,end:4)
        let windowed = model.windowedPoints(result)
        XCTAssertLessThan(windowed.count,result.points.count)
        XCTAssertTrue(windowed.allSatisfy { $0.time >= 2 && $0.time <= 4 })
    }

    func testTheSceneDrawsOnlyTheWindowWhileGroundAndHeightStayWholeRun() throws {
        let input = SimulatedTrack.generate(drop:0.58,includeJump:false,profile:.raisedFinish)
        let run = RunSession(source:.simulation,metadata:.init(verticalDrop:0.58),calibration:input.calibration,samples:input.samples)
        let result = try AnalysisPipeline.analyze(run)
        var options = TrackSceneOptions()
        let whole = TrackScene.make(result:result,options:options)
        options.window = .init(start:2,end:4)
        let windowed = TrackScene.make(result:result,options:options)
        func deckVertexCount(_ scene: SCNScene) -> Int {
            scene.rootNode.childNode(withName:"track-deck",recursively:false)?.geometry?.sources(for:.vertex).first?.vectorCount ?? 0
        }
        XCTAssertGreaterThan(deckVertexCount(whole),deckVertexCount(windowed))
        XCTAssertGreaterThan(deckVertexCount(windowed),0)
        // The height planes are the construction's, so they must not follow the window.
        func planeBounds(_ scene: SCNScene) -> SCNVector3? {
            scene.rootNode.childNode(withName:"height-planes",recursively:false).map { $0.boundingBox.max }
        }
        XCTAssertEqual(planeBounds(whole)?.y ?? 0,planeBounds(windowed)?.y ?? -1,accuracy:1e-6)
    }
}

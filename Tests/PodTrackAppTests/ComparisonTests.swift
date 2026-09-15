import XCTest
import SceneKit
import PodTrackCore
@testable import PodTrack

@MainActor final class ComparisonTests: XCTestCase {
    func testUnknownDefaultDoesNotChangeSaved42CentimetreRun() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let run = fixtureRun(height:0.42)
        let store = RunStore(directory:directory)
        try store.save(run)
        let model = AppModel(motionSource:SimulatedTrackMotionSource(),store:store)
        defer { model.shutdown() }
        XCTAssertEqual(model.dropCentimeters,"58")
        XCTAssertFalse(model.heightIsKnown)
        XCTAssertNil(model.setup.verticalDrop)
        XCTAssertNil(try model.preparedMetadata().verticalDrop)
        XCTAssertEqual(model.runs.first?.metadata.verticalDrop,0.42)
        XCTAssertEqual(model.runs.first?.samples,run.samples)
        let reloaded = try XCTUnwrap(model.runs.first)
        XCTAssertEqual(try AnalysisPipeline.analyze(reloaded).points,try AnalysisPipeline.analyze(run).points)
    }

    func testSavedRunsCanBeSelectedTogetherWithFourRunLimit() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let store = RunStore(directory:directory)
        for i in 0..<5 {
            var run = fixtureRun(height:0.58)
            run.metadata.carName = "Car \(i)"; run.createdAt = Date(timeIntervalSince1970:Double(i))
            try store.save(run)
        }
        let model = AppModel(motionSource:SimulatedTrackMotionSource(),store:store)
        defer { model.shutdown() }
        model.prepareComparison()
        await waitForLibrary(model)
        XCTAssertTrue(model.comparisonRuns.isEmpty,"Opening the library must not silently choose recordings.")
        for run in model.runs { model.setCompared(run,selected:true) }
        XCTAssertEqual(model.comparisonRuns.count,4)
        let fifth = model.runs[4]
        XCTAssertFalse(model.comparedRunIDs.contains(fifth.id))
        let keptColor = model.comparisonColors[model.runs[1].id]
        model.setCompared(model.runs[0],selected:false)
        model.setCompared(fifth,selected:true)
        XCTAssertEqual(model.comparisonColors[model.runs[1].id],keptColor,"A remaining track must keep its colour when another is removed.")
        XCTAssertEqual(Set(model.comparisonColors.values).count,4)
        let selection = model.comparedRunIDs
        model.prepareComparison()
        XCTAssertEqual(model.comparedRunIDs,selection)
        XCTAssertTrue(model.comparedRunIDs.contains(fifth.id))
        for run in model.runs { model.setCompared(run,selected:false) }
        model.prepareComparison()
        XCTAssertTrue(model.comparisonRuns.isEmpty)
    }

    func testLatestTwoSkipsRawAndFailedRecordings() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let store = RunStore(directory:directory)
        var readyA = fixtureRun(height:0.58), readyB = fixtureRun(height:0.58)
        readyA.createdAt = Date(timeIntervalSince1970:1); readyB.createdAt = Date(timeIntervalSince1970:2)
        var raw = fixtureRun(height:0.58)
        raw.createdAt = Date(timeIntervalSince1970:3); raw.calibration = nil
        var still = fixtureRun(height:0.58)
        still.createdAt = Date(timeIntervalSince1970:4)
        let sample = still.samples[0]
        still.samples = (0..<100).map { i in var copy = sample; copy.timestamp = Double(i)*0.02; return copy }
        for run in [readyA,readyB,raw,still] { try store.save(run) }
        let model = AppModel(motionSource:SimulatedTrackMotionSource(),store:store)
        defer { model.shutdown() }
        model.prepareComparison(); await waitForLibrary(model)
        XCTAssertEqual(model.readyComparisonRuns.count,2)
        XCTAssertNotNil(model.analysisErrors[raw.id]); XCTAssertNotNil(model.analysisErrors[still.id])
        model.setCompared(raw,selected:true); model.setCompared(still,selected:true)
        XCTAssertTrue(model.comparedRunIDs.isEmpty)
        model.compareLatestRuns()
        XCTAssertEqual(model.comparedRunIDs,[readyA.id,readyB.id])
        XCTAssertEqual(model.runs.count,4,"Unavailable trajectories must remain in the saved library.")
    }

    func testComparisonEntryPointIncludesCurrentRunAndHonoursFullSelection() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let model = AppModel(motionSource:SimulatedTrackMotionSource(),store:RunStore(directory:directory))
        defer { model.shutdown() }
        model.runs = (0..<5).map { _ in fixtureRun(height:0.58) }
        model.prepareComparison(); await waitForLibrary(model)
        let current = model.runs[2]
        model.openComparison(including:current)
        XCTAssertEqual(model.area,.compare)
        XCTAssertEqual(model.comparedRunIDs,[current.id])
        model.runs.prefix(4).forEach { model.setCompared($0,selected:true) }
        let selection = model.comparedRunIDs
        model.openComparison(including:model.runs[4])
        XCTAssertEqual(model.comparedRunIDs,selection)
        XCTAssertNotNil(model.comparisonNotice)
        model.clearComparison()
        XCTAssertTrue(model.comparedRunIDs.isEmpty); XCTAssertTrue(model.comparisonColors.isEmpty)
        model.openRun(current)
        XCTAssertEqual(model.area,.track); XCTAssertEqual(model.selectedRunID,current.id)
    }

    func testFailedReconstructionAfterEditLeavesRawRunButRemovesInvisibleSelection() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let store = RunStore(directory:directory)
        var run = fixtureRun(height:0.58); try store.save(run)
        let model = AppModel(motionSource:SimulatedTrackMotionSource(),store:store)
        defer { model.shutdown() }
        model.prepareComparison(); await waitForLibrary(model)
        model.setCompared(run,selected:true)
        run.calibration = nil
        model.updateRun(run); await waitForLibrary(model)
        XCTAssertTrue(model.comparedRunIDs.isEmpty); XCTAssertTrue(model.comparisonColors.isEmpty)
        XCTAssertNotNil(model.comparisonNotice)
        XCTAssertEqual(try store.load().runs.first?.samples,run.samples)
    }

    func testRecordingReviewFlagsAClippedFinishWithoutClaimingAccuracy() throws {
        let complete = fixtureRun(height:0.58)
        let completeResult = try AnalysisPipeline.analyze(complete)
        XCTAssertNil(RecordingReview(run:complete,result:completeResult).endpointAdvice)
        var clipped = complete
        let lastActiveTime = try XCTUnwrap(completeResult.signals.last(where:{ !$0.isQuiet })?.time)
        clipped.samples = complete.samples.filter { $0.timestamp-complete.samples[0].timestamp <= lastActiveTime }
        let clippedResult = try AnalysisPipeline.analyze(clipped)
        XCTAssertEqual(RecordingReview(run:clipped,result:clippedResult).endpointAdvice?.title,"No still finish detected")
        clipped.metadata.settings.startsAndEndsAtRest = false
        XCTAssertNil(RecordingReview(run:clipped,result:clippedResult).endpointAdvice)
    }

    private func waitForLibrary(_ model: AppModel) async {
        for _ in 0..<300 {
            if model.analysingIDs.isEmpty { return }
            try? await Task.sleep(nanoseconds:10_000_000)
        }
        XCTFail("Timed out waiting for the saved-run library to reconstruct.")
    }

    func testComparisonPreservesEachScaleAndNormalizesLegacyGround() throws {
        let newRun = fixtureRun(height:0.58)
        var oldRun = fixtureRun(height:0.42)
        oldRun.metadata.heightConstraint = .endpointDrop
        for (index,run) in [newRun,oldRun].enumerated() {
            let result = try AnalysisPipeline.analyze(run)
            let entry = ComparisonEntry(run:run,result:result,colorIndex:index)
            XCTAssertEqual(entry.points.map { $0.position.z }.min()!,0,accuracy:1e-9)
            XCTAssertEqual(entry.points.first!.position.x,0,accuracy:1e-9)
            XCTAssertEqual(entry.points.first!.position.y,0,accuracy:1e-9)
            XCTAssertEqual(entry.height,run.metadata.verticalDrop)
            for (display,original) in zip(entry.points,result.points) {
                XCTAssertEqual(display.speed,original.speed)
                XCTAssertEqual(display.distance,original.distance)
                XCTAssertEqual(display.position.z,original.position.z-result.groundZ,accuracy:1e-9)
            }
        }
    }

    func testSharedReplayAlignsReleaseAndSceneContainsOnlySelectedRuns() throws {
        let first = fixtureRun(height:0.58), second = fixtureRun(height:0.58)
        let firstResult = try AnalysisPipeline.analyze(first)
        var delayed = try AnalysisPipeline.analyze(second)
        // A second recording with an additional second of pre-release timeline.
        delayed.points = delayed.points.map { p in var copy = p; copy.time += 1; return copy }
        for i in delayed.segments.indices { delayed.segments[i].startTime += 1; delayed.segments[i].endTime += 1 }
        let entries = [ComparisonEntry(run:first,result:firstResult,colorIndex:0),ComparisonEntry(run:second,result:delayed,colorIndex:1)]
        XCTAssertEqual(entries[1].releaseTime-entries[0].releaseTime,1,accuracy:1e-8)
        let scene = ComparisonScene.make(entries:entries)
        ComparisonScene.updateCursors(in:scene,entries:entries,elapsed:2)
        for entry in entries {
            let point = try XCTUnwrap(entry.point(at:2))
            XCTAssertEqual(point.time,entry.releaseTime+2,accuracy:1e-8)
            let car = try XCTUnwrap(scene.rootNode.childNode(withName:"cursor-\(entry.id)",recursively:true) as? ReplayCarNode)
            XCTAssertEqual(car.wheels.count,4)
            XCTAssertEqual((TrackScene.dataPosition(car.position)-point.position).length,0.0006,accuracy:1e-5)
            XCTAssertNotNil(scene.rootNode.childNode(withName:"trajectory-\(entry.id)",recursively:false))
            XCTAssertEqual(entry.point(at:100)?.position,entry.points.last?.position)
        }
        XCTAssertEqual((entries[0].point(at:2)!.position-entries[1].point(at:2)!.position).length,0,accuracy:1e-8)
        ComparisonScene.updateCursors(in:scene,entries:entries,elapsed:100)
        for entry in entries {
            let car = try XCTUnwrap(scene.rootNode.childNode(withName:"cursor-\(entry.id)",recursively:true) as? ReplayCarNode)
            XCTAssertEqual((TrackScene.dataPosition(car.position)-entry.points.last!.position).length,0.0006,accuracy:1e-5)
        }
        let one = ComparisonScene.make(entries:[entries[1]],showPlanes:false)
        XCTAssertNil(one.rootNode.childNode(withName:"trajectory-\(first.id)",recursively:false))
        XCTAssertTrue(one.rootNode.childNode(withName:"height-planes",recursively:false)!.isHidden)
        let four = (0..<4).map { ComparisonEntry(run:fixtureRun(height:0.58),result:firstResult,colorIndex:$0) }
        let fourScene = ComparisonScene.make(entries:four)
        XCTAssertEqual(fourScene.rootNode.childNodes.filter { $0.name?.hasPrefix("trajectory-") == true }.count,4)
    }

    private func fixtureRun(height: Double) -> RunSession {
        let input = SimulatedTrack.generate(drop:height,includeJump:false)
        return .init(source:.simulation,metadata:.init(verticalDrop:height),calibration:input.calibration,samples:input.samples)
    }
}

import XCTest
import SceneKit
import PodTrackCore
@testable import PodTrack

@MainActor final class UnknownHeightAppTests: XCTestCase {
    private func fixtureRun(height: Double? = nil) -> RunSession {
        let input = SimulatedTrack.generate(includeJump:false,profile:.raisedFinish)
        return .init(source:.simulation,metadata:.init(verticalDrop:height),calibration:input.calibration,samples:input.samples)
    }

    func testRecordingUnknownIgnoresInactiveHeightTextAndCanReturnToMeasured() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let model = AppModel(motionSource:SimulatedTrackMotionSource(),store:RunStore(directory:directory))
        defer { model.shutdown() }
        XCTAssertFalse(model.heightIsKnown)
        XCTAssertNil(model.setup.verticalDrop)
        model.dropCentimeters = "invalid"
        XCTAssertNil(try model.preparedMetadata().verticalDrop)
        XCTAssertEqual(try model.preparedMetadata().scaleBasis,.relative)
        model.knownLengthCentimeters = "320"
        XCTAssertEqual(try model.preparedMetadata().scaleBasis,.trackLength)
        model.heightIsKnown = true
        XCTAssertThrowsError(try model.preparedMetadata())
        model.dropCentimeters = "42,5"
        XCTAssertEqual(try XCTUnwrap(model.preparedMetadata().verticalDrop),0.425,accuracy:1e-9)
    }

    func testRelativeSceneAndRulerNeverLabelDistancesAsCentimetres() throws {
        let recorded = fixtureRun(), result = try AnalysisPipeline.analyze(recorded)
        let scene = TrackScene.make(result:result)
        TrackScene.updateMeasurement(in:scene,points:result.points,selection:.init(aTime:1.3,bTime:5),isRelative:true)
        var labels: [String] = []
        scene.rootNode.enumerateChildNodes { node,_ in
            if let text = node.geometry as? SCNText, let value = text.string as? String { labels.append(value) }
        }
        XCTAssertTrue(labels.contains("GROUND · 0 u"))
        XCTAssertTrue(labels.contains { $0.hasPrefix("Δz = ") && $0.hasSuffix(" u") })
        XCTAssertFalse(labels.contains { $0.contains("cm") || $0.contains("H =") })
        XCTAssertNotNil(scene.rootNode.childNode(withName:"track-deck",recursively:false))
    }

    func testSavedUnknownRunCanAcquireHeightAndReturnToRelativeWithoutLosingSamples() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let store = RunStore(directory:directory), recorded = fixtureRun()
        try store.save(recorded)
        let model = AppModel(motionSource:SimulatedTrackMotionSource(),store:store)
        defer { model.shutdown() }
        // Recording setup and saved-run editing are independent.
        model.heightIsKnown = true
        model.dropCentimeters = "42"
        var editable = try XCTUnwrap(model.runs.first)
        XCTAssertNil(editable.metadata.verticalDrop)
        for height in [Double?(0.58),nil] {
            model.rulerSelection = .init(aTime:1.6,bTime:4.3)
            editable.metadata.verticalDrop = height
            model.updateRun(editable)
            XCTAssertEqual(model.rulerSelection.aTime,1.6)
            XCTAssertEqual(model.rulerSelection.bTime,4.3)
            for method in ReconstructionMethod.allCases {
                model.selectReconstructionMethod(method)
                let deadline = Date().addingTimeInterval(4)
                while model.selectedAnalysis == nil && Date()<deadline { try await Task.sleep(nanoseconds:10_000_000) }
                let result = try XCTUnwrap(model.selectedAnalysis)
                XCTAssertEqual(result.isRelative,height == nil)
                if let height { XCTAssertEqual(result.metrics.reconstructedHeightRange,height,accuracy:1e-8) }
                else { XCTAssertEqual(result.metrics.estimatedPathLength,1,accuracy:1e-8) }
            }
            let saved = try XCTUnwrap(store.load().runs.first)
            XCTAssertEqual(saved.id,recorded.id)
            XCTAssertEqual(saved.metadata.verticalDrop,height)
            XCTAssertEqual(saved.samples,recorded.samples)
            XCTAssertEqual(saved.calibration,editable.calibration)
            XCTAssertTrue(model.heightIsKnown)
        }
    }

    func testShapeComparisonNormalizesKnownAndUnknownRunsWithoutChangingSavedAnalysis() throws {
        let measuredRun = fixtureRun(height:0.58), relativeRun = fixtureRun()
        let measured = try AnalysisPipeline.analyze(measuredRun), relative = try AnalysisPipeline.analyze(relativeRun)
        let a = ComparisonEntry(run:measuredRun,result:measured,colorIndex:0,normalizeToUnitLength:true)
        let b = ComparisonEntry(run:relativeRun,result:relative,colorIndex:1,normalizeToUnitLength:true)
        XCTAssertTrue(a.isRelative); XCTAssertTrue(b.isRelative)
        XCTAssertEqual(a.points.last!.distance,1,accuracy:1e-9)
        XCTAssertEqual(b.points.last!.distance,1,accuracy:1e-9)
        for (p,q) in zip(a.points,b.points) {
            XCTAssertEqual((p.position-q.position).length,0,accuracy:1e-8)
            XCTAssertEqual(p.speed,q.speed,accuracy:1e-8)
        }
        XCTAssertEqual(measured.resolvedScaleBasis,.height)
        XCTAssertEqual(measured.metrics.reconstructedHeightRange,0.58,accuracy:1e-9)
        XCTAssertEqual(measuredRun.metadata.verticalDrop,0.58)
    }
}

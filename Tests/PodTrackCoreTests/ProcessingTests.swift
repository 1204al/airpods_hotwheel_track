import XCTest
@testable import PodTrackCore

final class ProcessingTests: XCTestCase {
    func testSmoothingPreservesConstantAndReducesImpulse() {
        XCTAssertEqual(SignalProcessor.smooth([3,3,3,3],radius:2),[3,3,3,3])
        XCTAssertEqual(SignalProcessor.smooth([0,0,9,0,0],radius:1)[2],3)
        XCTAssertEqual(SignalProcessor.smooth([3,3,3],times:[0,0.01,1],window:0.1),[3,3,3])
    }
    func testHeadingUnwrapAvoidsFalseTurnAtPi() {
        let unwrapped = SignalProcessor.unwrap([3.1,-3.1,-3.0])
        XCTAssertLessThan(unwrapped[1]-unwrapped[0],0.1)
        XCTAssertGreaterThan(unwrapped[2],unwrapped[1])
    }
    func testCurvatureOnConstantRadiusTurn() {
        XCTAssertEqual(SignalProcessor.curvature(turnRate:1,speed:2),0.5,accuracy:1e-9)
        XCTAssertEqual(SignalProcessor.curvature(turnRate:1,speed:0),0)
    }
    func testSyntheticReconstructionRecoversDropTurnsAndReasonableScale() throws {
        let fixture = SimulatedTrack.generate(drop:0.42)
        let result = try analyze(fixture)
        XCTAssertEqual(result.groundZ,0,accuracy:1e-8)
        XCTAssertEqual(result.points.map { $0.position.z }.max()!,0.42,accuracy:1e-8)
        XCTAssertTrue(result.points.allSatisfy { $0.position.isFinite && $0.speed.isFinite && $0.speed>=0 })
        let trueLength = zip(fixture.referencePositions,fixture.referencePositions.dropFirst()).map { ($1-$0).length }.reduce(0,+)
        XCTAssertEqual(result.metrics.estimatedPathLength,trueLength,accuracy:trueLength*0.40)
        XCTAssertEqual(result.metrics.estimatedMaximumSpeed,fixture.referenceSpeeds.max()!,accuracy:fixture.referenceSpeeds.max()!*0.60)
        XCTAssertGreaterThan(result.points.last!.position.y,0.4)
        XCTAssertTrue(result.segments.contains { $0.kind == .downhill })
        XCTAssertTrue(result.segments.contains { $0.kind == .uphill })
        XCTAssertTrue(result.segments.contains { $0.kind == .leftTurn })
        XCTAssertTrue(result.segments.contains { $0.kind == .rightTurn })
        XCTAssertTrue(result.segments.contains { $0.kind == .airborne })
        XCTAssertTrue(result.segments.contains { $0.kind == .landing })
        XCTAssertTrue(result.segments.contains { $0.kind == .bump && $0.startTime>3.6 && $0.startTime<3.9 })
        XCTAssertLessThan(result.metrics.candidateAirtime,0.3)
    }
    func testStationaryRunCannotProduceGeometryFromEnteredHeight() {
        let samples = (0..<100).map { MotionSample(timestamp:Double($0)/50,sensorLocation:.left) }
        let run = RunSession(source:.simulation,metadata:.init(verticalDrop:0.42),calibration:SimulatedTrack.generate().calibration,samples:samples)
        XCTAssertThrowsError(try AnalysisPipeline.analyze(run))
    }
    func testKnownLengthFitsBothConstraints() throws {
        let fixture = SimulatedTrack.generate(includeJump:false)
        var metadata = RunMetadata(verticalDrop:0.42); metadata.knownTrackLength = 3.4
        let result = try AnalysisPipeline.analyze(.init(source:.simulation,metadata:metadata,calibration:fixture.calibration,samples:fixture.samples))
        XCTAssertEqual(result.metrics.reconstructedHeightRange,0.42,accuracy:1e-8)
        XCTAssertEqual(result.points.last!.distance,3.4,accuracy:1e-6)
    }
    func testPipelineRejectsMixedBudsAndMissingCalibration() {
        var fixture = SimulatedTrack.generate()
        fixture.samples[100].sensorLocation = .right
        XCTAssertThrowsError(try analyze(fixture))
        XCTAssertThrowsError(try AnalysisPipeline.analyze(.init(source:.simulation,metadata:.init(verticalDrop:0.42),calibration:nil,samples:fixture.samples)))
    }
    func testQuietMiddleDoesNotStopEstimatedTravel() throws {
        let result = try analyze(SimulatedTrack.generate(includeJump:false))
        let middleFlat = result.points.filter { $0.time>2.15 && $0.time<2.35 }
        XCTAssertTrue(middleFlat.allSatisfy { $0.speed>0.1 })
    }
    func testExportsRemainExplicitlyEstimatedAndJSONRoundTrips() throws {
        let fixture = SimulatedTrack.generate()
        let run = RunSession(source:.simulation,metadata:.init(verticalDrop:0.42),calibration:fixture.calibration,samples:fixture.samples)
        let result = try AnalysisPipeline.analyze(run)
        let json = try CSVExporter.processedJSON(run:run,result:result)
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with:Data(json.utf8)))
        XCTAssertTrue(CSVExporter.reconstructedTrack(result).contains("estimated_speed_m_s"))
    }
    private func analyze(_ fixture: SimulationFixture) throws -> AnalysisResult {
        try AnalysisPipeline.analyze(.init(source:.simulation,metadata:.init(verticalDrop:0.42),calibration:fixture.calibration,samples:fixture.samples))
    }
}

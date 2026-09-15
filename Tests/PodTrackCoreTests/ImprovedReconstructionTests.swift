import XCTest
@testable import PodTrackCore

final class ImprovedReconstructionTests: XCTestCase {
    private func verticalCircuits(turns: Int = 4, radius: Double = 0.29) -> RunSession {
        // Independent analytic circle: position = (r sin θ, 0, r (1-cos θ)).
        // Constant known speed; no production simulator or integrator generates this fixture.
        let period = 1.2, omega = 2*Double.pi/period
        let samples = (0...turns*60).map { i -> MotionSample in
            let time = Double(i)*0.02, theta = omega*time
            let q = Quaternion(axis:.unitY,angle:-theta)
            let acceleration = Vector3(-radius*omega*omega*sin(theta),0,radius*omega*omega*cos(theta))
            return .init(timestamp:time,attitude:q,rotationRate:.init(0,-omega,0),
                userAcceleration:q.inverse.rotate(-acceleration)/standardGravity,
                gravity:q.inverse.rotate(.init(0,0,-1)),sensorLocation:.left)
        }
        var settings = ReconstructionSettings()
        settings.startsAndEndsAtRest = false; settings.gravityModelWeight = 0; settings.smoothingSeconds = 0
        return .init(source:.simulation,metadata:.init(verticalDrop:2*radius,settings:settings),
            calibration:.init(forwardDevice:.unitX,upDevice:.unitZ,sensorLocation:.left,source:.simulation),samples:samples)
    }

    func testVectorSmoothingKeepsVerticalCircleInItsPlane() throws {
        var run = verticalCircuits(); run.metadata.settings.smoothingSeconds = 0.10
        let improved = try ImprovedReconstruction.process(run.samples,calibration:run.calibration!,settings:run.metadata.settings)
        let baseline = try SignalProcessor.process(run.samples,calibration:run.calibration!,settings:run.metadata.settings)
        XCTAssertLessThan(improved.samples.map { abs($0.direction.y) }.max()!,1e-8)
        XCTAssertGreaterThan(baseline.samples.map { abs($0.direction.y) }.max()!,0.05)
        XCTAssertGreaterThan(improved.samples.map { abs($0.direction.z) }.max()!,0.99)
        XCTAssertTrue(improved.samples.allSatisfy { abs($0.direction.length-1)<1e-10 })
    }

    func testAnalyticCircuitsRecoverPhysicalLengthAndSpeed() throws {
        let run = verticalCircuits(), result = try ImprovedReconstruction.analyze(run)
        let expectedSpeed = 2*Double.pi*0.29/1.2
        XCTAssertEqual(result.metrics.estimatedPathLength,4*2*Double.pi*0.29,accuracy:0.04)
        XCTAssertEqual(result.metrics.estimatedMaximumSpeed,expectedSpeed,accuracy:0.06)
        XCTAssertEqual(result.metrics.reconstructedHeightRange,0.58,accuracy:1e-10)
        XCTAssertLessThan(result.points.map { abs($0.position.y) }.max()!,1e-8)
        let diagnostics = try XCTUnwrap(result.reconstructionDiagnostics)
        XCTAssertEqual(diagnostics.repeatCircuits.count,3)
        XCTAssertTrue(diagnostics.repeatConstraintsApplied)
        XCTAssertTrue(diagnostics.collapsedMotion.isEmpty)
        XCTAssertTrue(diagnostics.speedFitConverged)
        XCTAssertTrue(result.points.allSatisfy { $0.speed.isFinite && $0.speed>=0 })
    }

    func testSameInversionsOnDifferentRoutesAreNotMatched() throws {
        let run = verticalCircuits()
        var signals = try ImprovedReconstruction.process(run.samples,calibration:run.calibration!,settings:run.metadata.settings).samples
        for i in signals.indices {
            let section = max(0,min(2,Int(floor((signals[i].time-0.6)/1.2))))
            signals[i].forwardDirection = Quaternion(axis:.unitZ,angle:Double(section)*Double.pi/3).rotate(signals[i].direction)
        }
        XCTAssertTrue(ImprovedReconstruction.detectRepeatedCircuits(samples:run.samples,signals:signals,calibration:run.calibration!).isEmpty)
    }

    func testSinglePassDoesNotGetForcedClosedAndConstraintToggleIsRespected() throws {
        let single = try ImprovedReconstruction.analyze(verticalCircuits(turns:1))
        XCTAssertTrue(try XCTUnwrap(single.reconstructionDiagnostics).repeatCircuits.isEmpty)
        XCTAssertFalse(single.reconstructionDiagnostics!.repeatConstraintsApplied)
        let disabled = try ImprovedReconstruction.analyze(verticalCircuits(),useRepeatedCircuits:false)
        XCTAssertEqual(disabled.reconstructionDiagnostics?.repeatCircuits.count,3)
        XCTAssertFalse(disabled.reconstructionDiagnostics!.repeatConstraintsApplied)
    }

    func testStableBiasedRecordingRemainsStationaryAndRawDataIsUntouched() throws {
        var run = verticalCircuits()
        run.metadata.settings.startsAndEndsAtRest = true
        run.samples = (0...100).map { .init(timestamp:Double($0)*0.02,userAcceleration:.init(0.10,0,0),sensorLocation:.left) }
        let original = run
        XCTAssertThrowsError(try ImprovedReconstruction.analyze(run))
        XCTAssertEqual(run,original)
    }

    func testFinalRestAloneRemovesConstantTangentialBias() throws {
        // Keep centripetal acceleration well above the possible-airtime threshold so
        // adding this bias does not change which normal-speed observations are admitted.
        var run = verticalCircuits(radius:1.16)
        run.metadata.settings.startsAndEndsAtRest = true
        for i in 241...280 { run.samples.append(.init(timestamp:Double(i)*0.02,sensorLocation:.left)) }
        let reference = try ImprovedReconstruction.analyze(run)
        var biased = run
        for i in biased.samples.indices { biased.samples[i].userAcceleration.x += 0.10 }
        let result = try ImprovedReconstruction.analyze(biased)
        XCTAssertFalse(result.reconstructionDiagnostics!.startRestSupported)
        XCTAssertTrue(result.reconstructionDiagnostics!.endRestSupported)
        for (a,b) in zip(reference.points,result.points) {
            XCTAssertEqual(a.speed,b.speed,accuracy:1e-8)
            XCTAssertLessThan((a.position-b.position).length,1e-8)
        }
    }

    func testUnknownHeightRemainsRelativeAndInvalidSensorDataIsRejected() throws {
        var run = verticalCircuits(); run.metadata.verticalDrop = nil
        let result = try ImprovedReconstruction.analyze(run)
        XCTAssertTrue(result.isRelative)
        XCTAssertEqual(result.points.last!.distance,1,accuracy:1e-8)
        run.samples[25].timestamp += 2
        XCTAssertThrowsError(try ImprovedReconstruction.analyze(run))
    }

    func testLatestRecordingRegressionPreservesBaselineAndRecoversMissingMovement() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource:"repeated-circuit",withExtension:"json",subdirectory:"Fixtures"))
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let run = try decoder.decode(RunSession.self,from:Data(contentsOf:url)), original = run
        let before = try AnalysisPipeline.analyze(run)
        XCTAssertEqual(before.metrics.estimatedPathLength,10.97116518977551,accuracy:1e-8)
        let result = try ImprovedReconstruction.analyze(run)
        let diagnostics = try XCTUnwrap(result.reconstructionDiagnostics)
        XCTAssertTrue(diagnostics.speedFitConverged)
        XCTAssertTrue(diagnostics.collapsedMotion.isEmpty)
        XCTAssertEqual(diagnostics.repeatCircuits.count,3)
        for (actual,expected) in zip(diagnostics.repeatCircuits.map(\.startTime),[1.78,4.54,7.74]) {
            XCTAssertEqual(actual,expected,accuracy:0.021)
        }
        let lengths = diagnostics.repeatCircuits.map(\.estimatedLength)
        XCTAssertLessThan((lengths.max()!-lengths.min()!)/lengths.max()!,0.02)
        // These are fit-consistency checks, not ground-truth accuracy assertions.
        XCTAssertLessThan(diagnostics.repeatCircuits.map(\.closureDistance).max()!,0.10)
        XCTAssertTrue(result.points.filter { $0.time>9 && $0.time<10.5 }.contains { $0.speed>0.25 })
        XCTAssertEqual(run,original)
        XCTAssertEqual(try AnalysisPipeline.analyze(run).points,before.points)
        let encoded = try JSONEncoder().encode(result)
        XCTAssertEqual(try JSONDecoder().decode(AnalysisResult.self,from:encoded).reconstructionDiagnostics?.repeatCircuits.count,3)
    }
}

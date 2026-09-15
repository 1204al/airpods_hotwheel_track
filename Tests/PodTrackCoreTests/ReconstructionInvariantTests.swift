import XCTest
@testable import PodTrackCore

final class ReconstructionInvariantTests: XCTestCase {
    func testIndependentStraightRampRecoversLengthAndSpeed() throws {
        // Analytic controlled pass: v(t) = V sin(pi*t/T), fixed -20° slope.
        // This fixture does not use SimulatedTrack or the reconstruction integrator.
        let duration = 2.5, maximum = 1.2, slope = -20 * Double.pi/180
        let length = 2*maximum*duration / .pi
        let drop = -length*sin(slope)
        let mount = Quaternion(axis:Vector3(2,-1,3),angle:1.05)
        let q = Quaternion(axis:.unitY,angle:-slope)*mount
        let calibration = MountCalibration(forwardDevice:mount.inverse.rotate(.unitX),upDevice:mount.inverse.rotate(.unitZ),sensorLocation:.right,source:.simulation)
        let samples = (0...350).map { i -> MotionSample in
            let t = Double(i)/100, u = t-0.5
            let acceleration = u>=0 && u<=duration ? maximum * .pi/duration * cos(.pi*u/duration) : 0
            return .init(timestamp:t,attitude:q,userAcceleration:calibration.forwardDevice * (-acceleration/standardGravity),gravity:q.inverse.rotate(.init(0,0,-1)),sensorLocation:.right)
        }
        var settings = ReconstructionSettings(); settings.smoothingSeconds = 0; settings.gravityModelWeight = 0; settings.accelerationPolarity = .inverted
        let result = try AnalysisPipeline.analyze(.init(source:.simulation,metadata:.init(verticalDrop:drop,settings:settings),calibration:calibration,samples:samples))
        XCTAssertEqual(result.metrics.estimatedPathLength,length,accuracy:0.001)
        XCTAssertEqual(result.metrics.estimatedMaximumSpeed,maximum,accuracy:0.03)
        XCTAssertEqual(result.points.last!.position.x,length*cos(slope),accuracy:0.001)
        XCTAssertEqual(result.points.last!.position.y,0,accuracy:1e-8)
        XCTAssertEqual(result.points.first!.speed,0)
        XCTAssertEqual(result.points.last!.speed,0)
    }
    func testQuaternionConventionIsResolvedAgainstIndependentGravityAndGyro() throws {
        let native = SimulatedTrack.generate(includeJump:false)
        var inverted = native
        inverted.samples = native.samples.map { s in var copy = s; copy.attitude = s.attitude.inverse; return copy }
        func result(_ fixture: SimulationFixture) throws -> AnalysisResult {
            try AnalysisPipeline.analyze(.init(source:.simulation,metadata:.init(),calibration:fixture.calibration,samples:fixture.samples))
        }
        let a = try result(native), b = try result(inverted)
        XCTAssertNotEqual(a.attitudeMapping,b.attitudeMapping)
        XCTAssertEqual((a.points.last!.position-b.points.last!.position).length,0,accuracy:1e-8)
    }
    func testFlatMotionDoesNotInventDescent() throws {
        let fixture = SimulatedTrack.generate(includeJump:false)
        var signals = try SignalProcessor.process(fixture.samples,calibration:fixture.calibration,settings:.init()).samples
        for i in signals.indices { signals[i].slope = 0 }
        XCTAssertThrowsError(try TrackReconstructor.reconstruct(signals:signals,speeds:signals.map { _ in 1 },verticalDrop:0.42))
    }
    func testTimestampGapsAreRejectedAndNoJumpIsInventedWhenDisabled() throws {
        var fixture = SimulatedTrack.generate(includeJump:false)
        let result = try AnalysisPipeline.analyze(.init(source:.simulation,metadata:.init(),calibration:fixture.calibration,samples:fixture.samples))
        XCTAssertFalse(result.segments.contains { $0.kind == .airborne })
        fixture.samples.removeAll { $0.timestamp>2 && $0.timestamp<3 }
        XCTAssertThrowsError(try AnalysisPipeline.analyze(.init(source:.simulation,metadata:.init(),calibration:fixture.calibration,samples:fixture.samples)))
    }
    func testInvalidSettingsAndMetadataCannotBePersisted() {
        var metadata = RunMetadata(verticalDrop:.nan)
        XCTAssertThrowsError(try metadata.validate())
        metadata.verticalDrop = 0.42; metadata.knownTrackLength = 0.1
        XCTAssertThrowsError(try metadata.validate())
        metadata.knownTrackLength = nil; metadata.settings.smoothingSeconds = -.infinity
        XCTAssertThrowsError(try metadata.validate())
    }
}

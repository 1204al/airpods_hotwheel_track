import XCTest
@testable import PodTrackCore

final class SimulationTests: XCTestCase {
    func testSimulationHasKnownHeightArbitraryMountAndFiniteSamples() {
        let fixture = SimulatedTrack.generate(drop:0.42)
        XCTAssertEqual(fixture.referencePositions.first?.z,0)
        let heights = fixture.referencePositions.map(\.z)
        XCTAssertEqual(heights.max()!-heights.min()!,0.42,accuracy:1e-8)
        XCTAssertTrue(fixture.samples.allSatisfy(\.isValid))
        XCTAssertGreaterThan(fixture.calibration.forwardDevice.cross(.unitX).length,0.1)
        XCTAssertGreaterThan(fixture.referenceSpeeds.max()!,0.5)
        XCTAssertLessThan(fixture.referenceSpeeds.last!,0.01)
    }
    func testJumpContainsNearZeroTotalAcceleration() {
        let fixture = SimulatedTrack.generate(includeJump:true)
        let air = fixture.samples.filter { $0.timestamp > 5.16 && $0.timestamp < 5.25 }
        XCTAssertFalse(air.isEmpty)
        XCTAssertTrue(air.allSatisfy { $0.totalAccelerationMagnitudeG < 0.05 })
    }
}

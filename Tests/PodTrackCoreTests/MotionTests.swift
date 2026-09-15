import XCTest
@testable import PodTrackCore

final class MotionTests: XCTestCase {
    func testRingRetainsNewestSamplesInOrder() {
        var buffer = MotionBuffer(capacity:3)
        for i in 0..<7 { buffer.append(.init(timestamp:Double(i))) }
        XCTAssertEqual(buffer.samples.map(\.timestamp), [4,5,6])
        buffer.clear()
        XCTAssertTrue(buffer.samples.isEmpty)
    }
    func testSampleRateUsesSourceTimestamps() {
        let samples = (0..<51).map { MotionSample(timestamp:100 + Double($0)/50) }
        let stats = SampleStatistics(samples:samples)
        XCTAssertEqual(stats.frequencyHz, 50, accuracy:1e-8)
        XCTAssertEqual(stats.jitterMilliseconds, 0, accuracy:1e-8)
    }
    func testQuaternionRotationAndInverse() {
        let q = Quaternion(axis:.unitZ,angle:.pi/2)
        XCTAssertEqual(q.rotate(.unitX).y, 1, accuracy:1e-10)
        XCTAssertEqual((q.inverse.rotate(q.rotate(.unitX)) - .unitX).length, 0, accuracy:1e-10)
    }
    func testInvalidSamplesAreRejected() {
        var buffer = MotionBuffer()
        buffer.append(.init(timestamp:.nan))
        XCTAssertEqual(buffer.count,0)
    }
}

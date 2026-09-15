import XCTest
@testable import PodTrackCore

final class MotionDeliveryTests: XCTestCase {
    func testFiftyHertzSourceCanArriveSeveralSecondsLate() {
        var monitor = MotionDeliveryMonitor()
        let samples = (0..<100).map { MotionSample(timestamp:10+Double($0)/50) }
        for (index,sample) in samples.enumerated() {
            // First half normal; second half arrives with a three-second backlog.
            let receipt = 100+Double(index)/50+(index >= 50 ? 3.0 : 0)
            XCTAssertTrue(monitor.append(.init(sample:sample,receivedAt:receipt)))
        }
        XCTAssertEqual(SampleStatistics(samples:samples).frequencyHz,50,accuracy:1e-8)
        XCTAssertEqual(monitor.extraLag,3,accuracy:1e-8)
    }
    func testClockEpochDoesNotMasqueradeAsLatencyAndRecoveryIsVisible() {
        var monitor = MotionDeliveryMonitor()
        monitor.append(.init(sample:.init(timestamp:50),receivedAt:9000))
        XCTAssertEqual(monitor.extraLag,0)
        monitor.append(.init(sample:.init(timestamp:51),receivedAt:9004))
        XCTAssertEqual(monitor.extraLag,3)
        monitor.append(.init(sample:.init(timestamp:54.02),receivedAt:9004.02))
        XCTAssertEqual(monitor.extraLag,0,accuracy:1e-8)
    }
    func testDuplicatesAndBackwardsTimeCannotRefreshReceiptAge() {
        var monitor = MotionDeliveryMonitor()
        XCTAssertTrue(monitor.append(.init(sample:.init(timestamp:1),receivedAt:10)))
        XCTAssertFalse(monitor.append(.init(sample:.init(timestamp:1),receivedAt:15)))
        XCTAssertFalse(monitor.append(.init(sample:.init(timestamp:0.5),receivedAt:16)))
        XCTAssertEqual(monitor.lastReceipt,10)
        XCTAssertEqual(monitor.lastTimestamp,1)
        XCTAssertEqual(monitor.rejectedTimestamps,2)
    }
    func testArrivalCadenceIsIndependentOfSourceRate() {
        var monitor = MotionDeliveryMonitor()
        for i in 0...50 {
            monitor.append(.init(sample:.init(timestamp:10+Double(i)/50),receivedAt:100+Double(i)/25))
        }
        XCTAssertEqual(monitor.arrivalRateHz ?? -1,25,accuracy:1e-8)
        XCTAssertEqual(monitor.largestArrivalGap ?? -1,0.04,accuracy:1e-8)
        XCTAssertEqual(monitor.extraLag,1,accuracy:1e-8)
    }
    func testRecentPoseSurvivesRingWrapAndMatchesOriginalWindow() {
        var buffer = MotionBuffer(capacity:50)
        for i in 0..<120 { buffer.append(.init(timestamp:Double(i)/50)) }
        let end = buffer.samples.last!.timestamp
        XCTAssertEqual(buffer.recent(seconds:0.6),buffer.samples.filter { $0.timestamp >= end-0.6 })
        buffer.clear()
        XCTAssertEqual(buffer.recent(seconds:0.6),[])
    }
}

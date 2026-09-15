import XCTest
@testable import PodTrackCore

final class StabilityTests: XCTestCase {
    func testTimeAverageMatchesAnalyticLinearSignalWithIrregularSampling() {
        let times = [0.0,0.01,0.015,0.02,0.3,0.55,0.78,1]
        let smoothed = SignalProcessor.smooth(times,times:times,window:0.2)
        for (index,t) in times.enumerated() {
            let expected = (max(0,t-0.1)+min(1,t+0.1))/2
            XCTAssertEqual(smoothed[index],expected,accuracy:1e-10)
        }
    }
    func testAddingInterpolatedSamplesDoesNotChangeSmoothing() {
        let sparse = SignalProcessor.smooth([0,1,0],times:[0,0.5,1],window:0.4)
        let denseTimes = [0.0,0.02,0.1,0.15,0.4,0.5,0.8,1]
        let denseValues = denseTimes.map { $0 <= 0.5 ? 2*$0 : 2*(1-$0) }
        let dense = SignalProcessor.smooth(denseValues,times:denseTimes,window:0.4)
        for (a,b) in zip(sparse,[dense[0],dense[5],dense[7]]) {
            XCTAssertEqual(a,b,accuracy:1e-10)
        }
    }
    func testTimeSmoothingDisabledAndInvalidTimeInputsRemainUnchanged() {
        let values = [2.0,7,1]
        XCTAssertEqual(SignalProcessor.smooth(values,times:[0,1,2],window:0),values)
        XCTAssertEqual(SignalProcessor.smooth(values,times:[0,0,2],window:0.1),values)
        XCTAssertEqual(SignalProcessor.smooth([1],times:[0],window:0.1),[1])
    }
    func testCalibrationRequiresEnoughContinuousSingleSensorData() {
        let pose = steadyPose()
        XCTAssertNoThrow(try MountCalibration.checkSteady(pose))
        XCTAssertThrowsError(try MountCalibration.checkSteady(Array(pose.prefix(20))))
        var duplicate = pose; duplicate[10].timestamp = duplicate[9].timestamp
        XCTAssertThrowsError(try MountCalibration.checkSteady(duplicate))
        var gap = pose
        for i in 15..<gap.count { gap[i].timestamp += 0.2 }
        XCTAssertThrowsError(try MountCalibration.checkSteady(gap))
        var mixed = pose; mixed[10].sensorLocation = .left
        XCTAssertThrowsError(try MountCalibration.checkSteady(mixed))
    }
    func testSlowGravitySettlingCannotBeCapturedAsSteady() {
        var pose = steadyPose()
        for i in pose.indices {
            let angle = 3 * Double.pi/180 * Double(i)/Double(pose.count-1)
            pose[i].gravity = .init(-sin(angle),0,-cos(angle))
        }
        // Each sample is within 0.04 of the mean and gyro is zero: the previous
        // spread-only check accepted this slow drift.
        XCTAssertThrowsError(try MountCalibration.checkSteady(pose)) { error in
            XCTAssertTrue(error.localizedDescription.contains("settling"))
        }
    }
    func testSmallStationaryGravityNoiseIsAccepted() {
        var pose = steadyPose()
        for i in pose.indices {
            let angle = (i%2 == 0 ? 0.1 : -0.1) * Double.pi/180
            pose[i].gravity = .init(-sin(angle),0,-cos(angle))
        }
        XCTAssertNoThrow(try MountCalibration.checkSteady(pose))
    }
    func testYawReferenceResetIsRejectedEvenWhenGravityIsConsistent() {
        var samples = (0..<80).map { MotionSample(timestamp:Double($0)/50,sensorLocation:.right) }
        for i in 40..<samples.count { samples[i].attitude = .init(axis:.unitZ,angle:.pi/2) }
        XCTAssertThrowsError(try SignalProcessor.process(samples,calibration:calibration,settings:.init())) { error in
            XCTAssertTrue(error.localizedDescription.contains("Orientation jumps"))
        }
    }
    func testRealGyroSupportedRotationAndQuaternionSignFlipsAreAccepted() throws {
        let samples = (0..<80).map { i -> MotionSample in
            let time = Double(i)/50
            let q = Quaternion(axis:.unitZ,angle:time)
            let sign = i%2 == 0 ? 1.0 : -1.0
            return .init(timestamp:time,attitude:.init(x:q.x*sign,y:q.y*sign,z:q.z*sign,w:q.w*sign),
                         rotationRate:.init(0,0,1),sensorLocation:.right)
        }
        let result = try SignalProcessor.process(samples,calibration:calibration,settings:.init())
        XCTAssertGreaterThan(result.samples.last!.heading,1)
    }
    private var calibration: MountCalibration {
        .init(forwardDevice:.unitX,upDevice:.unitZ,sensorLocation:.right,source:.airPods)
    }
    private func steadyPose() -> [MotionSample] {
        (0...30).map { .init(timestamp:Double($0)/50,sensorLocation:.right) }
    }
}

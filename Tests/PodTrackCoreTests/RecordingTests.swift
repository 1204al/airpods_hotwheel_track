import XCTest
@testable import PodTrackCore

final class RecordingTests: XCTestCase {
    func testCalibrationSolvesArbitraryMount() throws {
        let mount = Quaternion(axis:Vector3(1,2,3),angle:1.1)
        let level = pose(gravity:mount.inverse.rotate(.init(0,0,-1)))
        let lifted = pose(gravity:mount.inverse.rotate(.init(-0.5,0,-sqrt(0.75))))
        let calibration = try MountCalibration.capture(level:level,noseUp:lifted,source:.airPods)
        XCTAssertEqual((calibration.forwardDevice-mount.inverse.rotate(.unitX)).length,0,accuracy:1e-8)
        XCTAssertEqual(calibration.forwardDevice.dot(calibration.upDevice),0,accuracy:1e-8)
    }
    func testCalibrationRejectsSamePose() {
        XCTAssertThrowsError(try MountCalibration.capture(level:pose(gravity:.init(0,0,-1)),noseUp:pose(gravity:.init(0,0,-1)),source:.airPods))
    }
    func testRecorderRejectsDuplicatesAndStopsBeforeBudSwitch() throws {
        var recorder = RunRecorder()
        try recorder.start(metadata:.init(),source:.airPods,calibration:nil)
        try recorder.append(.init(timestamp:1,sensorLocation:.left))
        try recorder.append(.init(timestamp:1,sensorLocation:.left))
        XCTAssertThrowsError(try recorder.append(.init(timestamp:1.02,sensorLocation:.right)))
        let run = try XCTUnwrap(recorder.finish())
        XCTAssertEqual(run.samples.count,1)
        XCTAssertFalse(run.recordingNotes.isEmpty)
    }
    func testStoreRoundTripAndCSVUnits() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let store = RunStore(directory:directory)
        let run = RunSession(source:.simulation,metadata:.init(),calibration:nil,samples:pose(gravity:.init(0,0,-1)))
        try store.save(run)
        let loaded = try store.load()
        XCTAssertEqual(loaded.runs.first?.samples,run.samples)
        XCTAssertEqual(loaded.runs.first?.id,run.id)
        let csv = CSVExporter.rawRun(run)
        XCTAssertTrue(csv.contains("user_accel_x_g"))
        XCTAssertTrue(csv.contains("Simulation,"))
        XCTAssertEqual(csv.split(separator:"\n").count,run.samples.count+1)
        XCTAssertEqual(Set(csv.split(separator:"\n").map { $0.split(separator:",",omittingEmptySubsequences:false).count }),[22])
    }
    private func pose(gravity: Vector3) -> [MotionSample] {
        (0..<30).map { .init(timestamp:Double($0)/50,gravity:gravity,sensorLocation:.left) }
    }
}

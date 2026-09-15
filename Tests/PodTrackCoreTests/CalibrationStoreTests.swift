import XCTest
@testable import PodTrackCore

final class CalibrationStoreTests: XCTestCase {
    func testIndependentProfilesRoundTripAndCorruptionIsIsolated() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let store = CalibrationStore(directory:directory)
        let left = MountCalibration(forwardDevice:.unitY,upDevice:.unitZ,sensorLocation:.left,source:.airPods,capturedAt:Date(timeIntervalSince1970:100))
        let right = MountCalibration(forwardDevice:.unitX,upDevice:.unitZ,sensorLocation:.right,source:.airPods,capturedAt:Date(timeIntervalSince1970:200))
        try store.save(left); try store.save(right)
        XCTAssertEqual(store.load().calibrations,[.left:left,.right:right])
        let rightData = try Data(contentsOf:directory.appendingPathComponent("right.json"))
        var replacement = left; replacement.forwardDevice = -.unitY
        try store.save(replacement)
        XCTAssertEqual(try Data(contentsOf:directory.appendingPathComponent("right.json")),rightData)
        // A valid Right file in the Left slot must not be applied to the Left bud.
        try rightData.write(to:directory.appendingPathComponent("left.json"))
        XCTAssertEqual(store.load().calibrations,[.right:right])
        XCTAssertEqual(store.load().warnings.count,1)
        try Data("broken JSON".utf8).write(to:directory.appendingPathComponent("left.json"))
        XCTAssertEqual(store.load().calibrations,[.right:right])
        XCTAssertEqual(store.load().warnings.count,1)
        try store.remove(for:.left)
        XCTAssertEqual(store.load().calibrations,[.right:right])
        XCTAssertTrue(store.load().warnings.isEmpty)
    }

    func testCannotPersistSyntheticUnknownOrInvalidMounts() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let store = CalibrationStore(directory:directory)
        var profile = MountCalibration(forwardDevice:.unitX,upDevice:.unitZ,sensorLocation:.right,source:.simulation)
        XCTAssertThrowsError(try store.save(profile))
        profile.source = .airPods; profile.sensorLocation = .unknown
        XCTAssertThrowsError(try store.save(profile))
        profile.sensorLocation = .right; profile.forwardDevice = .unitZ
        XCTAssertThrowsError(try store.save(profile))
        profile.forwardDevice = .zero
        XCTAssertThrowsError(try store.save(profile))
        XCTAssertTrue(store.load().calibrations.isEmpty)
    }
}

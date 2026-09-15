import XCTest
@testable import PodTrackCore

final class RunDeletionTests: XCTestCase {
    func testDeletionSurvivesReloadAndRestoreRetainsTheRecording() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let store = RunStore(directory:directory)
        let fixture = SimulatedTrack.generate(drop:0.58,includeJump:false)
        var run = RunSession(source:.simulation,metadata:.init(),calibration:fixture.calibration,samples:fixture.samples)
        try store.save(run)
        run.metadata.notes = "Latest unsaved edit"
        try store.moveToRecentlyDeleted(run)
        XCTAssertTrue(try RunStore(directory:directory).load().runs.isEmpty)
        let deleted = try XCTUnwrap(RunStore(directory:directory).loadRecentlyDeleted().runs.first)
        XCTAssertEqual(deleted.samples,run.samples)
        XCTAssertEqual(deleted.metadata,run.metadata)
        XCTAssertEqual(deleted.calibration?.forwardDevice,run.calibration?.forwardDevice)
        try store.restore(run.id)
        XCTAssertTrue(try store.loadRecentlyDeleted().runs.isEmpty)
        XCTAssertEqual(try store.load().runs.first?.samples,run.samples)
    }

    func testFailedRemovalAndRestoreCollisionNeverLoseExistingFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let store = RunStore(directory:directory)
        let run = RunSession(source:.simulation,metadata:.init(),calibration:nil,samples:[.init(timestamp:1)])
        try store.save(run)
        try Data("Directory obstruction".utf8).write(to:store.recentlyDeletedDirectory)
        XCTAssertThrowsError(try store.moveToRecentlyDeleted(run))
        XCTAssertEqual(try store.load().runs.first?.id,run.id)
        try FileManager.default.removeItem(at:store.recentlyDeletedDirectory)
        try store.moveToRecentlyDeleted(run)
        var newer = run; newer.metadata.notes = "Active version"
        try store.save(newer)
        XCTAssertThrowsError(try store.restore(run.id))
        XCTAssertEqual(try store.load().runs.first?.metadata.notes,"Active version")
        XCTAssertEqual(try store.loadRecentlyDeleted().runs.first?.samples,run.samples)
    }
}

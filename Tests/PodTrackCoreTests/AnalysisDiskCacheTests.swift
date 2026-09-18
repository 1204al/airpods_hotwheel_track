import XCTest
@testable import PodTrackCore

final class AnalysisDiskCacheTests: XCTestCase {
    func testRestartParameterChangesMethodsAndCorruption() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let store = RunStore(directory:directory)
        let cache = AnalysisDiskCache(directory:directory.appendingPathComponent("AnalysisCache"))
        let fixture = SimulatedTrack.generate(includeJump:false,profile:.raisedFinish)
        let run = RunSession(source:.simulation,metadata:.init(verticalDrop:0.42),calibration:fixture.calibration,samples:fixture.samples)
        try store.save(run)
        let result = try ReconstructionMethod.old.analyze(run)
        try cache.save(result,run:run,method:.old)
        let reloaded = try XCTUnwrap(store.load().runs.first)
        let restarted = AnalysisDiskCache(directory:cache.directory)
        XCTAssertEqual(restarted.load(reloaded,method:.old)?.points.count,result.points.count)
        XCTAssertEqual(restarted.load(reloaded,method:.old)?.metrics.estimatedPathLength,result.metrics.estimatedPathLength)
        XCTAssertNil(restarted.load(reloaded,method:.improved))
        var changed = reloaded
        changed.metadata.verticalDrop = 0.8
        XCTAssertNil(restarted.load(changed,method:.old))
        changed = reloaded
        changed.metadata.knownTrackLength = 4
        XCTAssertNil(restarted.load(changed,method:.old))
        var outdated = result
        outdated.algorithmVersion = "obsolete"
        try cache.save(outdated,run:run,method:.old)
        XCTAssertNil(restarted.load(reloaded,method:.old))
        try Data("broken".utf8).write(to:cache.fileURL(run.id,method:.old))
        XCTAssertNil(restarted.load(reloaded,method:.old))
        try cache.save(result,run:run,method:.old)
        XCTAssertNotNil(restarted.load(reloaded,method:.old))
        XCTAssertEqual(try store.load().runs.count,1)
    }
}

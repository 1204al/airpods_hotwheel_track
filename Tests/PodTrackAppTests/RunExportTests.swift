import XCTest
import PodTrackCore
@testable import PodTrack

final class RunExportTests: XCTestCase {
    func testSingleRawAndMultipleDatasetArchive() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let fixture = SimulatedTrack.generate(includeJump:false)
        let run = RunSession(source:.simulation,metadata:.init(verticalDrop:0.58),calibration:fixture.calibration,samples:fixture.samples)
        let cache = AnalysisDiskCache(directory:root.appendingPathComponent("cache"))
        let csv = root.appendingPathComponent("raw.csv")
        try RunExportWriter.write(run:run,datasets:[.raw],format:.csv,cache:cache,destination:csv)
        XCTAssertEqual(try String(contentsOf:csv),CSVExporter.rawRun(run))
        let json = try RunExportDataset.raw.data(run:run,format:.json,cache:cache)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try decoder.decode(RunSession.self,from:json).samples,run.samples)
        let zip = root.appendingPathComponent("export.zip")
        try RunExportWriter.write(run:run,datasets:[.raw,.algorithm(.old)],format:.csv,cache:cache,destination:zip)
        let unpacked = root.appendingPathComponent("unpacked")
        let process = Process()
        process.executableURL = URL(fileURLWithPath:"/usr/bin/ditto")
        process.arguments = ["-x","-k",zip.path,unpacked.path]
        try process.run(); process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus,0)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:unpacked.path).sorted(),["\(run.exportBasename)-old.csv","\(run.exportBasename)-raw.csv"])
        XCTAssertEqual(try String(contentsOf:unpacked.appendingPathComponent("\(run.exportBasename)-raw.csv")),CSVExporter.rawRun(run))
        var invalid = run; invalid.calibration = nil
        let prior = try Data(contentsOf:zip)
        XCTAssertThrowsError(try RunExportWriter.write(run:invalid,datasets:[.raw,.algorithm(.old)],format:.json,cache:cache,destination:zip))
        XCTAssertEqual(try Data(contentsOf:zip),prior)
    }
}

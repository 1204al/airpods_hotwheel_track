import XCTest
@testable import PodTrackCore

final class RecordingOriginTests: XCTestCase {
    func testOldRawRecordingsDeriveIdentityFromSamplesAfterReloadAndRename() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let store = RunStore(directory:directory)
        var run = RunSession(source:.airPods,metadata:.init(),calibration:nil,samples:[.init(timestamp:1,sensorLocation:.left)])
        try store.save(run)
        run = try XCTUnwrap(store.load().runs.first)
        XCTAssertEqual(run.recordedOrigin,.left)
        XCTAssertTrue(run.displayName.contains("Left AirPod"))
        run.metadata.carName = "Second car"
        XCTAssertEqual(run.carDisplayName,"Second car · Left AirPod")
        XCTAssertTrue(run.comparisonDisplayName.contains("Left AirPod"))
        XCTAssertTrue(run.exportBasename.hasPrefix("PodTrack-left-"))
        run.samples = [.init(timestamp:1,sensorLocation:.unknown)]
        run.calibration = .init(forwardDevice:.unitX,upDevice:.unitZ,sensorLocation:.right,source:.airPods)
        XCTAssertEqual(run.recordedOrigin,.unknown,"Calibration does not establish which bud actually recorded unknown samples")
        run.samples = [.init(timestamp:1,sensorLocation:.left),.init(timestamp:2,sensorLocation:.right)]
        XCTAssertEqual(run.recordedOrigin,.mixed)
        run.samples = []; XCTAssertEqual(run.recordedOrigin,.unknown)
        run.source = .simulation; run.samples = [.init(timestamp:1,sensorLocation:.left)]
        XCTAssertEqual(run.recordedOrigin,.simulation)
        XCTAssertFalse(run.displayName.contains("Left AirPod"))
    }

    func testProvenanceSurvivesReconstructionAndBothProcessedExports() throws {
        // Explicit test fixture with a reported Right source; no physical capture.
        var fixture = SimulatedTrack.generate(drop:0.58)
        fixture.samples = fixture.samples.map { var sample = $0; sample.sensorLocation = .right; return sample }
        fixture.calibration.source = .airPods; fixture.calibration.sensorLocation = .right
        let run = RunSession(source:.airPods,metadata:.init(),calibration:fixture.calibration,samples:fixture.samples)
        let result = try AnalysisPipeline.analyze(run)
        XCTAssertEqual(result.recordedOrigin,.right)
        let rows = CSVExporter.reconstructedTrack(result).split(separator:"\n")
        XCTAssertTrue(rows[0].hasSuffix(",recorded_from"))
        XCTAssertTrue(rows.dropFirst().allSatisfy { $0.hasSuffix(",right") })
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(CSVExporter.processedJSON(run:run,result:result).utf8)) as? [String:Any])
        XCTAssertEqual(json["recordedOrigin"] as? String,"right")
        XCTAssertTrue((json["displayName"] as? String)?.contains("Right AirPod") == true)
    }

    func testLiveExportDoesNotApplyTheOtherBudsSavedCalibration() {
        let samples = [MotionSample(timestamp:1,userAcceleration:.unitX,sensorLocation:.left),MotionSample(timestamp:2,userAcceleration:.unitX,sensorLocation:.right)]
        let calibration = MountCalibration(forwardDevice:.unitX,upDevice:.unitZ,sensorLocation:.right,source:.airPods)
        let rows = CSVExporter.rawSamples(samples,source:.airPods,calibration:calibration).split(separator:"\n").dropFirst()
            .map { $0.split(separator:",",omittingEmptySubsequences:false) }
        XCTAssertEqual(rows[0][20],"")
        XCTAssertEqual(Double(rows[1][20])!,standardGravity,accuracy:1e-6)
    }
}

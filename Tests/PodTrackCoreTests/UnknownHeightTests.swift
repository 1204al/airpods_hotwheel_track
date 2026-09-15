import XCTest
@testable import PodTrackCore

final class UnknownHeightTests: XCTestCase {
    private func fixtureRun() -> RunSession {
        let input = SimulatedTrack.generate(includeJump:false,profile:.raisedFinish)
        var calibration = input.calibration
        calibration.capturedAt = Date(timeIntervalSince1970:1_789_401_600)
        return .init(source:.simulation,metadata:.init(verticalDrop:nil),calibration:calibration,samples:input.samples)
    }

    func testUnknownHeightPreservesShapeAndTimingWhenHeightIsAddedLater() throws {
        var recorded = fixtureRun()
        let relative = try AnalysisPipeline.analyze(recorded)
        XCTAssertTrue(relative.isRelative)
        XCTAssertEqual(relative.metrics.estimatedPathLength,1,accuracy:1e-9)
        XCTAssertEqual(relative.groundZ,0,accuracy:1e-9)
        XCTAssertNil(relative.metrics.enteredVerticalDrop)
        recorded.metadata.verticalDrop = 0.58
        let measured = try AnalysisPipeline.analyze(recorded)
        let factor = 0.58/relative.metrics.reconstructedHeightRange
        XCTAssertEqual(measured.resolvedScaleBasis,.height)
        XCTAssertEqual(measured.metrics.reconstructedHeightRange,0.58,accuracy:1e-9)
        for (a,b) in zip(relative.points,measured.points) {
            XCTAssertEqual(a.time,b.time)
            XCTAssertEqual((a.position*factor-b.position).length,0,accuracy:1e-8)
            XCTAssertEqual(a.distance*factor,b.distance,accuracy:1e-8)
            XCTAssertEqual(a.speed*factor,b.speed,accuracy:1e-8)
        }
        XCTAssertEqual(relative.signals,measured.signals)
    }

    func testFlatMotionCanHaveRelativeShapeWithoutInventingHeight() throws {
        // Independent analytic path: 2 m/s along X for 3 seconds, zero vertical movement.
        let signals = (0...3).map {
            ProcessedSample(time:Double($0),verticalUserAcceleration:0,tangentialUserAcceleration:0,
                            slope:0,heading:0,bank:0,turnRate:0,supportProxyG:1,accelerationMagnitude:0,isQuiet:false)
        }
        let speeds = [Double](repeating:2,count:4)
        let result = try TrackReconstructor.reconstruct(signals:signals,speeds:speeds,verticalDrop:nil)
        XCTAssertEqual(result.points.last!.position.x,1,accuracy:1e-9)
        XCTAssertEqual(result.points.last!.distance,1,accuracy:1e-9)
        XCTAssertTrue(result.points.allSatisfy { $0.position.z == 0 && $0.position.y == 0 })
        XCTAssertEqual(result.points[1].speed,1.0/3,accuracy:1e-9)
        XCTAssertThrowsError(try TrackReconstructor.reconstruct(signals:signals,speeds:speeds,verticalDrop:0.58))
        XCTAssertThrowsError(try TrackReconstructor.reconstruct(signals:signals,speeds:[0,0,0,0],verticalDrop:nil))
    }

    func testMeasuredLengthAloneSetsUniformPhysicalScale() throws {
        var recorded = fixtureRun()
        let relative = try AnalysisPipeline.analyze(recorded)
        recorded.metadata.knownTrackLength = 3.2
        let measured = try AnalysisPipeline.analyze(recorded)
        XCTAssertEqual(measured.resolvedScaleBasis,.trackLength)
        XCTAssertFalse(measured.isRelative)
        XCTAssertEqual(measured.metrics.estimatedPathLength,3.2,accuracy:1e-9)
        XCTAssertNil(measured.metrics.enteredVerticalDrop)
        XCTAssertEqual(measured.horizontalScale,1)
        for (a,b) in zip(relative.points,measured.points) {
            XCTAssertEqual((a.position*3.2-b.position).length,0,accuracy:1e-8)
            XCTAssertEqual(a.speed*3.2,b.speed,accuracy:1e-8)
        }
    }

    func testUnknownHeightPersistsAndExportsWithRelativeUnits() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let recorded = fixtureRun(), store = RunStore(directory:directory)
        try store.save(recorded)
        let loaded = try XCTUnwrap(store.load().runs.first)
        XCTAssertNil(loaded.metadata.verticalDrop)
        XCTAssertEqual(loaded.id,recorded.id)
        XCTAssertEqual(loaded.samples,recorded.samples)
        XCTAssertEqual(loaded.calibration,recorded.calibration)
        let result = try AnalysisPipeline.analyze(loaded)
        let csv = CSVExporter.reconstructedTrack(result)
        XCTAssertTrue(csv.contains("estimated_x_u"))
        XCTAssertTrue(csv.contains("estimated_speed_u_s"))
        XCTAssertTrue(csv.contains("scale_basis"))
        XCTAssertTrue(csv.contains(",relative,simulation\n"))
        XCTAssertFalse(csv.contains("estimated_x_m"))
        XCTAssertFalse(csv.contains("estimated_speed_m_s"))
        let json = try CSVExporter.processedJSON(run:loaded,result:result)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(json.utf8)) as? [String:Any])
        XCTAssertTrue((object["description"] as? String)?.contains("Total path length = 1 u") == true)
        let encoded = try JSONEncoder().encode(result)
        XCTAssertTrue(try JSONDecoder().decode(AnalysisResult.self,from:encoded).isRelative)
    }

    func testUnknownDoesNotTurnInvalidMeasurementsOrMissingMotionIntoAPath() throws {
        for invalid in [0.0,-1,.nan,.infinity] {
            XCTAssertThrowsError(try RunMetadata(verticalDrop:invalid).validate())
            XCTAssertThrowsError(try RunMetadata(verticalDrop:nil,knownTrackLength:invalid).validate())
        }
        var recorded = fixtureRun()
        recorded.calibration = nil
        XCTAssertThrowsError(try AnalysisPipeline.analyze(recorded))
        recorded = fixtureRun()
        let sample = recorded.samples[0]
        recorded.samples = (0..<100).map { i in var copy = sample; copy.timestamp = Double(i)*0.02; return copy }
        XCTAssertThrowsError(try AnalysisPipeline.analyze(recorded))
    }

    func testLegacyAnalysisWithoutScaleBasisKeepsMetricUnits() throws {
        var recorded = fixtureRun(); recorded.metadata.verticalDrop = 0.58
        let result = try AnalysisPipeline.analyze(recorded)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(result)) as? [String:Any])
        object.removeValue(forKey:"scaleBasis")
        let loaded = try JSONDecoder().decode(AnalysisResult.self,from:JSONSerialization.data(withJSONObject:object))
        XCTAssertEqual(loaded.resolvedScaleBasis,.height)
        XCTAssertEqual(loaded.distanceUnit,"m")
        XCTAssertEqual(loaded.speedUnit,"m/s")
    }
}

import XCTest
@testable import PodTrackCore

final class TimeWindowTests: XCTestCase {
    private func fixtureRun() -> RunSession {
        let input = SimulatedTrack.generate(drop:0.58,includeJump:true,profile:.circuit)
        return .init(source:.simulation,metadata:.init(verticalDrop:0.58),calibration:input.calibration,samples:input.samples)
    }

    func testWindowSelectsRowsOfTheWholeRunFitWithoutChangingThem() throws {
        let run = fixtureRun()
        let whole = try AnalysisPipeline.analyze(run)
        let window = TimeWindow(start:2,end:4)
        let slice = whole.trimmed(to:window)
        XCTAssertFalse(slice.points.isEmpty)
        XCTAssertLessThan(slice.points.count,whole.points.count)
        // Same rows, not a refit: position, speed and cumulative distance are untouched.
        XCTAssertEqual(slice.points,whole.points.filter { window.contains($0.time) })
        XCTAssertEqual(slice.signals,whole.signals.filter { window.contains($0.time) })
        XCTAssertEqual(slice.heightScale,whole.heightScale)
        XCTAssertEqual(slice.horizontalScale,whole.horizontalScale)
        XCTAssertEqual(slice.resolvedScaleBasis,whole.resolvedScaleBasis)
        XCTAssertEqual(slice.algorithmVersion,whole.algorithmVersion)
        XCTAssertGreaterThan(try XCTUnwrap(slice.points.first).distance,0)
        XCTAssertTrue(slice.warnings.contains { $0.contains("Time window") && $0.contains("not recalculated") },slice.warnings.joined())
    }

    func testWindowMetricsDescribeOnlyTheWindow() throws {
        let run = fixtureRun()
        let whole = try AnalysisPipeline.analyze(run)
        let window = TimeWindow(start:2,end:4)
        let slice = whole.trimmed(to:window)
        let first = try XCTUnwrap(slice.points.first), last = try XCTUnwrap(slice.points.last)
        XCTAssertEqual(slice.metrics.recordingDuration,window.duration,accuracy:1e-9)
        XCTAssertEqual(slice.metrics.estimatedPathLength,last.distance-first.distance,accuracy:1e-9)
        XCTAssertLessThan(slice.metrics.estimatedPathLength,whole.metrics.estimatedPathLength)
        XCTAssertLessThanOrEqual(slice.metrics.estimatedMaximumSpeed,whole.metrics.estimatedMaximumSpeed)
        XCTAssertEqual(slice.metrics.estimatedMaximumSpeed,slice.points.map(\.speed).max())
        // The entered height belongs to the construction, not to the window.
        XCTAssertEqual(slice.metrics.enteredVerticalDrop,0.58)
        XCTAssertLessThanOrEqual(slice.metrics.reconstructedHeightRange,whole.metrics.reconstructedHeightRange+1e-9)
    }

    func testCandidatesAreClippedToTheWindowAndOnesOutsideAreDropped() throws {
        let run = fixtureRun()
        let whole = try AnalysisPipeline.analyze(run)
        let window = TimeWindow(start:2,end:4)
        let slice = whole.trimmed(to:window)
        XCTAssertFalse(slice.segments.isEmpty)
        for segment in slice.segments {
            XCTAssertGreaterThanOrEqual(segment.startTime,window.start-1e-9)
            XCTAssertLessThanOrEqual(segment.endTime,window.end+1e-9)
        }
        XCTAssertEqual(slice.segments.count,whole.segments.filter { $0.endTime>window.start && $0.startTime<window.end }.count)
        XCTAssertNil(RunSegment(kind:.bump,startTime:5,endTime:5.2).clipped(to:window))
    }

    func testTrimmedRecordingKeepsOriginalSamplesAndSaysItIsPartOfARun() {
        let run = fixtureRun()
        let window = TimeWindow(start:2,end:4)
        let trimmed = run.trimmed(to:window)
        let origin = run.samples[0].timestamp
        XCTAssertEqual(trimmed.samples,run.samples.filter { window.contains($0.timestamp-origin) })
        XCTAssertEqual(trimmed.id,run.id)
        XCTAssertEqual(trimmed.calibration,run.calibration)
        XCTAssertTrue(try XCTUnwrap(trimmed.recordingNotes.last).contains(run.id.uuidString))
        XCTAssertTrue(try XCTUnwrap(trimmed.recordingNotes.last).contains("2.00–4.00 s"))
    }

    func testAWindowedRawExportRepeatsTheSameRowsAsTheFullExport() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let run = fixtureRun()
        let cache = AnalysisDiskCache(directory:directory)
        let full = String(decoding:try RunExportDataset.raw.data(run:run,format:.csv,cache:cache),as:UTF8.self)
            .split(separator:"\n").map(String.init)
        let part = String(decoding:try RunExportDataset.raw.data(run:run,format:.csv,cache:cache,window:.init(start:2,end:4)),as:UTF8.self)
            .split(separator:"\n").map(String.init)
        XCTAssertEqual(part[0],full[0])
        XCTAssertLessThan(part.count,full.count)
        // Elapsed time still counts from the recording's start, so rows match exactly.
        for row in part.dropFirst() { XCTAssertTrue(full.contains(row),String(row.prefix(60))) }
    }

    func testAWindowWithNoSamplesIsRefusedRatherThanExportedEmpty() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let run = fixtureRun()
        let cache = AnalysisDiskCache(directory:directory)
        XCTAssertThrowsError(try RunExportDataset.raw.data(run:run,format:.csv,cache:cache,window:.init(start:60,end:61)))
        XCTAssertThrowsError(try RunExportDataset.algorithm(.old).data(run:run,format:.csv,cache:cache,window:.init(start:60,end:61)))
    }

    func testWindowsStayInsideTheRecordingAndNeverCollapse() {
        XCTAssertEqual(TimeWindow(start:4,end:1).start,1)
        XCTAssertEqual(TimeWindow(start:4,end:1).end,4)
        let clamped = TimeWindow(start:-3,end:99).limited(to:6.8)
        XCTAssertEqual(clamped.start,0)
        XCTAssertEqual(clamped.end,6.8)
        let collapsed = TimeWindow(start:3,end:3).limited(to:6.8)
        XCTAssertEqual(collapsed.duration,0.05,accuracy:1e-9)
        let atEnd = TimeWindow(start:6.8,end:6.8).limited(to:6.8)
        XCTAssertEqual(atEnd.end,6.8)
        XCTAssertEqual(atEnd.duration,0.05,accuracy:1e-9)
        XCTAssertTrue(TimeWindow(start:0,end:6.8).covers(6.8))
        XCTAssertFalse(TimeWindow(start:0.1,end:6.8).covers(6.8))
        XCTAssertEqual(TimeWindow(start:1,end:3).overlap(.init(start:2,end:9)),1,accuracy:1e-9)
        XCTAssertEqual(TimeWindow(start:1,end:3).overlap(.init(start:7,end:9)),0)
    }
}

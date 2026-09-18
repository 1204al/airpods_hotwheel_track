import XCTest
import PodTrackCore
@testable import PodTrack

@MainActor final class RunLibraryTests: XCTestCase {
    /// A recording that identifies as a real AirPod side, so library filters can be checked
    /// against the recorded samples rather than the simulation label.
    private func fixtureRun(car: String, track: String = "Untitled track", height: Double? = 0.58,
                            minutesAgo: Double = 0, side: SensorLocation = .left) -> RunSession {
        let input = SimulatedTrack.generate(drop:height ?? 0.42,includeJump:false,profile:.raisedFinish)
        let samples = input.samples.map { sample -> MotionSample in
            var moved = sample; moved.sensorLocation = side; return moved
        }
        let calibration = MountCalibration(forwardDevice:input.calibration.forwardDevice,upDevice:input.calibration.upDevice,
                                           sensorLocation:side,source:.airPods)
        return .init(createdAt:Date(timeIntervalSince1970:1_789_401_600-minutesAgo*60),source:.airPods,
                     metadata:.init(trackName:track,carName:car,verticalDrop:height),
                     calibration:calibration,samples:samples)
    }

    func testSearchNarrowsByCarSideAndRunIDWithoutNeedingTheWholeName() {
        let left = fixtureRun(car:"Falcon",side:.left)
        let right = fixtureRun(car:"Bolt",track:"Loop",side:.right)
        var query = RunLibraryQuery()
        query.search = "falcon"
        XCTAssertEqual(query.apply(to:[left,right],analyses:[:]).map(\.id),[left.id])
        query.search = "right"
        XCTAssertEqual(query.apply(to:[left,right],analyses:[:]).map(\.id),[right.id])
        query.search = right.id.uuidString
        XCTAssertEqual(query.apply(to:[left,right],analyses:[:]).map(\.id),[right.id])
        // Separate tokens combine instead of having to be typed in one order.
        query.search = "  right   loop "
        XCTAssertEqual(query.apply(to:[left,right],analyses:[:]).map(\.id),[right.id])
        query.search = "falcon right"
        XCTAssertTrue(query.apply(to:[left,right],analyses:[:]).isEmpty)
        query.search = "   "
        XCTAssertEqual(query.apply(to:[left,right],analyses:[:]).count,2)
    }

    func testStatusFilterKeepsRunsUnderAnalysisOutOfBothAnswers() throws {
        let ready = fixtureRun(car:"Ready")
        let pending = fixtureRun(car:"Pending")
        let rawOnly = fixtureRun(car:"Raw")
        let analyses = [ready.id:try AnalysisPipeline.analyze(ready)]
        let runs = [ready,pending,rawOnly]
        var query = RunLibraryQuery()
        query.status = .reconstructed
        XCTAssertEqual(query.apply(to:runs,analyses:analyses,analysing:[pending.id]).map(\.id),[ready.id])
        query.status = .withoutPath
        XCTAssertEqual(query.apply(to:runs,analyses:analyses,analysing:[pending.id]).map(\.id),[rawOnly.id])
        query.status = .all
        XCTAssertEqual(query.apply(to:runs,analyses:analyses,analysing:[pending.id]).count,3)
    }

    func testScaleFiltersSeparateMeasuredHeightFromRelativeRuns() throws {
        let measured = fixtureRun(car:"Measured",height:0.58)
        let unknown = fixtureRun(car:"Unknown",height:nil)
        let analyses = [unknown.id:try AnalysisPipeline.analyze(unknown)]
        var query = RunLibraryQuery()
        query.status = .measured
        XCTAssertEqual(query.apply(to:[measured,unknown],analyses:analyses).map(\.id),[measured.id])
        query.status = .unknownScale
        XCTAssertEqual(query.apply(to:[measured,unknown],analyses:analyses).map(\.id),[unknown.id])
    }

    func testSideFilterUsesTheRecordedSamplesNotTheCurrentSelection() {
        let left = fixtureRun(car:"Car A",side:.left)
        let right = fixtureRun(car:"Car A",side:.right)
        var query = RunLibraryQuery()
        query.side = .left
        XCTAssertEqual(query.apply(to:[left,right],analyses:[:]).map(\.id),[left.id])
        query.side = .simulation
        XCTAssertTrue(query.apply(to:[left,right],analyses:[:]).isEmpty)
    }

    func testEstimateSortsRankRunsWithoutAReconstructionLast() throws {
        let fast = fixtureRun(car:"Fast",height:1.2)
        let slow = fixtureRun(car:"Slow",height:0.2)
        let unreconstructed = fixtureRun(car:"None")
        let analyses = [fast.id:try AnalysisPipeline.analyze(fast),slow.id:try AnalysisPipeline.analyze(slow)]
        let runs = [slow,unreconstructed,fast]
        var query = RunLibraryQuery()
        query.sort = .longestPath
        XCTAssertEqual(query.apply(to:runs,analyses:analyses).map(\.id),[fast.id,slow.id,unreconstructed.id])
        query.sort = .fastest
        XCTAssertEqual(query.apply(to:runs,analyses:analyses).map(\.id).last,unreconstructed.id)
    }

    func testDateSortsUseTheRecordingDateInBothDirections() {
        let older = fixtureRun(car:"Older",minutesAgo:30)
        let newer = fixtureRun(car:"Newer",minutesAgo:0)
        var query = RunLibraryQuery()
        XCTAssertEqual(query.sort,.newest)
        XCTAssertEqual(query.apply(to:[older,newer],analyses:[:]).map(\.id),[newer.id,older.id])
        query.sort = .oldest
        XCTAssertEqual(query.apply(to:[older,newer],analyses:[:]).map(\.id),[older.id,newer.id])
    }

    private func unzip(_ archive: URL, into directory: URL) throws -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath:"/usr/bin/ditto")
        process.arguments = ["-x","-k",archive.path,directory.path]
        try process.run(); process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus,0)
        return try FileManager.default.contentsOfDirectory(atPath:directory.path).sorted()
    }

    func testLibraryExportKeepsGoingPastAnUnreconstructableRunAndReportsIt() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:directory) }
        let good = fixtureRun(car:"Good")
        var rawOnly = fixtureRun(car:"Raw")
        rawOnly.calibration = nil
        let destination = directory.appendingPathComponent("library.zip")
        let outcome = try RunExportWriter.write(runs:[good,rawOnly],datasets:[.algorithm(.old)],format:.csv,
                                                cache:AnalysisDiskCache(directory:directory.appendingPathComponent("cache")),
                                                destination:destination,
                                                extraFiles:["PodTrack-runs-index.csv":Data("run_id\n".utf8)],strict:false)
        XCTAssertEqual(outcome.runs,1)
        XCTAssertEqual(outcome.skipped.count,1)
        XCTAssertTrue(try XCTUnwrap(outcome.skipped.first).contains("Raw"))
        let unpacked = directory.appendingPathComponent("unpacked")
        let names = try unzip(destination,into:unpacked)
        XCTAssertEqual(names,["PodTrack-runs-index.csv","\(good.exportBasename)-old.csv","export-report.txt"].sorted())
        let report = try String(contentsOf:unpacked.appendingPathComponent("export-report.txt"),encoding:.utf8)
        XCTAssertTrue(report.contains("1 of 2 recording"))
        XCTAssertFalse(names.contains("\(rawOnly.exportBasename)-old.csv"))
    }

    func testSingleRunExportStillRefusesToWriteAPartialFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:directory) }
        var rawOnly = fixtureRun(car:"Raw")
        rawOnly.calibration = nil
        let destination = directory.appendingPathComponent("run.zip")
        XCTAssertThrowsError(try RunExportWriter.write(run:rawOnly,datasets:[.raw,.algorithm(.old)],format:.csv,
                                                       cache:AnalysisDiskCache(directory:directory.appendingPathComponent("cache")),
                                                       destination:destination))
        XCTAssertFalse(FileManager.default.fileExists(atPath:destination.path))
    }

    private func model(with runs: [RunSession], in directory: URL) throws -> AppModel {
        let store = RunStore(directory:directory)
        try runs.forEach { try store.save($0) }
        return AppModel(motionSource:SimulatedTrackMotionSource(),store:store)
    }

    func testDeletingSeveralRecordingsMovesThemTogetherAndUndoRestoresTheWholeGroup() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let runs = (0..<3).map { fixtureRun(car:"Car \($0)",minutesAgo:Double($0)*10) }
        let model = try model(with:runs,in:directory)
        defer { model.shutdown() }
        XCTAssertEqual(model.runs.count,3)
        let removing = Array(model.runs.prefix(2))
        XCTAssertEqual(model.deleteRecordings(removing),2)
        XCTAssertEqual(model.runs.map(\.id),[runs[2].id])
        XCTAssertEqual(Set(model.lastDeletedRunIDs),Set(removing.map(\.id)))
        XCTAssertEqual(Set(model.deletedRuns.map(\.id)),Set(removing.map(\.id)))
        XCTAssertNil(model.errorMessage)
        // Undo returns every recording of that group, with its samples and settings.
        model.restoreLastDeleted()
        XCTAssertEqual(Set(model.runs.map(\.id)),Set(runs.map(\.id)))
        XCTAssertTrue(model.lastDeletedRunIDs.isEmpty)
        XCTAssertTrue(model.deletedRuns.isEmpty)
        XCTAssertEqual(model.runs.first(where:{$0.id == removing[0].id})?.samples,removing[0].samples)
        let reopened = AppModel(motionSource:SimulatedTrackMotionSource(),store:RunStore(directory:directory))
        defer { reopened.shutdown() }
        XCTAssertEqual(Set(reopened.runs.map(\.id)),Set(runs.map(\.id)))
    }

    func testABlockedRemovalKeepsThatRecordingWhileTheOthersStillGo() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let runs = (0..<3).map { fixtureRun(car:"Car \($0)",minutesAgo:Double($0)*10) }
        let store = RunStore(directory:directory)
        let model = try model(with:runs,in:directory)
        defer { model.shutdown() }
        // An existing deleted file with the same ID blocks only that recording's removal.
        let blocked = runs[1]
        try FileManager.default.createDirectory(at:store.recentlyDeletedDirectory,withIntermediateDirectories:true)
        try Data("{}".utf8).write(to:store.recentlyDeletedDirectory.appendingPathComponent(blocked.id.uuidString).appendingPathExtension("json"))
        XCTAssertEqual(model.deleteRecordings(model.runs),2)
        XCTAssertEqual(model.runs.map(\.id),[blocked.id])
        XCTAssertFalse(model.lastDeletedRunIDs.contains(blocked.id))
        XCTAssertEqual(model.lastDeletedRunIDs.count,2)
        let message = try XCTUnwrap(model.errorMessage)
        XCTAssertTrue(message.contains(blocked.displayName),message)
        XCTAssertTrue(FileManager.default.fileExists(atPath:directory.appendingPathComponent(blocked.id.uuidString).appendingPathExtension("json").path))
    }

    func testDeletingClearsComparisonSelectionAndMovesTheOpenRun() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let runs = (0..<3).map { fixtureRun(car:"Car \($0)",minutesAgo:Double($0)*10) }
        let model = try model(with:runs,in:directory)
        defer { model.shutdown() }
        model.prepareComparison()
        let deadline = Date().addingTimeInterval(20)
        while !model.analysingIDs.isEmpty && Date()<deadline { try await Task.sleep(nanoseconds:20_000_000) }
        let removing = Array(model.runs.prefix(2))
        removing.forEach { model.setCompared($0,selected:true) }
        XCTAssertEqual(model.comparedRunIDs.count,2)
        model.selectedRunID = removing[0].id
        model.deleteRecordings(removing)
        XCTAssertTrue(model.comparedRunIDs.isEmpty)
        XCTAssertEqual(model.selectedRunID,runs[2].id)
        removing.forEach { XCTAssertNil(model.analyses[$0.id]) }
    }

    func testStateReportsRawOnlyOnlyWhenNoCalibrationWasSaved() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let store = RunStore(directory:directory)
        var rawOnly = fixtureRun(car:"Raw")
        rawOnly.calibration = nil
        try store.save(rawOnly)
        let model = AppModel(motionSource:SimulatedTrackMotionSource(),store:store)
        defer { model.shutdown() }
        let saved = try XCTUnwrap(model.runs.first)
        if case .rawOnly = model.reconstructionState(saved) {} else { XCTFail("Expected a raw-only recording") }
        XCTAssertFalse(model.reconstructionState(saved).isReady)
        XCTAssertEqual(model.fileURL(for:saved).lastPathComponent,"\(saved.id.uuidString).json")
    }
}

import XCTest
import PodTrackCore
@testable import PodTrack

@MainActor final class AppStateTests: XCTestCase {
    func testPausedPlotsAndClearedBufferDoNotLoseRecordedSamples() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at:directory) }
        let source = TestMotionSource()
        let model = AppModel(motionSource:source,store:RunStore(directory:directory))
        model.selectBud(.left)
        model.recordRawOnly = true
        model.startMotion(); source.emit(.init(timestamp:1,sensorLocation:.left))
        model.startRecording()
        XCTAssertTrue(model.recording)
        model.isDashboardPaused = true
        for i in 1...10 {
            source.emit(.init(timestamp:1+Double(i)/50,sensorLocation:.left))
            if i == 5 { model.clearBuffer() }
        }
        model.finishRecording()
        XCTAssertEqual(model.runs.first?.samples.count,10)
        XCTAssertNil(model.runs.first?.calibration)
        XCTAssertEqual(try model.store.load().runs.first?.samples.count,10)
        model.shutdown()
    }
    func testBudSwitchPreservesPrefixAndSavedCalibration() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at:directory) }
        let source = TestMotionSource()
        let store = try calibratedLibrary(in:directory,side:.left)
        let model = AppModel(motionSource:source,store:store)
        model.selectBud(.left)
        model.startMotion(); source.emit(.init(timestamp:1,sensorLocation:.left))
        let original = model.calibration
        model.startRecording()
        source.emit(.init(timestamp:1.02,sensorLocation:.left))
        source.emit(.init(timestamp:1.04,sensorLocation:.right))
        XCTAssertFalse(model.recording)
        XCTAssertEqual(model.calibration,original)
        XCTAssertEqual(model.runs.first?.samples.map(\.sensorLocation),[.left])
        XCTAssertTrue(model.runs.first?.recordingNotes.contains(where:{$0.contains("bud changed")}) == true)
        model.shutdown()
    }
    func testCannotStartRecordingWithoutFreshMotion() {
        let source = TestMotionSource()
        let model = AppModel(motionSource:source,store:RunStore(directory:temporaryDirectory()))
        model.recordRawOnly = true; model.startRecording()
        XCTAssertFalse(model.recording)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertTrue(model.runs.isEmpty)
        model.shutdown()
    }
    func testSimulationTimerRecordsPersistsAndAnalyzesThroughAppModel() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at:directory) }
        let model = AppModel(motionSource:SimulatedTrackMotionSource(),store:RunStore(directory:directory))
        model.selectReconstructionMethod(.old)
        model.recordSimulation()
        XCTAssertTrue(model.recording)
        // The real simulation source sends one sample per 20 ms on the run loop.
        let deadline = Date().addingTimeInterval(12)
        while (model.recording || model.selectedAnalysis == nil) && Date()<deadline {
            try await Task.sleep(nanoseconds:50_000_000)
        }
        XCTAssertFalse(model.recording)
        let run = try XCTUnwrap(model.runs.first)
        XCTAssertEqual(run.source,.simulation)
        XCTAssertEqual(run.samples.count,341)
        XCTAssertEqual(try model.store.load().runs.first?.samples.count,341)
        let analysis = try XCTUnwrap(model.selectedAnalysis)
        XCTAssertEqual(model.reconstructionMethod,.improved)
        XCTAssertEqual(analysis.algorithmVersion,ImprovedReconstruction.version)
        XCTAssertEqual(analysis.groundZ,0,accuracy:1e-8)
        XCTAssertNil(run.metadata.verticalDrop)
        XCTAssertNil(try model.store.load().runs.first?.metadata.verticalDrop)
        XCTAssertTrue(analysis.isRelative)
        XCTAssertEqual(analysis.metrics.estimatedPathLength,1,accuracy:1e-8)
        XCTAssertEqual(model.area,.analysis)
        model.shutdown()
    }
    func testCaptureIgnoresTheSteadyPoseFromBeforeTheClick() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at:directory) }
        let source = TestMotionSource()
        let model = AppModel(motionSource:source,store:RunStore(directory:directory))
        defer { model.shutdown() }
        model.startMotion()
        emitPose(source,side:.right,gravity:.init(0,0,-1),time:1)
        model.captureLevelPose(); model.retryCapture()
        XCTAssertFalse(model.hasLevelPose)
        // The position held AFTER the click becomes the captured reference.
        let newGravity = Vector3(-0.5,0,-sqrt(0.75))
        emitPose(source,side:.right,gravity:newGravity,time:2)
        model.retryCapture()
        XCTAssertTrue(model.hasLevelPose)
        XCTAssertEqual((model.savedLevelGravity!-newGravity).length,0,accuracy:1e-8)
    }
    func testExpiredCaptureCannotCommitLateArrivingValidPose() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at:directory) }
        let source = TestMotionSource()
        let model = AppModel(motionSource:source,store:RunStore(directory:directory))
        defer { model.shutdown() }
        model.startMotion(); model.captureLevelPose()
        emitPose(source,side:.right,gravity:.init(0,0,-1),time:1)
        model.retryCapture(now:ProcessInfo.processInfo.systemUptime+7)
        XCTAssertFalse(model.hasLevelPose)
        XCTAssertNil(model.captureStatus)
        XCTAssertTrue(model.errorMessage?.contains("timed out") == true)
    }

    func testLiveTiltUsesNewestSampleWithoutWindowLagOrSettling() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at:directory) }
        let source = TestMotionSource()
        let model = AppModel(motionSource:source,store:RunStore(directory:directory))
        defer { model.shutdown() }
        model.startMotion()
        model.captureLevelPose()
        emitPose(source,side:.right,gravity:.init(0,0,-1),time:1)
        model.retryCapture()
        source.emit(.init(timestamp:2,gravity:.init(-0.5,0,-sqrt(0.75)),sensorLocation:.right))
        XCTAssertEqual(model.calibrationTiltDegrees ?? -1,30,accuracy:0.001)
        // The capture window still contains old and new poses, but the live view
        // must show this step immediately and never decay back on its own.
        XCTAssertTrue(model.calibrationFeedback.contains("moved"))
        XCTAssertEqual(model.calibrationTiltDegrees ?? -1,30,accuracy:0.001)
        source.emit(.init(timestamp:2.02,gravity:.init(0,0,-1),sensorLocation:.right))
        XCTAssertEqual(model.calibrationTiltDegrees ?? -1,0,accuracy:0.001)
    }
    func testBatchedDeliveryRecordsEverySampleAndShowsOnlyNewest() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at:directory) }
        let source = TestMotionSource()
        let model = AppModel(motionSource:source,store:RunStore(directory:directory))
        defer { model.shutdown() }
        model.startMotion(); model.recordRawOnly = true
        source.emit(.init(timestamp:1,sensorLocation:.right))
        model.startRecording()
        let samples = (1...100).map { MotionSample(timestamp:1+Double($0)/50,sensorLocation:.right) }
        source.onSamples?(samples.map { MotionDelivery(sample:$0) })
        XCTAssertEqual(model.latest,samples.last)
        XCTAssertEqual(model.liveMotion.sample,samples.last)
        XCTAssertEqual(model.sampleCount,101)
        model.finishRecording()
        XCTAssertEqual(model.runs.first?.samples,samples)
    }
    func testDelayedCallbacksAndDeliveryBacklogCannotBeCalibrated() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at:directory) }
        let source = TestMotionSource()
        let model = AppModel(motionSource:source,store:RunStore(directory:directory))
        defer { model.shutdown() }
        model.startMotion()
        let now = ProcessInfo.processInfo.systemUptime
        source.onSamples?([.init(sample:.init(timestamp:10,sensorLocation:.right),receivedAt:now-4)])
        XCTAssertFalse(model.hasFreshMotion)
        XCTAssertGreaterThanOrEqual(model.uiDeliveryDelay ?? 0,4)
        source.onSamples?([.init(sample:.init(timestamp:10.02,sensorLocation:.right),receivedAt:now)])
        XCTAssertTrue(model.hasDeliveryBacklog)
        XCTAssertFalse(model.hasFreshMotion)
        model.captureLevelPose()
        XCTAssertFalse(model.hasLevelPose)
        XCTAssertTrue(model.captureStatus?.contains("late") == true)
        model.retryMotion()
        XCTAssertFalse(model.hasDeliveryBacklog)
        XCTAssertNil(model.liveMotion.sample)
    }
    func testRecordingBoundariesFlushPendingCallbacks() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at:directory) }
        let source = TestMotionSource()
        let model = AppModel(motionSource:source,store:RunStore(directory:directory))
        defer { model.shutdown() }
        model.startMotion(); model.recordRawOnly = true
        source.pending = [.init(sample:.init(timestamp:1,sensorLocation:.right))]
        model.startRecording()
        XCTAssertTrue(model.recording)
        source.pending = [.init(sample:.init(timestamp:1.02,sensorLocation:.right))]
        model.finishRecording()
        XCTAssertEqual(model.runs.first?.samples.map(\.timestamp),[1.02])
    }
    func testBudSwitchInsideBatchPreservesOnlyTheMatchingPrefix() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at:directory) }
        let source = TestMotionSource()
        let model = AppModel(motionSource:source,store:RunStore(directory:directory))
        defer { model.shutdown() }
        model.startMotion(); model.recordRawOnly = true
        source.emit(.init(timestamp:1,sensorLocation:.right)); model.startRecording()
        source.onSamples?([
            .init(sample:.init(timestamp:1.02,sensorLocation:.right)),
            .init(sample:.init(timestamp:1.04,sensorLocation:.left)),
            .init(sample:.init(timestamp:1.06,sensorLocation:.left))
        ])
        XCTAssertFalse(model.recording)
        XCTAssertEqual(model.runs.first?.samples.map(\.timestamp),[1.02])
        XCTAssertEqual(model.latest?.timestamp,1.06)
        XCTAssertEqual(model.latest?.sensorLocation,.left)
    }

    func testMailboxCoalescesWithoutLosingOrderAndRejectsOldSession() {
        let mailbox = MotionDeliveryMailbox()
        for i in 0..<150 {
            let needsDrain = mailbox.enqueue(.init(sample:.init(timestamp:Double(i))))
            XCTAssertEqual(needsDrain,i == 0)
        }
        let batch = mailbox.drain(releaseSchedule:false)
        XCTAssertFalse(mailbox.enqueue(.init(sample:.init(timestamp:149.5))))
        XCTAssertEqual(mailbox.drain().samples.count,1)
        XCTAssertEqual(batch.samples.map { $0.sample.timestamp },(0..<150).map(Double.init))
        XCTAssertTrue(mailbox.enqueue(.init(sample:.init(timestamp:150))))
        mailbox.invalidate()
        XCTAssertFalse(mailbox.enqueue(.init(sample:.init(timestamp:151))))
        XCTAssertTrue(mailbox.drain().samples.isEmpty)
    }

    func testCaptureRetriesUntilFreshSteadySamplesArrive() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at:directory) }
        let source = TestMotionSource()
        let model = AppModel(motionSource:source,store:RunStore(directory:directory))
        defer { model.shutdown() }
        model.startMotion()
        model.captureLevelPose()
        XCTAssertNotNil(model.captureStatus)
        XCTAssertNil(model.errorMessage)
        for i in 0...30 { source.emit(.init(timestamp:1+Double(i)/50,sensorLocation:.right)) }
        model.retryCapture()
        XCTAssertTrue(model.hasLevelPose)
        XCTAssertNil(model.captureStatus)

        XCTAssertTrue(model.calibrationFeedback.contains("0.0°"))
        XCTAssertTrue(model.calibrationFeedback.contains("Pose is steady."))
        // The unchanged level pose is not a valid nose-up pose.
        model.captureNosePose()
        XCTAssertNotNil(model.captureStatus)
        XCTAssertNil(model.errorMessage)
        model.retryCapture(now:ProcessInfo.processInfo.systemUptime+7)
        XCTAssertNil(model.captureStatus)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertTrue(model.hasLevelPose)
        XCTAssertNil(model.calibration)

        model.captureNosePose()
        model.selectBud(.left)
        XCTAssertNil(model.captureStatus)
        XCTAssertFalse(model.hasLevelPose)

        model.selectBud(.right)
        model.captureLevelPose()
        emitPose(source,side:.right,gravity:.init(0,0,-1),time:3)
        model.retryCapture()
        model.captureNosePose()
        XCTAssertNotNil(model.captureStatus)
        emitPose(source,side:.right,gravity:.init(-0.5,0,-sqrt(0.75)),time:4)
        XCTAssertEqual(model.calibrationTiltDegrees ?? -1,30,accuracy:0.01)
        model.sampleAge = 2
        XCTAssertNil(model.calibrationTiltDegrees)
        XCTAssertNil(model.liveCalibrationGravity)
        XCTAssertNotNil(model.savedLevelGravity)
        model.sampleAge = 0
        XCTAssertTrue(model.calibrationFeedback.contains("30.0°"))
        model.retryCapture()
        XCTAssertNotNil(model.calibration)
        XCTAssertNil(model.captureStatus)
        XCTAssertNil(model.errorMessage)
    }

    func testRightIsDefaultAndLeftMotionCannotBeRecordedOrCalibrated() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at:directory) }
        let source = TestMotionSource()
        let app = AppModel(motionSource:source,store:RunStore(directory:directory))
        defer { app.shutdown() }
        XCTAssertEqual(app.selectedBud,.right)
        XCTAssertEqual(app.area,.record)
        app.startMotion()
        for i in 0...30 { source.emit(.init(timestamp:1+Double(i)/50,sensorLocation:.left)) }
        XCTAssertTrue(app.hasFreshMotion)
        XCTAssertFalse(app.hasFreshSelectedMotion)
        XCTAssertEqual(app.headphoneLinkState,.wrongBud)
        XCTAssertEqual(app.latest?.sensorLocation,.left)
        app.recordRawOnly = true
        app.startRecording()
        XCTAssertFalse(app.recording)
        app.captureLevelPose()
        XCTAssertFalse(app.hasLevelPose)
        XCTAssertTrue(app.runs.isEmpty)
        source.emit(.init(timestamp:1.62,sensorLocation:.right))
        XCTAssertTrue(app.hasFreshSelectedMotion)
        app.startRecording(); source.emit(.init(timestamp:1.64,sensorLocation:.right)); app.finishRecording()
        XCTAssertEqual(app.runs.first?.samples.map(\.sensorLocation),[.right])
    }
    func testLeftSelectorUsesLeftSamplesAndClearsOldCalibration() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at:directory) }
        let source = TestMotionSource()
        let store = try calibratedLibrary(in:directory,side:.right)
        let model = AppModel(motionSource:source,store:store)
        defer { model.shutdown() }
        model.startMotion(); source.emit(.init(timestamp:1,sensorLocation:.left))
        XCTAssertEqual(model.calibration?.sensorLocation,.right)
        model.selectBud(.left)
        XCTAssertNil(model.calibration)
        XCTAssertFalse(model.hasLevelPose)
        XCTAssertTrue(model.history.isEmpty)
        model.captureLevelPose()
        for i in 1...30 { source.emit(.init(timestamp:1+Double(i)/50,sensorLocation:.left)) }
        XCTAssertTrue(model.hasFreshSelectedMotion)
        XCTAssertEqual(model.headphoneLinkState,.receiving)
        model.retryCapture()
        XCTAssertTrue(model.hasLevelPose)
        model.recordRawOnly = true; model.startRecording()
        XCTAssertTrue(model.recording)
        model.selectBud(.right)
        XCTAssertEqual(model.selectedBud,.left,"Changing buds is blocked during a recording")
        source.emit(.init(timestamp:1.62,sensorLocation:.left))
        source.emit(.init(timestamp:1.64,sensorLocation:.left))
        model.finishRecording()
        XCTAssertEqual(model.runs.first?.samples.map(\.sensorLocation),[.left,.left])
    }
    func testConnectionStatesDistinguishRequestsAndActualSamples() {
        let source = TestMotionSource()
        let model = AppModel(motionSource:source,store:RunStore(directory:temporaryDirectory()))
        defer { model.shutdown() }
        XCTAssertEqual(model.headphoneLinkState,.idle)
        model.startMotion(); source.status.connected = false; source.refreshStatus()
        XCTAssertEqual(model.headphoneLinkState,.searching)
        source.status.connected = true; source.refreshStatus()
        XCTAssertEqual(model.headphoneLinkState,.waitingForMotion)
        source.emit(.init(timestamp:1,sensorLocation:.right))
        XCTAssertEqual(model.headphoneLinkState,.receiving)
        model.sampleAge = 1.5
        XCTAssertEqual(model.headphoneLinkState,.stale)
        source.status.connected = false; source.status.active = false; source.refreshStatus()
        XCTAssertEqual(model.headphoneLinkState,.searching)
        model.stopMotion()
        XCTAssertEqual(model.headphoneLinkState,.idle)
        source.status.authorization = "Denied"; source.refreshStatus()
        XCTAssertEqual(model.headphoneLinkState,.permissionBlocked)
    }
    func testUnknownSideCannotBypassSelectionWithRawOnlyRecording() {
        let source = TestMotionSource()
        let model = AppModel(motionSource:source,store:RunStore(directory:temporaryDirectory()))
        defer { model.shutdown() }
        model.startMotion(); source.emit(.init(timestamp:1,sensorLocation:.unknown))
        XCTAssertEqual(model.headphoneLinkState,.unidentified)
        model.recordRawOnly = true; model.startRecording()
        XCTAssertFalse(model.recording)
        XCTAssertTrue(model.runs.isEmpty)
    }
    func testAutomaticConnectionOnlyUsesAnExistingPermissionOnce() {
        let source = TestMotionSource()
        let model = AppModel(motionSource:source,store:RunStore(directory:temporaryDirectory()))
        defer { model.shutdown() }
        source.status.authorization = "Authorized"; source.refreshStatus()
        model.startAuthorizedMotionIfNeeded()
        XCTAssertTrue(model.status.requested)
        model.stopMotion(); model.startAuthorizedMotionIfNeeded()
        XCTAssertFalse(model.status.requested)
        let notAuthorized = TestMotionSource()
        let other = AppModel(motionSource:notAuthorized,store:RunStore(directory:temporaryDirectory()))
        defer { other.shutdown() }
        other.startAuthorizedMotionIfNeeded()
        XCTAssertFalse(other.status.requested)
    }
    func testRetryDropsStaleSamplesAndPreservesSavedMount() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at:directory) }
        let source = TestMotionSource()
        let store = try calibratedLibrary(in:directory,side:.right)
        let model = AppModel(motionSource:source,store:store)
        defer { model.shutdown() }
        model.startMotion(); source.emit(.init(timestamp:1,sensorLocation:.right))
        let original = model.calibration
        model.retryMotion()
        XCTAssertNil(model.latest)
        XCTAssertNil(model.sampleAge)
        XCTAssertEqual(model.sampleCount,0)
        XCTAssertEqual(model.calibration,original)
        XCTAssertFalse(model.hasLevelPose)
        XCTAssertFalse(model.hasFreshSelectedMotion)
        XCTAssertTrue(model.status.requested)
    }
    func testDifferentLeftAndRightMountsSurviveRelaunchAndRecordTheirOwnSnapshots() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at:directory) }
        let store = RunStore(directory:directory)
        let source = TestMotionSource()
        let model = AppModel(motionSource:source,store:store)
        model.startMotion()
        captureMount(model,source:source,side:.right,forward:.unitX,time:1)
        let right = try XCTUnwrap(model.calibration)
        captureMount(model,source:source,side:.left,forward:.unitY,time:4)
        let left = try XCTUnwrap(model.calibration)
        XCTAssertEqual(right.forwardDevice.x,1,accuracy:1e-8)
        XCTAssertEqual(left.forwardDevice.y,1,accuracy:1e-8)
        XCTAssertEqual(model.calibrationProfiles.count,2)
        XCTAssertTrue(model.unsavedCalibrationSides.isEmpty)
        XCTAssertEqual(model.calibrationStore.load().calibrations.count,2)

        model.startRecording(); source.emit(.init(timestamp:6,sensorLocation:.left)); model.finishRecording()
        let leftRun = try XCTUnwrap(model.runs.first)
        XCTAssertEqual(leftRun.calibration,left)
        XCTAssertTrue(leftRun.displayName.contains("Left AirPod"))
        model.selectBud(.right)
        XCTAssertEqual(model.calibration,right)
        model.startRecording()
        XCTAssertFalse(model.recording,"Loading a saved profile cannot bypass the actual streaming-side guard")
        source.emit(.init(timestamp:7,sensorLocation:.right))
        model.startRecording(); source.emit(.init(timestamp:7.02,sensorLocation:.right))
        model.selectBud(.left); model.recalibrateSelectedBud(); model.captureLevelPose()
        XCTAssertEqual(model.selectedBud,.right,"The recorded side and calibration cannot change mid-run")
        XCTAssertEqual(model.calibration,right)
        model.finishRecording()
        let rightRun = try XCTUnwrap(model.runs.first)
        XCTAssertEqual(rightRun.calibration,right)
        XCTAssertTrue(rightRun.displayName.contains("Right AirPod"))
        XCTAssertTrue(leftRun.displayName.contains("Left AirPod"),"A later selection cannot rename historical runs")
        model.shutdown()

        let next = AppModel(motionSource:TestMotionSource(),store:store)
        defer { next.shutdown() }
        XCTAssertEqual(next.selectedBud,.right)
        XCTAssertEqual(next.calibration?.forwardDevice,right.forwardDevice)
        next.selectBud(.left)
        XCTAssertEqual(next.calibration?.forwardDevice,left.forwardDevice)
        XCTAssertEqual(Set(next.runs.map(\.recordedOrigin)),[.left,.right])
        let before = try Data(contentsOf:directory.appendingPathComponent(leftRun.id.uuidString+".json"))
        next.recalibrateSelectedBud()
        XCTAssertNil(next.calibration)
        XCTAssertNotNil(next.calibrationProfiles[.right])
        XCTAssertNil(next.calibrationStore.load().calibrations[.left])
        XCTAssertEqual(try Data(contentsOf:directory.appendingPathComponent(leftRun.id.uuidString+".json")),before)
    }

    func testUnfinishedPoseDoesNotMixSidesOrRestoreReplacedMount() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at:directory) }
        let source = TestMotionSource()
        let model = AppModel(motionSource:source,store:try calibratedLibrary(in:directory,side:.right))
        defer { model.shutdown() }
        model.startMotion()
        model.captureLevelPose()
        emitPose(source,side:.right,gravity:.init(0,0,-1),time:1)
        model.retryCapture()
        XCTAssertTrue(model.hasLevelPose)
        XCTAssertNil(model.calibrationProfiles[.right])
        model.selectBud(.left)
        emitPose(source,side:.left,gravity:.init(0,-0.5,-sqrt(0.75)),time:3)
        model.captureNosePose()
        XCTAssertNil(model.calibration,"Left nose-up must not combine with a Right level pose")
        model.selectBud(.right); model.retryMotion()
        XCTAssertFalse(model.hasLevelPose)
        XCTAssertNil(model.calibration,"An unfinished replacement must not reload the old mount")
        XCTAssertTrue(model.calibrationStore.load().calibrations.isEmpty)
    }

    func testCalibrationSaveFailureRetainsBothSessionProfileAndRetryAcrossSwitches() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at:directory) }
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let blocked = directory.appendingPathComponent("Calibrations")
        try Data("file blocks the calibration directory".utf8).write(to:blocked)
        let source = TestMotionSource()
        let model = AppModel(motionSource:source,store:RunStore(directory:directory))
        defer { model.shutdown() }
        model.startMotion()
        captureMount(model,source:source,side:.right,forward:.unitX,time:1)
        let profile = try XCTUnwrap(model.calibration)
        XCTAssertTrue(model.unsavedCalibrationSides.contains(.right))
        XCTAssertTrue(model.errorMessage?.contains("could not be saved") == true)
        model.selectBud(.left); model.selectBud(.right)
        XCTAssertEqual(model.calibration,profile)
        try FileManager.default.removeItem(at:blocked)
        model.saveCalibration(for:.right)
        XCTAssertTrue(model.unsavedCalibrationSides.isEmpty)
        XCTAssertEqual(model.calibrationStore.load().calibrations[.right]?.forwardDevice,profile.forwardDevice)
    }

    private func captureMount(_ model: AppModel, source: TestMotionSource, side: RecordingBud, forward: Vector3, time: Double) {
        model.selectBud(side)
        source.emit(.init(timestamp:time-0.02,sensorLocation:side.location))
        model.captureLevelPose()
        emitPose(source,side:side.location,gravity:.init(0,0,-1),time:time)
        model.retryCapture()
        model.captureNosePose()
        emitPose(source,side:side.location,gravity:forward * -0.5 + Vector3(0,0,-sqrt(0.75)),time:time+1)
        model.retryCapture()
    }
    private func emitPose(_ source: TestMotionSource, side: SensorLocation, gravity: Vector3, time: Double) {
        for index in 0..<50 { source.emit(.init(timestamp:time+Double(index)/50,gravity:gravity,sensorLocation:side)) }
    }
    private func calibratedLibrary(in directory: URL, side: SensorLocation) throws -> RunStore {
        let calibration = MountCalibration(forwardDevice:.unitX,upDevice:.unitZ,sensorLocation:side,source:.airPods)
        try CalibrationStore(directory:directory.appendingPathComponent("Calibrations")).save(calibration)
        return RunStore(directory:directory)
    }
    private func temporaryDirectory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("PodTrackTests-"+UUID().uuidString) }
}

@MainActor private final class TestMotionSource: MotionSource {
    let kind: SourceKind = .airPods
    var status = MotionSourceStatus()
    var onSamples: (([MotionDelivery]) -> Void)?
    var onStatus: ((MotionSourceStatus) -> Void)?
    var onEvent: ((String) -> Void)?
    func start() { status.active = true; status.requested = true; status.available = true; status.connected = true; status.authorization = "Authorized"; refreshStatus() }
    func stop() { status.active = false; status.requested = false; refreshStatus() }
    func refreshStatus() { onStatus?(status) }
    var pending: [MotionDelivery] = []
    func flushPendingSamples() {
        let samples = pending; pending = []
        if !samples.isEmpty { onSamples?(samples) }
    }
    func emit(_ sample: MotionSample) { onSamples?([.init(sample:sample)]) }
}

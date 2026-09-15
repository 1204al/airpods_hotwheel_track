import XCTest
import PodTrackCore
@testable import PodTrack

@MainActor final class HeadphoneConnectionTests: XCTestCase {
    func testRetryReplacesActiveManagerAndIgnoresOldCallbacks() throws {
        let fixture = SessionFixture()
        let source = fixture.source()
        var samples: [MotionSample] = []
        source.onSamples = { samples += $0.map(\.sample) }
        source.start()
        let old = try XCTUnwrap(fixture.sessions.last)
        let oldConnection = try XCTUnwrap(old.onConnectionChange)
        let oldMotion = try XCTUnwrap(old.handler)
        old.remainsActiveAfterStop = true
        old.emit(.init(timestamp:1,sensorLocation:.right)) // queued before retry
        source.stop(); source.start()
        let current = try XCTUnwrap(fixture.sessions.last)
        XCTAssertFalse(old === current)
        XCTAssertTrue(old.isActive, "Reproduce an old manager whose active flag has not cleared")
        XCTAssertEqual(current.motionStarts,1)
        current.onConnectionChange?(true)
        oldConnection(false) // delegate already queued before invalidation
        oldMotion(.init(timestamp:2,sensorLocation:.right),nil)
        current.emit(.init(timestamp:3,sensorLocation:.left))
        source.flushPendingSamples()
        XCTAssertTrue(source.status.connected)
        XCTAssertTrue(source.status.active)
        XCTAssertEqual(current.motionStops,0)
        XCTAssertEqual(samples.map(\.timestamp),[3])
        source.stop()
    }

    func testAvailabilityTransitionStartsWithoutAnotherConnectionEvent() throws {
        let fixture = SessionFixture(); fixture.available = false
        let source = fixture.source()
        source.start()
        let session = try XCTUnwrap(fixture.sessions.last)
        session.onConnectionChange?(true)
        XCTAssertEqual(session.motionStarts,0)
        session.isAvailable = true
        source.refreshStatus(); source.refreshStatus()
        XCTAssertEqual(session.motionStarts,1)
        source.stop()
    }

    func testNoDataTimeoutKeepsListeningAndRecoversOnAValidSample() throws {
        let fixture = SessionFixture()
        let source = fixture.source()
        var events: [String] = []
        source.onEvent = { events.append($0) }
        source.start()
        fixture.now = 109.9; source.refreshStatus()
        XCTAssertFalse(source.status.noMotionTimedOut)
        fixture.now = 110; source.refreshStatus()
        XCTAssertTrue(source.status.noMotionTimedOut)
        XCTAssertEqual(source.status.waitingSeconds,10)
        fixture.now = 125; source.refreshStatus()
        XCTAssertEqual(events.filter { $0.contains("No motion samples after") }.count,1)
        let session = try XCTUnwrap(fixture.sessions.last)
        XCTAssertEqual(session.motionStarts,1, "A timeout must not churn the hardware session")
        session.emit(.init(timestamp:1,sensorLocation:.left))
        source.flushPendingSamples()
        XCTAssertFalse(source.status.noMotionTimedOut)
        XCTAssertEqual(source.status.waitingSeconds,0)
        fixture.now = 150; source.refreshStatus()
        XCTAssertFalse(source.status.noMotionTimedOut)
        source.stop()
    }

    func testInvalidSamplesDoNotEndFirstSampleWait() throws {
        let fixture = SessionFixture()
        let source = fixture.source()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let model = AppModel(motionSource:source,store:RunStore(directory:directory))
        defer { model.shutdown() }
        model.selectBud(.left); model.startMotion()
        let session = try XCTUnwrap(fixture.sessions.last)
        session.onConnectionChange?(true)
        session.emit(.init(timestamp:1,gravity:.zero,sensorLocation:.left))
        source.flushPendingSamples()
        fixture.now = 111; source.refreshStatus()
        XCTAssertEqual(model.headphoneLinkState,.noMotion)
        XCTAssertEqual(model.sampleCount,0)
        XCTAssertEqual(model.invalidSampleCount,1)
        XCTAssertFalse(model.hasFreshSelectedMotion)
        let report = model.connectionDiagnosticReport
        XCTAssertTrue(report.contains("Required side: left"))
        XCTAssertTrue(report.contains("Motion authorization: Authorized"))
        XCTAssertTrue(report.contains("Accepted samples: 0"))
        XCTAssertTrue(report.contains("Invalid samples rejected: 1"))
        XCTAssertTrue(report.contains("Waiting for first valid sample: 11 s"))
        session.emit(.init(timestamp:2,sensorLocation:.left))
        source.flushPendingSamples()
        XCTAssertEqual(model.headphoneLinkState,.receiving)
        XCTAssertTrue(model.hasFreshSelectedMotion)
        model.retryMotion()
        XCTAssertEqual(model.invalidSampleCount,0)
        XCTAssertEqual(model.sampleCount,0)
    }

    func testMotionErrorBlocksReadinessUntilCleanValidDelivery() throws {
        let fixture = SessionFixture()
        let source = fixture.source()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let model = AppModel(motionSource:source,store:RunStore(directory:directory))
        defer { model.shutdown() }
        model.startMotion()
        let session = try XCTUnwrap(fixture.sessions.last)
        session.emit(.init(timestamp:1,sensorLocation:.right),error:"TestMotionError (42): interrupted")
        source.flushPendingSamples()
        XCTAssertEqual(model.headphoneLinkState,.motionError)
        XCTAssertFalse(model.hasFreshMotion)
        XCTAssertTrue(model.connectionDiagnosticReport.contains("TestMotionError (42): interrupted"))
        session.emit(.init(timestamp:2,gravity:.zero,sensorLocation:.right))
        source.flushPendingSamples()
        XCTAssertNotNil(source.status.motionError)
        session.emit(.init(timestamp:3,sensorLocation:.right))
        source.flushPendingSamples()
        XCTAssertNil(source.status.motionError)
        XCTAssertEqual(model.headphoneLinkState,.receiving)
    }

    func testStopCancelsWaitAndDoesNotRestartFromLateDelegate() throws {
        let fixture = SessionFixture()
        let source = fixture.source()
        source.start()
        let session = try XCTUnwrap(fixture.sessions.last)
        let callback = try XCTUnwrap(session.onConnectionChange)
        source.stop()
        callback(true)
        fixture.now = 150; source.refreshStatus()
        XCTAssertFalse(source.status.requested)
        XCTAssertFalse(source.status.active)
        XCTAssertFalse(source.status.connected)
        XCTAssertFalse(source.status.noMotionTimedOut)
        XCTAssertEqual(source.status.waitingSeconds,0)
        XCTAssertEqual(session.motionStarts,1)
    }

    func testDisconnectWaitsBeforeRequestingAgain() throws {
        let fixture = SessionFixture()
        let source = fixture.source()
        source.start()
        let session = try XCTUnwrap(fixture.sessions.last)
        session.onConnectionChange?(false)
        source.refreshStatus()
        XCTAssertEqual(session.motionStarts,1)
        fixture.now = 100.9; source.refreshStatus()
        XCTAssertEqual(session.motionStarts,1)
        fixture.now = 101; source.refreshStatus()
        XCTAssertEqual(session.motionStarts,2)
        source.stop()
    }

    func testPermissionPromptTimeDoesNotConsumeFirstSampleDeadline() throws {
        let fixture = SessionFixture(); fixture.authorization = "Not determined"
        let source = fixture.source()
        source.start()
        fixture.now = 150; source.refreshStatus()
        XCTAssertFalse(source.status.noMotionTimedOut)
        let session = try XCTUnwrap(fixture.sessions.last)
        session.authorization = "Authorized"; source.refreshStatus()
        XCTAssertEqual(source.status.waitingSeconds,0)
        fixture.now = 160; source.refreshStatus()
        XCTAssertTrue(source.status.noMotionTimedOut)
        source.stop()
    }

    func testDeniedPermissionDoesNotStartHardwareAndRevocationStopsIt() throws {
        let fixture = SessionFixture(); fixture.authorization = "Denied"
        let source = fixture.source()
        source.start()
        let denied = try XCTUnwrap(fixture.sessions.last)
        XCTAssertEqual(denied.motionStarts,0)
        XCTAssertEqual(denied.connectionStarts,0)
        XCTAssertFalse(source.status.requested)
        fixture.authorization = "Authorized"; source.start()
        let allowed = try XCTUnwrap(fixture.sessions.last)
        XCTAssertTrue(source.status.active)
        allowed.authorization = "Denied"; source.refreshStatus()
        XCTAssertFalse(source.status.active)
        XCTAssertFalse(source.status.requested)
        XCTAssertEqual(allowed.motionStops,1)
        XCTAssertEqual(source.status.authorization,"Denied")
    }
}

@MainActor private final class SessionFixture {
    var now: TimeInterval = 100
    var available = true
    var authorization = "Authorized"
    var sessions: [FakeHeadphoneSession] = []
    func source() -> AirPodsMotionSource {
        AirPodsMotionSource(sessionFactory: {
            let session = FakeHeadphoneSession()
            session.isAvailable = self.available
            session.authorization = self.authorization
            self.sessions.append(session)
            return session
        },uptime: { self.now })
    }
}

@MainActor private final class FakeHeadphoneSession: HeadphoneMotionSession {
    var authorization = "Authorized"
    var isAvailable = true
    var isActive = false
    var remainsActiveAfterStop = false
    var onConnectionChange: ((Bool) -> Void)?
    var handler: ((MotionSample?, String?) -> Void)?
    var motionStarts = 0
    var motionStops = 0
    var connectionStarts = 0
    func startConnectionUpdates() { connectionStarts += 1 }
    func stopConnectionUpdates() {}
    func startMotionUpdates(to queue: OperationQueue, handler: @escaping (MotionSample?, String?) -> Void) {
        motionStarts += 1; isActive = true; self.handler = handler
    }
    func stopMotionUpdates() {
        motionStops += 1
        if !remainsActiveAfterStop { isActive = false }
    }
    func emit(_ sample: MotionSample?, error: String? = nil) { handler?(sample,error) }
}

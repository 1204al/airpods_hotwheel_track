import Foundation
import PodTrackCore

@MainActor final class AirPodsMotionSource: MotionSource {
    let kind: SourceKind = .airPods
    private let sessionFactory: @MainActor () -> any HeadphoneMotionSession
    private let uptime: () -> TimeInterval
    private var session: any HeadphoneMotionSession
    private var sessionToken = UUID()
    private var wantsUpdates = false
    private var waitingSince: TimeInterval?
    private var hasReceivedSample = false
    private var nextMotionRequestAt: TimeInterval = 0
    private let motionQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "PodTrack.headphone-motion"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInteractive
        return queue
    }()
    private var mailbox: MotionDeliveryMailbox?
    private(set) var status = MotionSourceStatus()
    var onSamples: (([MotionDelivery]) -> Void)?
    var onStatus: ((MotionSourceStatus) -> Void)?
    var onEvent: ((String) -> Void)?

    init(sessionFactory: @escaping @MainActor () -> any HeadphoneMotionSession = { CoreMotionHeadphoneSession() },
         uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.sessionFactory = sessionFactory
        self.uptime = uptime
        session = sessionFactory()
        refreshStatus()
    }
    func refreshStatus() {
        let auth = session.authorization
        if status.authorization != auth {
            onEvent?("Authorization: \(auth)")
            if auth == "Authorized", wantsUpdates, !hasReceivedSample { waitingSince = uptime() }
        }
        status.authorization = auth
        status.available = session.isAvailable
        status.active = wantsUpdates && session.isActive
        if auth == "Denied" || auth == "Restricted" {
            if wantsUpdates { stop() }
            status.detail = "Motion access is \(auth.lowercased()). Check System Settings → Privacy & Security → Motion & Fitness."
        } else if wantsUpdates {
            // Availability can become true after the connection delegate fired.
            // Retry that transition without needing another Bluetooth event.
            if status.available, mailbox == nil, uptime() >= nextMotionRequestAt { requestMotion() }
            if !hasReceivedSample, let waitingSince, auth == "Authorized" {
                status.waitingSeconds = max(0,Int(uptime()-waitingSince))
                if status.waitingSeconds >= 10, !status.noMotionTimedOut {
                    status.noMotionTimedOut = true
                    onEvent?("No motion samples after 10 s. Available: \(status.available); API active: \(status.active); connection confirmed: \(status.connected).")
                }
            }
            if let error = status.motionError { status.detail = error }
            else if status.noMotionTimedOut {
                status.detail = "No motion samples received after \(status.waitingSeconds) s. Bluetooth connection alone does not confirm a motion stream. Retry opens a new Core Motion session."
            } else if !status.available {
                status.detail = "Core Motion reports no available motion device. Connect compatible AirPods to this Mac."
            }
        }
        onStatus?(status)
    }
    func start() {
        guard !wantsUpdates else { return }
        invalidateSession()
        // A retry must not depend on isDeviceMotionActive clearing on an old
        // manager. Its callbacks and delegate events belong to the old token.
        session = sessionFactory()
        let token = sessionToken
        wantsUpdates = true
        hasReceivedSample = false
        waitingSince = uptime()
        nextMotionRequestAt = 0
        status.connected = false
        status.requested = true
        status.waitingSeconds = 0
        status.noMotionTimedOut = false
        status.motionError = nil
        status.detail = "Starting a fresh Core Motion session…"
        session.onConnectionChange = { [weak self] connected in
            guard let self, self.wantsUpdates, self.sessionToken == token else { return }
            self.status.connected = connected
            self.onEvent?(connected ? "Connected (Core Motion delegate)" : "Disconnected (Core Motion delegate)")
            if !connected {
                self.mailbox?.invalidate(); self.mailbox = nil
                self.session.stopMotionUpdates()
                self.hasReceivedSample = false
                self.waitingSince = self.uptime()
                self.nextMotionRequestAt = self.uptime()+1
                self.status.waitingSeconds = 0
                self.status.noMotionTimedOut = false
                self.status.active = false
                self.status.detail = "Headphones disconnected. Waiting for a connection to this Mac."
                self.onStatus?(self.status)
            } else { self.refreshStatus() }
        }
        onEvent?("Fresh Core Motion session requested")
        if session.authorization != "Denied", session.authorization != "Restricted" {
            session.startConnectionUpdates()
        }
        refreshStatus()
    }
    private func requestMotion() {
        guard wantsUpdates, mailbox == nil else { return }
        status.detail = "Motion requested. Waiting for the first real sample…"
        onEvent?("Motion started (request sent to Core Motion)")
        let mailbox = MotionDeliveryMailbox()
        self.mailbox = mailbox
        session.startMotionUpdates(to:motionQueue) { [weak self] sample, error in
            let receivedAt = ProcessInfo.processInfo.systemUptime
            let delivery = sample.map { MotionDelivery(sample:$0,receivedAt:receivedAt) }
            if mailbox.enqueue(delivery,error:error) {
                DispatchQueue.main.asyncAfter(deadline:.now()+1.0/30) { [weak self] in
                    self?.deliver(mailbox)
                }
            }
        }
        status.active = session.isActive
    }
    private func invalidateSession() {
        sessionToken = UUID()
        session.onConnectionChange = nil
        mailbox?.invalidate(); mailbox = nil
        session.stopMotionUpdates()
        session.stopConnectionUpdates()
    }
    func stop() {
        wantsUpdates = false
        invalidateSession()
        waitingSince = nil; hasReceivedSample = false
        status.requested = false; status.active = false; status.connected = false
        status.waitingSeconds = 0; status.noMotionTimedOut = false; status.motionError = nil
        status.detail = "Motion stopped."
        onEvent?("Motion stopped")
        onStatus?(status)
    }
    func flushPendingSamples() {
        if let mailbox { deliver(mailbox,releaseSchedule:false) }
    }
    private func deliver(_ mailbox: MotionDeliveryMailbox, releaseSchedule: Bool = true) {
        guard wantsUpdates, self.mailbox === mailbox else { return }
        let batch = mailbox.drain(releaseSchedule:releaseSchedule)
        for error in batch.errors {
            if status.motionError != error { onEvent?("Core Motion error: \(error)") }
            status.motionError = error; status.detail = error
        }
        if let firstValid = batch.samples.first(where: { $0.sample.isValid }) {
            if !hasReceivedSample {
                onEvent?("First valid motion sample received; source: \(firstValid.sample.sensorLocation.rawValue)")
            }
            hasReceivedSample = true
            waitingSince = nil
            status.waitingSeconds = 0; status.noMotionTimedOut = false
            // Retain an error from the same callback; only a clean delivery
            // establishes that the stream has recovered.
            if batch.errors.isEmpty { status.motionError = nil }
            status.connected = true; status.active = true
            if status.motionError == nil {
                status.detail = "Receiving real headphone motion on a dedicated queue. Verify the reported bud is mounted on the car."
            }
        }
        if !batch.samples.isEmpty { onSamples?(batch.samples) }
        onStatus?(status)
    }
}

/// Lock-protected handoff; there is at most one scheduled main-queue drain.
/// Never replays each queued sample through SwiftUI individually.
final class MotionDeliveryMailbox: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [MotionDelivery] = []
    private var errors: [String] = []
    private var scheduled = false
    private var accepting = true

    func enqueue(_ delivery: MotionDelivery?, error: String? = nil) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard accepting else { return false }
        if let delivery { samples.append(delivery) }
        if let error { errors = [error] }
        guard !scheduled, !samples.isEmpty || !errors.isEmpty else { return false }
        scheduled = true
        return true
    }
    func drain(releaseSchedule: Bool = true) -> (samples: [MotionDelivery], errors: [String]) {
        lock.lock(); defer { lock.unlock() }
        let result = (samples,errors)
        samples = []; errors = []
        if releaseSchedule { scheduled = false }
        return result
    }
    func invalidate() {
        lock.lock(); defer { lock.unlock() }
        accepting = false; samples = []; errors = []; scheduled = false
    }
}

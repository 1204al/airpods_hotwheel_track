import Foundation
import PodTrackCore

struct MotionSourceStatus: Equatable {
    var connected = false
    var available = false
    var active = false
    /// A connection/motion request is pending, even if the API is not active yet.
    var requested = false
    var authorization = "Not determined"
    var detail = "Connect compatible AirPods to this Mac, then start motion."
    var waitingSeconds = 0
    var noMotionTimedOut = false
    var motionError: String?
}

enum RecordingBud: String, CaseIterable {
    case right = "Right", left = "Left"
    var location: SensorLocation { self == .right ? .right : .left }
}

enum HeadphoneLinkState: Equatable {
    case simulation, permissionBlocked, idle, searching, waitingForMotion, receiving, wrongBud, unidentified, stale, noMotion, motionError
}

@MainActor protocol MotionSource: AnyObject {
    var kind: SourceKind { get }
    var status: MotionSourceStatus { get }
    var onSamples: (([MotionDelivery]) -> Void)? { get set }
    var onStatus: ((MotionSourceStatus) -> Void)? { get set }
    var onEvent: ((String) -> Void)? { get set }
    func start()
    func stop()
    func refreshStatus()
    func flushPendingSamples()
}

extension MotionSource {
    func flushPendingSamples() {}
}

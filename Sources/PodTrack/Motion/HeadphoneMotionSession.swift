import CoreMotion
import Foundation
import PodTrackCore

/// One Core Motion request lifetime. The adapter also makes reconnect races
/// reproducible in tests without requesting hardware or privacy permissions.
@MainActor protocol HeadphoneMotionSession: AnyObject {
    var authorization: String { get }
    var isAvailable: Bool { get }
    var isActive: Bool { get }
    var onConnectionChange: ((Bool) -> Void)? { get set }
    func startConnectionUpdates()
    func startMotionUpdates(to queue: OperationQueue, handler: @escaping (MotionSample?, String?) -> Void)
    func stopMotionUpdates()
    func stopConnectionUpdates()
}

@MainActor final class CoreMotionHeadphoneSession: NSObject, HeadphoneMotionSession, CMHeadphoneMotionManagerDelegate {
    private let manager = CMHeadphoneMotionManager()
    var onConnectionChange: ((Bool) -> Void)?
    override init() { super.init(); manager.delegate = self }
    var authorization: String {
        switch CMHeadphoneMotionManager.authorizationStatus() {
        case .notDetermined: return "Not determined"
        case .restricted: return "Restricted"
        case .denied: return "Denied"
        case .authorized: return "Authorized"
        @unknown default: return "Unknown"
        }
    }
    var isAvailable: Bool { manager.isDeviceMotionAvailable }
    var isActive: Bool { manager.isDeviceMotionActive }
    func startConnectionUpdates() { manager.startConnectionStatusUpdates() }
    func stopConnectionUpdates() { manager.stopConnectionStatusUpdates() }
    func stopMotionUpdates() { manager.stopDeviceMotionUpdates() }
    func startMotionUpdates(to queue: OperationQueue, handler: @escaping (MotionSample?, String?) -> Void) {
        manager.startDeviceMotionUpdates(to:queue) { motion, error in
            let failure = error.map { error -> String in
                let error = error as NSError
                return "\(error.domain) (\(error.code)): \(error.localizedDescription)"
            }
            handler(motion.map(Self.sample),failure)
        }
    }
    nonisolated private static func sample(_ motion: CMDeviceMotion) -> MotionSample {
        let q = motion.attitude.quaternion
        let location: SensorLocation
        switch motion.sensorLocation {
        case .headphoneLeft: location = .left
        case .headphoneRight: location = .right
        default: location = .unknown
        }
        return MotionSample(timestamp:motion.timestamp,
            attitude:.init(x:q.x,y:q.y,z:q.z,w:q.w),
            roll:motion.attitude.roll,pitch:motion.attitude.pitch,yaw:motion.attitude.yaw,
            rotationRate:.init(motion.rotationRate.x,motion.rotationRate.y,motion.rotationRate.z),
            userAcceleration:.init(motion.userAcceleration.x,motion.userAcceleration.y,motion.userAcceleration.z),
            gravity:.init(motion.gravity.x,motion.gravity.y,motion.gravity.z),sensorLocation:location)
    }
    nonisolated func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        Task { @MainActor [weak self] in self?.onConnectionChange?(true) }
    }
    nonisolated func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        Task { @MainActor [weak self] in self?.onConnectionChange?(false) }
    }
}

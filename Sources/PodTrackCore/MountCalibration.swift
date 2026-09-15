import Foundation

public enum PodTrackError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { switch self { case .invalid(let message): return message } }
}

public struct MountCalibration: Codable, Hashable, Sendable {
    public var forwardDevice: Vector3
    public var upDevice: Vector3
    public var sensorLocation: SensorLocation
    public var source: SourceKind
    public var capturedAt: Date
    public init(forwardDevice: Vector3, upDevice: Vector3, sensorLocation: SensorLocation, source: SourceKind, capturedAt: Date = Date()) {
        self.forwardDevice = forwardDevice.normalized; self.upDevice = upDevice.normalized
        self.sensorLocation = sensorLocation; self.source = source; self.capturedAt = capturedAt
    }
    public static func capture(level: [MotionSample], noseUp: [MotionSample], source: SourceKind) throws -> Self {
        try checkSteady(level)
        try checkSteady(noseUp)
        guard Set((level+noseUp).map(\.sensorLocation)).count == 1 else { throw PodTrackError.invalid("The streaming bud changed during calibration. Start calibration again.") }
        let g0 = meanGravity(level), g1 = meanGravity(noseUp)
        let angle = acos(clamp(g0.dot(g1),-1,1))
        guard angle > 10 * .pi/180, angle < 65 * .pi/180 else { throw PodTrackError.invalid(String(format:"Tilt from the saved level pose is %.1f°. Aim for 15–45°. If the car is already raised, recapture level with all four wheels on a flat surface first.",angle * 180 / .pi)) }
        // Raising the nose rotates gravity toward the car's rear in the fixed sensor frame.
        // This solves a continuous mounting direction; no sensor axis is assumed to be forward.
        let forward = -(g1 - g0 * g1.dot(g0)).normalized
        return .init(forwardDevice:forward,upDevice:-g0,sensorLocation:level[0].sensorLocation,source:source)
    }
    public static let minimumPoseDuration: TimeInterval = 0.5
    public static let poseWindowDuration: TimeInterval = 0.6
    public static func checkSteady(_ samples: [MotionSample]) throws {
        guard samples.count >= 10, let a = samples.first, let b = samples.last,
              b.timestamp-a.timestamp >= minimumPoseDuration else {
            throw PodTrackError.invalid("Collecting a fresh pose: keep still for at least 0.5 seconds after Capture.")
        }
        guard Set(samples.map(\.sensorLocation)).count == 1,
              zip(samples,samples.dropFirst()).allSatisfy({ $1.timestamp > $0.timestamp && $1.timestamp-$0.timestamp <= 0.12 }) else {
            throw PodTrackError.invalid("Pose data is interrupted or mixes sensors. Wait for a continuous stream and keep holding still.")
        }
        guard samples.allSatisfy({ $0.isValid }) else {
            throw PodTrackError.invalid("The motion stream contains invalid sensor values.")
        }
        let rotation = samples.map { $0.rotationRate.length }.max() ?? 0
        let acceleration = samples.map { $0.userAcceleration.length }.max() ?? 0
        guard rotation < 0.22, acceleration < 0.10 else {
            throw PodTrackError.invalid(String(format:"The car is still moving: rotation %.2f rad/s (must be below 0.22), acceleration %.2f g (below 0.10). Rest it on a support.",rotation,acceleration))
        }
        let mean = meanGravity(samples)
        guard samples.allSatisfy({ ($0.gravity.normalized-mean).length < 0.04 }) else { throw PodTrackError.invalid("The car moved during calibration. Hold the pose steady and retry.") }
        // A slowly settling fused gravity vector can stay within the spread
        // threshold while still moving throughout the capture window.
        let edgeCount = max(3,samples.count/3)
        let firstGravity = meanGravity(Array(samples.prefix(edgeCount)))
        let lastGravity = meanGravity(Array(samples.suffix(edgeCount)))
        let drift = acos(clamp(firstGravity.dot(lastGravity),-1,1))
        guard drift <= .pi/180 else {
            throw PodTrackError.invalid(String(format:"Tilt is still settling (%.1f° change across the pose). Keep the car supported until it settles.",degrees(drift)))
        }
    }
    /// Time-weighted direction; dense parts of an irregular stream do not gain
    /// more influence just because they contain more samples.
    public static func meanGravity(_ samples: [MotionSample]) -> Vector3 {
        guard let first = samples.first else { return .zero }
        guard samples.count > 1 else { return first.gravity.normalized }
        var integral = Vector3.zero
        for (a,b) in zip(samples,samples.dropFirst()) {
            let dt = b.timestamp-a.timestamp
            if dt > 0 { integral = integral + (a.gravity.normalized+b.gravity.normalized)*(dt/2) }
        }
        return integral.normalized
    }
}

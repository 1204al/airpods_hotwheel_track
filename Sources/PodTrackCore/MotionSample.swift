import Foundation

public enum SensorLocation: String, Codable, Sendable { case left, right, unknown }
public enum SourceKind: String, Codable, CaseIterable, Sendable { case airPods = "AirPods", simulation = "Simulation" }

/// Sensor values are preserved in Core Motion units: acceleration in g, angles in radians,
/// angular velocity in rad/s. Timestamp is source-monotonic, never a wall-clock date.
public struct MotionSample: Codable, Hashable, Sendable, Identifiable {
    public var timestamp: Double
    public var attitude: Quaternion
    public var roll: Double
    public var pitch: Double
    public var yaw: Double
    public var rotationRate: Vector3
    public var userAcceleration: Vector3
    public var gravity: Vector3
    public var sensorLocation: SensorLocation
    public var id: Double { timestamp }
    public init(timestamp: Double, attitude: Quaternion = .init(), roll: Double = 0, pitch: Double = 0,
                yaw: Double = 0, rotationRate: Vector3 = .zero, userAcceleration: Vector3 = .zero,
                gravity: Vector3 = .init(0,0,-1), sensorLocation: SensorLocation = .unknown) {
        self.timestamp = timestamp; self.attitude = attitude; self.roll = roll; self.pitch = pitch; self.yaw = yaw
        self.rotationRate = rotationRate; self.userAcceleration = userAcceleration; self.gravity = gravity
        self.sensorLocation = sensorLocation
    }
    public var isValid: Bool {
        timestamp.isFinite && attitude.isFinite && roll.isFinite && pitch.isFinite && yaw.isFinite &&
        rotationRate.isFinite && userAcceleration.isFinite && gravity.isFinite && gravity.length > 0.1
    }
    public var verticalUserAcceleration: Double { userAcceleration.dot(-gravity.normalized) * standardGravity }
    public var totalAccelerationMagnitudeG: Double { (gravity + userAcceleration).length }
}

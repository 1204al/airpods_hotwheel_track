import Foundation

public enum CSVExporter {
    public static func rawSamples(_ samples: [MotionSample], source: SourceKind, calibration: MountCalibration? = nil) -> String {
        let header = "source,timestamp_s,elapsed_s,qx,qy,qz,qw,roll_rad,pitch_rad,yaw_rad,rotation_x_rad_s,rotation_y_rad_s,rotation_z_rad_s,user_accel_x_g,user_accel_y_g,user_accel_z_g,gravity_x_g,gravity_y_g,gravity_z_g,derived_vertical_user_accel_m_s2,derived_tangential_user_accel_m_s2,sensor_location"
        let origin = samples.first?.timestamp ?? 0
        let rows = samples.map { s -> String in
            let values = [s.timestamp,s.timestamp-origin,s.attitude.x,s.attitude.y,s.attitude.z,s.attitude.w,
                          s.roll,s.pitch,s.yaw,s.rotationRate.x,s.rotationRate.y,s.rotationRate.z,
                          s.userAcceleration.x,s.userAcceleration.y,s.userAcceleration.z,s.gravity.x,s.gravity.y,s.gravity.z,s.verticalUserAcceleration]
            let matchingCalibration = calibration.flatMap { $0.source == source && $0.sensorLocation == s.sensorLocation ? $0 : nil }
            let tangent = matchingCalibration.map { number(s.userAcceleration.dot($0.forwardDevice)*standardGravity) } ?? ""
            return ([source.rawValue] + values.map(number) + [tangent,s.sensorLocation.rawValue]).joined(separator:",")
        }
        return ([header]+rows).joined(separator:"\n") + "\n"
    }
    public static func rawRun(_ run: RunSession) -> String { rawSamples(run.samples,source:run.source,calibration:run.calibration) }
    public static func number(_ value: Double) -> String { value.isFinite ? String(format:"%.9g",locale:Locale(identifier:"en_US_POSIX"),value) : "" }
    public static func escaped(_ value: String) -> String { "\"" + value.replacingOccurrences(of:"\"",with:"\"\"") + "\"" }
}

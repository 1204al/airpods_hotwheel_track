import Foundation

/// One atomic file per bud. A damaged or replaced profile cannot overwrite the
/// other side, and recorded sessions keep their own immutable value snapshots.
public struct CalibrationStore: Sendable {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }

    private struct Profile: Codable {
        var schemaVersion = 1
        let calibration: MountCalibration
    }

    public func save(_ calibration: MountCalibration) throws {
        try validate(calibration,side:calibration.sensorLocation)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(Profile(calibration:calibration))
        try data.write(to:file(for:calibration.sensorLocation),options:.atomic)
    }

    public func remove(for side: SensorLocation) throws {
        guard side == .left || side == .right else { throw PodTrackError.invalid("Choose a Left or Right AirPod profile.") }
        let url = file(for:side)
        if FileManager.default.fileExists(atPath:url.path) { try FileManager.default.removeItem(at:url) }
    }

    public func load() -> (calibrations: [SensorLocation:MountCalibration], warnings: [String]) {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        var calibrations: [SensorLocation:MountCalibration] = [:]
        var warnings: [String] = []
        for side in [SensorLocation.left,.right] {
            let url = file(for:side)
            guard FileManager.default.fileExists(atPath:url.path) else { continue }
            do {
                let profile = try decoder.decode(Profile.self,from:Data(contentsOf:url))
                guard profile.schemaVersion == 1 else { throw PodTrackError.invalid("Unsupported calibration version.") }
                try validate(profile.calibration,side:side)
                calibrations[side] = profile.calibration
            } catch {
                warnings.append("Could not load the \(side.rawValue) AirPod calibration: \(error.localizedDescription). Calibrate that side again.")
            }
        }
        return (calibrations,warnings)
    }

    private func file(for side: SensorLocation) -> URL { directory.appendingPathComponent(side.rawValue).appendingPathExtension("json") }
    private func validate(_ calibration: MountCalibration, side: SensorLocation) throws {
        guard side == .left || side == .right, calibration.sensorLocation == side, calibration.source == .airPods,
              calibration.forwardDevice.isFinite, calibration.upDevice.isFinite,
              abs(calibration.forwardDevice.length-1)<0.001, abs(calibration.upDevice.length-1)<0.001,
              abs(calibration.forwardDevice.dot(calibration.upDevice))<0.001,
              calibration.capturedAt.timeIntervalSince1970.isFinite else {
            throw PodTrackError.invalid("The saved mounting directions or AirPod side are invalid.")
        }
    }
}

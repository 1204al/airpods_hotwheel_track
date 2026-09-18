import Foundation

public enum CSVExporter {
    /// `elapsedOrigin` keeps `elapsed_s` counting from the whole recording's first sample when
    /// only part of it is exported, so a row is identical in the full and the partial file.
    public static func rawSamples(_ samples: [MotionSample], source: SourceKind, calibration: MountCalibration? = nil,
                                  elapsedOrigin: Double? = nil) -> String {
        let header = "source,timestamp_s,elapsed_s,qx,qy,qz,qw,roll_rad,pitch_rad,yaw_rad,rotation_x_rad_s,rotation_y_rad_s,rotation_z_rad_s,user_accel_x_g,user_accel_y_g,user_accel_z_g,gravity_x_g,gravity_y_g,gravity_z_g,derived_vertical_user_accel_m_s2,derived_tangential_user_accel_m_s2,sensor_location"
        let origin = elapsedOrigin ?? samples.first?.timestamp ?? 0
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
    public static func rawRun(_ run: RunSession, elapsedOrigin: Double? = nil) -> String {
        rawSamples(run.samples,source:run.source,calibration:run.calibration,elapsedOrigin:elapsedOrigin)
    }
    public static func number(_ value: Double) -> String { value.isFinite ? String(format:"%.9g",locale:Locale(identifier:"en_US_POSIX"),value) : "" }
    public static func escaped(_ value: String) -> String { "\"" + value.replacingOccurrences(of:"\"",with:"\"\"") + "\"" }
}

public enum RunExportFormat: String, CaseIterable, Sendable {
    case csv = "CSV", json = "JSON"
    public var fileExtension: String { rawValue.lowercased() }
}

public enum RunExportDataset: Hashable, Sendable {
    case raw
    case algorithm(ReconstructionMethod)
    public static var all: [Self] { [.raw] + ReconstructionMethod.allCases.map { .algorithm($0) } }
    public var title: String {
        switch self {
        case .raw: return "Raw data"
        case .algorithm(let method): return "\(method.rawValue) algorithm"
        }
    }
    public var suffix: String {
        switch self {
        case .raw: return "raw"
        case .algorithm(let method): return method.rawValue.lowercased()
        }
    }
    /// `window` restricts the file to part of the recording's elapsed time. The reconstruction
    /// is still the whole run's: a window selects its rows, it never refits a shorter run.
    public func data(run: RunSession, format: RunExportFormat, cache: AnalysisDiskCache,
                     window: TimeWindow? = nil) throws -> Data {
        let exported = window.map { run.trimmed(to:$0) } ?? run
        switch self {
        case .raw:
            guard !exported.samples.isEmpty else { throw PodTrackError.invalid("The selected time window contains no samples.") }
            // Elapsed time still counts from the whole recording, not from the window.
            if format == .csv { return Data(CSVExporter.rawRun(exported,elapsedOrigin:run.samples.first?.timestamp).utf8) }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            return try encoder.encode(exported)
        case .algorithm(let method):
            // Analyse the complete recording, then take the window from that result.
            let whole = try cache.load(run,method:method) ?? method.analyze(run)
            let result = window.map { whole.trimmed(to:$0) } ?? whole
            guard !result.points.isEmpty else { throw PodTrackError.invalid("The selected time window contains no reconstructed points.") }
            return Data(try (format == .csv ? CSVExporter.reconstructedTrack(result) : CSVExporter.processedJSON(run:exported,result:result)).utf8)
        }
    }
}

/// One saved recording as a row of the library index. `result` is absent for raw-only or
/// failed reconstructions; their estimated columns stay empty rather than carrying a
/// substituted value, and `status` records why.
public struct RunIndexEntry: Sendable {
    public var run: RunSession
    public var result: AnalysisResult?
    public var status: String
    public init(run: RunSession, result: AnalysisResult?, status: String) {
        self.run = run; self.result = result; self.status = status
    }
}

extension CSVExporter {
    /// Flat summary of several recordings. Estimated columns are named as estimates and
    /// carry the unit of each run's own scale basis, which differs between rows when some
    /// runs have no measured height or length.
    public static func runIndex(_ entries: [RunIndexEntry], method: ReconstructionMethod) -> String {
        let header = "run_id,recorded_at,track,car,recorded_from,source,status,algorithm,algorithm_version,samples,recording_duration_s,motion_duration_s,entered_height_h_cm,known_track_length_cm,scale_basis,distance_unit,speed_unit,estimated_path_length,estimated_top_speed,estimated_average_speed,estimated_height_range,candidate_airtime_s,observed_peak_user_accel_m_s2,recording_notes,notes"
        let dates = ISO8601DateFormatter()
        let rows = entries.map { entry -> String in
            let run = entry.run, metrics = entry.result?.metrics
            let estimated: [String] = metrics.map { m in
                [number(m.estimatedPathLength),number(m.estimatedMaximumSpeed),number(m.estimatedAverageSpeed),
                 number(m.reconstructedHeightRange),number(m.candidateAirtime),number(m.observedPeakUserAcceleration)]
            } ?? Array(repeating:"",count:6)
            return ([escaped(run.id.uuidString),escaped(dates.string(from:run.createdAt)),
                     escaped(run.metadata.trackName),escaped(run.metadata.carName),
                     escaped(run.recordedOrigin.rawValue),escaped(run.source.rawValue),escaped(entry.status),
                     escaped(method.rawValue),escaped(entry.result?.algorithmVersion ?? ""),
                     String(run.samples.count),number(run.duration),
                     metrics.map { number($0.motionDuration) } ?? "",
                     run.metadata.verticalDrop.map { number($0*100) } ?? "",
                     run.metadata.knownTrackLength.map { number($0*100) } ?? "",
                     escaped(run.metadata.scaleBasis.rawValue),
                     escaped(entry.result?.distanceUnit ?? ""),escaped(entry.result?.speedUnit ?? "")]
                    + estimated
                    + [escaped(run.recordingNotes.joined(separator:" · ")),escaped(run.metadata.notes)]).joined(separator:",")
        }
        return ([header]+rows).joined(separator:"\n") + "\n"
    }
}

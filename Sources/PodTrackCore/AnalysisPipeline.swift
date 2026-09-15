import Foundation

public struct AnalysisResult: Codable, Sendable {
    public var algorithmVersion = "0.4.0-heuristic"
    public var runID: UUID
    public var source: SourceKind
    public var recordedOrigin: RecordingOrigin? = nil
    public var signals: [ProcessedSample]
    public var points: [TrackPoint]
    public var segments: [RunSegment]
    public var metrics: RunMetrics
    public var warnings: [String]
    public var attitudeMapping: String
    public var inferredAccelerationSign: Double
    public var endpointAccelerationCorrection: Double
    public var heightScale: Double
    public var horizontalScale: Double
    public var unscaledDrop: Double
    public var unscaledHeightRange: Double?
    public var heightConstraint: HeightConstraint?
    /// Missing only on analyses exported before unknown-height support.
    public var scaleBasis: ReconstructionScale? = nil
    public var reconstructionDiagnostics: ReconstructionDiagnostics? = nil
    public var resolvedScaleBasis: ReconstructionScale { scaleBasis ?? .height }
    public var isRelative: Bool { resolvedScaleBasis.isRelative }
    public var distanceUnit: String { resolvedScaleBasis.distanceUnit }
    public var speedUnit: String { resolvedScaleBasis.speedUnit }
    public var groundZ: Double { points.map { $0.position.z }.min() ?? 0 }
    public var coordinateDescription: String {
        if isRelative {
            return "Relative units (u). Total path length = 1 u; position and distance use u, speed uses u/s, curvature uses 1/u. Z up; lowest point Z=0. X/Y origin at the start; X follows the initial horizontal heading. Physical scale is unknown."
        }
        if resolvedScaleBasis == .trackLength {
            return "Metres. Uniform scale from measured along-track length. Z up; lowest reconstructed point Z=0; height is estimated. X/Y origin at the start; X follows the initial horizontal heading."
        }
        return heightConstraint == .heightRange
            ? "Metres. Z up; lowest reconstructed centerline point Z=0, highest Z=H. X/Y origin at the start; X follows the initial horizontal heading."
            : "Metres. Z up; start Z=0, finish Z=-H (legacy endpoint-drop constraint). X/Y origin at the start; X follows the initial horizontal heading."
    }
}

public enum AnalysisPipeline {
    public static func analyze(_ run: RunSession) throws -> AnalysisResult {
        try run.metadata.validate()
        guard let calibration = run.calibration else { throw PodTrackError.invalid("This run has no mounting calibration. Raw samples can be inspected and exported; track reconstruction is unavailable.") }
        guard calibration.source == run.source else { throw PodTrackError.invalid("Calibration source does not match this run.") }
        let processed = try SignalProcessor.process(run.samples,calibration:calibration,settings:run.metadata.settings)
        let speed = try SpeedEstimator.estimate(processed.samples,settings:run.metadata.settings)
        let track = try TrackReconstructor.reconstruct(signals:processed.samples,speeds:speed.speeds,verticalDrop:run.metadata.verticalDrop,
                                                      knownLength:run.metadata.knownTrackLength,heightConstraint:run.metadata.resolvedHeightConstraint)
        let segments = RunSegmenter.attachMetrics(RunSegmenter.detect(processed.samples,startIndex:speed.startIndex,endIndex:speed.endIndex),points:track.points,signals:processed.samples)
        var points = track.points
        for i in points.indices { points[i].segmentLabel = RunSegmenter.labels(at:points[i].time,segments:segments) }
        var warnings = run.recordingNotes + processed.warnings + speed.warnings + track.warnings
        warnings.append("Reconstructed geometry and speed are drift-prone estimates. A measured height or length can set scale; neither makes the shape unique.")
        if segments.contains(where:{ $0.kind == .airborne }) { warnings.append("Possible airtime is heuristic. Body orientation may not match travel direction in flight; jump geometry is especially uncertain.") }
        return .init(runID:run.id,source:run.source,recordedOrigin:run.recordedOrigin,signals:processed.samples,points:points,segments:segments,
                     metrics:MetricsCalculator.calculate(run:run,signals:processed.samples,points:points,segments:segments,speed:speed),
                     warnings:warnings,attitudeMapping:processed.attitudeMapping,inferredAccelerationSign:speed.accelerationSign,
                     endpointAccelerationCorrection:speed.endpointCorrection,heightScale:track.heightScale,horizontalScale:track.horizontalScale,
                     unscaledDrop:track.unscaledDrop,unscaledHeightRange:track.unscaledHeightRange,heightConstraint:run.metadata.resolvedHeightConstraint,
                     scaleBasis:run.metadata.scaleBasis)
    }
}

extension CSVExporter {
    public static func reconstructedTrack(_ result: AnalysisResult) -> String {
        let origin = result.recordedOrigin ?? (result.source == .simulation ? .simulation : .unknown)
        let unit = result.isRelative ? "u" : "m"
        let header = "source,time_s,estimated_x_\(unit),estimated_y_\(unit),estimated_z_\(unit),estimated_speed_\(unit)_s,estimated_distance_\(unit),estimated_curvature_1_\(unit),segment_label,scale_basis,recorded_from"
        return ([header]+result.points.map { p in
            ([result.source.rawValue]+[p.time,p.position.x,p.position.y,p.position.z,p.speed,p.distance,p.curvature].map(number)+[escaped(p.segmentLabel),result.resolvedScaleBasis.rawValue,origin.rawValue]).joined(separator:",")
        }).joined(separator:"\n") + "\n"
    }
    public static func processedJSON(run: RunSession, result: AnalysisResult) throws -> String {
        struct Export: Encodable {
            let description: String
            let displayName: String
            let recordedOrigin: RecordingOrigin
            let metadata: RunMetadata
            let calibration: MountCalibration?
            let analysis: AnalysisResult
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(Export(description:"PodTrack experimental estimates, not measured position or speed. Processed acceleration: m/s²; angles: radians unless field says Degrees; time: seconds. \(result.coordinateDescription)",displayName:run.displayName,recordedOrigin:run.recordedOrigin,metadata:run.metadata,calibration:run.calibration,analysis:result))
        return String(decoding:data,as:UTF8.self)
    }
}

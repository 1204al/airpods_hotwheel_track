import Foundation

public struct RunRecorder: Sendable {
    public private(set) var session: RunSession?
    public private(set) var rejectedSamples = 0
    public let maxDuration: Double
    public var isRecording: Bool { session != nil }
    public init(maxDuration: Double = 180) { self.maxDuration = maxDuration }
    public mutating func start(metadata: RunMetadata, source: SourceKind, calibration: MountCalibration?) throws {
        guard !isRecording else { throw PodTrackError.invalid("A recording is already in progress.") }
        try metadata.validate()
        if let calibration, calibration.source != source { throw PodTrackError.invalid("Calibration belongs to a different motion source.") }
        rejectedSamples = 0
        session = .init(source:source,metadata:metadata,calibration:calibration,samples:[])
    }
    public mutating func append(_ sample: MotionSample) throws {
        guard session != nil else { return }
        guard sample.isValid else { rejectedSamples += 1; return }
        if let last = session?.samples.last {
            guard sample.timestamp > last.timestamp else { rejectedSamples += 1; return }
            if sample.sensorLocation != last.sensorLocation {
                throw PodTrackError.invalid("Sensor location changed from \(last.sensorLocation.rawValue) to \(sample.sensorLocation.rawValue). Recording ended before mixing buds.")
            }
            if sample.timestamp-last.timestamp > 0.5 { throw PodTrackError.invalid("Motion gap exceeded 0.5 s. Recording ended at the last continuous sample.") }
        }
        if let calibration = session?.calibration, sample.sensorLocation != calibration.sensorLocation {
            throw PodTrackError.invalid("The current bud differs from the calibrated bud. Recalibrate the mounted car.")
        }
        if let first = session?.samples.first, sample.timestamp-first.timestamp > maxDuration {
            throw PodTrackError.invalid("Recording reached the \(Int(maxDuration))-second limit.")
        }
        session?.samples.append(sample)
    }
    public mutating func finish(reason: String? = nil) -> RunSession? {
        guard var result = session else { return nil }
        if let reason { result.recordingNotes.append(reason) }
        if rejectedSamples > 0 { result.recordingNotes.append("Rejected \(rejectedSamples) invalid or non-increasing samples.") }
        session = nil
        return result
    }
}

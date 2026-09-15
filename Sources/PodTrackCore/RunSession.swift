import Foundation

/// Recording identity comes from the samples, never the current UI selection or
/// a mounting calibration that may be absent on older/raw-only recordings.
public enum RecordingOrigin: String, Codable, Sendable {
    case left, right, unknown, mixed, simulation
    public var label: String {
        switch self {
        case .left: return "Left AirPod"
        case .right: return "Right AirPod"
        case .unknown: return "AirPod · side unknown"
        case .mixed: return "AirPods · mixed sides"
        case .simulation: return "Simulation"
        }
    }
    public static func identify(source: SourceKind, samples: [MotionSample]) -> Self {
        if source == .simulation { return .simulation }
        let sides = Set(samples.map(\.sensorLocation))
        if sides == [.left] { return .left }
        if sides == [.right] { return .right }
        return sides.count > 1 ? .mixed : .unknown
    }
}

public enum AccelerationPolarity: String, Codable, CaseIterable, Sendable {
    case automatic = "Infer from release", asReported = "As reported", inverted = "Inverted"
}

public enum HeightConstraint: String, Codable, CaseIterable, Sendable {
    case heightRange, endpointDrop
    public var label: String {
        switch self {
        case .heightRange: return "Lowest → highest (H)"
        case .endpointDrop: return "Start → finish drop (legacy)"
        }
    }
}

public enum ReconstructionScale: String, Codable, Sendable {
    case height, trackLength, relative
    public var isRelative: Bool { self == .relative }
    public var distanceUnit: String { isRelative ? "u" : "m" }
    public var speedUnit: String { isRelative ? "u/s" : "m/s" }
    public var label: String {
        switch self {
        case .height: return "Scale from height"
        case .trackLength: return "Scale from track length"
        case .relative: return "Relative shape · scale unknown"
        }
    }
}

public struct ReconstructionSettings: Codable, Hashable, Sendable {
    public var smoothingSeconds: Double = 0.10
    public var gravityModelWeight: Double = 0.20
    public var rollingResistance: Double = 0.15
    public var accelerationPolarity: AccelerationPolarity = .automatic
    public var startsAndEndsAtRest = true
    public init() {}
}

public struct RunMetadata: Codable, Hashable, Sendable {
    /// Prefill when the user selects Measured, also used by the synthetic track.
    /// New recordings have no measured height until the user supplies one.
    public static let defaultHeightMeters = 0.58
    public var trackName: String
    public var carName: String
    /// Nil means the height has not been measured. Never substitute a guessed H.
    public var verticalDrop: Double?
    /// Absent in original schema-1 recordings, which used an endpoint drop.
    public var heightConstraint: HeightConstraint?
    public var resolvedHeightConstraint: HeightConstraint { heightConstraint ?? .endpointDrop }
    public var scaleBasis: ReconstructionScale {
        verticalDrop != nil ? .height : knownTrackLength != nil ? .trackLength : .relative
    }
    public var notes: String
    /// Optional measured along-track length, in metres. Never a straight-line displacement.
    public var knownTrackLength: Double?
    public var settings: ReconstructionSettings
    public init(trackName: String = "Untitled track", carName: String = "Hot Wheels", verticalDrop: Double? = nil,
                notes: String = "", knownTrackLength: Double? = nil, settings: ReconstructionSettings = .init(),
                heightConstraint: HeightConstraint = .heightRange) {
        self.trackName = trackName; self.carName = carName; self.verticalDrop = verticalDrop
        self.notes = notes; self.knownTrackLength = knownTrackLength; self.settings = settings
        self.heightConstraint = heightConstraint
    }
    public func validate() throws {
        guard !trackName.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, !carName.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else {
            throw PodTrackError.invalid("Enter a track name and a car name.")
        }
        if let verticalDrop {
            guard verticalDrop.isFinite, verticalDrop > 0, verticalDrop <= 100 else { throw PodTrackError.invalid("Enter a positive track height H (up to 10,000 cm), or choose Unknown.") }
        }
        if let length = knownTrackLength {
            guard length.isFinite, length > 0, length >= (verticalDrop ?? 0), length <= 10000 else { throw PodTrackError.invalid("Known track length must be positive, at least H when provided, and no greater than 1,000,000 cm.") }
        }
        guard settings.smoothingSeconds.isFinite, (0...1).contains(settings.smoothingSeconds),
              settings.gravityModelWeight.isFinite, (0...1).contains(settings.gravityModelWeight),
              settings.rollingResistance.isFinite, (0...2).contains(settings.rollingResistance) else { throw PodTrackError.invalid("Reconstruction settings are out of range.") }
    }
}

public struct RunSession: Codable, Identifiable, Hashable, Sendable {
    public var schemaVersion = 1
    public var id: UUID
    public var createdAt: Date
    public var source: SourceKind
    public var metadata: RunMetadata
    public var calibration: MountCalibration?
    public var samples: [MotionSample]
    public var recordingNotes: [String]
    public init(id: UUID = UUID(), createdAt: Date = Date(), source: SourceKind, metadata: RunMetadata,
                calibration: MountCalibration?, samples: [MotionSample], recordingNotes: [String] = []) {
        self.id = id; self.createdAt = createdAt; self.source = source; self.metadata = metadata
        self.calibration = calibration; self.samples = samples; self.recordingNotes = recordingNotes
    }
    public var duration: Double { max(0,(samples.last?.timestamp ?? 0) - (samples.first?.timestamp ?? 0)) }
    public var recordedOrigin: RecordingOrigin { .identify(source:source,samples:samples) }
    public var carDisplayName: String { "\(metadata.carName) · \(recordedOrigin.label)" }
    public var displayName: String { "\(metadata.trackName) · \(carDisplayName)" }
    public var comparisonDisplayName: String { "\(carDisplayName) · \(createdAt.formatted(date:.omitted,time:.standard))" }
    public var exportBasename: String { "PodTrack-\(recordedOrigin.rawValue)-\(id.uuidString.prefix(8))" }
}

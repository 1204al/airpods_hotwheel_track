import Foundation

public struct RunMetrics: Codable, Hashable, Sendable {
    public var recordingDuration: Double
    public var motionDuration: Double
    public var estimatedPathLength: Double
    public var enteredVerticalDrop: Double?
    public var reconstructedHeightRange: Double
    public var estimatedMaximumSpeed: Double
    public var estimatedAverageSpeed: Double
    public var observedPeakUserAcceleration: Double
    public var estimatedMaximumTurnRate: Double
    public var estimatedSteepestDownhillDegrees: Double
    public var estimatedSteepestUphillDegrees: Double
    public var estimatedTotalHeadingChangeDegrees: Double
    public var candidateAirtime: Double
    public var candidateLandingPeakAcceleration: Double?
}

public enum MetricsCalculator {
    public static func calculate(run: RunSession, signals: [ProcessedSample], points: [TrackPoint], segments: [RunSegment], speed: SpeedEstimate) -> RunMetrics {
        let length = points.last?.distance ?? 0
        let motionDuration = signals[speed.endIndex].time-signals[speed.startIndex].time
        let heights = points.map { $0.position.z }
        let movingSignals = Array(signals[speed.startIndex...speed.endIndex])
        let headingChange = zip(movingSignals,movingSignals.dropFirst()).map { abs($1.heading-$0.heading) }.reduce(0,+)
        return .init(recordingDuration:run.duration,motionDuration:motionDuration,estimatedPathLength:length,
                     enteredVerticalDrop:run.metadata.verticalDrop,reconstructedHeightRange:(heights.max() ?? 0)-(heights.min() ?? 0),
                     estimatedMaximumSpeed:points.map(\.speed).max() ?? 0,estimatedAverageSpeed:length/max(0.001,motionDuration),
                     observedPeakUserAcceleration:signals.map(\.accelerationMagnitude).max() ?? 0,
                     estimatedMaximumTurnRate:movingSignals.map { abs($0.turnRate) }.max() ?? 0,
                     estimatedSteepestDownhillDegrees:degrees(min(0,movingSignals.map(\.slope).min() ?? 0)),
                     estimatedSteepestUphillDegrees:degrees(max(0,movingSignals.map(\.slope).max() ?? 0)),
                     estimatedTotalHeadingChangeDegrees:degrees(headingChange),
                     candidateAirtime:segments.filter { $0.kind == .airborne }.map(\.duration).reduce(0,+),
                     candidateLandingPeakAcceleration:segments.filter { $0.kind == .landing }.map(\.peakAcceleration).max())
    }
}

import Foundation

/// A span of a recording's own elapsed time, in seconds from its first sample.
/// Used to inspect and export part of a run. It never re-runs a reconstruction: a window
/// selects rows of an existing result, so scale and fit still come from the whole run.
public struct TimeWindow: Codable, Hashable, Sendable {
    public var start: Double
    public var end: Double
    public init(start: Double, end: Double) {
        self.start = min(start,end); self.end = max(start,end)
    }
    public var duration: Double { max(0,end-start) }
    public func contains(_ time: Double) -> Bool { time >= start && time <= end }
    public func clamping(_ time: Double) -> Double { min(max(time,start),end) }
    public func overlap(_ other: TimeWindow) -> Double { max(0,min(end,other.end)-max(start,other.start)) }
    /// Keeps the window inside the recording and never lets the two edges meet.
    public func limited(to duration: Double, minimumSpan: Double = 0.05) -> TimeWindow {
        let total = max(0,duration)
        var low = min(max(start,0),total), high = min(max(end,0),total)
        if high-low < minimumSpan {
            let span = min(minimumSpan,total)
            if low+span <= total { high = low+span } else { low = max(0,total-span); high = total }
        }
        return .init(start:low,end:high)
    }
    public func covers(_ duration: Double) -> Bool { start <= 1e-9 && end >= duration-1e-9 }
    public var label: String { String(format:"%.2f–%.2f s",start,end) }
    public var fileSuffix: String { String(format:"%.2fs-%.2fs",start,end) }
}

extension RunSession {
    /// The same recording restricted to a window of its own elapsed time. Samples are the
    /// original API values; nothing is resampled. The note records that the file is a slice.
    public func trimmed(to window: TimeWindow) -> RunSession {
        guard let origin = samples.first?.timestamp else { return self }
        var copy = self
        copy.samples = samples.filter { window.contains($0.timestamp-origin) }
        copy.recordingNotes = recordingNotes + [String(format:"Time window %@ of a %.2f s recording. This file is part of saved run %@, not a separate recording.",window.label,duration,id.uuidString)]
        return copy
    }
}

extension RunSegment {
    /// The part of this candidate inside the window, or nil when it falls outside.
    public func clipped(to window: TimeWindow) -> RunSegment? {
        let low = max(startTime,window.start), high = min(endTime,window.end)
        guard high > low else { return nil }
        var copy = self
        copy.startTime = low; copy.endTime = high
        return copy
    }
}

extension AnalysisResult {
    /// A window of this reconstruction. Signals, points and candidates are the original rows,
    /// restricted and clipped; per-window metrics are recomputed from those rows. The fit,
    /// its scale and its endpoint assumptions are NOT recomputed — they remain the whole
    /// run's, which the added warning states.
    public func trimmed(to window: TimeWindow) -> AnalysisResult {
        var copy = self
        copy.signals = signals.filter { window.contains($0.time) }
        copy.points = points.filter { window.contains($0.time) }
        copy.segments = RunSegmenter.attachMetrics(segments.compactMap { $0.clipped(to:window) },
                                                   points:copy.points,signals:copy.signals)
        copy.metrics = Self.metrics(of:copy,whole:self,window:window)
        copy.warnings = warnings + [String(format:"Time window %@ of a %.2f s recording. These rows are a slice of the whole-run reconstruction: its scale, endpoint assumptions and fit come from the complete recording and were not recalculated for this window. Distance along the path keeps counting from the start of the run.",window.label,metrics.recordingDuration)]
        return copy
    }

    private static func metrics(of slice: AnalysisResult, whole: AnalysisResult, window: TimeWindow) -> RunMetrics {
        var metrics = whole.metrics
        let points = slice.points, signals = slice.signals
        let heights = points.map { $0.position.z }
        // Motion time inside the window excludes the pre-release and post-stop candidates.
        let quiet = whole.segments.filter { $0.kind == .start || $0.kind == .finish }
            .map { window.overlap(.init(start:$0.startTime,end:$0.endTime)) }.reduce(0,+)
        let motion = max(0,window.duration-quiet)
        let length = max(0,(points.last?.distance ?? 0)-(points.first?.distance ?? 0))
        metrics.recordingDuration = window.duration
        metrics.motionDuration = motion
        metrics.estimatedPathLength = length
        metrics.reconstructedHeightRange = (heights.max() ?? 0)-(heights.min() ?? 0)
        metrics.estimatedMaximumSpeed = points.map(\.speed).max() ?? 0
        metrics.estimatedAverageSpeed = motion > 0.001 ? length/motion : 0
        metrics.observedPeakUserAcceleration = signals.map(\.accelerationMagnitude).max() ?? 0
        metrics.estimatedMaximumTurnRate = signals.map { abs($0.turnRate) }.max() ?? 0
        metrics.estimatedSteepestDownhillDegrees = degrees(min(0,signals.map(\.slope).min() ?? 0))
        metrics.estimatedSteepestUphillDegrees = degrees(max(0,signals.map(\.slope).max() ?? 0))
        metrics.estimatedTotalHeadingChangeDegrees = degrees(zip(signals,signals.dropFirst()).map { abs($1.heading-$0.heading) }.reduce(0,+))
        metrics.candidateAirtime = slice.segments.filter { $0.kind == .airborne }.map(\.duration).reduce(0,+)
        metrics.candidateLandingPeakAcceleration = slice.segments.filter { $0.kind == .landing }.map(\.peakAcceleration).max()
        return metrics
    }
}

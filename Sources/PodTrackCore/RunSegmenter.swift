import Foundation

public enum SegmentKind: String, Codable, CaseIterable, Sendable {
    case start = "Start", release = "Release", downhill = "Downhill", flat = "Flat", uphill = "Uphill"
    case leftTurn = "Left turn", rightTurn = "Right turn", bump = "Bump / rough", airborne = "Possible airtime", landing = "Possible landing", finish = "Finish / rest"
    public var lane: String {
        switch self {
        case .downhill,.flat,.uphill: return "Slope"
        case .leftTurn,.rightTurn: return "Turns"
        case .bump,.airborne,.landing: return "Events"
        case .start,.release,.finish: return "Run"
        }
    }
}

public struct RunSegment: Codable, Hashable, Sendable, Identifiable {
    public var kind: SegmentKind
    public var startTime: Double
    public var endTime: Double
    public var estimatedLength: Double = 0
    public var estimatedAverageSpeed: Double = 0
    public var entrySpeed: Double = 0
    public var exitSpeed: Double = 0
    public var peakAcceleration: Double = 0
    public var id: String { "\(kind.rawValue)-\(startTime)" }
    public var duration: Double { max(0,endTime-startTime) }
}

public enum RunSegmenter {
    public static func detect(_ signals: [ProcessedSample], startIndex: Int, endIndex: Int) -> [RunSegment] {
        guard !signals.isEmpty,startIndex>=0,endIndex<signals.count,startIndex<=endIndex else { return [] }
        let startTime = signals[startIndex].time, endTime = signals[endIndex].time
        var segments = [RunSegment(kind:.start,startTime:0,endTime:startTime),
                        .init(kind:.release,startTime:startTime,endTime:min(endTime,startTime+0.10)),
                        .init(kind:.finish,startTime:endTime,endTime:signals.last!.time)]
        func addRuns(_ kind: SegmentKind, minimum: Double, predicate: (ProcessedSample) -> Bool) {
            var start: Int?
            for i in startIndex...endIndex {
                if predicate(signals[i]) {
                    if start == nil { start = i }
                } else if let a = start {
                    if signals[i].time-signals[a].time >= minimum { segments.append(.init(kind:kind,startTime:signals[a].time,endTime:signals[i].time)) }
                    start = nil
                }
            }
            if let a = start, signals[endIndex].time-signals[a].time >= minimum {
                segments.append(.init(kind:kind,startTime:signals[a].time,endTime:signals[endIndex].time))
            }
        }
        addRuns(.downhill,minimum:0.12) { $0.slope < -0.07 }
        addRuns(.uphill,minimum:0.12) { $0.slope > 0.07 }
        addRuns(.flat,minimum:0.12) { abs($0.slope)<=0.07 }
        addRuns(.leftTurn,minimum:0.12) { $0.turnRate>0.30 }
        addRuns(.rightTurn,minimum:0.12) { $0.turnRate < -0.30 }
        // Total accelerometer magnitude is a proxy, not a direct contact-force measurement.
        addRuns(.airborne,minimum:0.06) { $0.supportProxyG < 0.22 }
        let air = segments.filter { $0.kind == .airborne }
        addRuns(.bump,minimum:0.015) {
            ($0.accelerationMagnitude>0.70*standardGravity || abs($0.verticalUserAcceleration)>0.20*standardGravity) && $0.supportProxyG>0.4
        }
        for event in air {
            let candidates = signals.filter { $0.time>=event.endTime && $0.time<=event.endTime+0.3 && $0.accelerationMagnitude>0.70*standardGravity }
            if let peak = candidates.max(by:{ $0.accelerationMagnitude<$1.accelerationMagnitude }) {
                segments.append(.init(kind:.landing,startTime:max(event.endTime,peak.time-0.03),endTime:min(signals.last!.time,peak.time+0.06)))
            }
        }
        return segments.filter { $0.duration>0 }.sorted { $0.startTime == $1.startTime ? $0.kind.rawValue<$1.kind.rawValue : $0.startTime<$1.startTime }
    }
    public static func attachMetrics(_ segments: [RunSegment], points: [TrackPoint], signals: [ProcessedSample]) -> [RunSegment] {
        segments.map { segment in
            var result = segment
            let within = points.filter { $0.time>=segment.startTime && $0.time<=segment.endTime }
            if let first = within.first, let last = within.last {
                result.estimatedLength = max(0,last.distance-first.distance)
                result.estimatedAverageSpeed = result.estimatedLength/max(0.001,segment.duration)
                result.entrySpeed = first.speed; result.exitSpeed = last.speed
            }
            result.peakAcceleration = signals.filter { $0.time>=segment.startTime && $0.time<=segment.endTime }.map(\.accelerationMagnitude).max() ?? 0
            return result
        }
    }
    public static func labels(at time: Double, segments: [RunSegment]) -> String {
        segments.filter { time >= $0.startTime && time < $0.endTime }.map { $0.kind.rawValue }.joined(separator:"; ")
    }
}

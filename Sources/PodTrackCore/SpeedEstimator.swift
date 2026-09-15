import Foundation

public struct SpeedEstimate: Sendable {
    public var speeds: [Double]
    public var startIndex: Int
    public var endIndex: Int
    public var accelerationSign: Double
    public var endpointCorrection: Double
    public var warnings: [String]
}

public enum SpeedEstimator {
    public static func estimate(_ signals: [ProcessedSample], settings: ReconstructionSettings) throws -> SpeedEstimate {
        guard signals.count >= 10 else { throw PodTrackError.invalid("Too few samples for speed estimation.") }
        var first: Int?, last: Int?
        // Only trim edge rest. Quiet intervals inside a run may be constant-speed travel.
        for i in signals.indices where !signals[i].isQuiet { if first == nil { first = i }; last = i }
        guard let firstActive = first, let lastActive = last, signals[lastActive].time-signals[firstActive].time > 0.25 else {
            throw PodTrackError.invalid("No sustained motion was detected. A stationary recording cannot constrain track geometry.")
        }
        let start = settings.startsAndEndsAtRest ? max(0,firstActive-1) : 0
        let end = settings.startsAndEndsAtRest ? min(signals.count-1,lastActive+1) : signals.count-1
        let duration = signals[end].time-signals[start].time
        guard duration > 0.25 else { throw PodTrackError.invalid("The motion interval is too short.") }
        var warnings: [String] = []
        let initialQuiet = signals[start].time-signals[0].time
        let finalQuiet = signals.last!.time-signals[end].time
        if settings.startsAndEndsAtRest && (initialQuiet < 0.2 || finalQuiet < 0.2) {
            warnings.append("Less than 0.2 s of quiet data at an endpoint. The zero-speed endpoint assumption is weak.")
        }
        if !settings.startsAndEndsAtRest { warnings.append("No end-rest constraint applied. Initial speed is assumed zero and cannot be recovered from the IMU alone.") }
        let baseline = start > 2 ? signals[0..<max(1,start-1)].map(\.tangentialUserAcceleration).reduce(0,+)/Double(max(1,start-1)) : 0
        let evidence = signals[start...end].filter { $0.time-signals[start].time < 1.2 && $0.slope < -0.08 && abs($0.tangentialUserAcceleration-baseline) > 0.1 }
        let polarityScore = evidence.map { ($0.tangentialUserAcceleration-baseline) * -sin($0.slope) }.reduce(0,+)
        let sign: Double
        switch settings.accelerationPolarity {
        case .asReported: sign = 1
        case .inverted: sign = -1
        case .automatic:
            sign = polarityScore < 0 ? -1 : 1
            warnings.append("Acceleration sign \(sign < 0 ? "inverted" : "as reported") inferred from early descent; validate it with a known straight ramp.")
            if evidence.count < 5 { warnings.append("Insufficient downhill release evidence to determine acceleration sign reliably.") }
        }
        var acceleration = signals.map { s -> Double in
            let sensor = sign*(s.tangentialUserAcceleration-baseline)
            let slopeModel = -standardGravity*sin(s.slope)-settings.rollingResistance
            // Reduce the model's weight when it contradicts the sensor. During possible
            // free fall the rolling-contact model is inapplicable, so use only the sensor.
            let weight = s.supportProxyG < 0.25 ? 0 : settings.gravityModelWeight*exp(-abs(sensor-slopeModel)/2)
            return (1-weight)*sensor + weight*slopeModel
        }
        var impulse = 0.0
        for i in (start+1)...end { impulse += (acceleration[i-1]+acceleration[i])*0.5*(signals[i].time-signals[i-1].time) }
        let correction = settings.startsAndEndsAtRest ? impulse/duration : 0
        for i in start...end { acceleration[i] -= correction }
        var speeds = Array(repeating:0.0,count:signals.count), integral = 0.0
        for i in (start+1)...end {
            integral += (acceleration[i-1]+acceleration[i])*0.5*(signals[i].time-signals[i-1].time)
            speeds[i] = max(0,integral)
        }
        speeds = SignalProcessor.smooth(speeds,times:signals.map(\.time),window:settings.smoothingSeconds)
        for i in 0...start { speeds[i] = 0 }
        if settings.startsAndEndsAtRest { for i in end..<speeds.count { speeds[i] = 0 } }
        guard (speeds.max() ?? 0) > 0.03 else { throw PodTrackError.invalid("A nonnegative speed profile could not be recovered. Check mounting direction, acceleration sign, and endpoint assumptions.") }
        if abs(correction)>1 { warnings.append("Endpoint velocity correction exceeds 1 m/s²; speed drift or endpoint mismatch is substantial.") }
        return .init(speeds:speeds,startIndex:start,endIndex:end,accelerationSign:sign,endpointCorrection:correction,warnings:warnings)
    }
}

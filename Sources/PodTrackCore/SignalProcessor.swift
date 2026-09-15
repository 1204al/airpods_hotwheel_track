import Foundation

public struct ProcessedSample: Codable, Hashable, Sendable, Identifiable {
    public var time: Double
    public var verticalUserAcceleration: Double
    public var tangentialUserAcceleration: Double
    public var slope: Double
    public var heading: Double
    public var bank: Double
    public var turnRate: Double
    public var supportProxyG: Double
    public var accelerationMagnitude: Double
    public var isQuiet: Bool
    /// New methods integrate this vector directly; old exports retain the angle-derived tangent.
    public var forwardDirection: Vector3? = nil
    public var id: Double { time }
    public var direction: Vector3 { forwardDirection ?? .init(cos(slope)*cos(heading),cos(slope)*sin(heading),sin(slope)) }
}

public struct ProcessedSignals: Sendable {
    public var samples: [ProcessedSample]
    public var attitudeMapping: String
    public var warnings: [String]
}

public enum SignalProcessor {
    /// Centered sample-window average, including shortened windows at the endpoints.
    public static func smooth(_ values: [Double], radius: Int) -> [Double] {
        guard !values.isEmpty, radius > 0 else { return values }
        var prefix = [0.0]
        values.forEach { prefix.append(prefix.last!+$0) }
        return values.indices.map { i in
            let low = max(0,i-radius), high = min(values.count,i+radius+1)
            return (prefix[high]-prefix[low])/Double(high-low)
        }
    }
    /// Centered time average of the piecewise-linear signal. Integrating over
    /// elapsed time makes this invariant to inserting interpolated samples.
    /// Endpoint windows are clipped to observed time, with no extrapolation.
    public static func smooth(_ values: [Double], times: [Double], window: Double) -> [Double] {
        guard values.count == times.count, values.count > 1, window.isFinite, window > 0,
              times.allSatisfy(\.isFinite), values.allSatisfy(\.isFinite),
              zip(times,times.dropFirst()).allSatisfy({ $1 > $0 }) else { return values }
        // Center before building the integral to reduce cancellation when a
        // small variation rides on a large constant offset.
        let baseline = values[0]
        let centered = values.map { $0-baseline }
        var integral = Array(repeating:0.0,count:values.count)
        for i in 1..<values.count {
            integral[i] = integral[i-1] + (centered[i-1]+centered[i]) * (times[i]-times[i-1])/2
        }
        // Both integration bounds move only forwards: O(n), even for large runs.
        func area(to time: Double, segment: inout Int) -> Double {
            while segment+1 < times.count-1 && times[segment+1] < time { segment += 1 }
            let dt = time-times[segment]
            let slope = (centered[segment+1]-centered[segment])/(times[segment+1]-times[segment])
            return integral[segment] + centered[segment]*dt + slope*dt*dt/2
        }
        var low = 0, high = 0
        return values.indices.map { i in
            let start = max(times[0],times[i]-window/2)
            let end = min(times.last!,times[i]+window/2)
            guard end > start else { return values[i] }
            return baseline + (area(to:end,segment:&high)-area(to:start,segment:&low))/(end-start)
        }
    }
    public static func unwrap(_ values: [Double]) -> [Double] {
        guard let first = values.first else { return [] }
        var result = [first]
        for i in 1..<values.count {
            var difference = values[i]-values[i-1]
            while difference > .pi { difference -= 2 * .pi }
            while difference < -.pi { difference += 2 * .pi }
            result.append(result.last!+difference)
        }
        return result
    }
    public static func derivative(_ values: [Double], times: [Double]) -> [Double] {
        guard values.count > 1, values.count == times.count else { return values.map { _ in 0 } }
        return values.indices.map { i in
            let a = max(0,i-1), b = min(values.count-1,i+1)
            return (values[b]-values[a])/max(1e-6,times[b]-times[a])
        }
    }
    public static func curvature(turnRate: Double, speed: Double) -> Double { speed > 0.05 ? abs(turnRate)/speed : 0 }

    public static func process(_ samples: [MotionSample], calibration: MountCalibration, settings: ReconstructionSettings) throws -> ProcessedSignals {
        guard samples.count >= 10, samples.allSatisfy(\.isValid) else { throw PodTrackError.invalid("At least 10 valid motion samples are required.") }
        guard zip(samples,samples.dropFirst()).allSatisfy({ $1.timestamp > $0.timestamp && $1.timestamp-$0.timestamp <= 0.5 }) else {
            throw PodTrackError.invalid("Sample timestamps must increase continuously, with no gap greater than 0.5 s.")
        }
        guard Set(samples.map(\.sensorLocation)) == [calibration.sensorLocation] else { throw PodTrackError.invalid("The run mixes sensors or differs from the mounting calibration.") }
        guard calibration.forwardDevice.isFinite, calibration.upDevice.isFinite,
              abs(calibration.forwardDevice.length-1)<0.01,abs(calibration.upDevice.length-1)<0.01,
              abs(calibration.forwardDevice.dot(calibration.upDevice))<0.05 else { throw PodTrackError.invalid("Mounting calibration has invalid axes.") }
        try checkAttitudeContinuity(samples)
        let times = samples.map { $0.timestamp-samples[0].timestamp }
        let native = orientation(samples,forward:calibration.forwardDevice,inverse:false)
        let inverse = orientation(samples,forward:calibration.forwardDevice,inverse:true)
        // Resolve passive/active quaternion convention using gravity constancy and gyro sign.
        // This also checks that the reported attitude is useful in the current reference frame.
        let useInverse = inverse.score + 0.00001 < native.score
        let chosen = useInverse ? inverse : native
        var warnings: [String] = []
        if chosen.gravityError > 0.15 { throw PodTrackError.invalid("Attitude and gravity disagree by more than 0.15 g. The reference frame may have reset; record a new continuous run.") }
        if chosen.gravityError > 0.035 { warnings.append("Attitude/gravity consistency is weak; heading and geometry may be distorted.") }
        let headings = smooth(chosen.heading,times:times,window:settings.smoothingSeconds)
        let slopes = smooth(samples.map { asin(clamp(calibration.forwardDevice.dot(-$0.gravity.normalized),-1,1)) },times:times,window:settings.smoothingSeconds)
        let tangential = smooth(samples.map { $0.userAcceleration.dot(calibration.forwardDevice)*standardGravity },times:times,window:settings.smoothingSeconds)
        let vertical = smooth(samples.map(\.verticalUserAcceleration),times:times,window:settings.smoothingSeconds)
        let turning = derivative(headings,times:times)
        if turning.contains(where:{ abs($0)>12 }) { warnings.append("Abrupt heading changes detected. Reference resets, a loose mount, or impacts may invalidate the path.") }
        let signals = samples.indices.map { i -> ProcessedSample in
            let s = samples[i], up = -s.gravity.normalized, forward = calibration.forwardDevice
            let projectedUp = (up-forward*up.dot(forward)).normalized
            let bank = atan2(forward.dot(calibration.upDevice.cross(projectedUp)),calibration.upDevice.dot(projectedUp))
            return .init(time:times[i],verticalUserAcceleration:vertical[i],tangentialUserAcceleration:tangential[i],
                         slope:slopes[i],heading:headings[i],bank:bank,turnRate:turning[i],supportProxyG:s.totalAccelerationMagnitudeG,
                         accelerationMagnitude:s.userAcceleration.length*standardGravity,
                         isQuiet:s.userAcceleration.length<0.035 && s.rotationRate.length<0.15)
        }
        let statistics = SampleStatistics(samples:samples)
        if statistics.frequencyHz < 25 { warnings.append("Sample rate is below 25 Hz; short impacts and airtime may be missed.") }
        if statistics.largestGap > 0.10 { warnings.append("Sample gaps exceed 100 ms; interpolation spans missing motion.") }
        return .init(samples:signals,attitudeMapping:useInverse ? "Inverse quaternion, checked against gravity and gyro" : "Direct quaternion, checked against gravity and gyro",warnings:warnings)
    }

    /// A reference reset can rotate heading while gravity remains consistent.
    /// Check the full quaternion step against a conservative gyro travel bound.
    /// This is a rejection test, not an attempted correction of unknown motion.
    private static func checkAttitudeContinuity(_ samples: [MotionSample]) throws {
        for (a,b) in zip(samples,samples.dropFirst()) {
            let qa = a.attitude.normalized, qb = b.attitude.normalized
            let dot = qa.x*qb.x + qa.y*qb.y + qa.z*qb.z + qa.w*qb.w
            // q and -q encode the same rotation.
            let step = 2*acos(clamp(abs(dot),0,1))
            let gyroBound = max(a.rotationRate.length,b.rotationRate.length)*(b.timestamp-a.timestamp)
            if step > gyroBound + 20 * .pi/180 {
                throw PodTrackError.invalid(String(format:"Orientation jumps by %.1f° near %.2f s without matching gyroscope motion. A reference reset or missing motion may have occurred; this run cannot provide a reliable track.",degrees(step),b.timestamp-samples[0].timestamp))
            }
        }
    }

    private static func orientation(_ samples: [MotionSample], forward: Vector3, inverse: Bool) -> (heading:[Double],score:Double,gravityError:Double) {
        let qs = samples.map { inverse ? $0.attitude.inverse : $0.attitude.normalized }
        let down = zip(qs,samples).map { $0.rotate($1.gravity.normalized) }
        let up = -down[0]
        let firstForward = qs[0].rotate(forward)
        let x = (firstForward-up*firstForward.dot(up)).normalized
        let y = up.cross(x).normalized
        let heading = unwrap(qs.map { q in let f = q.rotate(forward); return atan2(f.dot(y),f.dot(x)) })
        let gravityError = sqrt(down.map { pow(($0-down[0]).length,2) }.reduce(0,+)/Double(down.count))
        let rates = derivative(heading,times:samples.map(\.timestamp))
        let gyroError = zip(rates,samples).map { rate,s in min(4,pow(rate-s.rotationRate.dot(-s.gravity.normalized),2)) }.reduce(0,+)/Double(samples.count)
        return (heading,gravityError+0.02*gyroError,gravityError)
    }
}

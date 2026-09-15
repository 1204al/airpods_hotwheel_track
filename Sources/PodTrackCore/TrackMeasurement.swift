import Foundation

/// Measurements use the reconstructed centerline and its units (metres or relative units),
/// never the road mesh.
public struct TrackMeasurement: Equatable, Sendable {
    public var straightLine: Double
    public var alongTrack: Double
    public var horizontal: Double
    public var heightChange: Double
    public init(a: TrackPoint, b: TrackPoint) {
        let delta = b.position-a.position
        straightLine = delta.length
        alongTrack = abs(b.distance-a.distance)
        horizontal = hypot(delta.x,delta.y)
        heightChange = delta.z
    }
}

public enum TrackSampling {
    /// Interpolating time also preserves a selection when a run is reconstructed at a new H.
    public static func point(at time: Double, in points: [TrackPoint]) -> TrackPoint? {
        guard time.isFinite, let first = points.first, let last = points.last else { return nil }
        if time <= first.time { return first }
        if time >= last.time { return last }
        var low = 0, high = points.count-1
        while high-low>1 {
            let middle = (low+high)/2
            if points[middle].time<time { low = middle } else { high = middle }
        }
        let dt = points[high].time-points[low].time
        return interpolate(points[low],points[high],fraction:dt>0 ? (time-points[low].time)/dt : 0)
    }

    /// The nearest continuous segment, including interior points between motion samples.
    /// A preferred time disambiguates exact crossings and repeated stationary positions.
    public static func nearest(to position: Vector3, in points: [TrackPoint], preferredTime: Double = 0) -> TrackPoint? {
        guard position.isFinite, let first = points.first else { return nil }
        var best = first, bestDistance = (first.position-position).length
        for (a,b) in zip(points,points.dropFirst()) {
            let delta = b.position-a.position, squared = delta.dot(delta)
            let fraction = squared>1e-16 ? clamp((position-a.position).dot(delta)/squared,0,1)
                : clamp((preferredTime-a.time)/max(1e-12,b.time-a.time),0,1)
            let candidate = interpolate(a,b,fraction:fraction)
            let distance = (candidate.position-position).length
            if distance<bestDistance-1e-9 || (abs(distance-bestDistance)<1e-9 && abs(candidate.time-preferredTime)<abs(best.time-preferredTime)) {
                best = candidate; bestDistance = distance
            }
        }
        return best
    }

    private static func interpolate(_ a: TrackPoint, _ b: TrackPoint, fraction: Double) -> TrackPoint {
        let u = clamp(fraction,0,1)
        return .init(time:a.time+(b.time-a.time)*u,position:a.position+(b.position-a.position)*u,
                     speed:a.speed+(b.speed-a.speed)*u,distance:a.distance+(b.distance-a.distance)*u,
                     curvature:a.curvature+(b.curvature-a.curvature)*u,segmentLabel:u<0.5 ? a.segmentLabel : b.segmentLabel)
    }
}

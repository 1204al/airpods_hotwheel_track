import Foundation

public struct TrackPoint: Codable, Hashable, Sendable, Identifiable {
    public var time: Double
    public var position: Vector3
    public var speed: Double
    public var distance: Double
    public var curvature: Double
    public var segmentLabel: String = ""
    public var id: Double { time }
    public init(time: Double, position: Vector3, speed: Double, distance: Double, curvature: Double = 0, segmentLabel: String = "") {
        self.time = time; self.position = position; self.speed = speed; self.distance = distance
        self.curvature = curvature; self.segmentLabel = segmentLabel
    }
}

public struct TrackEstimate: Sendable {
    public var points: [TrackPoint]
    public var heightScale: Double
    public var horizontalScale: Double
    public var unscaledDrop: Double
    public var unscaledHeightRange: Double
    public var warnings: [String]
}

public enum TrackReconstructor {
    public static func reconstruct(signals: [ProcessedSample], speeds: [Double], verticalDrop: Double?,
                                   knownLength: Double? = nil, heightConstraint: HeightConstraint = .heightRange) throws -> TrackEstimate {
        guard signals.count == speeds.count, signals.count>1,
              verticalDrop.map({ $0.isFinite && $0 > 0 }) ?? true,
              knownLength.map({ $0.isFinite && $0 > 0 }) ?? true,
              speeds.allSatisfy({ $0.isFinite && $0>=0 }) else { throw PodTrackError.invalid("Invalid reconstruction inputs.") }
        var raw = [Vector3.zero]
        for i in 1..<signals.count {
            let dt = signals[i].time-signals[i-1].time
            guard dt.isFinite, dt > 0, signals[i].direction.isFinite, signals[i-1].direction.isFinite else {
                throw PodTrackError.invalid("Invalid reconstruction timing or direction.")
            }
            raw.append(raw[i-1] + (signals[i-1].direction*speeds[i-1]+signals[i].direction*speeds[i])*(0.5*dt))
        }
        let rawDrop = -raw.last!.z
        let rawMinZ = raw.map(\.z).min()!, rawMaxZ = raw.map(\.z).max()!
        let rawHeight = rawMaxZ-rawMinZ
        let observedHeight = heightConstraint == .heightRange ? rawHeight : rawDrop
        let rawLength = zip(raw,raw.dropFirst()).map { ($1-$0).length }.reduce(0,+)
        guard rawLength.isFinite, rawLength > 1e-6 else {
            throw PodTrackError.invalid("The motion trace has no usable path. Check mounting calibration and record sustained movement.")
        }
        let scale: Double
        if let verticalDrop {
            guard observedHeight > 0.005, observedHeight/max(rawLength,0.001)>0.005 else {
                throw PodTrackError.invalid(heightConstraint == .heightRange
                    ? "The motion trace has too little vertical movement to fit H. Check mounting calibration or choose Unknown to inspect the relative shape."
                    : "The orientation trace does not constrain a net descent. Check forward calibration or choose Unknown to inspect the relative shape.")
            }
            scale = verticalDrop/observedHeight
            guard (0.05...20).contains(scale) else { throw PodTrackError.invalid("The height would require a \(String(format:"%.1f",scale))× scale correction. The reconstruction is too weak to display as a useful path.") }
        } else {
            // With no physical reference, normalize the complete centerline to 1 unit.
            // A measured length alone instead supplies one uniform metric scale.
            scale = (knownLength ?? 1)/rawLength
        }
        var positions = raw.map { $0*scale }, horizontalScale = 1.0, warnings: [String] = []
        if verticalDrop == nil || heightConstraint == .heightRange {
            // A datum translation changes neither distances nor speed. The lowest sampled
            // centerline point is ground (Z=0), regardless of where the run ends.
            positions = positions.map { .init($0.x,$0.y,$0.z-rawMinZ*scale) }
        }
        if verticalDrop == nil {
            warnings.append(knownLength == nil
                ? "Height and track length are unknown. The whole path is normalized to 1 relative unit (u); distances use u and speeds use u/s. Add a measured height or length later to set a physical scale. Shape remains drift-prone."
                : "Height is unknown. Measured track length sets a uniform scale; the reconstructed height is an estimate.")
        } else if scale < 0.5 || scale > 2 {
            warnings.append("Height constraint rescales geometry and speed by more than 2×. Absolute scale is weakly observed.")
        }
        if let knownLength, verticalDrop != nil {
            let deltas = zip(positions,positions.dropFirst()).map { $1-$0 }
            let minimumLength = deltas.map { abs($0.z) }.reduce(0,+)
            func lengthAt(_ factor: Double) -> Double { deltas.map { sqrt(($0.x*$0.x+$0.y*$0.y)*factor*factor+$0.z*$0.z) }.reduce(0,+) }
            if knownLength < minimumLength || lengthAt(100)<knownLength {
                warnings.append("Known track length is incompatible with the reconstructed vertical profile. Only the height constraint was applied.")
            } else {
                var low = 0.0, high = 100.0
                for _ in 0..<70 { let middle = (low+high)/2; if lengthAt(middle)<knownLength { low = middle } else { high = middle } }
                horizontalScale = (low+high)/2
                positions = positions.map { .init($0.x*horizontalScale,$0.y*horizontalScale,$0.z) }
                warnings.append("Known length fitted by horizontal scaling. This changes path slope relative to the orientation-derived slope.")
            }
        }
        var distance = 0.0, points: [TrackPoint] = []
        for i in signals.indices {
            if i>0 { distance += (positions[i]-positions[i-1]).length }
            // Uniform scaling keeps the integrated speed. With a second length constraint,
            // scale each tangent consistently with the anisotropic geometry transform.
            let d = signals[i].direction
            let tangentScale = sqrt((d.x*d.x+d.y*d.y)*horizontalScale*horizontalScale+d.z*d.z)*scale
            let speed = speeds[i]*tangentScale
            // A relative unit is arbitrary; keep the low-speed cutoff in the
            // original velocity estimate, then transform curvature to 1/u.
            let curvature = verticalDrop == nil && knownLength == nil
                ? SignalProcessor.curvature(turnRate:signals[i].turnRate,speed:speeds[i])/scale
                : SignalProcessor.curvature(turnRate:signals[i].turnRate,speed:speed)
            points.append(.init(time:signals[i].time,position:positions[i],speed:speed,distance:distance,
                                curvature:curvature))
        }
        let minimumZ = positions.map(\.z).min() ?? 0
        let maximumZ = positions.map(\.z).max() ?? 0
        if let verticalDrop, heightConstraint == .endpointDrop && (minimumZ < -verticalDrop-0.05*verticalDrop || maximumZ>0.05*verticalDrop) {
            warnings.append("The path exceeds the assumed highest/lowest endpoints. Entered H constrains net endpoint drop; the full height range is inconsistent.")
        }
        return .init(points:points,heightScale:scale,horizontalScale:horizontalScale,unscaledDrop:rawDrop,unscaledHeightRange:rawHeight,warnings:warnings)
    }
}

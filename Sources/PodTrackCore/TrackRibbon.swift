import Foundation

public struct RibbonMesh: Sendable {
    public var vertices: [Vector3] = []
    public var normals: [Vector3] = []
    public var speeds: [Double] = []
    public var triangles: [UInt32] = []
    public init() {}
}

/// A schematic road, not a measured track cross-section. The path itself is unchanged.
public enum TrackRibbon {
    public static let width = 0.06
    public static let thickness = 0.004
    public static let railHeight = 0.014
    public static let railWidth = 0.004

    public struct Frame: Sendable {
        public var point: TrackPoint
        public var tangent: Vector3
        public var lateral: Vector3
        public var up: Vector3
    }

    /// Parallel transport avoids the singularity of cross(worldUp, tangent) on verticals.
    public static func frames(points: [TrackPoint], maximum: Int = 1200) -> [Frame] {
        var unique: [TrackPoint] = []
        for point in points where point.position.isFinite {
            if let last = unique.last, (point.position-last.position).length<1e-6 { continue }
            unique.append(point)
        }
        guard unique.count>1 else { return [] }
        if unique.count>max(2,maximum) {
            let count = max(2,maximum)
            unique = (0..<count).map { unique[$0*(unique.count-1)/(count-1)] }
        }
        var frames: [Frame] = []
        for i in unique.indices {
            let before = unique[max(0,i-1)].position, after = unique[min(unique.count-1,i+1)].position
            var tangent = (after-before).normalized
            if tangent.length<0.5 { tangent = (unique[i].position-before).normalized }
            if tangent.length<0.5 { tangent = .unitX }
            var up: Vector3
            if let previous = frames.last {
                let axis = previous.tangent.cross(tangent), sine = axis.length
                let cosine = clamp(previous.tangent.dot(tangent),-1,1)
                up = sine>1e-8 ? Quaternion(axis:axis,angle:atan2(sine,cosine)).rotate(previous.up) : previous.up
                up = (up-tangent*up.dot(tangent)).normalized
            } else {
                up = (Vector3.unitZ-tangent*tangent.z).normalized
            }
            if up.length<0.5 {
                let seed: Vector3 = abs(tangent.y)<0.9 ? .unitY : .unitX
                up = (seed-tangent*seed.dot(tangent)).normalized
            }
            let lateral = up.cross(tangent).normalized
            frames.append(.init(point:unique[i],tangent:tangent,lateral:lateral,up:tangent.cross(lateral).normalized))
        }
        return frames
    }

    public static func make(frames: [Frame], rails: Bool, crossSectionScale: Double = 1) -> RibbonMesh {
        var mesh = RibbonMesh()
        guard frames.count>1 else { return mesh }
        let width = Self.width*crossSectionScale, railWidth = Self.railWidth*crossSectionScale
        let thickness = Self.thickness*crossSectionScale, railHeight = Self.railHeight*crossSectionScale
        if rails {
            appendPrism(to:&mesh,frames:frames,left:-width/2,right:-width/2+railWidth,bottom:0,top:railHeight)
            appendPrism(to:&mesh,frames:frames,left:width/2-railWidth,right:width/2,bottom:0,top:railHeight)
        } else {
            appendPrism(to:&mesh,frames:frames,left:-width/2,right:width/2,bottom:-thickness,top:0)
        }
        return mesh
    }

    private static func appendPrism(to mesh: inout RibbonMesh, frames: [Frame], left: Double, right: Double, bottom: Double, top: Double) {
        let section = [(left,bottom),(right,bottom),(right,top),(left,top)]
        func vertex(_ frame: Frame, _ corner: Int) -> Vector3 {
            frame.point.position+frame.lateral*section[corner].0+frame.up*section[corner].1
        }
        // Separate faces retain crisp toy-plastic edges instead of rounding the normals.
        for side in 0..<4 {
            let next = (side+1)%4, base = UInt32(mesh.vertices.count)
            for frame in frames {
                let a = vertex(frame,side), b = vertex(frame,next)
                let normal = (b-a).cross(frame.tangent).normalized
                mesh.vertices += [a,b]; mesh.normals += [normal,normal]
                mesh.speeds += [frame.point.speed,frame.point.speed]
            }
            for i in 0..<(frames.count-1) {
                let a = base+UInt32(i*2)
                mesh.triangles += [a,a+1,a+3,a,a+3,a+2]
            }
        }
        for (frame,isStart) in [(frames.first!,true),(frames.last!,false)] {
            let base = UInt32(mesh.vertices.count), normal = frame.tangent*(isStart ? -1 : 1)
            for corner in 0..<4 {
                mesh.vertices.append(vertex(frame,corner)); mesh.normals.append(normal); mesh.speeds.append(frame.point.speed)
            }
            mesh.triangles += isStart ? [base,base+2,base+1,base,base+3,base+2] : [base,base+1,base+2,base,base+2,base+3]
        }
    }
}

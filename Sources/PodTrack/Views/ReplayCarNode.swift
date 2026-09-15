import AppKit
import SceneKit
import simd
import PodTrackCore

/// Schematic sports car. Its pose and wheel angle come only from the replay cursor,
/// so pausing, scrubbing and restarting cannot leave a separate animation running.
@MainActor final class ReplayCarNode: SCNNode {
    static let wheelRadius = 0.008
    let roadScale: Double
    private let poses: [(time: Double, orientation: simd_quatf)]
    private(set) var wheels: [SCNNode] = []

    init(frames: [TrackRibbon.Frame], roadScale: Double, stripeColor: NSColor = .white) {
        self.roadScale = max(0.0001,roadScale.isFinite ? roadScale : 1)
        poses = frames.map { frame in
            let basis = simd_float3x3(columns:(Self.vector(frame.tangent),Self.vector(frame.up),Self.vector(-frame.lateral)))
            return (frame.point.time,simd_quatf(basis))
        }
        super.init()
        name = "cursor"
        simdScale = SIMD3(repeating:Float(self.roadScale))
        buildCar(stripeColor:stripeColor)
        if let point = frames.first?.point { update(point:point) }
    }

    required init?(coder: NSCoder) { return nil }

    func update(point: TrackPoint) {
        guard point.time.isFinite, point.position.isFinite, point.distance.isFinite else { return }
        let attitude = orientation(at:point.time)
        simdOrientation = attitude
        // Lift along the road normal, including on the underside of a loop.
        simdPosition = Self.vector(point.position)+attitude.act(.init(0,Float(0.0006*roadScale),0))
        let angle = -point.distance/(Self.wheelRadius*roadScale)
        for wheel in wheels { wheel.eulerAngles.z = CGFloat(angle.truncatingRemainder(dividingBy:2 * .pi)) }
    }

    private func orientation(at time: Double) -> simd_quatf {
        guard let first = poses.first, let last = poses.last else { return simd_quatf(angle:0,axis:.init(0,1,0)) }
        if time<=first.time { return first.orientation }
        if time>=last.time { return last.orientation }
        var low = 0, high = poses.count-1
        while high-low>1 {
            let middle = (low+high)/2
            if poses[middle].time<time { low = middle } else { high = middle }
        }
        let fraction = Float(clamp((time-poses[low].time)/max(1e-12,poses[high].time-poses[low].time),0,1))
        return simd_slerp(poses[low].orientation,poses[high].orientation,fraction)
    }

    private static func vector(_ p: Vector3) -> SIMD3<Float> { .init(Float(p.x),Float(p.z),Float(-p.y)) }

    private func buildCar(stripeColor: NSColor) {
        let red = material(NSColor(calibratedRed:0.94,green:0.035,blue:0.06,alpha:1),shine:0.7)
        let glass = material(NSColor(calibratedRed:0.04,green:0.11,blue:0.18,alpha:1),shine:0.9)
        let rubber = material(NSColor(white:0.025,alpha:1))
        let carbon = material(NSColor(white:0.085,alpha:1))
        let alloy = material(NSColor(white:0.68,alpha:1),shine:0.8)
        let white = material(NSColor(white:0.97,alpha:1),shine:0.5)
        let stripe = material(stripeColor,shine:0.5)

        let body = extrusion([(-0.047,0.012),(0.047,0.012),(0.049,0.018),(0.031,0.025),(-0.037,0.026),(-0.048,0.021)],width:0.039,material:red)
        body.name = "sports-body"; addChildNode(body)
        addBox("front-splitter",size:(0.019,0.003,0.042),at:(0.039,0.010,0),material:carbon)
        addBox("rear-diffuser",size:(0.014,0.004,0.041),at:(-0.041,0.011,0),material:carbon)
        for side in [-1.0,1.0] {
            addBox("side-skirt",size:(0.047,0.004,0.043/12),at:(0,0.012,side*0.021),material:red)
            addBox("hood-stripe",size:(0.026,0.0008,0.003),at:(0.025,0.0255,side*0.004),material:stripe)
            addBox("rear-stripe",size:(0.013,0.0008,0.003),at:(-0.035,0.0265,side*0.004),material:stripe)
            addBox("wing-support",size:(0.003,0.010,0.002),at:(-0.039,0.030,side*0.014),material:carbon)
            let headlight = material(NSColor(calibratedRed:0.78,green:0.93,blue:1,alpha:1),glow:true)
            addBox("headlight",size:(0.002,0.003,0.012),at:(0.048,0.019,side*0.012),material:headlight)
            addBox("tail-light",size:(0.002,0.003,0.013),at:(-0.048,0.020,side*0.012),material:material(.systemRed,glow:true))
        }
        let cockpit = extrusion([(-0.023,0.026),(0.018,0.026),(0.005,0.039),(-0.013,0.039)],width:0.030,material:glass)
        cockpit.name = "dark-cockpit"; addChildNode(cockpit)
        addBox("roof",size:(0.017,0.001,0.030),at:(-0.004,0.0395,0),material:red)
        addBox("rear-wing",size:(0.013,0.003,0.050),at:(-0.041,0.036,0),material:carbon)

        for x in [-0.030,0.030] {
            for z in [-0.021,0.021] {
                let wheel = SCNNode(); wheel.name = "wheel"; wheel.position = .init(x,Self.wheelRadius,z)
                let tyre = SCNCylinder(radius:Self.wheelRadius,height:0.006); tyre.radialSegmentCount = 24
                tyre.materials = [rubber]
                let tyreNode = SCNNode(geometry:tyre); tyreNode.eulerAngles.x = .pi/2; wheel.addChildNode(tyreNode)
                let rim = SCNCylinder(radius:0.0055,height:0.0064); rim.radialSegmentCount = 16; rim.materials = [carbon]
                let rimNode = SCNNode(geometry:rim); rimNode.eulerAngles.x = .pi/2; wheel.addChildNode(rimNode)
                for angle in [0.0,Double.pi/2] {
                    let spoke = SCNBox(width:0.011,height:0.0014,length:0.0067,chamferRadius:0.0005); spoke.materials = [alloy]
                    let spokeNode = SCNNode(geometry:spoke); spokeNode.eulerAngles.z = CGFloat(angle); wheel.addChildNode(spokeNode)
                }
                wheels.append(wheel); addChildNode(wheel)
            }
        }

        // One visible AirPod represents the single bud mounted on the physical car.
        let pod = SCNNode(); pod.name = "mounted-airpod"; pod.position = .init(-0.002,0.044,0)
        pod.eulerAngles.z = -0.24
        let stem = SCNCapsule(capRadius:0.0027,height:0.024); stem.capSegmentCount = 5; stem.radialSegmentCount = 16; stem.materials = [white]
        let stemNode = SCNNode(geometry:stem); stemNode.position = .init(0,0.009,0); pod.addChildNode(stemNode)
        let head = SCNSphere(radius:0.0074); head.segmentCount = 20; head.materials = [white]
        let headNode = SCNNode(geometry:head); headNode.scale = .init(1.25,0.94,1); headNode.position = .init(0.003,0.022,0); pod.addChildNode(headNode)
        let tip = SCNSphere(radius:0.0045); tip.segmentCount = 12; tip.materials = [white]
        let tipNode = SCNNode(geometry:tip); tipNode.scale = .init(1,0.8,0.8); tipNode.position = .init(0.010,0.022,0); pod.addChildNode(tipNode)
        for side in [-1.0,1.0] {
            let vent = SCNSphere(radius:0.0023); vent.segmentCount = 12; vent.materials = [rubber]
            let ventNode = SCNNode(geometry:vent); ventNode.scale = .init(0.8,1.2,0.25); ventNode.position = .init(0.003,0.023,side*0.0073); pod.addChildNode(ventNode)
        }
        addBox("airpod-mount",size:(0.016,0.003,0.013),at:(-0.002,0.042,0),material:carbon)
        addChildNode(pod)
    }

    private func material(_ color: NSColor, shine: CGFloat = 0, glow: Bool = false) -> SCNMaterial {
        let value = SCNMaterial(); value.diffuse.contents = color; value.lightingModel = .blinn
        value.specular.contents = NSColor(white:shine,alpha:1); value.shininess = 0.55
        if glow { value.emission.contents = color }
        return value
    }

    private func addBox(_ name: String, size: (Double,Double,Double), at p: (Double,Double,Double), material: SCNMaterial) {
        let geometry = SCNBox(width:size.0,height:size.1,length:size.2,chamferRadius:min(size.0,size.1,size.2)*0.2)
        geometry.materials = [material]
        let node = SCNNode(geometry:geometry); node.name = name; node.position = .init(p.0,p.1,p.2); addChildNode(node)
    }

    private func extrusion(_ profile: [(Double,Double)], width: Double, material: SCNMaterial) -> SCNNode {
        var vertices: [SCNVector3] = [], normals: [SCNVector3] = [], indices: [Int32] = []
        func face(_ points: [SIMD3<Float>]) {
            let base = Int32(vertices.count), normal = simd_normalize(simd_cross(points[1]-points[0],points[2]-points[0]))
            vertices += points.map { SCNVector3($0.x,$0.y,$0.z) }
            normals += points.map { _ in SCNVector3(normal.x,normal.y,normal.z) }
            for i in 1..<(points.count-1) { indices += [base,base+Int32(i),base+Int32(i+1)] }
        }
        let front = profile.map { SIMD3<Float>(Float($0.0),Float($0.1),Float(width/2)) }
        let back = profile.map { SIMD3<Float>(Float($0.0),Float($0.1),Float(-width/2)) }
        face(front); face(Array(back.reversed()))
        for i in profile.indices { let j = (i+1)%profile.count; face([back[i],back[j],front[j],front[i]]) }
        let geometry = SCNGeometry(sources:[SCNGeometrySource(vertices:vertices),SCNGeometrySource(normals:normals)],
                                  elements:[SCNGeometryElement(indices:indices,primitiveType:.triangles)])
        geometry.materials = [material]
        return SCNNode(geometry:geometry)
    }
}

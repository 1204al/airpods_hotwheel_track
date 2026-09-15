import SceneKit
import AppKit
import PodTrackCore

@MainActor enum TrackScene {
    static let trackCategory = 2
    static let background = NSColor(calibratedRed:0.045,green:0.063,blue:0.082,alpha:1)
    static let orange = NSColor(calibratedRed:1,green:0.32,blue:0.055,alpha:1)
    static let cyan = NSColor(calibratedRed:0.22,green:0.88,blue:0.94,alpha:1)
    static let pink = NSColor(calibratedRed:1,green:0.43,blue:0.76,alpha:1)
    static func position(_ p: Vector3) -> SCNVector3 { .init(p.x,p.z,-p.y) }
    static func dataPosition(_ p: SCNVector3) -> Vector3 { .init(Double(p.x),Double(-p.z),Double(p.y)) }
    static func center(_ points: [TrackPoint]) -> SCNVector3 {
        let b = bounds(points)
        return position((b.low+b.high)/2)
    }
    static func bounds(_ points: [TrackPoint]) -> (low:Vector3,high:Vector3,span:Double) {
        let xs = points.map { $0.position.x }, ys = points.map { $0.position.y }, zs = points.map { $0.position.z }
        let low = Vector3(xs.min() ?? 0,ys.min() ?? 0,zs.min() ?? 0)
        let high = Vector3(xs.max() ?? 1,ys.max() ?? 1,zs.max() ?? RunMetadata.defaultHeightMeters)
        return (low,high,max(0.3,high.x-low.x,high.y-low.y,high.z-low.z))
    }
    static func speedColor(_ fraction: Double) -> NSColor {
        NSColor(calibratedHue:0.52-0.43*clamp(fraction,0,1),saturation:0.72,brightness:0.94,alpha:1)
    }

    static func make(result: AnalysisResult, options: TrackSceneOptions = .init()) -> SCNScene {
        let points = result.points, scene = baseScene(points:result.points)
        guard let first = points.first, let last = points.last else { return scene }
        let b = bounds(points), radius = result.isRelative ? b.span*0.004 : max(0.008,b.span*0.004)
        let crossSectionScale = result.isRelative ? b.span*0.5 : 1
        let frames = TrackRibbon.frames(points:points)
        for rails in [false,true] {
            let mesh = TrackRibbon.make(frames:frames,rails:rails,crossSectionScale:crossSectionScale)
            let node = SCNNode(geometry:geometry(mesh,appearance:options.appearance,rails:rails,maximumSpeed:result.metrics.estimatedMaximumSpeed))
            node.name = rails ? "track-rails" : "track-deck"
            node.categoryBitMask = trackCategory
            scene.rootNode.addChildNode(node)
        }
        let planes = makePlanes(points:points,height:result.metrics.enteredVerticalDrop ?? result.metrics.reconstructedHeightRange,
                                isRange:result.heightConstraint == .heightRange || result.metrics.enteredVerticalDrop == nil,
                                isRelative:result.isRelative,measuredHeight:result.metrics.enteredVerticalDrop != nil)
        planes.isHidden = !options.showPlanes
        scene.rootNode.addChildNode(planes)
        // Sparse supports are illustrative, not reconstructed hardware.
        let supports = SCNNode(); supports.name = "supports"
        for frame in frames.enumerated() where frame.offset % max(1,frames.count/8) == 0 {
            let p = frame.element.point.position
            if p.z-b.low.z>0.05*crossSectionScale {
                supports.addChildNode(tube(from:position(.init(p.x,p.y,b.low.z-TrackRibbon.thickness*crossSectionScale)),to:position(p-Vector3(0,0,TrackRibbon.thickness*crossSectionScale)),radius:0.007*crossSectionScale,color:NSColor(white:0.28,alpha:1)))
            }
        }
        scene.rootNode.addChildNode(supports)
        for (point,name,color) in [(first,"START",cyan),(last,"FINISH",orange)] {
            scene.rootNode.addChildNode(marker(at:position(point.position),radius:radius*1.5,color:color))
            scene.rootNode.addChildNode(label(name,at:point.position+Vector3(0,0,b.span*0.045),size:b.span*0.022,color:color))
        }
        let events = SCNNode(); events.name = "events"; events.isHidden = !options.showEvents
        for event in result.segments where [.leftTurn,.rightTurn,.bump,.airborne,.landing].contains(event.kind) {
            guard let point = TrackSampling.point(at:event.startTime,in:points) else { continue }
            let color: NSColor = event.kind == .airborne ? .systemPurple : event.kind == .landing ? .systemPink : .white
            let node = marker(at:position(point.position+Vector3(0,0,0.015*crossSectionScale)),radius:radius,color:color)
            node.name = event.kind.rawValue; events.addChildNode(node)
        }
        scene.rootNode.addChildNode(events)
        let cursor = ReplayCarNode(frames:frames,roadScale:crossSectionScale)
        scene.rootNode.addChildNode(cursor)
        cursor.update(point:first)
        return scene
    }

    static func baseScene(points: [TrackPoint]) -> SCNScene {
        let scene = SCNScene(), b = bounds(points)
        scene.background.contents = background
        let camera = SCNNode(); camera.name = "camera"; camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 44
        camera.camera?.zNear = 0.001; camera.camera?.zFar = b.span*100
        scene.rootNode.addChildNode(camera); fitCamera(in:scene,points:points)
        let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light?.type = .ambient
        ambient.light?.color = NSColor(calibratedRed:0.8,green:0.86,blue:1,alpha:1); ambient.light?.intensity = 520
        scene.rootNode.addChildNode(ambient)
        let sun = SCNNode(); sun.light = SCNLight(); sun.light?.type = .directional; sun.light?.intensity = 850
        sun.eulerAngles = .init(-Double.pi/3,-Double.pi/5,0)
        scene.rootNode.addChildNode(sun)
        return scene
    }

    static func fitCamera(in scene: SCNScene?, points: [TrackPoint]) {
        guard let camera = scene?.rootNode.childNode(withName:"camera",recursively:false) else { return }
        let b = bounds(points), target = center(points)
        camera.position = .init(target.x+CGFloat(b.span)*0.69,target.y+CGFloat(b.span)*1.04,target.z+CGFloat(b.span)*1.24)
        camera.look(at:target)
    }

    static func updateCursor(in scene: SCNScene, points: [TrackPoint], time: Double, isRelative: Bool = false) {
        guard let point = TrackSampling.point(at:time,in:points) else { return }
        SCNTransaction.begin(); SCNTransaction.animationDuration = 0
        (scene.rootNode.childNode(withName:"cursor",recursively:false) as? ReplayCarNode)?.update(point:point)
        SCNTransaction.commit()
    }

    static func updateMeasurement(in scene: SCNScene, points: [TrackPoint], selection: TrackRulerSelection, isRelative: Bool = false) {
        scene.rootNode.childNode(withName:"measurement",recursively:false)?.removeFromParentNode()
        let group = SCNNode(); group.name = "measurement"
        let span = bounds(points).span, radius = isRelative ? span*0.0045 : max(0.008,span*0.0045)
        let a = selection.aTime.flatMap { TrackSampling.point(at:$0,in:points) }
        let b = selection.bTime.flatMap { TrackSampling.point(at:$0,in:points) }
        for (point,name,color) in [(a,"A",cyan),(b,"B",pink)] {
            guard let point else { continue }
            let lifted = point.position+Vector3(0,0,span*0.06)
            group.addChildNode(tube(from:position(point.position),to:position(lifted),radius:radius*0.3,color:color,unlit:true))
            group.addChildNode(marker(at:position(point.position),radius:radius*1.5,color:color))
            group.addChildNode(label(name,at:lifted,size:span*0.032,color:color))
        }
        if let a, let b {
            let delta = b.position-a.position
            let count = min(120,max(1,Int(delta.length/max(0.01,span*0.018))))
            for i in 0..<count {
                let from = a.position+delta*(Double(i)/Double(count))
                let to = a.position+delta*((Double(i)+0.58)/Double(count))
                let node = tube(from:position(from),to:position(to),radius:radius*0.28,color:.white,unlit:true)
                node.geometry?.firstMaterial?.readsFromDepthBuffer = false; node.renderingOrder = 20
                group.addChildNode(node)
            }
            let distanceLabel = isRelative ? String(format:"%.3f u",delta.length) : String(format:"%.1f cm",delta.length*100)
            group.addChildNode(label(distanceLabel,at:(a.position+b.position)/2+Vector3(0,0,span*0.055),size:span*0.023,color:.white))
        }
        scene.rootNode.addChildNode(group)
    }

    private static func geometry(_ mesh: RibbonMesh, appearance: TrackAppearance, rails: Bool, maximumSpeed: Double) -> SCNGeometry {
        var sources = [SCNGeometrySource(vertices:mesh.vertices.map(position)),SCNGeometrySource(normals:mesh.normals.map(position))]
        if appearance == .speed {
            let values: [Float] = mesh.speeds.flatMap { speed in
                let color = speedColor(speed/max(0.01,maximumSpeed)).usingColorSpace(.deviceRGB)!
                return [Float(color.redComponent),Float(color.greenComponent),Float(color.blueComponent),1]
            }
            let data = values.withUnsafeBytes { Data($0) }
            sources.append(SCNGeometrySource(data:data,semantic:.color,vectorCount:mesh.vertices.count,usesFloatComponents:true,componentsPerVector:4,bytesPerComponent:4,dataOffset:0,dataStride:16))
        }
        let geometry = SCNGeometry(sources:sources,elements:[SCNGeometryElement(indices:mesh.triangles,primitiveType:.triangles)])
        let material = SCNMaterial(); material.lightingModel = .lambert
        material.diffuse.contents = appearance == .speed ? NSColor.white : (rails ? NSColor(calibratedRed:1,green:0.51,blue:0.12,alpha:1) : orange)
        material.isDoubleSided = true
        geometry.materials = [material]
        return geometry
    }

    static func makePlanes(points: [TrackPoint], height: Double, isRange: Bool, isRelative: Bool = false, measuredHeight: Bool = true) -> SCNNode {
        let b = bounds(points), padding = max(0.10,b.span*0.08)
        let xmin = b.low.x-padding, xmax = b.high.x+padding
        let ymin = b.low.y-padding, ymax = b.high.y+padding
        let group = SCNNode(); group.name = "height-planes"
        let groundLabel = isRelative ? "GROUND · 0 u" : "GROUND · 0 cm"
        let upperLabel = isRelative ? String(format:"HIGHEST · %.3f u",height)
            : isRange ? String(format:"HIGHEST · %.0f cm",height*100) : String(format:"GROUND + H · %.0f cm",height*100)
        for (z,name,color,alpha) in [(b.low.z,groundLabel,cyan,0.05),(b.low.z+height,upperLabel,orange,0.018)] {
            let corners = [Vector3(xmin,ymin,z),Vector3(xmax,ymin,z),Vector3(xmax,ymax,z),Vector3(xmin,ymax,z)]
            let plane = SCNGeometry(sources:[SCNGeometrySource(vertices:corners.map(position))],elements:[SCNGeometryElement(indices:[Int32(0),1,2,0,2,3],primitiveType:.triangles)])
            let material = SCNMaterial(); material.lightingModel = .constant
            material.diffuse.contents = color.withAlphaComponent(alpha); material.isDoubleSided = true
            material.writesToDepthBuffer = false; plane.materials = [material]
            let node = SCNNode(geometry:plane); node.renderingOrder = -10; group.addChildNode(node)
            for i in 0..<4 {
                group.addChildNode(tube(from:position(corners[i]),to:position(corners[(i+1)%4]),radius:b.span*0.0007,color:color.withAlphaComponent(0.5),unlit:true))
            }
            group.addChildNode(label(name,at:Vector3(xmin,ymin+(ymax-ymin)*0.60,z+b.span*0.014),size:b.span*0.02,color:color))
        }
        let candidates = [0.05,0.1,0.25,0.5,1,2,5,10,20,50]
        let spacing = candidates.first(where:{b.span/$0<=12}) ?? max(1,b.span/10)
        for i in Int(floor(xmin/spacing))...Int(ceil(xmax/spacing)) {
            let x = Double(i)*spacing
            group.addChildNode(tube(from:position(.init(x,ymin,b.low.z-0.006)),to:position(.init(x,ymax,b.low.z-0.006)),radius:b.span*0.00035,color:NSColor.white.withAlphaComponent(0.1),unlit:true))
        }
        for i in Int(floor(ymin/spacing))...Int(ceil(ymax/spacing)) {
            let y = Double(i)*spacing
            group.addChildNode(tube(from:position(.init(xmin,y,b.low.z-0.006)),to:position(.init(xmax,y,b.low.z-0.006)),radius:b.span*0.00035,color:NSColor.white.withAlphaComponent(0.1),unlit:true))
        }
        let lower = Vector3(xmin,ymax,b.low.z), upper = lower+Vector3(0,0,height)
        group.addChildNode(tube(from:position(lower),to:position(upper),radius:b.span*0.0012,color:orange,unlit:true))
        for end in [lower,upper] {
            group.addChildNode(tube(from:position(end-Vector3(b.span*0.015,0,0)),to:position(end+Vector3(b.span*0.015,0,0)),radius:b.span*0.0012,color:orange,unlit:true))
        }
        let heightLabel = isRelative ? String(format:"Δz = %.3f u",height)
            : String(format:measuredHeight ? "H = %.0f cm" : "EST. HEIGHT = %.0f cm",height*100)
        group.addChildNode(label(heightLabel,at:(lower+upper)/2+Vector3(b.span*0.02,0,0),size:b.span*0.021,color:orange))
        return group
    }

    static func label(_ text: String, at p: Vector3, size: Double, color: NSColor) -> SCNNode {
        let geometry = SCNText(string:text,extrusionDepth:0)
        geometry.font = NSFont.monospacedSystemFont(ofSize:12,weight:.semibold)
        geometry.flatness = 0.5
        geometry.firstMaterial?.lightingModel = .constant
        geometry.firstMaterial?.diffuse.contents = color
        geometry.firstMaterial?.isDoubleSided = true
        let node = SCNNode(geometry:geometry); node.position = position(p)
        node.scale = .init(size/12,size/12,size/12)
        node.constraints = [SCNBillboardConstraint()]
        return node
    }
    static func marker(at p: SCNVector3, radius: Double, color: NSColor) -> SCNNode {
        let sphere = SCNSphere(radius:radius); sphere.segmentCount = 12
        sphere.firstMaterial?.lightingModel = .constant; sphere.firstMaterial?.diffuse.contents = color
        let node = SCNNode(geometry:sphere); node.position = p; return node
    }
    private static func tube(from a: SCNVector3, to b: SCNVector3, radius: Double, color: NSColor, unlit: Bool = false) -> SCNNode {
        let dx = b.x-a.x, dy = b.y-a.y, dz = b.z-a.z, length = sqrt(dx*dx+dy*dy+dz*dz)
        guard length>1e-7 else { return SCNNode() }
        let cylinder = SCNCylinder(radius:radius,height:length); cylinder.radialSegmentCount = 6
        cylinder.firstMaterial?.diffuse.contents = color
        if unlit { cylinder.firstMaterial?.lightingModel = .constant }
        let node = SCNNode(geometry:cylinder); node.position = .init((a.x+b.x)/2,(a.y+b.y)/2,(a.z+b.z)/2)
        node.simdOrientation = simd_quatf(from:SIMD3<Float>(0,1,0),to:SIMD3<Float>(Float(dx/length),Float(dy/length),Float(dz/length)))
        return node
    }
}

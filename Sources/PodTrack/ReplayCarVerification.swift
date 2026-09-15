import AppKit
import ImageIO
import Metal
import SceneKit
import UniformTypeIdentifiers
import simd
import PodTrackCore

/// Offscreen, synthetic replay checks. Never connects headphones or reads saved runs.
@MainActor enum ReplayCarVerification {
    static func run(output: URL) throws {
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        let radius = 0.24
        let loop = (0...240).map { index -> TrackPoint in
            let angle = Double(index)/240 * 2 * Double.pi
            return .init(time:angle,position:.init(radius*sin(angle),0,radius*(1-cos(angle))),speed:radius,distance:radius*angle)
        }
        let car = ReplayCarNode(frames:TrackRibbon.frames(points:loop),roadScale:1)
        for angle in stride(from:0.10,through:6.1,by:0.025) {
            let point = TrackSampling.point(at:angle,in:loop)!
            car.update(point:point)
            let forward = car.simdOrientation.act(SIMD3<Float>(1,0,0)), up = car.simdOrientation.act(SIMD3<Float>(0,1,0))
            guard simd_dot(forward,.init(Float(cos(angle)),Float(sin(angle)),0))>0.999,
                  simd_dot(up,.init(Float(-sin(angle)),Float(cos(angle)),0))>0.999 else {
                throw PodTrackError.invalid("The replay car lost alignment on the loop at \(angle).")
            }
        }
        let quarterTurn = Double.pi*ReplayCarNode.wheelRadius/2
        car.update(point:.init(time:0,position:.zero,speed:0,distance:quarterTurn))
        let wheelPose = car.wheels[0].simdOrientation
        guard abs(wheelPose.act(.init(1,0,0)).y+1)<1e-5 else { throw PodTrackError.invalid("Wheel distance rotation failed.") }
        for _ in 0..<10 { car.update(point:.init(time:0,position:.zero,speed:0,distance:quarterTurn)) }
        guard abs(simd_dot(car.wheels[0].simdOrientation.vector,wheelPose.vector))>0.99999 else { throw PodTrackError.invalid("Paused wheels drifted.") }
        car.update(point:loop[0])
        guard car.wheels[0].simdOrientation.act(.init(1,0,0)).x>0.99999 else { throw PodTrackError.invalid("Wheel rewind failed.") }
        let relative = ReplayCarNode(frames:TrackRibbon.frames(points:loop),roadScale:0.25)
        relative.update(point:.init(time:0,position:.zero,speed:0,distance:quarterTurn*0.25))
        guard abs(relative.wheels[0].simdOrientation.act(.init(1,0,0)).y+1)<1e-5 else { throw PodTrackError.invalid("Relative-scale wheel rotation failed.") }
        guard car.childNode(withName:"mounted-airpod",recursively:false) != nil, car.wheels.count == 4 else {
            throw PodTrackError.invalid("Car geometry is incomplete.")
        }

        guard let device = MTLCreateSystemDefaultDevice() else { throw PodTrackError.invalid("A Metal device is required for the replay preview.") }
        let renderer = SCNRenderer(device:device,options:nil)
        let fixture = SimulatedTrack.generate(includeJump:false)
        var result = try AnalysisPipeline.analyze(.init(source:.simulation,metadata:.init(verticalDrop:0.42),calibration:fixture.calibration,samples:fixture.samples))
        let trackScene = TrackScene.make(result:result)
        TrackScene.updateCursor(in:trackScene,points:result.points,time:2.9)
        SCNTransaction.flush()
        let target = TrackSampling.point(at:2.9,in:result.points)!
        let roadHits = trackScene.rootNode.hitTestWithSegment(from:TrackScene.position(target.position+Vector3(0,0,1)),
            to:TrackScene.position(target.position-Vector3(0,0,1)),options:[SCNHitTestOption.categoryBitMask.rawValue:TrackScene.trackCategory,
                                                                       SCNHitTestOption.backFaceCulling.rawValue:false])
        guard !roadHits.isEmpty, roadHits.allSatisfy({ $0.node.name == "track-deck" || $0.node.name == "track-rails" }) else {
            throw PodTrackError.invalid("The replay car interfered with road measurement picking.")
        }
        renderer.scene = trackScene; renderer.pointOfView = trackScene.rootNode.childNode(withName:"camera",recursively:false)
        try save(renderer.snapshot(atTime:0,with:.init(width:1200,height:760),antialiasingMode:.multisampling4X),to:output.appendingPathComponent("track-sports-car.png"))

        let closeup = TrackScene.baseScene(points:loop)
        let displayCar = ReplayCarNode(frames:[],roadScale:1); closeup.rootNode.addChildNode(displayCar)
        displayCar.update(point:.init(time:0,position:.zero,speed:0,distance:quarterTurn/3))
        let plinth = SCNBox(width:0.21,height:0.004,length:0.066,chamferRadius:0.001)
        plinth.firstMaterial?.diffuse.contents = TrackScene.orange
        let road = SCNNode(geometry:plinth); road.position = .init(0,-0.002,0); closeup.rootNode.addChildNode(road)
        let camera = closeup.rootNode.childNode(withName:"camera",recursively:false)!
        camera.position = .init(0.14,0.115,0.18); camera.camera?.fieldOfView = 34; camera.look(at:.init(0,0.029,0))
        renderer.scene = closeup; renderer.pointOfView = camera
        try save(renderer.snapshot(atTime:0,with:.init(width:960,height:640),antialiasingMode:.multisampling4X),to:output.appendingPathComponent("sports-car-closeup.png"))

        result.points = loop; result.segments = []
        result.metrics.reconstructedHeightRange = radius*2; result.metrics.enteredVerticalDrop = radius*2
        result.metrics.estimatedPathLength = loop.last!.distance
        // Exercise the shared replay, including release offsets and normalized tracks.
        let firstRun = RunSession(source:.simulation,metadata:.init(carName:"Red car A",verticalDrop:radius*2),calibration:fixture.calibration,samples:fixture.samples)
        let secondRun = RunSession(source:.simulation,metadata:.init(carName:"Red car B",verticalDrop:radius*2),calibration:fixture.calibration,samples:fixture.samples)
        var secondResult = result
        secondResult.points = loop.map { point in
            var copy = point; copy.time += 0.8
            copy.position.y = 0.14*sin(point.time)
            return copy
        }
        for relative in [false,true] {
            let entries = [ComparisonEntry(run:firstRun,result:result,colorIndex:0,normalizeToUnitLength:relative),
                           ComparisonEntry(run:secondRun,result:secondResult,colorIndex:1,normalizeToUnitLength:relative)]
            let comparison = ComparisonScene.make(entries:entries,showPlanes:false)
            let scale = relative ? TrackScene.bounds(entries.flatMap(\.points)).span*0.5 : 1
            for elapsed in [0.0,0.7,1.8,Double.pi,5.3,100,0] {
                ComparisonScene.updateCursors(in:comparison,entries:entries,elapsed:elapsed)
                for entry in entries {
                    guard let point = entry.point(at:elapsed),
                          let replayCar = comparison.rootNode.childNode(withName:"cursor-\(entry.id)",recursively:true) as? ReplayCarNode else {
                        throw PodTrackError.invalid("Comparison replay is missing a car.")
                    }
                    let position = TrackScene.position(point.position)
                    let offset = replayCar.simdPosition-SIMD3(Float(position.x),Float(position.y),Float(position.z))
                    let up = replayCar.simdOrientation.act(SIMD3<Float>(0,1,0))
                    guard replayCar.wheels.count == 4, abs(replayCar.roadScale-scale)<1e-8,
                          abs(Double(simd_dot(offset,up))-0.0006*scale)<1e-6,
                          abs(Double(simd_length(offset))-0.0006*scale)<1e-6 else {
                        throw PodTrackError.invalid("Comparison car left its road during replay, rewind or finish clamping.")
                    }
                }
            }
            if !relative {
                ComparisonScene.updateCursors(in:comparison,entries:entries,elapsed:1.4)
                renderer.scene = comparison; renderer.pointOfView = comparison.rootNode.childNode(withName:"camera",recursively:false)
                try save(renderer.snapshot(atTime:0,with:.init(width:1200,height:760),antialiasingMode:.multisampling4X),to:output.appendingPathComponent("comparison-red-cars.png"))
            }
        }
        let scene = TrackScene.make(result:result,options:.init(showPlanes:false))
        for node in scene.rootNode.childNodes where node.geometry is SCNText { node.removeFromParentNode() }
        renderer.scene = scene; renderer.pointOfView = scene.rootNode.childNode(withName:"camera",recursively:false)
        let url = output.appendingPathComponent("sports-car-loop.gif")
        let frameCount = 64
        guard let gif = CGImageDestinationCreateWithURL(url as CFURL,UTType.gif.identifier as CFString,frameCount,nil) else {
            throw PodTrackError.invalid("Could not create the animation preview.")
        }
        CGImageDestinationSetProperties(gif,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFLoopCount:0]] as CFDictionary)
        for index in 0..<frameCount {
            TrackScene.updateCursor(in:scene,points:loop,time:Double(index)/Double(frameCount)*2 * .pi)
            let image = renderer.snapshot(atTime:Double(index)/20,with:.init(width:720,height:560),antialiasingMode:.multisampling4X)
            if [0,16,32,48].contains(index) { try save(image,to:output.appendingPathComponent("loop-\(index).png")) }
            guard let cgImage = image.cgImage(forProposedRect:nil,context:nil,hints:nil) else { throw PodTrackError.invalid("Animation frame render failed.") }
            CGImageDestinationAddImage(gif,cgImage,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFDelayTime:0.05]] as CFDictionary)
        }
        guard CGImageDestinationFinalize(gif) else { throw PodTrackError.invalid("Could not finish the animation preview.") }
        let report = "PASS: analytic loop alignment (including vertical and inverted poses), wheel distance, pause, rewind, relative scale, four wheels, mounted AirPod and road measurement picking.\nPASS: comparison uses cars with correct road scale, release alignment, inverted road contact, rewind and finish clamping in metric and relative units.\nRendered static track, red car closeup, comparison and 64-frame loop animation from synthetic data.\nNo hardware or user recordings accessed.\n"
        try report.write(to:output.appendingPathComponent("checks.txt"),atomically:true,encoding:.utf8)
        print(report)
    }

    private static func save(_ image: NSImage, to url: URL) throws {
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data:tiff),
              let png = bitmap.representation(using:.png,properties:[:]) else { throw PodTrackError.invalid("Scene preview failed.") }
        try png.write(to:url)
    }
}

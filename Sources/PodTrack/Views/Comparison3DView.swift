import SwiftUI
import SceneKit
import PodTrackCore

struct ComparisonEntry: Identifiable, Equatable {
    let id: UUID
    let name: String
    let colorIndex: Int
    let height: Double?
    let isRelative: Bool
    let bud: String
    let points: [TrackPoint]
    let releaseTime: Double
    var duration: Double { max(0,(points.last?.time ?? releaseTime)-releaseTime) }

    init(run: RunSession, result: AnalysisResult, colorIndex: Int, normalizeToUnitLength: Bool = false) {
        id = run.id
        name = run.comparisonDisplayName
        self.colorIndex = colorIndex
        height = run.metadata.verticalDrop
        isRelative = result.isRelative || normalizeToUnitLength
        bud = run.recordedOrigin.label
        // A comparison containing an unknown scale normalizes every path to 1 u.
        // Otherwise preserve each saved metric scale.
        let start = result.points.first?.position ?? .zero
        let offset = Vector3(start.x,start.y,result.groundZ)
        let factor = normalizeToUnitLength ? 1/max(1e-12,result.metrics.estimatedPathLength) : 1
        points = result.points.map { p in
            var copy = p
            copy.position = (p.position-offset)*factor
            copy.distance *= factor; copy.speed *= factor; copy.curvature /= factor
            return copy
        }
        releaseTime = result.segments.first { $0.kind == .release }?.startTime ?? result.points.first?.time ?? 0
    }
    func point(at elapsed: Double) -> TrackPoint? { TrackSampling.point(at:releaseTime+elapsed,in:points) }
}

@MainActor enum ComparisonScene {
    static let colors: [NSColor] = [TrackScene.orange,TrackScene.cyan,TrackScene.pink,NSColor(calibratedRed:0.56,green:0.49,blue:1,alpha:1)]
    static func color(_ index: Int) -> NSColor { colors[index % colors.count] }

    static func make(entries: [ComparisonEntry], showPlanes: Bool = true) -> SCNScene {
        let all = entries.flatMap(\.points)
        let scene = TrackScene.baseScene(points:all)
        guard !all.isEmpty else { return scene }
        let span = TrackScene.bounds(all).span
        let planes = TrackScene.makePlanes(points:all,height:(all.map { $0.position.z }.max() ?? 0),isRange:true,
                                          isRelative:entries.contains(where:\.isRelative),measuredHeight:false)
        planes.isHidden = !showPlanes; scene.rootNode.addChildNode(planes)
        for entry in entries {
            guard let last = entry.points.last else { continue }
            let color = color(entry.colorIndex)
            let group = SCNNode(); group.name = "trajectory-\(entry.id)"
            let frames = TrackRibbon.frames(points:entry.points)
            let roadScale = entry.isRelative ? span*0.5 : 1
            for rails in [false,true] {
                let mesh = TrackRibbon.make(frames:frames,rails:rails,crossSectionScale:roadScale)
                let geometry = SCNGeometry(sources:[SCNGeometrySource(vertices:mesh.vertices.map(TrackScene.position)),
                    SCNGeometrySource(normals:mesh.normals.map(TrackScene.position))],
                    elements:[SCNGeometryElement(indices:mesh.triangles,primitiveType:.triangles)])
                let material = SCNMaterial(); material.diffuse.contents = color
                material.lightingModel = .lambert; material.isDoubleSided = true
                geometry.materials = [material]
                let road = SCNNode(geometry:geometry); road.name = rails ? "rails" : "road"
                group.addChildNode(road)
            }
            let car = ReplayCarNode(frames:frames,roadScale:roadScale,stripeColor:color)
            car.name = "cursor-\(entry.id)"; group.addChildNode(car)
            group.addChildNode(TrackScene.label("\(entry.colorIndex+1) · \(entry.bud) · FINISH",at:last.position+Vector3(0,0,span*0.035),size:span*0.017,color:color))
            scene.rootNode.addChildNode(group)
        }
        updateCursors(in:scene,entries:entries,elapsed:0)
        return scene
    }

    static func updateCursors(in scene: SCNScene, entries: [ComparisonEntry], elapsed: Double) {
        SCNTransaction.begin(); SCNTransaction.animationDuration = 0
        for entry in entries {
            guard let point = entry.point(at:elapsed) else { continue }
            (scene.rootNode.childNode(withName:"cursor-\(entry.id)",recursively:true) as? ReplayCarNode)?.update(point:point)
        }
        SCNTransaction.commit()
    }
}

struct Comparison3DView: NSViewRepresentable {
    let entries: [ComparisonEntry]
    var elapsed: Double
    var showPlanes: Bool
    var cameraReset: Int
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.allowsCameraControl = true; view.antialiasingMode = .multisampling4X
        view.backgroundColor = TrackScene.background
        view.setAccessibilityLabel("Selected trajectories in a shared 3D scene. Drag to orbit and scroll to zoom. Red replay cars align to each run's release; their stripes match the track colors.")
        return view
    }
    func updateNSView(_ view: SCNView, context: Context) {
        let coordinator = context.coordinator
        if view.scene == nil || coordinator.entries != entries {
            view.scene = ComparisonScene.make(entries:entries,showPlanes:showPlanes)
            view.pointOfView = view.scene?.rootNode.childNode(withName:"camera",recursively:false)
            view.defaultCameraController.stopInertia()
            view.defaultCameraController.target = TrackScene.center(entries.flatMap(\.points))
            coordinator.entries = entries
        }
        view.scene?.rootNode.childNode(withName:"height-planes",recursively:false)?.isHidden = !showPlanes
        if coordinator.cameraReset != cameraReset {
            TrackScene.fitCamera(in:view.scene,points:entries.flatMap(\.points))
            view.pointOfView = view.scene?.rootNode.childNode(withName:"camera",recursively:false)
            view.defaultCameraController.stopInertia()
            view.defaultCameraController.target = TrackScene.center(entries.flatMap(\.points))
            coordinator.cameraReset = cameraReset
        }
        if let scene = view.scene { ComparisonScene.updateCursors(in:scene,entries:entries,elapsed:elapsed) }
    }
    final class Coordinator {
        var entries: [ComparisonEntry] = []
        var cameraReset = 0
    }
}

struct ComparisonExplorerView: View {
    let entries: [ComparisonEntry]
    // Offscreen verification uses a separately rendered image of this same SceneKit scene.
    var renderedScene: NSImage? = nil
    var onRemove: ((UUID) -> Void)?
    @State private var elapsed: Double = 0
    @State private var isPlaying = false
    @State private var showPlanes = true
    @State private var cameraReset = 0
    private var duration: Double { entries.map(\.duration).max() ?? 0 }
    private var isRelative: Bool { entries.contains(where:\.isRelative) }

    init(entries: [ComparisonEntry], renderedScene: NSImage? = nil, initialElapsed: Double = 0, onRemove: ((UUID) -> Void)? = nil) {
        self.entries = entries; self.renderedScene = renderedScene
        self.onRemove = onRemove
        _elapsed = State(initialValue:initialElapsed)
    }

    var body: some View {
        Panel(title:"2 · Compare in 3D",subtitle:"\(entries.count) \(entries.count == 1 ? "trajectory" : "trajectories")") {
            if isRelative {
                Text("Shape comparison · every path = 1 u. Physical sizes and speeds cannot be compared while a scale is unknown.")
                    .font(.callout).foregroundStyle(PodTheme.teal).fixedSize(horizontal:false,vertical:true)
            }
            HStack {
                Toggle("Height planes",isOn:$showPlanes)
                Spacer()
                Button("Fit all",systemImage:"arrow.up.left.and.arrow.down.right") { cameraReset += 1 }
            }.font(.caption)
            if let renderedScene {
                Image(nsImage:renderedScene).resizable().aspectRatio(contentMode:.fit).frame(height:360).frame(maxWidth:.infinity)
            } else {
                Comparison3DView(entries:entries,elapsed:elapsed,showPlanes:showPlanes,cameraReset:cameraReset)
                    .frame(height:360).clipShape(RoundedRectangle(cornerRadius:8))
            }
            Text("Drag to rotate · scroll to zoom · colours match your selected runs").font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns:[GridItem(.adaptive(minimum:200),alignment:.leading)],alignment:.leading,spacing:10) {
                ForEach(entries) { entry in
                    HStack {
                        VStack(alignment:.leading,spacing:4) {
                            Label("\(entry.colorIndex+1) · \(entry.name)",systemImage:"circle.fill")
                                .foregroundStyle(Color(nsColor:ComparisonScene.color(entry.colorIndex))).font(.caption.bold())
                            Text(entry.height.map { "Recorded H \(formatted($0*100,0)) cm" } ?? "H unknown").font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer(minLength:0)
                        if let onRemove {
                            Button { onRemove(entry.id) } label: { Image(systemName:"xmark.circle.fill") }
                                .buttonStyle(.plain).foregroundStyle(.secondary)
                                .accessibilityLabel("Remove \(entry.name) from comparison")
                                .help("Remove this run from the comparison")
                        }
                    }.padding(8).background(Color.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:7))
                }
            }
            HStack {
                Button(isPlaying ? "Pause" : "Play together",systemImage:isPlaying ? "pause.fill" : "play.fill") {
                    if !isPlaying && elapsed>=duration { elapsed = 0 }
                    isPlaying.toggle()
                }.disabled(duration<=0)
                Button("Restart",systemImage:"backward.end.fill") { isPlaying = false; elapsed = 0 }
                Spacer(minLength:0)
                Text("\(formatted(elapsed)) / \(formatted(duration)) s").font(.caption.monospacedDigit())
            }
                Slider(value:$elapsed,in:0...max(0.01,duration),onEditingChanged:{ if $0 { isPlaying = false } })
                    .accessibilityLabel("Comparison time since each run's release")
            DisclosureGroup("How the tracks line up") {
                Text(isRelative
                     ? "Ground = 0. Each path is normalized to a total length of 1 relative unit. Starting X/Y and initial heading align. Replay uses actual elapsed seconds since release. This compares estimated shape and progress, not physical size or speed."
                     : "Ground = 0. Paths share their starting X/Y and initial heading; each keeps its recorded scale. Replay aligns each run's release. Actual spacing between cars is unknown; coincident paths overlap. Shapes and speeds are estimates.")
                    .foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }.font(.caption)
        }.onChange(of:entries) { _,_ in isPlaying = false; elapsed = 0 }
            .task(id:isPlaying) {
                guard isPlaying else { return }
                let started = ProcessInfo.processInfo.systemUptime, startTime = elapsed
                while !Task.isCancelled {
                    elapsed = min(duration,startTime+ProcessInfo.processInfo.systemUptime-started)
                    if elapsed>=duration { isPlaying = false; break }
                    do { try await Task.sleep(nanoseconds:33_000_000) } catch { break }
                }
            }
    }
}

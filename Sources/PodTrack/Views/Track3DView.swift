import SceneKit
import SwiftUI
import PodTrackCore

enum TrackAppearance: String, CaseIterable { case orange = "Orange track", speed = "Speed colors" }
struct TrackSceneOptions: Equatable {
    var appearance: TrackAppearance = .orange
    var showPlanes = true
    var showEvents = false
}

struct TrackRulerSelection: Equatable {
    enum Endpoint: String { case a = "A", b = "B" }
    var aTime: Double?
    var bTime: Double?
    var next: Endpoint = .a
    mutating func select(_ time: Double) {
        if next == .a { aTime = time; next = .b }
        else { bTime = time; next = .a }
    }
}

struct Track3DView: NSViewRepresentable {
    let result: AnalysisResult
    var selectedTime: Double
    var options = TrackSceneOptions()
    var selection = TrackRulerSelection()
    var isMeasuring = false
    var cameraReset = 0
    var cameraPoints: [TrackPoint]? = nil
    var onPick: (Double) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.allowsCameraControl = true
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = TrackScene.background
        view.defaultCameraController.inertiaEnabled = true
        view.setAccessibilityLabel("Estimated orange track in 3D. Drag to orbit, scroll to zoom. Use the A and B cursor buttons below to measure without clicking in 3D.")
        let click = NSClickGestureRecognizer(target:context.coordinator,action:#selector(Coordinator.clicked(_:)))
        click.delegate = context.coordinator
        view.addGestureRecognizer(click)
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        let framing = cameraPoints ?? result.points
        let geometryChanged = coordinator.runID != result.runID || coordinator.points != result.points || coordinator.scaleBasis != result.resolvedScaleBasis
        if geometryChanged || coordinator.options != options {
            let oldCamera = view.pointOfView?.transform
            let oldTarget = view.defaultCameraController.target
            let scene = TrackScene.make(result:result,options:options)
            view.scene = scene
            view.pointOfView = scene.rootNode.childNode(withName:"camera",recursively:false)
            if !geometryChanged, let oldCamera {
                view.pointOfView?.transform = oldCamera
                view.defaultCameraController.target = oldTarget
            } else {
                TrackScene.fitCamera(in:scene,points:framing)
                view.defaultCameraController.target = TrackScene.center(framing)
            }
            coordinator.runID = result.runID; coordinator.points = result.points; coordinator.options = options
            coordinator.scaleBasis = result.resolvedScaleBasis
        }
        if coordinator.cameraReset != cameraReset {
            TrackScene.fitCamera(in:view.scene,points:framing)
            view.pointOfView = view.scene?.rootNode.childNode(withName:"camera",recursively:false)
            view.defaultCameraController.stopInertia()
            view.defaultCameraController.target = TrackScene.center(framing)
            coordinator.cameraReset = cameraReset
        }
        if let scene = view.scene {
            TrackScene.updateCursor(in:scene,points:result.points,time:selectedTime,isRelative:result.isRelative)
            if geometryChanged || coordinator.selection != selection || coordinator.wasMeasuring != isMeasuring || coordinator.rulerScene !== scene {
                TrackScene.updateMeasurement(in:scene,points:result.points,selection:isMeasuring ? selection : .init(),isRelative:result.isRelative)
                coordinator.selection = selection; coordinator.wasMeasuring = isMeasuring; coordinator.rulerScene = scene
            }
        }
    }

    @MainActor final class Coordinator: NSObject, NSGestureRecognizerDelegate {
        var parent: Track3DView?
        var runID: UUID?
        var points: [TrackPoint] = []
        var scaleBasis: ReconstructionScale?
        var options: TrackSceneOptions?
        var selection: TrackRulerSelection?
        var cameraReset = 0
        var wasMeasuring = false
        weak var rulerScene: SCNScene?
        @objc func clicked(_ recognizer: NSClickGestureRecognizer) {
            guard let parent, parent.isMeasuring, let view = recognizer.view as? SCNView else { return }
            let hits = view.hitTest(recognizer.location(in:view),options:[.categoryBitMask:TrackScene.trackCategory,.backFaceCulling:false,.searchMode:SCNHitTestSearchMode.closest.rawValue])
            guard let hit = hits.first,
                  let point = TrackSampling.nearest(to:TrackScene.dataPosition(hit.worldCoordinates),in:points,preferredTime:parent.selectedTime) else { return }
            parent.onPick(point.time)
        }
        func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: NSGestureRecognizer) -> Bool { true }
    }
}

import SwiftUI
import PodTrackCore

struct TrackExplorerView: View {
    @EnvironmentObject var model: AppModel
    let run: RunSession
    let result: AnalysisResult
    var sceneHeight: CGFloat = 420
    var renderedScene: NSImage? = nil
    @State private var options = TrackSceneOptions()
    @State private var cameraReset = 0
    @State private var isPlaying = false

    var body: some View {
        Panel(title:"Estimated track in 3D",subtitle:"Drag to orbit · scroll to zoom") {
            HStack {
                Text(run.carDisplayName).font(.callout.bold()).fixedSize(horizontal:false,vertical:true)
                Spacer()
                Text(model.reconstructionMethod.rawValue).font(.caption.bold()).foregroundStyle(PodTheme.teal)
            }
            TrackHeightControl(run:run) { model.updateRun($0) }
            HStack(spacing:14) {
                Picker("Track appearance",selection:$options.appearance) {
                    ForEach(TrackAppearance.allCases,id:\.self) { Text($0.rawValue).tag($0) }
                }.labelsHidden().frame(width:150)
                Toggle("Height planes",isOn:$options.showPlanes)
                Toggle("Events",isOn:$options.showEvents)
                Spacer(minLength:0)
                Button("Fit view",systemImage:"arrow.up.left.and.arrow.down.right") { cameraReset += 1 }
            }.font(.caption)
            if let renderedScene {
                Image(nsImage:renderedScene).resizable().aspectRatio(contentMode:.fit).frame(height:sceneHeight).frame(maxWidth:.infinity)
            } else {
              Track3DView(result:result,selectedTime:model.cursorTime,options:options,selection:model.rulerSelection,
                        isMeasuring:model.rulerEnabled,cameraReset:cameraReset) { time in
                model.rulerSelection.select(time); model.cursorTime = time
            }.frame(height:sceneHeight).clipShape(RoundedRectangle(cornerRadius:8))
            }
            HStack {
                Button(isPlaying ? "Pause" : "Play run",systemImage:isPlaying ? "pause.fill" : "play.fill") {
                    if !isPlaying, model.cursorTime>=run.duration-0.01 { model.cursorTime = 0 }
                    isPlaying.toggle()
                }
                Button(model.rulerEnabled ? "Done measuring" : "Measure A–B",systemImage:"ruler") { model.rulerEnabled.toggle() }
                    .buttonStyle(.borderedProminent).tint(model.rulerEnabled ? PodTheme.teal : .orange)
                if model.rulerEnabled {
                    Text("Click the track to set \(model.rulerSelection.next.rawValue). Drag to rotate.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Orange road, rails & supports are schematic.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength:0)
            }
            if model.rulerEnabled {
                TrackRulerControls(points:result.points,groundZ:result.groundZ,selection:$model.rulerSelection,cursorTime:$model.cursorTime,isRelative:result.isRelative)
            }
            if options.appearance == .speed { SpeedLegend(maximum:result.metrics.estimatedMaximumSpeed,unit:result.speedUnit) }
        }.task(id:isPlaying) {
            guard isPlaying else { return }
            let started = ProcessInfo.processInfo.systemUptime, startTime = model.cursorTime
            while !Task.isCancelled {
                let time = startTime+ProcessInfo.processInfo.systemUptime-started
                model.cursorTime = min(run.duration,time)
                if time>=run.duration { isPlaying = false; break }
                do { try await Task.sleep(nanoseconds:33_000_000) } catch { break }
            }
        }
    }
}

struct TrackHeightControl: View {
    let run: RunSession
    var onChange: (RunSession) -> Void
    @State private var heightText = ""
    @State private var heightIsKnown = false
    @State private var error: String?
    init(run: RunSession, onChange: @escaping (RunSession) -> Void) {
        self.run = run; self.onChange = onChange
        _heightText = State(initialValue:formatted((run.metadata.verticalDrop ?? RunMetadata.defaultHeightMeters)*100,1))
        _heightIsKnown = State(initialValue:run.metadata.verticalDrop != nil)
    }
    private var enteredHeight: Double? { Double(heightText.replacingOccurrences(of:",",with:".")).map { $0/100 } }
    private var hasChanges: Bool {
        if heightIsKnown != (run.metadata.verticalDrop != nil) { return true }
        return heightIsKnown && (enteredHeight != run.metadata.verticalDrop || run.metadata.resolvedHeightConstraint != .heightRange)
    }
    var body: some View {
        VStack(alignment:.leading,spacing:6) {
            HStack(spacing:10) {
                Image(systemName:"arrow.up.and.down").foregroundStyle(.orange)
                Text("Height H").font(.callout.weight(.medium))
                HeightKnowledgePicker(isKnown:$heightIsKnown).frame(width:175)
                Spacer(minLength:0)
            }
            HStack(spacing:10) {
                if heightIsKnown {
                TextField("58",text:$heightText).textFieldStyle(.roundedBorder).frame(width:70)
                    .accessibilityLabel("Highest point above ground in centimetres")
                    .onSubmit(apply)
                HeightStepper(text:$heightText)
                Text("cm").foregroundStyle(.secondary)
                }
                Button(heightIsKnown ? "Apply height" : "Apply unknown",action:apply)
                    .disabled(!hasChanges)
                Spacer(minLength:0)
            }
            if hasChanges {
                Text(heightIsKnown ? "Not saved yet. Apply height to update this recording." : "Not saved yet. Apply unknown to update this recording.")
                    .font(.caption).foregroundStyle(PodTheme.amber)
            }
            Text(!heightIsKnown
                 ? run.metadata.knownTrackLength == nil
                    ? "Scale unknown · whole path = 1 u. Distances use u; speeds use u/s. Enter a measured height later to set scale."
                    : "Height unknown · scale comes from the measured track length."
                 : run.metadata.resolvedHeightConstraint == .heightRange
                 ? "Ground = lowest point. Highest point = H. Record a pass through both levels."
                 : "This saved run uses a start-to-finish drop. Apply height to use lowest-to-highest H.")
                .font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }.onAppear { sync() }
            .onChange(of:run.metadata) { _,_ in sync() }
            .onChange(of:run.id) { _,_ in sync() }
            .onChange(of:heightIsKnown) { _,_ in error = nil }
    }
    private func sync() {
        heightIsKnown = run.metadata.verticalDrop != nil
        if let height = run.metadata.verticalDrop { heightText = formatted(height*100,1) }
        error = nil
    }
    private func apply() {
        do {
            var updated = run
            if heightIsKnown {
                guard let height = enteredHeight else { throw PodTrackError.invalid("Enter a height in cm, or choose Unknown.") }
                updated.metadata.verticalDrop = height
            } else { updated.metadata.verticalDrop = nil }
            updated.metadata.heightConstraint = .heightRange
            try updated.metadata.validate()
            onChange(updated); error = nil
        } catch { self.error = error.localizedDescription }
    }
}

struct TrackRulerControls: View {
    let points: [TrackPoint]
    let groundZ: Double
    @Binding var selection: TrackRulerSelection
    @Binding var cursorTime: Double
    var isRelative = false
    private var a: TrackPoint? { selection.aTime.flatMap { TrackSampling.point(at:$0,in:points) } }
    private var b: TrackPoint? { selection.bTime.flatMap { TrackSampling.point(at:$0,in:points) } }
    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            HStack(spacing:12) {
                endpoint(.a,point:a,color:Color(nsColor:TrackScene.cyan))
                endpoint(.b,point:b,color:Color(nsColor:TrackScene.pink))
                VStack(spacing:8) {
                    Button("Swap") { let oldA = selection.aTime; selection.aTime = selection.bTime; selection.bTime = oldA }.disabled(a == nil || b == nil)
                    Button("Clear") { selection = .init() }.disabled(a == nil && b == nil)
                }.font(.caption)
            }
            HStack(spacing:10) {
                Text("Cursor").font(.caption).foregroundStyle(.secondary)
                Slider(value:$cursorTime,in:(points.first?.time ?? 0)...max(0.01,points.last?.time ?? 1))
                    .accessibilityLabel("Track measurement cursor time")
                Text("\(formatted(cursorTime)) s").font(.system(.caption,design:.monospaced)).frame(width:62,alignment:.trailing)
            }
            if let a, let b { TrackMeasurementReadout(measurement:.init(a:a,b:b),isRelative:isRelative) }
            else {
                Text("Choose A and B on the track, or move the cursor and use the buttons above.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Estimated distances between centerline points; Δ height is B minus A.")
                .font(.caption2).foregroundStyle(.secondary)
        }.padding(12).background(Color.white.opacity(0.025),in:RoundedRectangle(cornerRadius:8))
    }
    private func endpoint(_ end: TrackRulerSelection.Endpoint, point: TrackPoint?, color: Color) -> some View {
        VStack(alignment:.leading,spacing:7) {
            HStack(spacing:8) {
                Button { selection.next = end } label: {
                    Text("Pick \(end.rawValue)").font(.caption.bold())
                }.tint(color).buttonStyle(.bordered)
                    .overlay(RoundedRectangle(cornerRadius:5).stroke(selection.next == end ? color : .clear,lineWidth:1))
                    .accessibilityLabel("Select point \(end.rawValue) on next track click")
                Text(point.map { "\(formatted($0.time)) s" } ?? "Not set").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Spacer(minLength:0)
            }
            Text(point.map { "Height \(formatted(($0.position.z-groundZ)*(isRelative ? 1 : 100),isRelative ? 3 : 1)) \(isRelative ? "u" : "cm")" } ?? "Click any point")
                .font(.caption).foregroundStyle(color)
            Button("Set \(end.rawValue) at cursor") {
                if end == .a { selection.aTime = cursorTime; selection.next = .b }
                else { selection.bTime = cursorTime; selection.next = .a }
            }.font(.caption)
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
}

struct TrackMeasurementReadout: View {
    let measurement: TrackMeasurement
    var isRelative = false
    var body: some View {
        ViewThatFits(in:.horizontal) {
            HStack(spacing:20) { values }
            LazyVGrid(columns:[GridItem(.flexible(),alignment:.leading),GridItem(.flexible(),alignment:.leading)],alignment:.leading,spacing:12) { values }
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
    @ViewBuilder private var values: some View {
        value("Straight A–B",measurement.straightLine)
        value("Along track",measurement.alongTrack)
        value("Horizontal",measurement.horizontal)
        value("Δ height",measurement.heightChange,signed:true)
    }
    private func value(_ title: String, _ metres: Double, signed: Bool = false) -> some View {
        VStack(alignment:.leading,spacing:4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text("\(signed && metres>0 ? "+" : "")\(formatted(metres*(isRelative ? 1 : 100),isRelative ? 3 : 1)) \(isRelative ? "u" : "cm")")
                .font(.system(size:18,weight:.semibold,design:.rounded)).monospacedDigit().fixedSize()
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
}

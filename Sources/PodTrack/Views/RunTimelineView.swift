import SwiftUI
import PodTrackCore

extension SegmentKind {
    var timelineColor: Color {
        switch self {
        case .start: return .gray
        case .release: return PodTheme.teal
        case .finish: return .gray
        case .downhill: return .green
        case .uphill: return .yellow
        case .flat: return .secondary
        case .leftTurn, .rightTurn: return .blue
        case .bump: return .white
        case .airborne: return .purple
        case .landing: return .pink
        }
    }
    /// Short, distinct candidates get a full-height tick; continuous slope and turn runs
    /// stay a background band, so the timeline is not a wall of ticks.
    var isPointEvent: Bool {
        switch self {
        case .release, .bump, .airborne, .landing, .finish: return true
        default: return false
        }
    }
}

/// A moment the range handles and the playhead snap to.
struct TimelineMarker: Identifiable {
    let time: Double
    let kind: SegmentKind
    let isStart: Bool
    var id: String { "\(kind.rawValue)-\(time)-\(isStart)" }
    var label: String { "\(kind.rawValue) \(isStart ? "start" : "end") · \(formatted(time)) s" }
}

enum RunTimeline {
    /// Every candidate boundary, plus the recording's own ends. Duplicated times collapse so
    /// snapping does not stutter between two markers a millisecond apart.
    static func markers(segments: [RunSegment], duration: Double) -> [TimelineMarker] {
        var found: [TimelineMarker] = []
        for segment in segments {
            found.append(.init(time:segment.startTime,kind:segment.kind,isStart:true))
            found.append(.init(time:segment.endTime,kind:segment.kind,isStart:false))
        }
        found = found.filter { $0.time.isFinite && $0.time >= 0 && $0.time <= duration }
        return found.sorted { $0.time<$1.time }
    }
    static func snapTimes(_ markers: [TimelineMarker], duration: Double) -> [Double] {
        var times = markers.map(\.time)+[0,duration]
        times.sort()
        var unique: [Double] = []
        for time in times where unique.last.map({ time-$0 > 0.004 }) ?? true { unique.append(time) }
        return unique
    }
    /// Nearest snap time within `tolerance`, or the raw value when nothing is close.
    static func snapped(_ time: Double, to times: [Double], tolerance: Double) -> Double {
        guard let nearest = times.min(by:{ abs($0-time)<abs($1-time) }), abs(nearest-time) <= tolerance else { return time }
        return nearest
    }
    static func neighbour(of time: Double, in times: [Double], forward: Bool) -> Double? {
        forward ? times.first { $0 > time+0.004 } : times.last { $0 < time-0.004 }
    }
}

/// The play line: candidate events, a draggable playhead, and two range handles that limit
/// the run to part of its own time. The range selects rows; it never re-runs a reconstruction.
struct RunTimelineView: View {
    let segments: [RunSegment]
    let duration: Double
    @Binding var cursorTime: Double
    @Binding var window: TimeWindow?
    var onExportSelection: (() -> Void)? = nil

    @State private var dragging: Handle?
    private enum Handle { case start, end, cursor }
    private var span: Double { max(0.01,duration) }
    private var markers: [TimelineMarker] { RunTimeline.markers(segments:segments,duration:span) }
    private var snapTimes: [Double] { RunTimeline.snapTimes(markers,duration:span) }
    private var active: TimeWindow { window ?? .init(start:0,end:span) }
    private var isTrimmed: Bool { window != nil }

    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            timeline.frame(height:64)
            controls
            legend
        }
    }

    private func x(_ time: Double, _ width: Double) -> Double { clamp(time/span,0,1)*width }
    private func time(_ x: Double, _ width: Double) -> Double { clamp(x/max(1,width),0,1)*span }

    private var timeline: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let low = x(active.start,width), high = x(active.end,width)
            ZStack(alignment:.topLeading) {
                Canvas { context, size in draw(&context,size:size) }
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance:0,coordinateSpace:.named("timeline")).onChanged { value in
                        cursorTime = active.clamping(time(value.location.x,width))
                    })
                // Everything outside the range is dimmed rather than hidden, so the run's
                // full length stays visible while only part of it is shown in 3D.
                if isTrimmed {
                    Rectangle().fill(.black.opacity(0.55)).frame(width:max(0,low)).allowsHitTesting(false)
                    Rectangle().fill(.black.opacity(0.55)).frame(width:max(0,width-high)).offset(x:high).allowsHitTesting(false)
                }
                playhead(at:x(cursorTime,width))
                handle(.start,at:low,width:width)
                handle(.end,at:high,width:width)
            }.coordinateSpace(name:"timeline")
        }.accessibilityElement()
            .accessibilityLabel("Run timeline with candidate events")
            .accessibilityValue("Showing \(formatted(active.start)) to \(formatted(active.end)) seconds, playhead at \(formatted(cursorTime)) seconds")
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize) {
        let width = size.width, laneTop = 8.0, laneHeight = size.height-22
        context.fill(Path(roundedRect:CGRect(x:0,y:laneTop,width:width,height:laneHeight),cornerRadius:5),
                     with:.color(.primary.opacity(0.08)))
        // Continuous slope and turn candidates as faint bands, newest lane on top.
        let lanes = ["Slope","Turns","Events","Run"]
        for segment in segments where !segment.kind.isPointEvent {
            guard let lane = lanes.firstIndex(of:segment.kind.lane) else { continue }
            let bandHeight = laneHeight/Double(lanes.count)
            let rect = CGRect(x:x(segment.startTime,width),y:laneTop+Double(lane)*bandHeight+1,
                              width:max(1,x(segment.endTime,width)-x(segment.startTime,width)),height:bandHeight-2)
            context.fill(Path(roundedRect:rect,cornerRadius:2),with:.color(segment.kind.timelineColor.opacity(0.28)))
        }
        for segment in segments where segment.kind.isPointEvent {
            let position = x(segment.startTime,width)
            let rect = CGRect(x:position-1,y:laneTop,width:2.5,height:laneHeight)
            context.fill(Path(rect),with:.color(segment.kind.timelineColor.opacity(0.95)))
            context.fill(Path(ellipseIn:CGRect(x:position-3,y:laneTop-3,width:6,height:6)),
                         with:.color(segment.kind.timelineColor))
        }
        // Whole seconds, so the scale of the recording is readable without a chart axis.
        let step = span>20 ? 5.0 : span>8 ? 2.0 : 1.0
        var tick = 0.0
        while tick <= span {
            let position = x(tick,width)
            context.stroke(Path { $0.move(to:.init(x:position,y:laneTop+laneHeight)); $0.addLine(to:.init(x:position,y:laneTop+laneHeight+4)) },
                           with:.color(.secondary.opacity(0.5)),lineWidth:1)
            context.draw(Text("\(Int(tick))s").font(.system(size:9,design:.monospaced)).foregroundStyle(.secondary),
                         at:.init(x:position,y:laneTop+laneHeight+11))
            tick += step
        }
    }

    private func playhead(at position: Double) -> some View {
        VStack(spacing:0) {
            Circle().fill(.white).frame(width:9,height:9)
            Rectangle().fill(.white).frame(width:2,height:51)
        }.frame(width:9,alignment:.center).offset(x:position-4.5,y:2).allowsHitTesting(false)
    }

    private func handle(_ which: Handle, at position: Double, width: Double) -> some View {
        let isStart = which == .start
        return ZStack {
            // A transparent margin around the 9 pt bar, so the edge is easy to grab.
            Rectangle().fill(.clear).frame(width:26,height:64)
            RoundedRectangle(cornerRadius:3).fill(dragging == which ? .white : PodTheme.teal)
                .frame(width:9,height:64)
                .overlay(Rectangle().fill(.black.opacity(0.35)).frame(width:1.5,height:20))
        // Kept inside the control at both ends, so a handle at 0 s stays fully grabbable.
        }.frame(width:26,height:64).contentShape(Rectangle())
            .offset(x:min(max(position-13,0),max(0,width-26)))
            .gesture(DragGesture(minimumDistance:0,coordinateSpace:.named("timeline")).onChanged { value in
                dragging = which
                let raw = time(value.location.x,width)
                let snapped = RunTimeline.snapped(raw,to:snapTimes,tolerance:span*6/max(1,width))
                let current = active
                let updated = isStart ? TimeWindow(start:snapped,end:current.end) : TimeWindow(start:current.start,end:snapped)
                window = updated.limited(to:span)
                cursorTime = (window ?? updated).clamping(cursorTime)
            }.onEnded { _ in dragging = nil })
            .help(isStart ? "Drag to move the start of the shown range. It snaps to candidate events."
                          : "Drag to move the end of the shown range. It snaps to candidate events.")
            .accessibilityLabel(isStart ? "Range start \(formatted(active.start)) seconds" : "Range end \(formatted(active.end)) seconds")
    }

    private var controls: some View {
        HStack(spacing:10) {
            Text(isTrimmed ? "Showing \(formatted(active.start))–\(formatted(active.end)) s of \(formatted(span)) s"
                           : "Whole run · \(formatted(span)) s")
                .font(.caption.monospacedDigit())
                .foregroundStyle(isTrimmed ? PodTheme.teal : .secondary)
            step(.start,forward:false); step(.start,forward:true)
            Text("start").font(.caption2).foregroundStyle(.secondary)
            step(.end,forward:false); step(.end,forward:true)
            Text("end").font(.caption2).foregroundStyle(.secondary)
            Spacer(minLength:0)
            Button("Trim to playhead") { window = TimeWindow(start:cursorTime,end:active.end).limited(to:span) }
                .font(.caption).help("Move the start of the range to the playhead.")
            Button("Whole run") { window = nil }.font(.caption).disabled(!isTrimmed)
            if let onExportSelection {
                Button(isTrimmed ? "Export \(formatted(active.duration)) s…" : "Export run…",systemImage:"square.and.arrow.up") {
                    onExportSelection()
                }.font(.caption).buttonStyle(.borderedProminent).tint(PodTheme.teal)
                    .help("Export only the shown range of this recording.")
            }
        }
    }

    /// Jump one candidate boundary at a time, which is more precise than dragging.
    private func step(_ which: Handle, forward: Bool) -> some View {
        Button {
            let current = active
            let from = which == .start ? current.start : current.end
            guard let next = RunTimeline.neighbour(of:from,in:snapTimes,forward:forward) else { return }
            let updated = which == .start ? TimeWindow(start:next,end:current.end) : TimeWindow(start:current.start,end:next)
            window = updated.limited(to:span)
            cursorTime = (window ?? updated).clamping(cursorTime)
        } label: {
            Image(systemName:forward ? "chevron.right.2" : "chevron.left.2").font(.caption2)
        }.buttonStyle(.bordered).controlSize(.small)
            .accessibilityLabel("Move range \(which == .start ? "start" : "end") to the \(forward ? "next" : "previous") event")
    }

    private var legend: some View {
        HStack(spacing:14) {
            ForEach(SegmentKind.allCases.filter { kind in segments.contains { $0.kind == kind } },id:\.self) { kind in
                HStack(spacing:4) {
                    RoundedRectangle(cornerRadius:1.5).fill(kind.timelineColor.opacity(kind.isPointEvent ? 0.95 : 0.4))
                        .frame(width:kind.isPointEvent ? 3 : 10,height:8)
                    Text(kind.rawValue)
                }
            }
            Spacer(minLength:0)
        }.font(.system(size:10)).foregroundStyle(.secondary)
    }
}

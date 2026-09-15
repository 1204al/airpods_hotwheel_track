import SwiftUI
import Charts
import PodTrackCore

struct TrackTopDownView: View {
    let points: [TrackPoint]
    var selectedTime: Double
    var color: Color = PodTheme.teal
    var isRelative = false
    var body: some View {
        GeometryReader { geometry in
            Canvas { context,size in
                let xs = points.map { $0.position.x }, ys = points.map { $0.position.y }
                let xmin = xs.min() ?? 0, xmax = xs.max() ?? 1, ymin = ys.min() ?? 0, ymax = ys.max() ?? 1
                let scale = min((size.width-32)/max(0.1,xmax-xmin),(size.height-32)/max(0.1,ymax-ymin))
                func project(_ p: TrackPoint) -> CGPoint {
                    .init(x:size.width/2+(p.position.x-(xmin+xmax)/2)*scale,y:size.height/2-(p.position.y-(ymin+ymax)/2)*scale)
                }
                for i in 0...4 {
                    var grid = Path()
                    let x = size.width*Double(i)/4, y = size.height*Double(i)/4
                    grid.move(to:.init(x:x,y:0)); grid.addLine(to:.init(x:x,y:size.height))
                    grid.move(to:.init(x:0,y:y)); grid.addLine(to:.init(x:size.width,y:y))
                    context.stroke(grid,with:.color(.secondary.opacity(0.1)),lineWidth:1)
                }
                var path = Path()
                for (i,p) in points.enumerated() { if i == 0 { path.move(to:project(p)) } else { path.addLine(to:project(p)) } }
                context.stroke(path,with:.color(color),style:.init(lineWidth:2.5,lineCap:.round,lineJoin:.round))
                for (p,c) in [(points.first,color),(points.last,PodTheme.amber),(points.min(by:{abs($0.time-selectedTime)<abs($1.time-selectedTime)}),Color.white)] {
                    if let p { let xy = project(p); context.fill(Path(ellipseIn:.init(x:xy.x-4,y:xy.y-4,width:8,height:8)),with:.color(c)) }
                }
                context.draw(Text("X →   Y ↑  ·  \(isRelative ? "relative units" : "metres") · equal scale").font(.system(size:9,design:.monospaced)).foregroundStyle(.secondary),at:.init(x:8,y:size.height-4),anchor:.bottomLeading)
            }.frame(width:geometry.size.width,height:geometry.size.height)
        }.frame(minHeight:170)
            .accessibilityLabel("Estimated top-down XY path, equal axis scale, coordinates in \(isRelative ? "relative units" : "metres")")
    }
}

struct TrackSideProfileView: View {
    let points: [TrackPoint]
    var selectedTime: Double
    var unit = "m"
    private var ground: Double { points.map { $0.position.z }.min() ?? 0 }
    private var height: Double { (points.map { $0.position.z }.max() ?? 0)-ground }
    var body: some View {
        Chart {
            RuleMark(y:.value("Ground",0)).foregroundStyle(PodTheme.teal.opacity(0.4)).lineStyle(.init(dash:[4,4]))
            RuleMark(y:.value("Highest",height)).foregroundStyle(.orange.opacity(0.5)).lineStyle(.init(dash:[4,4]))
            ForEach(thinned(points)) { p in
                LineMark(x:.value("Path distance (\(unit))",p.distance),y:.value("Above ground (\(unit))",p.position.z-ground)).foregroundStyle(.orange)
            }
            if let p = points.min(by:{abs($0.time-selectedTime)<abs($1.time-selectedTime)}) {
                PointMark(x:.value("Path distance (\(unit))",p.distance),y:.value("Above ground (\(unit))",p.position.z-ground)).foregroundStyle(.white)
            }
        }.chartYScale(domain:0...max(0.001,height*1.1))
            .chartXAxisLabel("Estimated path distance (\(unit))").chartYAxisLabel("Above ground (\(unit))").frame(height:170)
    }
}

func thinned<T>(_ values: [T], maximum: Int = 500) -> [T] {
    guard values.count>maximum else { return values }
    let step = max(1,values.count/maximum)
    var output = stride(from:0,to:values.count,by:step).map { values[$0] }
    if (values.count-1)%step != 0, let last = values.last { output.append(last) }
    return output
}

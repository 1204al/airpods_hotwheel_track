import SwiftUI
import Charts
import PodTrackCore

struct SpeedChartView: View {
    let points: [TrackPoint]
    @Binding var selectedTime: Double
    var byDistance = false
    var distanceUnit = "m"
    var speedUnit = "m/s"
    var body: some View {
        Chart {
            ForEach(thinned(points)) { p in
                AreaMark(x:.value("X",byDistance ? p.distance : p.time),y:.value("Speed",p.speed)).foregroundStyle(PodTheme.teal.opacity(0.1))
                LineMark(x:.value("X",byDistance ? p.distance : p.time),y:.value("Speed",p.speed)).foregroundStyle(PodTheme.teal)
            }
            if let p = points.min(by:{abs($0.time-selectedTime)<abs($1.time-selectedTime)}) {
                RuleMark(x:.value("Selected",byDistance ? p.distance : p.time)).foregroundStyle(.secondary).lineStyle(.init(dash:[3,3]))
                PointMark(x:.value("Selected",byDistance ? p.distance : p.time),y:.value("Speed",p.speed)).foregroundStyle(.white)
            }
        }.chartXAxisLabel(byDistance ? "Estimated distance (\(distanceUnit))" : "Time (s)").chartYAxisLabel("Est. speed (\(speedUnit))")
            .chartXSelection(value:Binding<Double?>(get:{
                if byDistance { return points.min(by:{abs($0.time-selectedTime)<abs($1.time-selectedTime)})?.distance }
                return selectedTime
            },set:{ value in
                if let value {
                    selectedTime = byDistance ? (points.min(by:{abs($0.distance-value)<abs($1.distance-value)})?.time ?? selectedTime) : value
                }
            }))
            .frame(height:160)
    }
}

struct DerivedSignalChart: View {
    let signals: [ProcessedSample]
    let field: KeyPath<ProcessedSample,Double>
    let units: String
    var multiplier: Double = 1
    var cursor: Double
    var color: Color = PodTheme.amber
    var body: some View {
        Chart {
            ForEach(thinned(signals)) { s in
                LineMark(x:.value("Time",s.time),y:.value(units,s[keyPath:field]*multiplier)).foregroundStyle(color)
            }
            RuleMark(x:.value("Cursor",cursor)).foregroundStyle(.secondary).lineStyle(.init(dash:[3,3]))
            RuleMark(y:.value("Zero",0)).foregroundStyle(.secondary.opacity(0.3))
        }.chartXAxisLabel("Time (s)").chartYAxisLabel(units).frame(height:160)
    }
}

struct SegmentTimelineView: View {
    let segments: [RunSegment]
    let duration: Double
    @Binding var selectedTime: Double
    var body: some View {
        Chart {
            ForEach(segments) { s in
                BarMark(xStart:.value("Start",s.startTime),xEnd:.value("End",s.endTime),y:.value("Layer",s.kind.lane),height:14)
                    .foregroundStyle(by:.value("Candidate",s.kind.rawValue)).cornerRadius(3)
            }
            RuleMark(x:.value("Selected",selectedTime)).foregroundStyle(.white)
        }.chartXScale(domain:0...max(0.1,duration)).chartLegend(.hidden)
            .chartXSelection(value:Binding<Double?>(get:{selectedTime},set:{if let value = $0 { selectedTime = clamp(value,0,duration) }}))
            .frame(height:110)
    }
}

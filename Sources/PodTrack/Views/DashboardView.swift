import SwiftUI
import PodTrackCore

struct DashboardView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                PageHeader(eyebrow:"Live telemetry",title:"Every motion, in view.",detail:"Measured Core Motion outputs in the sensor frame. The charts keep a rolling history; recording preserves every received sample separately.")
                HStack {
                    Button("Start motion",systemImage:"play.fill") { model.startMotion() }.buttonStyle(.borderedProminent)
                    Button("Stop motion",systemImage:"stop.fill") { model.stopMotion() }
                    Divider().frame(height:20)
                    Button(model.isDashboardPaused ? "Resume plots" : "Pause plots",systemImage:model.isDashboardPaused ? "play" : "pause") { model.isDashboardPaused.toggle() }
                    Button("Clear buffer",systemImage:"trash") { model.clearBuffer() }
                    Button("CSV",systemImage:"square.and.arrow.up") { model.exportBuffer() }.disabled(model.history.isEmpty)
                    Spacer()
                    Text(model.sourceKind == .airPods ? "STREAM · \(model.latest?.sensorLocation.rawValue.uppercased() ?? "UNKNOWN") AIRPOD" : "SIMULATED INPUT")
                        .font(.system(.caption,design:.monospaced)).foregroundStyle(PodTheme.teal)
                }
                HStack {
                    if model.sourceKind == .airPods { RecordingBudPicker().frame(maxWidth:350) }
                    Button(model.recording ? "Stop & save \(model.recordingSourceLabel)" : "Record \(model.recordingSourceLabel)",systemImage:"record.circle") {
                        if model.recording { model.finishRecording() } else { model.area = .record }
                    }.tint(model.recording ? .red : PodTheme.teal)
                    Spacer(minLength:0)
                    HeadphoneStatusSummary(compact:true)
                }
                if model.isDashboardPaused { Notice(text:"Plots are paused. Motion reception and any active recording continue.") }
                HStack(spacing:12) {
                    MetricTile(title:"Sample rate",value:formatted(model.statistics.frequencyHz,1),unit:"Hz")
                    MetricTile(title:"Interval jitter",value:formatted(model.statistics.jitterMilliseconds,1),unit:"ms")
                    MetricTile(title:"User acceleration |a|",value:model.latest.map { formatted($0.userAcceleration.length,3) } ?? "—",unit:"g")
                    MetricTile(title:"Rotation |ω|",value:model.latest.map { formatted($0.rotationRate.length,3) } ?? "—",unit:"rad/s")
                }
                LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:16) {
                    ForEach(RawSignal.allCases,id:\.self) { signal in
                        Panel(title:signal.rawValue,subtitle:"Sensor frame · \(signal.units)") {
                            SignalChartView(samples:model.history,signal:signal)
                        }
                    }
                }
                Text("\(model.history.count) buffered samples · largest recent interval \(formatted(model.statistics.largestGap*1000,1)) ms · AirPods reporting frequency is controlled by the system.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(28)
        }
    }
}

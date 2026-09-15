import Charts
import SwiftUI
import PodTrackCore

enum RawSignal: String, CaseIterable {
    case acceleration = "User acceleration", rotation = "Rotation rate", gravity = "Gravity", attitude = "Attitude"
    var units: String { switch self { case .acceleration,.gravity: return "g"; case .rotation: return "rad/s"; case .attitude: return "°" } }
    func vector(_ s: MotionSample) -> Vector3 {
        switch self {
        case .acceleration: return s.userAcceleration
        case .rotation: return s.rotationRate
        case .gravity: return s.gravity
        case .attitude: return .init(degrees(s.roll),degrees(s.pitch),degrees(s.yaw))
        }
    }
}

struct SignalChartView: View {
    var samples: [MotionSample]
    var signal: RawSignal
    var origin: Double? = nil
    var cursor: Double? = nil
    private var chartSamples: [MotionSample] {
        let strideSize = max(1,samples.count/500)
        return samples.enumerated().compactMap { $0.offset % strideSize == 0 ? $0.element : nil }
    }
    var body: some View {
        Chart {
            ForEach(chartSamples) { sample in
                let v = signal.vector(sample)
                let t = sample.timestamp - (origin ?? samples.first?.timestamp ?? 0)
                LineMark(x:.value("Time (s)",t),y:.value(signal.units,v.x),series:.value("Axis","x"))
                    .foregroundStyle(by:.value("Axis",signal == .attitude ? "roll" : "x"))
                LineMark(x:.value("Time (s)",t),y:.value(signal.units,v.y),series:.value("Axis","y"))
                    .foregroundStyle(by:.value("Axis",signal == .attitude ? "pitch" : "y"))
                LineMark(x:.value("Time (s)",t),y:.value(signal.units,v.z),series:.value("Axis","z"))
                    .foregroundStyle(by:.value("Axis",signal == .attitude ? "yaw" : "z"))
            }
            if let cursor { RuleMark(x:.value("Selected time",cursor)).foregroundStyle(.white.opacity(0.5)).lineStyle(.init(dash:[3,3])) }
        }.chartForegroundStyleScale(range:[PodTheme.teal,Color.blue,PodTheme.amber])
            .chartXAxisLabel("Time (s)").chartYAxisLabel(signal.units)
            .frame(height:170)
            .overlay { if samples.isEmpty { Text("Waiting for samples").foregroundStyle(.secondary) } }
            .accessibilityLabel("\(signal.rawValue), \(samples.count) samples, \(signal.units)")
    }
}

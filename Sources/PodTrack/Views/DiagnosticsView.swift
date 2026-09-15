import SwiftUI
import PodTrackCore

struct DiagnosticsView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(eyebrow:"Hardware diagnostic",title:"Prove the signal first.",detail:"Verify connection, permissions, sample delivery, and the streaming bud before mounting or releasing the car.")
                HStack {
                    Label("Track height is set on the recording screen.",systemImage:"arrow.up.and.down").foregroundStyle(.secondary)
                    Spacer()
                    Button("Set height H & record",systemImage:"ruler") { model.area = .record }.buttonStyle(.borderedProminent)
                }
                if model.sourceKind == .simulation { Notice(text:"SIMULATION selected. All values below are synthetic; this does not verify AirPods hardware.") }
                HeadphoneConnectionPanel()
                if ![.noMotion,.motionError].contains(model.headphoneLinkState) { ConnectionDiagnosticsButton() }
                Text(model.status.detail).foregroundStyle(.secondary)
                Grid(alignment: .leading, horizontalSpacing: 40, verticalSpacing: 10) {
                    row("Compatible headphones connected", model.status.connected ? "YES" : "NO / not confirmed")
                    row("Motion available", model.status.available ? "YES" : "NO")
                    row("Authorization", model.status.authorization)
                    row("Motion streaming active", model.status.active ? "YES (API active)" : "NO")
                    row("Sensor location", model.latest?.sensorLocation.rawValue ?? "unknown")
                    row("Required for recording", model.sourceKind == .airPods ? model.selectedBud.rawValue : "Not applicable (simulation)")
                    row("Source sample rate", String(format: "%.1f Hz", model.statistics.frequencyHz))
                    row("Age since sensor callback", model.sampleAge.map { String(format: "%.2f s", $0) } ?? "—")
                    row("Arrival rate on Mac", (model.sampleAge ?? 2) < 1 ? model.deliveryMonitor.arrivalRateHz.map { String(format:"%.1f Hz",$0) } ?? "Collecting…" : "—")
                    row("Largest callback gap (last 2 s)", model.deliveryMonitor.largestArrivalGap.map { String(format:"%.0f ms",$0*1000) } ?? "—")
                    row("Newest callback → app", model.uiDeliveryDelay.map { String(format:"%.0f ms",$0*1000) } ?? "—")
                    row("Longest app wait since connecting", String(format:"%.0f ms",model.longestUIWait*1000))
                    row("Extra delivery lag", String(format:"%.0f ms",model.deliveryMonitor.extraLag*1000))
                    row("Repeated / old timestamps", "\(model.deliveryMonitor.rejectedTimestamps)")
                    row("Samples received", "\(model.sampleCount)")
                    row("Invalid samples rejected", "\(model.invalidSampleCount)")
                    row("Waiting for first valid sample", "\(model.status.waitingSeconds) s")
                    row("Core Motion error", model.status.motionError ?? "None reported")
                }
                Text("Extra delivery lag compares source time with Mac callback time, relative to the best delivery since connecting. It detects growing delay, not constant Bluetooth latency or Core Motion filtering. A 50 Hz source rate alone does not prove low latency.")
                    .font(.caption).foregroundStyle(.secondary)
                if let sample = model.latest {
                    GroupBox(model.sourceKind == .airPods ? "Measured • Core Motion output" : "Simulated • synthetic motion") {
                        VStack(alignment: .leading, spacing: 10) {
                            if model.sourceKind == .airPods && !model.hasFreshSelectedMotion {
                                Text("Diagnostic sample only — the selected AirPod is not supplying fresh motion.").font(.caption).foregroundStyle(PodTheme.amber)
                            }
                            Text(String(format: "Quaternion  x %.4f   y %.4f   z %.4f   w %.4f", sample.attitude.x,sample.attitude.y,sample.attitude.z,sample.attitude.w))
                            Text(String(format: "Roll %.2f°   Pitch %.2f°   Yaw %.2f°",degrees(sample.roll),degrees(sample.pitch),degrees(sample.yaw)))
                            vector("Rotation rate", sample.rotationRate, "rad/s")
                            vector("User acceleration", sample.userAcceleration, "g")
                            vector("Gravity", sample.gravity, "g")
                        }.font(.system(.body, design: .monospaced)).frame(maxWidth:.infinity, alignment:.leading).padding(8)
                    }
                } else {
                    ContentUnavailableView("Waiting for real motion", systemImage: "airpodspro", description: Text("No sample values are invented when hardware is unavailable."))
                }
                GroupBox("Event log") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(model.events) { event in
                            HStack(alignment: .top) {
                                Text(event.date, style:.time).foregroundStyle(.secondary)
                                Text(event.message)
                            }
                        }
                    }.font(.system(.caption,design:.monospaced)).frame(maxWidth:.infinity, alignment:.leading).padding(8).textSelection(.enabled)
                }
            }.padding(28)
        }
    }
    private func row(_ label: String, _ value: String) -> some View { GridRow { Text(label).foregroundStyle(.secondary); Text(value).monospacedDigit() } }
    private func vector(_ label: String, _ v: Vector3, _ units: String) -> some View {
        Text(String(format:"%@  x % .4f   y % .4f   z % .4f   |v| %.4f %@",label,v.x,v.y,v.z,v.length,units))
    }
}

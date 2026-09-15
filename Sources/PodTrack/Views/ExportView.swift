import SwiftUI
import PodTrackCore

struct ExportView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                PageHeader(eyebrow:"Local data",title:"Keep the evidence.",detail:"Each saved run retains its source, untouched motion samples, mounting calibration, and reconstruction settings.")
                HStack { ReconstructionMethodPicker(); Spacer(); RecentlyDeletedButton() }
                DeletedRecordingNotice()
                if model.runs.isEmpty {
                    ContentUnavailableView("No recorded runs",systemImage:"tray",description:Text("Record an AirPods run or explicitly select simulation to generate input."))
                } else {
                    ForEach(model.runs) { run in
                        Panel(title:run.displayName) {
                            HStack {
                                Text(run.createdAt,style:.date)
                                Text("· \(run.samples.count) samples · \(formatted(run.duration)) s").foregroundStyle(.secondary)
                                Spacer()
                                Button("Raw samples CSV") { model.exportRaw(run) }
                                Button("Metrics JSON") { model.exportMetrics(run) }.disabled(model.analyses[run.id] == nil)
                                Button("Estimated track CSV") { model.exportTrack(run) }.disabled(model.analyses[run.id] == nil)
                                if model.unsavedIDs.contains(run.id) { Button("Retry save") { model.persist(run) }.tint(.orange) }
                                DeleteRecordingButton(run:run,compact:true)
                            }
                            if let result = model.analyses[run.id], result.isRelative {
                                Text("Scale unknown · track exports use relative units (u) and u/s. Raw sensor units are unchanged.")
                                    .font(.caption).foregroundStyle(PodTheme.teal)
                            }
                            if !run.recordingNotes.isEmpty { Text(run.recordingNotes.joined(separator:"\n")).font(.caption).foregroundStyle(PodTheme.amber) }
                            if let reason = model.analysisErrors[run.id] { Text("Reconstruction unavailable: \(reason)").font(.caption).foregroundStyle(PodTheme.amber) }
                        }.onAppear { model.ensureAnalysis(run) }
                    }
                }
                Text("Library: \(model.store.directory.path)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }.padding(28)
        }.onAppear { model.prepareComparison() }
    }
}

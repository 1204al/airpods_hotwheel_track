import SwiftUI
import PodTrackCore

struct ReconstructionMethodPicker: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        HStack(spacing:12) {
            Picker("Algorithm",selection:Binding(get:{model.reconstructionMethod},set:{model.selectReconstructionMethod($0)})) {
                ForEach(ReconstructionMethod.allCases,id:\.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).frame(width:260)
                .accessibilityLabel("Reconstruction algorithm")
            Button("Recalculate",systemImage:"arrow.clockwise") { model.recalculateSelectedRun() }
                .disabled(model.selectedRun == nil || model.selectedRunID.map { model.analysingIDs.contains($0) } == true)
                .help("Recalculate the selected run using the selected algorithm and save the new result.")
            Text(model.reconstructionMethod == .improved ? "Improved · experimental estimates" : "Old · original reconstruction")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct DeleteRecordingButton: View {
    @EnvironmentObject private var model: AppModel
    let run: RunSession
    var compact = false
    var body: some View {
        Button(role:.destructive) { model.deleteRecording(run) } label: {
            if compact { Image(systemName:"trash") }
            else { Label("Delete recording",systemImage:"trash") }
        }.help("Move this recording to Recently Deleted. You can restore it later.")
            .accessibilityLabel("Delete recording: \(run.comparisonDisplayName)")
    }
}

struct DeletedRecordingNotice: View {
    @EnvironmentObject private var model: AppModel
    private var justDeleted: [RunSession] {
        model.lastDeletedRunIDs.compactMap { id in model.deletedRuns.first(where:{$0.id == id}) }
    }
    var body: some View {
        if !justDeleted.isEmpty {
            HStack(spacing:12) {
                Label(justDeleted.count == 1 ? "\(justDeleted[0].carDisplayName) moved to Recently Deleted"
                                             : "\(justDeleted.count) recordings moved to Recently Deleted",
                      systemImage:"trash").lineLimit(2)
                Spacer(minLength:0)
                Button("Undo") { model.restoreLastDeleted() }
                Button { model.lastDeletedRunIDs = [] } label: { Image(systemName:"xmark") }
                    .buttonStyle(.plain).accessibilityLabel("Dismiss deletion notice")
            }.font(.callout).padding(12).background(PodTheme.teal.opacity(0.08),in:RoundedRectangle(cornerRadius:8))
        }
    }
}

struct RecentlyDeletedButton: View {
    @EnvironmentObject private var model: AppModel
    @State private var isPresented = false
    var body: some View {
        Button("Recently Deleted (\(model.deletedRuns.count))",systemImage:"trash") {
            model.reloadDeletedRuns(); isPresented = true
        }.sheet(isPresented:$isPresented) { RecentlyDeletedView().environmentObject(model) }
    }
}

struct RecentlyDeletedView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            HStack {
                Text("Recently Deleted").font(.title2.bold())
                Spacer()
                Button("Restore all \(model.deletedRuns.count)",systemImage:"arrow.uturn.backward") {
                    model.restoreRecordings(model.deletedRuns)
                }.disabled(model.deletedRuns.isEmpty)
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("Removed recordings are kept on this Mac until you restore them. Their raw samples, calibration and saved settings are retained.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            if model.deletedRuns.isEmpty {
                ContentUnavailableView("No deleted recordings",systemImage:"trash",description:Text("Recordings you remove from the library will appear here."))
            } else {
                ScrollView {
                    LazyVStack(spacing:12) {
                        ForEach(model.deletedRuns) { run in
                            HStack(spacing:16) {
                                VStack(alignment:.leading,spacing:5) {
                                    Text(run.carDisplayName).font(.headline)
                                    Text(run.createdAt.formatted(date:.abbreviated,time:.standard)).font(.caption)
                                    Text("\(run.samples.count) samples · \(formatted(run.duration)) s · H \(run.metadata.heightLabel)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Restore",systemImage:"arrow.uturn.backward") { model.restoreRecording(run) }
                                    .accessibilityLabel("Restore \(run.comparisonDisplayName)")
                            }.padding(14).background(Color.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:8))
                        }
                    }
                }
            }
            if let message = model.errorMessage { Text(message).font(.caption).foregroundStyle(PodTheme.amber) }
        }.padding(24).frame(width:650,height:500)
    }
}

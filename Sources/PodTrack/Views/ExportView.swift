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
                                RunExportButton(run:run)
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

struct RunExportButton: View {
    let run: RunSession
    @State private var showingExport = false
    var body: some View {
        Button("Export",systemImage:"square.and.arrow.up") { showingExport = true }
            .sheet(isPresented:$showingExport) { RunExportSheet(run:run) }
    }
}

struct RunExportSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let run: RunSession
    /// Set to export only part of the recording's elapsed time.
    var window: TimeWindow? = nil
    @State private var format: RunExportFormat = .csv
    @State private var selected: Set<RunExportDataset> = [.raw]
    @State private var exporting = false
    @State private var error: String?
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            Text(window == nil ? "Export run" : "Export part of a run").font(.title2.bold())
            Text(run.displayName).foregroundStyle(.secondary)
            if let window {
                Label("Only \(window.label) · \(formatted(window.duration)) s of \(formatted(run.duration)) s",systemImage:"scissors")
                    .font(.callout).foregroundStyle(PodTheme.teal)
                Text("Rows outside this range are left out. Values are unchanged: the reconstruction, its scale and its endpoint assumptions still come from the whole recording, and distance along the path keeps counting from the run's start. Each file records the range.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }
            Picker("Format",selection:$format) {
                ForEach(RunExportFormat.allCases,id:\.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            Menu {
                ForEach(RunExportDataset.all,id:\.self) { dataset in
                    Toggle(dataset.title,isOn:Binding(get:{ selected.contains(dataset) },set:{ enabled in
                        if enabled { selected.insert(dataset) } else { selected.remove(dataset) }
                    }))
                }
            } label: {
                HStack {
                    Text("Data to export")
                    Spacer()
                    Text("\(selected.count) selected")
                }
            }.menuStyle(.borderedButton)
            Text(RunExportDataset.all.filter { selected.contains($0) }.map(\.title).joined(separator:", "))
                .font(.callout).fixedSize(horizontal:false,vertical:true)
            Text(selected.count > 1 ? "Saves a ZIP containing one \(format.rawValue) file per selected dataset." : "Saves one \(format.rawValue) file. Raw data includes every recorded sample.")
                .font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            if exporting { ProgressView("Preparing export…") }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).disabled(exporting)
                Button("Export") { export() }.buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction).disabled(exporting || selected.isEmpty)
            }
        }.padding(24).frame(width:480)
            .interactiveDismissDisabled(exporting)
    }
    private func export() {
        let datasets = RunExportDataset.all.filter { selected.contains($0) }
        let zipped = datasets.count > 1
        let range = window.map { "-\($0.fileSuffix)" } ?? ""
        let name = zipped ? "\(run.exportBasename)\(range)-export.zip"
                          : "\(run.exportBasename)-\(datasets[0].suffix)\(range).\(format.fileExtension)"
        guard let destination = SaveExporter.destination(name:name,format:format,zipped:zipped) else { return }
        exporting = true; error = nil
        let cache = AnalysisDiskCache(directory:model.store.directory.appendingPathComponent("AnalysisCache"))
        let run = run, format = format, window = window
        Task {
            let outcome = await Task.detached(priority:.userInitiated) {
                try RunExportWriter.write(run:run,datasets:datasets,format:format,cache:cache,destination:destination,window:window)
            }.result
            exporting = false
            switch outcome {
            case .success: dismiss()
            case .failure(let failure): error = "Export failed: \(failure.localizedDescription)"
            }
        }
    }
}

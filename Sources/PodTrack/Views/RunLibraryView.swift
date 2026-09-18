import AppKit
import SwiftUI
import PodTrackCore

/// What the library can say about a recording without opening it. A recording whose
/// reconstruction has not been attempted yet is `pending`, never "no path": the library
/// must not label a run unusable before its analysis has run.
enum RunReconstructionState {
    case ready(AnalysisResult)
    case analysing
    case failed(String)
    case rawOnly
    case pending
    var isReady: Bool { if case .ready = self { return true }; return false }
    /// Short status used in the row badge and in the exported run index.
    var label: String {
        switch self {
        case .ready(let result): return result.isRelative ? "Relative 3D shape" : "3D path ready"
        case .analysing: return "Reconstructing…"
        case .failed: return "No 3D path"
        case .rawOnly: return "Raw only · no calibration"
        case .pending: return "Not reconstructed yet"
        }
    }
    var systemImage: String {
        switch self {
        case .ready: return "cube.transparent"
        case .analysing: return "hourglass"
        case .failed: return "exclamationmark.triangle"
        case .rawOnly: return "waveform"
        case .pending: return "clock"
        }
    }
    var tint: Color {
        switch self {
        case .ready: return PodTheme.teal
        case .failed, .rawOnly: return PodTheme.amber
        case .analysing, .pending: return .secondary
        }
    }
}

extension AppModel {
    func reconstructionState(_ run: RunSession) -> RunReconstructionState {
        if let result = analyses[run.id] { return .ready(result) }
        if analysingIDs.contains(run.id) { return .analysing }
        if let reason = analysisErrors[run.id] { return .failed(reason) }
        return run.calibration == nil ? .rawOnly : .pending
    }
    /// Location of a recording's own JSON file, for revealing it in Finder.
    func fileURL(for run: RunSession) -> URL {
        store.directory.appendingPathComponent(run.id.uuidString).appendingPathExtension("json")
    }
}

enum RunSortOrder: String, CaseIterable, Identifiable {
    case newest = "Newest first"
    case oldest = "Oldest first"
    case longestRecording = "Longest recording"
    case longestPath = "Longest estimated path"
    case fastest = "Highest estimated speed"
    case car = "Car name (A–Z)"
    var id: String { rawValue }
}

enum RunSideFilter: String, CaseIterable, Identifiable {
    case all = "Any source"
    case right = "Right AirPod"
    case left = "Left AirPod"
    case simulation = "Simulation"
    var id: String { rawValue }
    func accepts(_ run: RunSession) -> Bool {
        switch self {
        case .all: return true
        case .right: return run.recordedOrigin == .right
        case .left: return run.recordedOrigin == .left
        case .simulation: return run.recordedOrigin == .simulation
        }
    }
}

enum RunStatusFilter: String, CaseIterable, Identifiable {
    case all = "Any status"
    case reconstructed = "With a 3D path"
    case withoutPath = "Without a 3D path"
    case measured = "Measured height H"
    case unknownScale = "Unknown scale"
    var id: String { rawValue }
}

/// Pure list shaping: no view state, so the same rules can be exercised in tests.
struct RunLibraryQuery: Equatable {
    var search = ""
    var sort: RunSortOrder = .newest
    var side: RunSideFilter = .all
    var status: RunStatusFilter = .all
    var isFiltering: Bool {
        side != .all || status != .all || !search.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty
    }

    /// Every whitespace-separated token must appear somewhere in the run's text, so
    /// "left 18:5" and a pasted run ID both narrow the list.
    static func matches(_ run: RunSession, search: String) -> Bool {
        let tokens = search.split(whereSeparator:\.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return true }
        let haystack = [run.displayName,run.metadata.trackName,run.metadata.carName,run.recordedOrigin.label,
                        run.source.rawValue,run.metadata.notes,run.metadata.heightLabel,run.id.uuidString,
                        run.createdAt.formatted(date:.abbreviated,time:.standard),
                        run.createdAt.formatted(date:.numeric,time:.shortened)].joined(separator:" ")
        return tokens.allSatisfy { haystack.localizedCaseInsensitiveContains($0) }
    }

    func apply(to runs: [RunSession], analyses: [UUID:AnalysisResult], analysing: Set<UUID> = []) -> [RunSession] {
        let filtered = runs.filter { run in
            guard side.accepts(run), Self.matches(run,search:search) else { return false }
            switch status {
            case .all: return true
            case .reconstructed: return analyses[run.id] != nil
            // A run still being reconstructed has no verdict yet; it stays out of both sides.
            case .withoutPath: return analyses[run.id] == nil && !analysing.contains(run.id)
            case .measured: return run.metadata.verticalDrop != nil
            case .unknownScale: return analyses[run.id]?.isRelative ?? (run.metadata.scaleBasis == .relative)
            }
        }
        func metric(_ run: RunSession, _ value: (RunMetrics) -> Double) -> Double {
            analyses[run.id].map { value($0.metrics) } ?? -.greatestFiniteMagnitude
        }
        switch sort {
        case .newest: return filtered.sorted { $0.createdAt>$1.createdAt }
        case .oldest: return filtered.sorted { $0.createdAt<$1.createdAt }
        case .longestRecording: return filtered.sorted { $0.duration>$1.duration }
        case .longestPath: return filtered.sorted { metric($0,\.estimatedPathLength)>metric($1,\.estimatedPathLength) }
        case .fastest: return filtered.sorted { metric($0,\.estimatedMaximumSpeed)>metric($1,\.estimatedMaximumSpeed) }
        case .car: return filtered.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        }
    }
}

struct RunLibraryView: View {
    @EnvironmentObject var model: AppModel
    /// Switches the workspace to the multi-run comparison screen.
    var startComparison: () -> Void
    /// Preselected rows, used only by the developer render command.
    var initialSelection: Set<UUID> = []
    @State private var query = RunLibraryQuery()
    @State private var editRun: RunSession?
    @State private var exportRequest: RunExportRequest?
    @State private var selection: Set<UUID> = []
    /// Last row whose checkbox was clicked, so Shift-click can extend from it.
    @State private var selectionAnchor: UUID?
    @State private var confirmingDelete = false
    @FocusState private var searchFocused: Bool

    private var visibleRuns: [RunSession] {
        query.apply(to:model.runs,analyses:model.analyses,analysing:model.analysingIDs)
    }
    /// Selected rows in list order; rows hidden by the current filters are not included.
    private var selectedRuns: [RunSession] { visibleRuns.filter { selection.contains($0.id) } }
    private var readyCount: Int { model.runs.filter { model.analyses[$0.id] != nil }.count }
    private var mixesScales: Bool {
        let relative = model.runs.compactMap { model.analyses[$0.id]?.isRelative }
        return relative.contains(true) && relative.contains(false)
    }

    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            header
            controls
            summary
            if !selection.isEmpty { selectionBar }
            DeletedRecordingNotice()
            if model.runs.isEmpty { emptyLibrary } else { list }
        }.padding(28)
            .onAppear { model.prepareComparison(); if selection.isEmpty { selection = initialSelection } }
            .onChange(of:model.runs.map(\.id)) { _,_ in
                model.prepareComparison()
                // A removed or restored recording must not stay in a stale selection.
                selection.formIntersection(Set(model.runs.map(\.id)))
                if let anchor = selectionAnchor, !selection.contains(anchor) { selectionAnchor = nil }
            }
            .sheet(item:$editRun) { RunEditSheet(run:$0).environmentObject(model) }
            .sheet(item:$exportRequest) { LibraryExportSheet(runs:$0.runs).environmentObject(model) }
            .confirmationDialog("Move \(selectedRuns.count) recordings to Recently Deleted?",
                                isPresented:$confirmingDelete,titleVisibility:.visible) {
                Button("Move \(selectedRuns.count) to Recently Deleted",role:.destructive) {
                    model.deleteRecordings(selectedRuns)
                    selection = []; selectionAnchor = nil
                }
                Button("Cancel",role:.cancel) {}
            } message: {
                Text("Their raw samples, calibration, names and heights are kept on this Mac. Restore them from Recently Deleted, or undo right after.")
            }
    }

    private var header: some View {
        HStack {
            Text("Runs").font(.largeTitle.bold())
            Spacer()
            Button("Export \(visibleRuns.count) runs…",systemImage:"square.and.arrow.up.on.square") {
                exportRequest = .init(runs:visibleRuns)
            }.disabled(visibleRuns.isEmpty)
                .help("Export raw data, reconstructions and a summary index for every run listed below.")
            Button("Compare runs",systemImage:"square.stack.3d.up") { startComparison() }.disabled(model.runs.count<2)
            RecentlyDeletedButton()
        }
    }

    private var selectionBar: some View {
        HStack(spacing:12) {
            Text("\(selection.count) selected").font(.callout.bold())
            Button(selection.count == visibleRuns.count ? "Deselect all" : "Select all \(visibleRuns.count)") {
                if selection.count == visibleRuns.count { selection = [] }
                else { selection = Set(visibleRuns.map(\.id)) }
                selectionAnchor = nil
            }
            Text("Shift-click a checkbox to select a range.").font(.caption).foregroundStyle(.secondary)
            Spacer(minLength:0)
            Button("Export \(selection.count) selected…",systemImage:"square.and.arrow.up") {
                exportRequest = .init(runs:selectedRuns)
            }
            Button("Delete \(selection.count)…",systemImage:"trash",role:.destructive) { confirmingDelete = true }
                .help("Move the selected recordings to Recently Deleted. They can be restored.")
        }.padding(12).background(PodTheme.teal.opacity(0.10),in:RoundedRectangle(cornerRadius:8))
    }

    /// Shift extends from the last clicked checkbox, so a long run of rows needs two clicks.
    private func setSelected(_ run: RunSession, _ selected: Bool, extending: Bool) {
        let ids = visibleRuns.map(\.id)
        if extending, let anchor = selectionAnchor,
           let from = ids.firstIndex(of:anchor), let to = ids.firstIndex(of:run.id) {
            let range = from<=to ? from...to : to...from
            if selected { selection.formUnion(ids[range]) } else { selection.subtract(ids[range]) }
        } else if selected { selection.insert(run.id) } else { selection.remove(run.id) }
        selectionAnchor = run.id
    }

    private var controls: some View {
        HStack(spacing:10) {
            Image(systemName:"magnifyingglass").foregroundStyle(.secondary)
            TextField("Search by car, track, side, date or run ID",text:$query.search)
                .textFieldStyle(.roundedBorder).focused($searchFocused)
                .accessibilityLabel("Search saved runs")
            if !query.search.isEmpty {
                Button { query.search = "" } label: { Image(systemName:"xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Clear search")
            }
            Picker("Sort",selection:$query.sort) {
                ForEach(RunSortOrder.allCases) { Text($0.rawValue).tag($0) }
            }.frame(width:210).help("Order of the list. Estimated sorts put runs without a reconstruction last.")
            Menu {
                Picker("Source",selection:$query.side) { ForEach(RunSideFilter.allCases) { Text($0.rawValue).tag($0) } }
                Picker("Status",selection:$query.status) { ForEach(RunStatusFilter.allCases) { Text($0.rawValue).tag($0) } }
                Divider()
                Button("Reset filters") { query.side = .all; query.status = .all }
            } label: {
                Label(query.side == .all && query.status == .all ? "Filter" : "Filtered",systemImage:"line.3.horizontal.decrease.circle")
            }.menuStyle(.borderlessButton).fixedSize()
            // Keyboard route to the search field; the control itself stays out of the layout.
            Button("") { searchFocused = true }.keyboardShortcut("f",modifiers:.command)
                .opacity(0).frame(width:0).accessibilityHidden(true)
        }
    }

    private var summary: some View {
        HStack(spacing:8) {
            Text("\(model.runs.count) saved · \(readyCount) with a 3D path · \(formatted(model.runs.map(\.duration).reduce(0,+),1)) s recorded")
            if visibleRuns.count != model.runs.count { Text("· \(visibleRuns.count) shown").foregroundStyle(PodTheme.teal) }
            if mixesScales { Text("· some runs have no measured scale (u)").foregroundStyle(PodTheme.amber) }
            Spacer()
            Button("Show library in Finder",systemImage:"folder") {
                NSWorkspace.shared.activateFileViewerSelecting([model.store.directory])
            }.buttonStyle(.link)
        }.font(.caption).foregroundStyle(.secondary)
    }

    private var emptyLibrary: some View {
        VStack(alignment:.leading,spacing:14) {
            ContentUnavailableView("No saved runs",systemImage:"tray",description:Text("Record your first run to explore its track and signals."))
            Button("Record a run") { model.area = .record }.buttonStyle(.borderedProminent)
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing:10) {
                ForEach(visibleRuns) { run in
                    RunLibraryRow(run:run,isSelected:selection.contains(run.id),
                                  setSelected:{ selected,extending in setSelected(run,selected,extending:extending) },
                                  edit:{ editRun = run }).environmentObject(model)
                }
                if visibleRuns.isEmpty {
                    ContentUnavailableView("No runs match these filters",systemImage:"magnifyingglass",
                                           description:Text("\(model.runs.count) recordings are saved. Clear the search or reset the filters to see them."))
                        .padding(.vertical,30)
                    Button("Clear search & filters") { query = .init(sort:query.sort) }
                }
            }.padding(.trailing,4)
        }
    }
}

/// A sheet request carries its own run list, so exporting the whole list and exporting the
/// current selection open the same dialog without a second piece of view state.
struct RunExportRequest: Identifiable {
    let id = UUID()
    let runs: [RunSession]
}

private extension RunLibraryQuery {
    init(sort: RunSortOrder) { self.init(); self.sort = sort }
}

struct RunLibraryRow: View {
    @EnvironmentObject var model: AppModel
    let run: RunSession
    var isSelected = false
    var setSelected: (Bool,Bool) -> Void = { _,_ in }
    var edit: () -> Void
    @State private var hovering = false

    private var state: RunReconstructionState { model.reconstructionState(run) }

    var body: some View {
        HStack(alignment:.top,spacing:14) {
            Toggle("",isOn:Binding(get:{ isSelected },
                                   set:{ setSelected($0,NSEvent.modifierFlags.contains(.shift)) }))
                .toggleStyle(.checkbox).labelsHidden().padding(.top,8)
                .accessibilityLabel("Select \(run.comparisonDisplayName)")
            originBadge
            VStack(alignment:.leading,spacing:6) {
                Text(run.metadata.carName).font(.headline)
                Text("\(run.metadata.trackName) · \(run.recordedOrigin.label)").font(.subheadline).foregroundStyle(.secondary)
                Text("\(run.createdAt.formatted(date:.abbreviated,time:.standard)) · \(formatted(run.duration,1)) s · \(run.samples.count) samples")
                    .font(.caption).foregroundStyle(.secondary)
                statusLine
                if let advice = readinessAdvice {
                    Label(advice,systemImage:"exclamationmark.triangle").font(.caption2).foregroundStyle(PodTheme.amber)
                }
            }
            Spacer(minLength:8)
            VStack(alignment:.trailing,spacing:8) {
                Text("H \(run.metadata.heightLabel)").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                actions
            }
        }.padding(16).contentShape(Rectangle())
            .background(isSelected ? AnyShapeStyle(PodTheme.teal.opacity(0.12)) : AnyShapeStyle(PodTheme.panel.opacity(hovering ? 1 : 0.6)),
                        in:RoundedRectangle(cornerRadius:12))
            .overlay(RoundedRectangle(cornerRadius:12)
                .strokeBorder(isSelected ? PodTheme.teal.opacity(0.7) : .primary.opacity(hovering ? 0.14 : 0.07),
                              lineWidth:isSelected ? 1.5 : 1))
            .onHover { hovering = $0 }
            .onTapGesture { model.openRun(run) }
            .contextMenu { menuItems }
            .onAppear { model.ensureAnalysis(run) }
            .accessibilityElement(children:.contain)
            .accessibilityLabel("\(run.displayName), \(run.createdAt.formatted()), \(state.label)")
    }

    private var originBadge: some View {
        let text: String
        switch run.recordedOrigin {
        case .left: text = "L"
        case .right: text = "R"
        case .simulation: text = "SIM"
        case .mixed: text = "MIX"
        case .unknown: text = "?"
        }
        return Text(text).font(.system(size:12,weight:.bold,design:.rounded))
            .frame(width:36,height:36)
            .background(state.tint.opacity(0.14),in:RoundedRectangle(cornerRadius:9))
            .foregroundStyle(state.tint)
            .accessibilityHidden(true)
    }

    @ViewBuilder private var statusLine: some View {
        switch state {
        case .ready(let result):
            HStack(spacing:12) {
                Label(state.label,systemImage:state.systemImage).foregroundStyle(PodTheme.teal)
                Text("\(formatted(result.metrics.estimatedPathLength)) \(result.distanceUnit) path")
                Text("top \(formatted(result.metrics.estimatedMaximumSpeed)) \(result.speedUnit)")
                Text("avg \(formatted(result.metrics.estimatedAverageSpeed)) \(result.speedUnit)")
            }.font(.caption.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
        case .analysing:
            HStack(spacing:8) { ProgressView().controlSize(.small); Text(state.label).font(.caption).foregroundStyle(.secondary) }
        case .failed(let reason):
            Label("\(state.label) · \(reason)",systemImage:state.systemImage)
                .font(.caption).foregroundStyle(PodTheme.amber).lineLimit(2)
        case .rawOnly, .pending:
            Label(state.label,systemImage:state.systemImage).font(.caption).foregroundStyle(state.tint)
        }
    }

    /// Recording-quality note the user would otherwise only see after opening the run.
    private var readinessAdvice: String? {
        if case .ready(let result) = state, let advice = RecordingReview(run:run,result:result).endpointAdvice { return advice.title }
        return run.recordingNotes.first
    }

    private var actions: some View {
        HStack(spacing:6) {
            RunExportButton(run:run).labelStyle(.iconOnly).controlSize(.small)
                .help("Export this recording")
            Menu { menuItems } label: { Image(systemName:"ellipsis.circle") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel("Actions for \(run.comparisonDisplayName)")
        }
    }

    @ViewBuilder private var menuItems: some View {
        Button("Open 3D track",systemImage:"cube.transparent") { model.openRun(run,in:.track) }
        Button("Open analysis",systemImage:"chart.xyaxis.line") { model.openRun(run,in:.analysis) }
        Button("Add to comparison",systemImage:"square.stack.3d.up") { model.openComparison(including:run) }
            .disabled(!state.isReady)
        Divider()
        Button("Edit name & height",systemImage:"square.and.pencil") { edit() }
        Button("Recalculate reconstruction",systemImage:"arrow.clockwise") {
            model.selectedRunID = run.id
            model.recalculateSelectedRun()
        }
        Divider()
        Button("Copy run ID",systemImage:"doc.on.doc") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(run.id.uuidString,forType:.string)
        }
        Button("Show recording file in Finder",systemImage:"folder") {
            NSWorkspace.shared.activateFileViewerSelecting([model.fileURL(for:run)])
        }
        Divider()
        Button("Delete recording",systemImage:"trash",role:.destructive) { model.deleteRecording(run) }
    }
}

/// Export every listed recording in one operation. A recording without a reconstruction
/// cannot block the others: it is skipped, listed in the archive, and reported here.
struct LibraryExportSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let runs: [RunSession]
    @State private var format: RunExportFormat = .csv
    @State private var selected: Set<RunExportDataset> = [.raw]
    @State private var includeIndex = true
    @State private var exporting = false
    @State private var error: String?

    private var fileCount: Int { runs.count*selected.count + (includeIndex ? 1 : 0) }

    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            Text("Export \(runs.count) runs").font(.title2.bold())
            Text("Every recording currently listed in the library. Raw samples, calibration and settings are exported unchanged; reconstructed values remain estimates.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
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
                HStack { Text("Data per run"); Spacer(); Text("\(selected.count) selected") }
            }.menuStyle(.borderedButton)
            Text(selected.isEmpty ? "No per-run data selected."
                                  : RunExportDataset.all.filter { selected.contains($0) }.map(\.title).joined(separator:", "))
                .font(.callout).fixedSize(horizontal:false,vertical:true)
            Toggle("Include run index (one CSV summarising every run)",isOn:$includeIndex)
            Text(includeIndex ? "The index lists identity, recording facts and the \(model.reconstructionMethod.rawValue) estimates already computed for each run. Runs without a reconstruction keep empty estimate columns."
                              : "Without the index the archive contains only the per-run files.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            Text(fileCount > 1 ? "Saves a ZIP with \(fileCount) files." : "Saves one \(format.rawValue) file.")
                .font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled).fixedSize(horizontal:false,vertical:true) }
            if exporting { ProgressView("Preparing \(runs.count) recordings…") }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).disabled(exporting)
                Button("Export") { export() }.buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction).disabled(exporting || fileCount == 0)
            }
        }.padding(24).frame(width:520).interactiveDismissDisabled(exporting)
    }

    private func export() {
        let datasets = RunExportDataset.all.filter { selected.contains($0) }
        let zipped = fileCount > 1
        let name = zipped ? "PodTrack-library-\(runs.count)-runs.zip"
                          : "\(runs[0].exportBasename)-\(datasets.first?.suffix ?? "index").\(format.fileExtension)"
        guard let destination = SaveExporter.destination(name:name,format:format,zipped:zipped) else { return }
        var extras: [String:Data] = [:]
        if includeIndex {
            let entries = runs.map { RunIndexEntry(run:$0,result:model.analyses[$0.id],status:model.reconstructionState($0).label) }
            extras["PodTrack-runs-index.csv"] = Data(CSVExporter.runIndex(entries,method:model.reconstructionMethod).utf8)
        }
        let cache = AnalysisDiskCache(directory:model.store.directory.appendingPathComponent("AnalysisCache"))
        let runs = runs, format = format, files = extras
        exporting = true; error = nil
        Task {
            let outcome = await Task.detached(priority:.userInitiated) {
                try RunExportWriter.write(runs:runs,datasets:datasets,format:format,cache:cache,
                                          destination:destination,extraFiles:files,strict:false)
            }.result
            exporting = false
            switch outcome {
            case .success(let report):
                if report.skipped.isEmpty { dismiss() }
                else {
                    model.log("Exported \(report.runs) of \(runs.count) recordings. Skipped: \(report.skipped.joined(separator:"; "))")
                    error = "Saved \(report.files) files from \(report.runs) of \(runs.count) recordings. export-report.txt in the archive lists what was not written:\n" + report.skipped.prefix(4).joined(separator:"\n")
                }
            case .failure(let failure): error = "Export failed: \(failure.localizedDescription)"
            }
        }
    }
}

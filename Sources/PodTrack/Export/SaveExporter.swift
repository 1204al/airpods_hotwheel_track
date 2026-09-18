import AppKit
import UniformTypeIdentifiers

@MainActor enum SaveExporter {
    static func save(text: String, name: String, json: Bool, onError: (String) -> Void) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.allowedContentTypes = [json ? .json : .commaSeparatedText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try text.write(to:url,atomically:true,encoding:.utf8) }
        catch { onError("Export failed: \(error.localizedDescription)") }
    }
}

extension SaveExporter {
    static func destination(name: String, format: RunExportFormat, zipped: Bool) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.allowedContentTypes = [zipped ? .zip : (format == .json ? .json : .commaSeparatedText)]
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }
}

import PodTrackCore

struct RunExportOutcome: Sendable {
    var runs: Int
    var files: Int
    /// One line per dataset that produced no file, with the reason. Never silently dropped:
    /// the archive carries the same list and the caller reports it.
    var skipped: [String]
}

/// Build all selected files before writing the destination, so failures never produce a partial export.
enum RunExportWriter {
    /// One recording. Every selected dataset must succeed, so a partial file is never written.
    static func write(run: RunSession, datasets: [RunExportDataset], format: RunExportFormat,
                      cache: AnalysisDiskCache, destination: URL, window: TimeWindow? = nil) throws {
        try write(runs:[run],datasets:datasets,format:format,cache:cache,destination:destination,
                  window:window,strict:true)
    }

    /// Several recordings. A raw-only recording cannot block the rest of the library, so with
    /// `strict` off the failures are collected, listed in `export-report.txt`, and returned.
    @discardableResult
    static func write(runs: [RunSession], datasets: [RunExportDataset], format: RunExportFormat,
                      cache: AnalysisDiskCache, destination: URL,
                      extraFiles: [String:Data] = [:], window: TimeWindow? = nil, strict: Bool) throws -> RunExportOutcome {
        guard !runs.isEmpty else { throw PodTrackError.invalid("Select at least one run.") }
        guard !datasets.isEmpty || !extraFiles.isEmpty else { throw PodTrackError.invalid("Select at least one dataset.") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true)
        let contents = root.appendingPathComponent("contents",isDirectory:true)
        try FileManager.default.createDirectory(at:contents,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        var files: [URL] = [], skipped: [String] = [], exportedRuns = 0
        for run in runs {
            var wroteRun = false
            for dataset in datasets {
                let data: Data
                do { data = try dataset.data(run:run,format:format,cache:cache,window:window) }
                catch {
                    let reason = strict ? "\(dataset.title): \(error.localizedDescription)"
                                        : "\(run.displayName) · \(dataset.title): \(error.localizedDescription)"
                    if strict { throw PodTrackError.invalid(reason) }
                    skipped.append(reason); continue
                }
                let suffix = window.map { "\(dataset.suffix)-\($0.fileSuffix)" } ?? dataset.suffix
                let file = contents.appendingPathComponent("\(run.exportBasename)-\(suffix).\(format.fileExtension)")
                try data.write(to:file,options:.atomic)
                files.append(file); wroteRun = true
            }
            if wroteRun { exportedRuns += 1 }
        }
        for (name,data) in extraFiles.sorted(by:{ $0.key<$1.key }) {
            let file = contents.appendingPathComponent(name)
            try data.write(to:file,options:.atomic)
            files.append(file)
        }
        if !skipped.isEmpty {
            let report = "PodTrack export report\n\nWritten: \(files.count) file(s) from \(exportedRuns) of \(runs.count) recording(s).\nNot written:\n" + skipped.map { "- \($0)" }.joined(separator:"\n") + "\n"
            let file = contents.appendingPathComponent("export-report.txt")
            try Data(report.utf8).write(to:file,options:.atomic)
            files.append(file)
        }
        guard let first = files.first else {
            throw PodTrackError.invalid("Nothing could be exported.\n" + skipped.joined(separator:"\n"))
        }
        let output: URL
        if files.count == 1 {
            output = first
        } else {
            output = root.appendingPathComponent("export.zip")
            let process = Process()
            process.executableURL = URL(fileURLWithPath:"/usr/bin/ditto")
            process.arguments = ["-c","-k",contents.path,output.path]
            process.standardError = FileHandle.nullDevice
            try process.run(); process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw PodTrackError.invalid("Could not create ZIP archive.") }
        }
        try Data(contentsOf:output).write(to:destination,options:.atomic)
        return .init(runs:exportedRuns,files:files.count,skipped:skipped)
    }
}

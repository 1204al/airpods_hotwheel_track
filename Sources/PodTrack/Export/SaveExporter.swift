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

/// Build all selected files before writing the destination, so failures never produce a partial export.
enum RunExportWriter {
    static func write(run: RunSession, datasets: [RunExportDataset], format: RunExportFormat,
                      cache: AnalysisDiskCache, destination: URL) throws {
        guard !datasets.isEmpty else { throw PodTrackError.invalid("Select at least one dataset.") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true)
        let contents = root.appendingPathComponent("contents",isDirectory:true)
        try FileManager.default.createDirectory(at:contents,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        for dataset in datasets {
            let data: Data
            do { data = try dataset.data(run:run,format:format,cache:cache) }
            catch { throw PodTrackError.invalid("\(dataset.title): \(error.localizedDescription)") }
            let file = contents.appendingPathComponent("\(run.exportBasename)-\(dataset.suffix).\(format.fileExtension)")
            try data.write(to:file,options:.atomic)
        }
        let output: URL
        if datasets.count == 1 {
            output = contents.appendingPathComponent("\(run.exportBasename)-\(datasets[0].suffix).\(format.fileExtension)")
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
    }
}

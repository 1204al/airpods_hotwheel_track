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

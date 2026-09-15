import AppKit

@MainActor final class AppLifecycle: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model?.shutdown()
        if model?.unsavedIDs.isEmpty == false {
            let alert = NSAlert()
            alert.messageText = "Some runs could not be saved"
            alert.informativeText = "Retry saving or export the runs before quitting. They are still available in this window."
            alert.addButton(withTitle:"Keep PodTrack open")
            alert.addButton(withTitle:"Quit and discard unsaved runs")
            return alert.runModal() == .alertFirstButtonReturn ? .terminateCancel : .terminateNow
        }
        return .terminateNow
    }
}

import SwiftUI

@main struct PodTrackApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycle.self) private var lifecycle
    @StateObject private var model = AppModel()
    init() { PrototypeVerification.runIfRequested() }
    var body: some Scene {
        WindowGroup("PodTrack") {
            RootView().environmentObject(model).frame(minWidth: 1100, minHeight: 760)
                .onAppear {
                    lifecycle.model = model
                    let arguments = ProcessInfo.processInfo.arguments
                    if !["--compare-algorithms","--open-latest-track","--open-recording-setup","--verify-library"].contains(where:arguments.contains) { model.startAuthorizedMotionIfNeeded() }
                }
        }
        .defaultSize(width: 1440, height: 960)
        .commands {
            CommandGroup(after:.newItem) {
                Button("Record a run") { model.area = .record }.keyboardShortcut("r",modifiers:[.command,.shift])
                Button("Stop recording") { model.finishRecording() }.keyboardShortcut(".",modifiers:.command).disabled(!model.recording)
                ComparisonWindowCommand()
            }
            CommandGroup(replacing:.help) {
                Button("How PodTrack works · Як це працює") { model.area = .howItWorks }
            }
        }
        Window("PodTrack · Algorithm Comparison",id:"algorithm-comparison") {
            AlgorithmComparisonView().environmentObject(model)
        }.defaultSize(width:1420,height:940)
    }
}

private struct ComparisonWindowCommand: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Compare reconstruction methods") { openWindow(id:"algorithm-comparison") }
            .keyboardShortcut("k",modifiers:[.command,.shift])
    }
}

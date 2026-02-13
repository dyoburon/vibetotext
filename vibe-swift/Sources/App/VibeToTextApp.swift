import SwiftUI

@main
struct VibeToTextApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // The window is managed by AppDelegate via MainWindowController.
        // We use Settings as a no-op scene since we need at least one.
        Settings {
            EmptyView()
        }
    }
}

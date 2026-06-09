import SwiftUI
import LostUI

@main
struct LostApp: App {
    init() {
        #if os(macOS)
        // Running via `swift run` has no app bundle, so bring the window forward.
        DispatchQueue.main.async {
            NSApplication.shared.setActivationPolicy(.regular)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            LostRootView()
        }
    }
}

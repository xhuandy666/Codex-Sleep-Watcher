import SwiftUI

@main
struct CodexSleepWatcherApp: App {
    @StateObject private var controller = AppController()
    var body: some Scene {
        MenuBarExtra("Codex Sleep Watcher", systemImage: "moon.zzz") {
            MenuBarView(controller: controller)
                .task { await controller.start() }
        }
        .menuBarExtraStyle(.window)
    }
}

import SwiftUI

@main
struct CodexSleepWatcherApp: App {
    @StateObject private var controller: AppController

    init() {
        let controller = AppController()
        _controller = StateObject(wrappedValue: controller)
        Task { @MainActor in await controller.start() }
    }

    var body: some Scene {
        MenuBarExtra("Codex Sleep Watcher", systemImage: "moon.zzz") {
            MenuBarView(controller: controller)
        }
        .menuBarExtraStyle(.window)
    }
}

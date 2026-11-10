import AppKit
import SwiftUI
import QForEmailCore

@main
enum Entrypoint {
    static func main() {
        if CommandLine.arguments.contains("--version") {
            print("q-for-email \(Version.version)")
            return
        }
        QForEmailApp.main()
    }
}

struct QForEmailApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("Q for Email", id: "main") {
            MainView()
                .environmentObject(model)
        }
        .defaultSize(width: 560, height: 680)

        MenuBarExtra("Q", systemImage: "q.circle") {
            MenuBarMenu()
                .environmentObject(model)
        }
    }
}

struct MenuBarMenu: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Q for Email") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "main")
        }
        Button(model.busy ? "Working…" : "Sort now") {
            Task { await model.sortNow() }
        }
        .disabled(model.busy)
        Divider()
        Button("Quit") {
            NSApp.terminate(nil)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--snapshot") {
            writeSnapshots()
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@MainActor
private func writeSnapshots() {
    let directory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first { $0.hasPrefix("/") } ?? "/tmp", isDirectory: true)
    let model = AppModel()
    model.bootstrap()
    let views: [(String, AnyView)] = [
        ("review", AnyView(MainView().environmentObject(model))),
        ("settings", AnyView(SettingsPane().environmentObject(model).frame(width: 560, height: 1280)))
    ]
    for (name, view) in views {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 560, height: name == "settings" ? 1280 : 680)
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
        host.cacheDisplay(in: host.bounds, to: rep)
        let url = directory.appendingPathComponent("q-\(name).png")
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        fputs("wrote \(url.path)\n", stderr)
    }
}

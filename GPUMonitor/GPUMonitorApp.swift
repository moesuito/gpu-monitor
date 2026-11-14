import SwiftUI
import AppKit

@main
struct GPUMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanelView(viewModel: appDelegate.viewModel)
        } label: {
            MenuBarLabelView(viewModel: appDelegate.viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let viewModel = GPUMonitorViewModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        viewModel.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        viewModel.stop()
    }
}

private struct MenuBarLabelView: View {
    @ObservedObject var viewModel: GPUMonitorViewModel

    var body: some View {
        Label {
            Text(viewModel.menuBarTitle)
                .monospacedDigit()
        } icon: {
            Image(systemName: "cpu")
        }
        .labelStyle(.titleAndIcon)
    }
}

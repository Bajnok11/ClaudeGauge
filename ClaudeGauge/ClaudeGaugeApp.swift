import SwiftUI
import AppKit

@main
struct ClaudeGaugeApp: App {
    @StateObject private var model = UsageModel.makeForLaunch()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(model)
        } label: {
            MenuBarLabel(snapshot: model.snapshot, preferences: model.preferences)
        }
        .menuBarExtraStyle(.window)

        Window("Usage History", id: HistoryWindow.id) {
            HistoryView()
                .environmentObject(model)
        }
        .defaultSize(width: 760, height: 640)

        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}

/// Handles the two things SwiftUI's `App` lifecycle can't express: a launch
/// that renders assets and exits, and a launch that opens its windows so an
/// external script can screenshot them.
///
/// Everything touching `NSApp` below is explicitly `@MainActor`. Swift 6.2+
/// (Xcode 26) infers main-actor isolation for this kind of code and compiles
/// it without the annotations; Swift 6.0 (the Xcode 16 toolchain the README
/// claims support for, and what CI builds with) does not. Being explicit is
/// what makes the project actually build on the versions it says it supports.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Opens the History and Settings windows, for `Scripts/render-screenshots.sh`.
    static let openWindowsArgument = "--open-windows"

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let outputDirectory = ScreenshotRenderer.requestedOutputDirectory() {
            // Render on the next runloop turn so SwiftUI has finished
            // setting up (fonts, materials, the environment) — rendering
            // during launch produces subtly unstyled output.
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    ScreenshotRenderer.renderAll(into: outputDirectory)
                    NSApp.terminate(nil)
                }
            }
            return
        }

        if CommandLine.arguments.contains(Self.openWindowsArgument) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                MainActor.assumeIsolated {
                    Self.openCaptureWindows()
                }
            }
        }
    }

    /// Opens both windows by invoking the menu items SwiftUI already
    /// installs for them. Going through the menu (rather than reaching for
    /// `openWindow`, which is only available inside a `View`/`Scene`) keeps
    /// this to public AppKit API and works from the app delegate.
    @MainActor
    private static func openCaptureWindows() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        performMenuItem(matching: "Usage History")

        // The Settings selector has been renamed across macOS releases
        // (`showPreferencesWindow:` → `showSettingsWindow:`), and on recent
        // versions neither reliably fires for a SwiftUI `Settings` scene in
        // an agent app. Driving the menu item SwiftUI installs works
        // regardless of which name the current OS uses; the selectors stay
        // as a fallback for the reverse case.
        if !performMenuItem(matching: "Settings") {
            if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
                _ = NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
            }
        }
    }

    /// Case-insensitive substring match, so "Settings" finds the real item
    /// title "Settings…" (which ends in a U+2026 ellipsis, not three dots).
    @MainActor
    @discardableResult
    private static func performMenuItem(matching needle: String) -> Bool {
        guard let mainMenu = NSApp.mainMenu else { return false }
        for topLevel in mainMenu.items {
            guard let submenu = topLevel.submenu else { continue }
            for item in submenu.items
            where item.title.range(of: needle, options: .caseInsensitive) != nil {
                submenu.performActionForItem(at: submenu.index(of: item))
                return true
            }
        }
        return false
    }
}

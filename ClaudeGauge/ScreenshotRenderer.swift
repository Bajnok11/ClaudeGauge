import SwiftUI
import AppKit
import WidgetKit
import ImageIO
import UniformTypeIdentifiers
import ClaudeGaugeCore

/// Renders the app's real views to PNGs for the README, then exits.
///
/// Why this exists instead of taking screen captures: the menu bar popover
/// belongs to an `LSUIElement` agent app, so there's no window to focus and
/// no Dock icon for automation to click — and a desktop capture would drag
/// in whatever else happens to be on screen. `ImageRenderer` draws the
/// exact same `MenuBarView`/`HistoryView`/widget views the app ships, at a
/// chosen scale, against fixed sample data, so the images are clean,
/// reproducible, and can't drift away from the real UI.
///
/// Usage (from the repo root):
///     ./Scripts/render-screenshots.sh
@MainActor
enum ScreenshotRenderer {
    static let launchArgument = "--render-screenshots"

    /// Returns the output directory when the app was launched to render
    /// screenshots, or nil for a normal launch.
    static func requestedOutputDirectory() -> URL? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: launchArgument),
              index + 1 < arguments.count else {
            return nil
        }
        return URL(fileURLWithPath: arguments[index + 1])
    }

    static func renderAll(into directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var showcase = Preferences.default
        showcase.enabledExtraProviderIDs = ["codex"]

        // Sample data throughout — never the machine's real usage, which
        // would put local project names into a public README. See
        // `UsageModel.makeForLaunch()`.
        let model = UsageModel.sample(preferences: showcase)

        render(
            MenuBarView()
                .environmentObject(model)
                .frame(width: 288)
                .background(BackdropPanel()),
            to: directory.appendingPathComponent("popover.png")
        )

        var accented = showcase
        accented.accent = .purple
        accented.menuBarStyle = .iconAndBar
        let accentedModel = UsageModel.sample(preferences: accented)
        render(
            MenuBarView()
                .environmentObject(accentedModel)
                .frame(width: 288)
                .background(BackdropPanel()),
            to: directory.appendingPathComponent("popover-accent.png")
        )

        // History and Settings are deliberately NOT rendered here: they're
        // built from AppKit-backed SwiftUI (Table, Form, TabView) that
        // `ImageRenderer` can only draw as a placeholder. They're captured
        // as real windows instead — see Scripts/render-screenshots.sh.

        render(
            WidgetShowcase(model: model),
            to: directory.appendingPathComponent("widgets.png")
        )

        renderDemoGIF(to: directory.appendingPathComponent("demo.gif"))

        print("Rendered screenshots into \(directory.path)")
    }

    // MARK: - Animated demo

    /// Builds the README's animated GIF by rendering the popover across a
    /// sweep of usage values and accent choices, then assembling the frames
    /// with ImageIO.
    ///
    /// Assembling frames beats screen-recording here: no cursor, no window
    /// chrome, no timing jitter, and the result is reproducible — rerunning
    /// the script produces a byte-comparable animation instead of whatever
    /// the recorder happened to catch.
    private static func renderDemoGIF(to url: URL) {
        struct Frame {
            let session: Double
            let weekly: Double
            let accent: AccentChoice
        }

        // Climb through the thresholds so the traffic-light colors all get
        // screen time, then switch accents to show the theming.
        var frames: [Frame] = []
        for percent in stride(from: 6.0, through: 96.0, by: 6.0) {
            frames.append(Frame(session: percent, weekly: percent * 0.55, accent: .status))
        }
        for accent in [AccentChoice.blue, .purple, .pink, .orange] {
            for _ in 0..<4 {
                frames.append(Frame(session: 68, weekly: 41, accent: accent))
            }
        }

        var images: [CGImage] = []
        for frame in frames {
            var preferences = Preferences.default
            preferences.accent = frame.accent
            preferences.enabledExtraProviderIDs = ["codex"]

            let model = UsageModel.sample(preferences: preferences)
            model.overrideSampleUsage(session: frame.session, weekly: frame.weekly)

            let view = MenuBarView()
                .environmentObject(model)
                .frame(width: 288)
                .background(BackdropPanel())

            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            if let cgImage = renderer.cgImage {
                images.append(cgImage)
            }
        }

        guard !images.isEmpty,
              let destination = CGImageDestinationCreateWithURL(
                url as CFURL,
                "com.compuserve.gif" as CFString,
                images.count,
                nil
              ) else {
            print("Failed to create demo.gif")
            return
        }

        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
        ] as CFDictionary)

        for image in images {
            CGImageDestinationAddImage(destination, image, [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFUnclampedDelayTime: 0.09]
            ] as CFDictionary)
        }

        if CGImageDestinationFinalize(destination) {
            print("wrote demo.gif (\(images.count) frames)")
        } else {
            print("Failed to finalize demo.gif")
        }
    }

    private static func render<V: View>(_ view: V, to url: URL, scale: CGFloat = 2) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else {
            print("Failed to render \(url.lastPathComponent)")
            return
        }
        try? data.write(to: url)
        print("wrote \(url.lastPathComponent)")
    }
}

/// A neutral rounded backdrop so a rendered panel reads as a floating
/// window rather than a transparent rectangle in the README.
private struct BackdropPanel: View {
    var cornerRadius: CGFloat = 10

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color(nsColor: .windowBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(.separator, lineWidth: 1)
            )
    }
}

/// The three widget sizes side by side, drawn with the same views the
/// extension uses so the README can show all of them in one image.
private struct WidgetShowcase: View {
    let model: UsageModel

    private var snapshot: UsageSnapshot { model.snapshot }

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            tile(width: 158, height: 158, label: "Small") { widget(.systemSmall) }
            tile(width: 338, height: 158, label: "Medium") { widget(.systemMedium) }
            tile(width: 338, height: 338, label: "Large") { widget(.systemLarge) }
        }
        .padding(22)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private func widget(_ family: WidgetFamily) -> some View {
        WidgetContentView(
            snapshot: snapshot,
            preferences: model.preferences,
            metric: .both,
            showTrend: true,
            trend: model.history.dailyPadded(days: 14).map(\.totalTokens),
            family: family
        )
    }

    private func tile<Content: View>(
        width: CGFloat,
        height: CGFloat,
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 6) {
            content()
                .padding(14)
                .frame(width: width, height: height)
                .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 18))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(.separator.opacity(0.6), lineWidth: 1)
                )
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

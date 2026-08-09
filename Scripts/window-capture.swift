#!/usr/bin/env swift
//
// Prints the on-screen window IDs belonging to ClaudeGauge, one per line as
//     <windowID>\t<title>
// so a shell script can hand them to `screencapture -l`.
//
// Needed because the Settings and History windows are built from AppKit-backed
// SwiftUI (TabView, Form, Table). `ImageRenderer` can't draw those — it emits a
// yellow "unsupported" placeholder — and rewriting them as hand-rolled SwiftUI
// purely to make screenshots work would mean shipping a less native app to
// serve the README. So those two get captured as real windows instead.
//
import CoreGraphics
import Foundation

let ownerName = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "ClaudeGauge"

guard let windows = CGWindowListCopyWindowInfo(
    [.optionOnScreenOnly, .excludeDesktopElements],
    kCGNullWindowID
) as? [[String: Any]] else {
    FileHandle.standardError.write(Data("Could not read the window list.\n".utf8))
    exit(1)
}

var found = false
for window in windows {
    guard let owner = window[kCGWindowOwnerName as String] as? String, owner == ownerName else { continue }
    guard let number = window[kCGWindowNumber as String] as? Int else { continue }
    let title = window[kCGWindowName as String] as? String ?? ""
    // Menu bar items and other zero-size chrome show up here too; only real
    // windows are worth capturing.
    if let bounds = window[kCGWindowBounds as String] as? [String: Any],
       let height = bounds["Height"] as? Double, height < 120 {
        continue
    }
    print("\(number)\t\(title)")
    found = true
}

if !found {
    FileHandle.standardError.write(Data("No on-screen windows found for \(ownerName).\n".utf8))
    exit(2)
}

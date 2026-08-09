#!/usr/bin/env swift
//
// Renders ClaudeGauge's app icon at every size the asset catalog needs.
//
// Kept as source (rather than committing only the PNGs) so the icon is
// reproducible and tweakable: change a constant here, re-run, and every
// size regenerates consistently. Run from the repo root:
//
//     swift Scripts/generate-icon.swift
//
import AppKit
import CoreGraphics
import Foundation

// MARK: - Design constants

/// Deep slate base — dark enough that the gauge arc reads at 16pt, and
/// neutral enough not to imitate any vendor's brand color.
let backgroundTop = CGColor(red: 0.16, green: 0.18, blue: 0.24, alpha: 1)
let backgroundBottom = CGColor(red: 0.09, green: 0.10, blue: 0.14, alpha: 1)

/// The arc runs green → amber → red, the same traffic light the app uses
/// for its thresholds, so the icon states what the app measures.
let arcStops: [(CGFloat, CGColor)] = [
    (0.00, CGColor(red: 0.30, green: 0.82, blue: 0.47, alpha: 1)),
    (0.55, CGColor(red: 0.98, green: 0.78, blue: 0.26, alpha: 1)),
    (1.00, CGColor(red: 0.94, green: 0.35, blue: 0.33, alpha: 1))
]

let needleColor = CGColor(gray: 1.0, alpha: 0.96)

// MARK: - Drawing

func drawIcon(size: CGFloat, context: CGContext) {
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    context.clear(rect)

    // macOS icons sit inside a rounded square with a little breathing room
    // rather than filling the full canvas edge to edge.
    let inset = size * 0.055
    let plate = rect.insetBy(dx: inset, dy: inset)
    let corner = plate.width * 0.225

    let platePath = CGPath(roundedRect: plate, cornerWidth: corner, cornerHeight: corner, transform: nil)

    // Background gradient
    context.saveGState()
    context.addPath(platePath)
    context.clip()
    if let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [backgroundTop, backgroundBottom] as CFArray,
        locations: [0, 1]
    ) {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: plate.midX, y: plate.maxY),
            end: CGPoint(x: plate.midX, y: plate.minY),
            options: []
        )
    }
    context.restoreGState()

    // Subtle top highlight so the plate reads as a physical surface at
    // large sizes; invisible (harmlessly) at 16pt.
    context.saveGState()
    context.addPath(platePath)
    context.clip()
    context.setStrokeColor(CGColor(gray: 1, alpha: 0.16))
    context.setLineWidth(size * 0.012)
    context.addPath(platePath)
    context.strokePath()
    context.restoreGState()

    // MARK: Gauge arc
    let center = CGPoint(x: plate.midX, y: plate.midY - plate.height * 0.06)
    let radius = plate.width * 0.30
    let lineWidth = plate.width * 0.115

    // Sweep from 210° to -30° (i.e. a 240° dial opening downward), which is
    // the classic gauge silhouette and stays recognizable when scaled down.
    let startAngle: CGFloat = .pi * 7 / 6
    let endAngle: CGFloat = -.pi / 6
    let totalSweep = startAngle - endAngle

    // Track
    context.setLineCap(.round)
    context.setLineWidth(lineWidth)
    context.setStrokeColor(CGColor(gray: 1, alpha: 0.12))
    context.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
    context.strokePath()

    // Colored arc, drawn as short segments so it can carry a gradient along
    // its length — CGContext has no native "gradient along a path".
    //
    // Each segment is extended half a step past its neighbour: butted
    // segments leave antialiased seams that show up as radial striping
    // across the arc, and the overlap costs nothing because adjacent colors
    // are nearly identical.
    let segments = max(64, Int(size / 3))
    let step = totalSweep / CGFloat(segments)
    for index in 0..<segments {
        let t = CGFloat(index) / CGFloat(segments)
        let a0 = startAngle - step * CGFloat(index)
        let a1 = a0 - step * 1.5

        context.setStrokeColor(color(at: t))
        context.setLineWidth(lineWidth)
        // Round caps everywhere: at this segment length the cap is smaller
        // than a pixel mid-arc, and it keeps both ends of the dial rounded.
        context.setLineCap(.round)
        context.addArc(
            center: center,
            radius: radius,
            startAngle: a0,
            endAngle: max(a1, endAngle),
            clockwise: true
        )
        context.strokePath()
    }

    // MARK: Needle
    // Parked at ~72% of the sweep: visibly "in the warning band", which
    // says "this is a meter that's telling you something".
    let needleT: CGFloat = 0.72
    let needleAngle = startAngle - totalSweep * needleT
    let needleLength = radius * 0.86
    let needleTip = CGPoint(
        x: center.x + cos(needleAngle) * needleLength,
        y: center.y + sin(needleAngle) * needleLength
    )

    context.setLineCap(.round)
    context.setLineWidth(size * 0.030)
    context.setStrokeColor(CGColor(gray: 0, alpha: 0.35))
    context.move(to: CGPoint(x: center.x, y: center.y - size * 0.006))
    context.addLine(to: CGPoint(x: needleTip.x, y: needleTip.y - size * 0.006))
    context.strokePath()

    context.setLineWidth(size * 0.026)
    context.setStrokeColor(needleColor)
    context.move(to: center)
    context.addLine(to: needleTip)
    context.strokePath()

    // Hub
    let hubRadius = size * 0.043
    context.setFillColor(needleColor)
    context.fillEllipse(in: CGRect(
        x: center.x - hubRadius, y: center.y - hubRadius,
        width: hubRadius * 2, height: hubRadius * 2
    ))
    context.setFillColor(backgroundBottom)
    let innerHub = hubRadius * 0.42
    context.fillEllipse(in: CGRect(
        x: center.x - innerHub, y: center.y - innerHub,
        width: innerHub * 2, height: innerHub * 2
    ))
}

/// Linear interpolation through `arcStops`.
func color(at t: CGFloat) -> CGColor {
    let clamped = min(max(t, 0), 1)
    for index in 0..<(arcStops.count - 1) {
        let (p0, c0) = arcStops[index]
        let (p1, c1) = arcStops[index + 1]
        guard clamped >= p0, clamped <= p1 else { continue }
        let local = p1 == p0 ? 0 : (clamped - p0) / (p1 - p0)
        let comps0 = c0.components ?? [0, 0, 0, 1]
        let comps1 = c1.components ?? [0, 0, 0, 1]
        return CGColor(
            red: comps0[0] + (comps1[0] - comps0[0]) * local,
            green: comps0[1] + (comps1[1] - comps0[1]) * local,
            blue: comps0[2] + (comps1[2] - comps0[2]) * local,
            alpha: 1
        )
    }
    return arcStops.last!.1
}

func writePNG(size: Int, to url: URL) throws {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw NSError(domain: "icon", code: 1)
    }

    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    drawIcon(size: CGFloat(size), context: context)

    guard let image = context.makeImage() else { throw NSError(domain: "icon", code: 2) }
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: size, height: size)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "icon", code: 3)
    }
    try data.write(to: url)
}

// MARK: - Entry point

let outputDirectory = URL(fileURLWithPath: "ClaudeGauge/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

/// (point size, scale) pairs macOS asset catalogs expect.
let variants: [(point: Int, scale: Int)] = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2)
]

var images: [[String: String]] = []
for variant in variants {
    let pixels = variant.point * variant.scale
    let filename = "icon_\(variant.point)x\(variant.point)\(variant.scale == 2 ? "@2x" : "").png"
    try writePNG(size: pixels, to: outputDirectory.appendingPathComponent(filename))
    images.append([
        "size": "\(variant.point)x\(variant.point)",
        "idiom": "mac",
        "filename": filename,
        "scale": "\(variant.scale)x"
    ])
    print("wrote \(filename) (\(pixels)px)")
}

let contents: [String: Any] = [
    "images": images,
    "info": ["version": 1, "author": "xcode"]
]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: outputDirectory.appendingPathComponent("Contents.json"))
print("wrote Contents.json")

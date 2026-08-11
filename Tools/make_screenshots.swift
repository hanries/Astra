// Compose App Store screenshots from raw simulator captures.
//
//   swift Tools/make_screenshots.swift <raw-dir> <out-dir>
//
// Capturing the raws is the part that is easy to get wrong:
//
//   1. Boot an iPhone 17 Pro Max. It is the 6.9" size, and its screenshots come
//      out at 1320x2868 with no resizing.
//   2. Pin the status bar, or every panel carries a different clock and a
//      half-drained battery:
//        xcrun simctl status_bar <udid> override --time 9:41 \
//          --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4
//   3. Install a DEBUG build, run onboarding, add a second habit, then use the
//      debug menu's "Seed 60 days". An empty sky makes a poor case for an app
//      about filling one.
//   4. Install a RELEASE build over the top. The data container survives and
//      the debug menu's ladybug leaves the toolbar, which a reviewer would
//      otherwise find sitting in the corner of two of these panels.
//   5. Capture with `xcrun simctl io <udid> screenshot`.
//
// 1320x2868, the 6.9" iPhone size App Store Connect asks for. The panel is the
// app's own grammar rather than a marketing template: the same ground colour,
// the same letterspaced margin label over a plain sentence, the same hairline
// rules. A screenshot set that looks like a different product than the app is
// the most common way these go wrong.

import AppKit
import CoreGraphics
import CoreText
import Foundation

let scale: Double = 3
let pointW: Double = 440
let pointH: Double = 956
let W = Int(pointW * scale)
let H = Int(pointH * scale)

// Built in the same space as the context and as the baked assets. Mixing sRGB
// with DeviceRGB shifts the fill by a value or two, which is invisible on its
// own and very visible as a rectangle around an image carrying the same colour.
let deviceRGB = CGColorSpaceCreateDeviceRGB()
let ground = CGColor(colorSpace: deviceRGB, components: [10 / 255, 13 / 255, 20 / 255, 1])!
let starlight = NSColor(srgbRed: 0.93, green: 0.94, blue: 0.97, alpha: 1)
let subdued = NSColor(srgbRed: 0.55, green: 0.58, blue: 0.66, alpha: 1)
let rule = CGColor(colorSpace: deviceRGB, components: [41 / 255, 48 / 255, 64 / 255, 1])!

let margin: Double = 44
/// The device's own corner radius, as a fraction of its width, so the rounded
/// screenshot keeps the proportion of the hardware it came from.
let cornerFraction: Double = 55.0 / 440.0

struct Panel {
    let file: String
    let label: String
    let caption: String
    var sub: String? = nil
    /// Panels with no screenshot show the mark instead.
    var isMark: Bool = false
}

// Ordered for the store, where the first two or three carry most of the weight:
// what you get, then how it works, then what it costs.
let panels: [Panel] = [
    Panel(file: "sky", label: "Your sky",
          caption: "Every day you keep\nlights a real star.",
          sub: "Free, with no ads and no account."),
    Panel(file: "today", label: "Today",
          caption: "Mark them all, or the\nday doesn't count."),
    Panel(file: "unlock", label: "One star a day",
          caption: "Nothing you light\nis ever taken back."),
    Panel(file: "star", label: "Real astronomy",
          caption: "1,584 catalogued stars,\nwith measured colours."),
    Panel(file: "log", label: "Your record",
          caption: "No streak to break.\nJust what you've done."),
    Panel(file: "widget", label: "Home screen",
          caption: "Mark the day without\nopening the app."),
    Panel(file: "mark", label: "Free, and private",
          caption: "No ads. No subscription.\nNo account.",
          sub: "Nothing you record ever leaves your phone.",
          isMark: true),
]

func load(_ path: String) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else {
        return nil
    }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

/// Draws a run of text and returns the y it consumed, working top-down.
@discardableResult
func draw(
    _ text: String, in context: CGContext, top: Double,
    size: Double, weight: NSFont.Weight, colour: NSColor,
    kern: Double = 0, leading: Double = 1.28, centred: Bool = false
) -> Double {
    let font = NSFont.systemFont(ofSize: size * scale, weight: weight)
    var y = top
    for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
        let attributed = NSAttributedString(string: String(line), attributes: [
            .font: font, .kern: kern * scale, .foregroundColor: colour,
        ])
        let ctLine = CTLineCreateWithAttributedString(attributed)
        let inked = CTLineGetTypographicBounds(ctLine, nil, nil, nil) - kern * scale
        let x = centred ? (Double(W) - inked) / 2 : margin * scale
        // CoreText draws from the baseline up, and everything here is measured
        // from the top, so drop by the ascent before drawing.
        context.textPosition = CGPoint(x: x, y: Double(H) - (y + Double(font.ascender)))
        CTLineDraw(ctLine, context)
        y += size * scale * leading
    }
    return y
}

func compose(_ panel: Panel, rawDirectory: String, outDirectory: String) {
    guard let context = CGContext(
        data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
        space: deviceRGB,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return }

    context.setFillColor(ground)
    context.fill(CGRect(x: 0, y: 0, width: Double(W), height: Double(H)))

    var y = 84 * scale
    y = draw(panel.label.uppercased(), in: context, top: y,
             size: 12, weight: .medium, colour: subdued, kern: 2.2, leading: 1.9)
    y = draw(panel.caption, in: context, top: y,
             size: 29, weight: .regular, colour: starlight, leading: 1.30)

    if let sub = panel.sub {
        y += 10 * scale
        y = draw(sub, in: context, top: y, size: 15, weight: .regular, colour: subdued)
    }

    let top = y + 38 * scale
    let available = Double(H) - top - 26 * scale

    if panel.isMark {
        // No screenshot to show, so the app's own mark holds the space.
        if let mark = load("\(rawDirectory)/mark-source.png") {
            let width = 299.0 * scale
            let height = 370.0 * scale
            context.draw(mark, in: CGRect(
                x: (Double(W) - width) / 2,
                y: Double(H) - (top + (available - height) / 2 + height),
                width: width, height: height
            ))
        }
    } else if let shot = load("\(rawDirectory)/\(panel.file).png") {
        let height = available
        let width = height * (pointW / pointH)
        let x = (Double(W) - width) / 2
        let rect = CGRect(x: x, y: Double(H) - (top + height), width: width, height: height)
        let radius = width * cornerFraction

        context.saveGState()
        let clip = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius,
                          transform: nil)
        context.addPath(clip)
        context.clip()
        context.draw(shot, in: rect)
        context.restoreGState()

        // A hairline so a dark screenshot separates from the dark ground
        // instead of dissolving into it.
        context.addPath(clip)
        context.setStrokeColor(rule)
        context.setLineWidth(1.2 * scale)
        context.strokePath()
    }

    guard let image = context.makeImage() else { return }
    let index = panels.firstIndex { $0.file == panel.file }! + 1
    let path = "\(outDirectory)/\(String(format: "%02d", index))-\(panel.file).png"
    guard let destination = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil
    ) else { return }
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
    print("\(path)  \(image.width)x\(image.height)")
}

let raw = CommandLine.arguments[1]
let out = CommandLine.arguments[2]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for panel in panels { compose(panel, rawDirectory: raw, outDirectory: out) }

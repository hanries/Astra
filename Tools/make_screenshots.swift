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
//      otherwise find sitting in the corner of two panels.
//   5. Capture with `xcrun simctl io <udid> screenshot`.
//   6. For sky-day1, uninstall, reinstall, set hasSeenFirstLight, add one habit
//      and mark it. One star against thirty-eight is the whole argument for the
//      app, and it has to be a real capture.
//
// The panels put the app's own instruments on the page: the star portrait, the
// widget, the size comparison, the stats rule. That is what there is to look
// at here, and a phone sitting alone in the middle of a dark rectangle shows
// none of it.

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
// with DeviceRGB shifts a fill by a value or two, which is invisible on its own
// and very visible as a rectangle around an image carrying the same colour.
let deviceRGB = CGColorSpaceCreateDeviceRGB()
func colour(_ r: Int, _ g: Int, _ b: Int, _ a: Double = 1) -> CGColor {
    CGColor(colorSpace: deviceRGB,
            components: [Double(r) / 255, Double(g) / 255, Double(b) / 255, a])!
}
let ground = colour(10, 13, 20)
let rule = colour(41, 48, 64)
let ruleFaint = colour(30, 36, 48)
let starlight = NSColor(srgbRed: 0.93, green: 0.94, blue: 0.97, alpha: 1)
let subdued = NSColor(srgbRed: 0.55, green: 0.58, blue: 0.66, alpha: 1)

let margin: Double = 40
let cornerFraction: Double = 55.0 / 440.0

// MARK: - Geometry, all in points, measured from the top like a layout is

func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect {
    CGRect(x: x * scale, y: Double(H) - (y + h) * scale, width: w * scale, height: h * scale)
}

/// A region of a source capture, in the capture's own points.
func crop(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect {
    CGRect(x: x * scale, y: y * scale, width: w * scale, height: h * scale)
}

func load(_ path: String) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil)
    else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

// MARK: - The field behind everything

/// The same kind of sky the app draws, at a fraction of the brightness.
///
/// A flat rectangle of one colour is what made the first version of these look
/// like a template. This is quiet enough to read as depth rather than as
/// decoration.
func drawField(in context: CGContext) {
    var seed: UInt64 = 0x5EED_1CE
    func next() -> Double {
        seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(seed >> 11) / Double(UInt64(1) << 53)
    }
    for _ in 0..<420 {
        let x = next() * Double(W)
        let y = next() * Double(H)
        let r = (0.6 + next() * 1.6) * scale
        let alpha = 0.05 + next() * 0.16
        context.setFillColor(colour(200, 210, 235, alpha))
        context.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    }
}

// MARK: - Type

@discardableResult
func draw(
    _ text: String, in context: CGContext, top: Double,
    size: Double, weight: NSFont.Weight, colour textColour: NSColor,
    kern: Double = 0, leading: Double = 1.22, x: Double = margin
) -> Double {
    let font = NSFont.systemFont(ofSize: size * scale, weight: weight)
    var y = top
    for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
        let attributed = NSAttributedString(string: String(line), attributes: [
            .font: font, .kern: kern * scale, .foregroundColor: textColour,
        ])
        // CoreText draws from the baseline up, and this lays out from the top.
        context.textPosition = CGPoint(x: x * scale,
                                       y: Double(H) - (y * scale + Double(font.ascender)))
        CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
        y += size * leading
    }
    return y
}

// MARK: - Screens and the pieces cut out of them

/// A capture, rounded like the hardware.
///
/// `visible` trims the source from the bottom. Most of these screens put their
/// content in the top two thirds and leave the rest dark, and a large empty
/// rectangle is what made the first pass of these look like filler.
func drawScreen(
    _ image: CGImage, in context: CGContext,
    x: Double, top: Double, width: Double, visible: Double = pointH
) {
    let source = crop(0, 0, pointW, visible)
    let shown = image.cropping(to: source) ?? image
    let height = width * (visible / pointW)
    let frame = rect(x, top, width, height)
    let radius = width * cornerFraction * scale

    context.saveGState()
    let path = CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil)
    context.addPath(path)
    context.clip()
    context.draw(shown, in: frame)
    context.restoreGState()

    context.addPath(path)
    context.setStrokeColor(rule)
    context.setLineWidth(1.1 * scale)
    context.strokePath()
}

/// A piece of the interface lifted out and set down on the page.
///
/// Backed and ruled so it reads as a separate object rather than as a hole cut
/// in the screenshot behind it.
func drawPiece(
    _ image: CGImage, in context: CGContext, from source: CGRect,
    x: Double, top: Double, width: Double, radius: Double = 16, pad: Double = 0
) {
    guard let piece = image.cropping(to: source) else { return }
    let ratio = Double(piece.height) / Double(piece.width)
    let height = width * ratio
    let outer = rect(x - pad, top - pad, width + pad * 2, height + pad * 2)
    let inner = rect(x, top, width, height)
    let path = CGPath(roundedRect: outer, cornerWidth: radius * scale,
                      cornerHeight: radius * scale, transform: nil)

    context.saveGState()
    context.addPath(path)
    context.clip()
    context.setFillColor(colour(16, 20, 30))
    context.fill(outer)
    context.draw(piece, in: inner)
    context.restoreGState()

    context.addPath(path)
    context.setStrokeColor(rule)
    context.setLineWidth(1.1 * scale)
    context.strokePath()
}

/// A circular cut, for the star portraits, which are round to begin with.
func drawDisc(
    _ image: CGImage, in context: CGContext, from source: CGRect,
    centreX: Double, centreY: Double, diameter: Double
) {
    guard let piece = image.cropping(to: source) else { return }
    let frame = rect(centreX - diameter / 2, centreY - diameter / 2, diameter, diameter)
    context.saveGState()
    context.addEllipse(in: frame)
    context.clip()
    context.setFillColor(ground)
    context.fill(frame)
    context.draw(piece, in: frame)
    context.restoreGState()

    context.addEllipse(in: frame)
    context.setStrokeColor(rule)
    context.setLineWidth(1.1 * scale)
    context.strokePath()
}

/// A caption under a lifted piece, in the app's own margin-label voice.
func drawTag(_ text: String, in context: CGContext, top: Double, x: Double) {
    draw(text.uppercased(), in: context, top: top, size: 11, weight: .medium,
         colour: subdued, kern: 2.0, x: x)
}

// MARK: - Panels

func panel(_ name: String, _ body: (CGContext) -> Void) {
    guard let context = CGContext(
        data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
        space: deviceRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return }
    context.setFillColor(ground)
    context.fill(CGRect(x: 0, y: 0, width: Double(W), height: Double(H)))
    drawField(in: context)
    body(context)
    guard let image = context.makeImage() else { return }
    let path = "\(outDirectory)/\(name).png"
    guard let destination = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil
    ) else { return }
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
    print("\(path)")
}

/// Label, headline, supporting line. Returns where the art can start.
@discardableResult
func heading(_ context: CGContext, _ label: String, _ head: String, _ sub: String) -> Double {
    var y = draw(label.uppercased(), in: context, top: 76, size: 12, weight: .semibold,
                 colour: subdued, kern: 2.6, leading: 1.9)
    y = draw(head, in: context, top: y + 4, size: 41, weight: .semibold,
             colour: starlight, kern: -1.0, leading: 1.14)
    y = draw(sub, in: context, top: y + 12, size: 16, weight: .regular,
             colour: subdued, leading: 1.35)
    return y
}

let rawDirectory = CommandLine.arguments[1]
let outDirectory = CommandLine.arguments[2]
try? FileManager.default.createDirectory(atPath: outDirectory, withIntermediateDirectories: true)

let today = load("\(rawDirectory)/today.png")!
let unlock = load("\(rawDirectory)/unlock.png")!
let sky = load("\(rawDirectory)/sky.png")!
let skyDay1 = load("\(rawDirectory)/sky-day1.png")!
let star = load("\(rawDirectory)/star.png")!
let log = load("\(rawDirectory)/log.png")!
let widget = load("\(rawDirectory)/widget.png")!
let sun = load("\(rawDirectory)/sun.png")!
let word = load("\(rawDirectory)/word.png")!


// 1. The loop the whole app runs on. The phone runs off the bottom on purpose:
//    the interesting half of the Today screen is the top half, and the rest is
//    the empty space a day leaves once you have marked it.
panel("01-loop") { context in
    let y = heading(context, "How it works", "Keep every habit.\nLight a real star.",
                    "One completed day gives you one star.")
    drawScreen(today, in: context, x: 20, top: y + 70, width: 400, visible: 580)
    drawDisc(unlock, in: context, from: crop(126, 306, 188, 188),
             centreX: 372, centreY: y + 122, diameter: 146)
    drawPiece(unlock, in: context, from: crop(88, 566, 264, 116),
              x: 192, top: y + 428, width: 232, pad: 12)
}

// 2. The reason to keep going, and the only claim here that needs two separate
//    captures to make honestly.
panel("02-grows") { context in
    let y = heading(context, "It grows", "Sixty days ago,\nthis sky was empty.",
                    "Every day you keep adds one more star.")
    drawTag("Day 1", in: context, top: y + 62, x: 18)
    drawScreen(skyDay1, in: context, x: 18, top: y + 92, width: 196)
    drawTag("Day 60", in: context, top: y + 62, x: 228)
    drawScreen(sky, in: context, x: 228, top: y + 92, width: 196)
    drawPiece(sky, in: context, from: crop(14, 122, 412, 74),
              x: 40, top: y + 560, width: 360, pad: 12)
}

// 3. What it costs, said plainly and then itemised.
//
//    The mark goes down as the two transparent pieces rather than the flattened
//    one: the flattened copy carries its own background, which would sit on the
//    field behind it as a dark rectangle.
panel("03-free") { context in
    let y = heading(context, "Free", "Free, with nothing\nto buy inside.",
                    "No ads, no subscription, and no account to make.")
    let k = 210.0 / 299.0                 // the mark's canvas, scaled down
    let centreY = y + 186
    context.draw(sun, in: rect(pointW / 2 - 105, centreY - 105, 210, 210))
    context.draw(word, in: rect(pointW / 2 - 152 * k / 2, centreY + 116.81 * k - 22 * k / 2,
                                152 * k, 22 * k))

    var line = y + 372
    for entry in ["Every feature, from the first day",
                  "No sign-up, no email, no profile",
                  "Nothing you record leaves the phone"] {
        context.setFillColor(ruleFaint)
        context.fill(rect(margin, line, pointW - margin * 2, 1))
        draw(entry, in: context, top: line + 18, size: 17, weight: .regular, colour: starlight)
        line += 62
    }
    context.setFillColor(ruleFaint)
    context.fill(rect(margin, line, pointW - margin * 2, 1))
}

// 4. Where the stars come from. The disc at the left is the same star enlarged,
//    which is the one piece of duplication worth keeping: it is the texture
//    that does not survive being shrunk to a phone.
panel("04-real") { context in
    let y = heading(context, "Real stars", "Every one of them\nis a real star.",
                    "Colour and temperature measured, not invented.")
    drawScreen(star, in: context, x: 136, top: y + 60, width: 296, visible: 706)
    drawDisc(star, in: context, from: crop(112, 140, 216, 216),
             centreX: 98, centreY: y + 178, diameter: 172)
}

// 5. The widget, which is the part people use most and see least, so it is the
//    hero here and the Home Screen is only there for context.
panel("05-widget") { context in
    let y = heading(context, "Home screen", "Log it without\nopening the app.",
                    "The widget marks a habit in one tap.")
    drawScreen(widget, in: context, x: 196, top: y + 172, width: 300, visible: 640)
    drawPiece(widget, in: context, from: crop(43, 101, 358, 158),
              x: 20, top: y + 44, width: 368, radius: 22, pad: 10)
}

// 6. The record. A cropped card rather than a whole phone, because the calendar
//    and the consistency bars are the entire point of the screen and a phone
//    frame around them would only make them smaller.
panel("06-log") { context in
    let y = heading(context, "Your log", "It keeps the days\nyou did keep.",
                    "A month at a time, with consistency for each habit.")
    drawPiece(log, in: context, from: crop(12, 118, 416, 512),
              x: 34, top: y + 60, width: 372, radius: 22, pad: 14)
}

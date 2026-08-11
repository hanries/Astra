// Four ways to set the same headline, at the size it ships at.
//
//   swift TypeCompare.swift <out.png>

import AppKit
import CoreGraphics
import CoreText
import Foundation

let scale: Double = 3
let W = Int(440 * scale)
let blockH = 300.0
let H = Int((blockH * 4 + 40) * scale)

let deviceRGB = CGColorSpaceCreateDeviceRGB()
func colour(_ r: Int, _ g: Int, _ b: Int, _ a: Double = 1) -> CGColor {
    CGColor(colorSpace: deviceRGB,
            components: [Double(r) / 255, Double(g) / 255, Double(b) / 255, a])!
}
let starlight = NSColor(srgbRed: 0.93, green: 0.94, blue: 0.97, alpha: 1)
let subdued = NSColor(srgbRed: 0.55, green: 0.58, blue: 0.66, alpha: 1)
let accent = NSColor(srgbRed: 0.79, green: 0.57, blue: 0.18, alpha: 1)

struct Option {
    let name: String
    let font: (Double, NSFont.Weight) -> NSFont
    let size: Double
    let kern: Double
    let leading: Double
}

/// A system font with a design applied, falling back if the design is missing.
func designed(_ size: Double, _ weight: NSFont.Weight, _ design: NSFontDescriptor.SystemDesign) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    guard let descriptor = base.fontDescriptor.withDesign(design) else { return base }
    return NSFont(descriptor: descriptor, size: size) ?? base
}

/// Narrowed by the width trait rather than by a separate family, which is how
/// SF exposes its compressed cuts.
func narrowed(_ size: Double, _ weight: NSFont.Weight, _ width: Double) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    let descriptor = base.fontDescriptor.addingAttributes([
        .traits: [NSFontDescriptor.TraitKey.width: width]
    ])
    return NSFont(descriptor: descriptor, size: size) ?? base
}

let options: [Option] = [
    Option(name: "A  SF Pro semibold (current)",
           font: { NSFont.systemFont(ofSize: $0, weight: $1) },
           size: 41, kern: -1.0, leading: 1.14),
    Option(name: "B  SF Pro Rounded bold",
           font: { designed($0, $1, .rounded) },
           size: 41, kern: -0.8, leading: 1.14),
    Option(name: "C  New York, Apple's serif",
           font: { designed($0, $1, .serif) },
           size: 42, kern: -0.6, leading: 1.12),
    Option(name: "D  SF Pro compressed black",
           font: { narrowed($0, $1, -0.35) },
           size: 52, kern: -0.6, leading: 1.02),
]

guard let context = CGContext(
    data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
    space: deviceRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { exit(1) }

context.setFillColor(colour(10, 13, 20))
context.fill(CGRect(x: 0, y: 0, width: Double(W), height: Double(H)))

func line(_ text: String, font: NSFont, colour c: NSColor, kern: Double, x: Double, y: Double) {
    let attributed = NSAttributedString(string: text, attributes: [
        .font: font, .kern: kern * scale, .foregroundColor: c,
    ])
    context.textPosition = CGPoint(x: x * scale,
                                   y: Double(H) - (y * scale + Double(font.ascender)))
    CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
}

var top = 26.0
for option in options {
    line(option.name.uppercased(),
         font: NSFont.systemFont(ofSize: 11 * scale, weight: .semibold),
         colour: accent, kern: 2.0, x: 40, y: top)

    line("SIXTY DAYS APART",
         font: NSFont.systemFont(ofSize: 12 * scale, weight: .semibold),
         colour: subdued, kern: 2.6, x: 40, y: top + 34)

    let head = option.font(option.size * scale, .semibold)
    let heavy = option.name.hasPrefix("D") ? option.font(option.size * scale, .black) : head
    line("One star on day one.", font: heavy, colour: starlight,
         kern: option.kern, x: 40, y: top + 62)
    line("Thirty-eight by day sixty.", font: heavy, colour: starlight,
         kern: option.kern, x: 40, y: top + 62 + option.size * option.leading)

    line("Thirteen constellations finished on the way.",
         font: NSFont.systemFont(ofSize: 16 * scale, weight: .regular),
         colour: subdued, kern: 0, x: 40, y: top + 62 + option.size * option.leading * 2 + 14)

    context.setFillColor(colour(30, 36, 48))
    context.fill(CGRect(x: 40 * scale, y: Double(H) - (top + blockH - 26) * scale,
                        width: Double(W) - 80 * scale, height: 1 * scale))
    top += blockH
}

guard let image = context.makeImage() else { exit(1) }
let url = URL(fileURLWithPath: CommandLine.arguments[1])
guard let destination = CGImageDestinationCreateWithURL(
    url as CFURL, "public.png" as CFString, 1, nil
) else { exit(1) }
CGImageDestinationAddImage(destination, image, nil)
CGImageDestinationFinalize(destination)
print(url.path)

// Render the launch screen's mark.
//
//     swift Tools/make_launch_mark.swift Astra/Assets.xcassets/LaunchMark.imageset
//
// Swift rather than Python, unlike the icon, for one reason: the wordmark has
// to be real San Francisco at the weight and kerning the onboarding already
// sets, and only the system can draw that. The sun is the same arithmetic as
// `make_icon.py` and the in-app star portraits.
//
// The mark is opaque, painted on Theme.background rather than left
// transparent, and the canvas is sized so the glow has fallen below one step
// of 8-bit colour before it reaches an edge. Both together mean the image's
// rectangle is invisible against the launch screen's background colour, so it
// can sit centred on any device without a seam.

import AppKit
import CoreGraphics
import CoreText
import Foundation

// MARK: - The design

/// Diameter of the disc, in points.
let sunDiameter: Double = 108
/// Bottom of the disc to the cap height of the word.
let gap: Double = 54
let typeSize: Double = 25
/// The resting value the onboarding's title animates out to.
let kerning: Double = 18

let ground: (Double, Double, Double) = (10, 13, 20)          // Theme.background
let starlight = CGColor(red: 0.93, green: 0.94, blue: 0.97, alpha: 1)
let tint: (Double, Double, Double) = (1.00, 0.80, 0.45)      // a ~5,300 K surface

let discRadius = sunDiameter / 2
let coronaRadius = discRadius * (0.40 / 0.235)

/// Where the glow has decayed below half a step of 8-bit colour, so the canvas
/// can be cut there without leaving an edge.
let glowRadius: Double = {
    let faintest = 0.002                       // 1.00 * 255 * 0.002 < 0.51
    let beyond = log(0.50 / faintest) / 2.2
    return discRadius + beyond * (coronaRadius - discRadius)
}()

let capHeight = typeSize * 0.72
let groupHeight = sunDiameter + gap + capHeight
/// The disc's centre, measured down from the top of the group.
let discCentreInGroup = discRadius

/// The canvas is centred on the group, so it has to reach whichever is further
/// from that centre: the top of the glow, or whichever of the glow's bottom and
/// the word's baseline sits lower.
let canvasW = (glowRadius * 2).rounded(.up)
let canvasH: Double = {
    let centre = groupHeight / 2
    let top = discCentreInGroup - glowRadius
    let bottom = max(discCentreInGroup + glowRadius, groupHeight)
    return (max(centre - top, bottom - centre) * 2).rounded(.up)
}()

// MARK: - The same noise the icon is built from

func hash01(_ x: Int, _ y: Int, _ seed: UInt64 = 0x9E37_79B9) -> Double {
    var z = UInt64(bitPattern: Int64(x)) &* 374_761_393
    z = z &+ UInt64(bitPattern: Int64(y)) &* 668_265_263 &+ seed
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    z = z ^ (z >> 31)
    return Double(z >> 11) / Double(1 << 53)
}

func valueNoise(_ x: Double, _ y: Double) -> Double {
    let cx = Int(floor(x)), cy = Int(floor(y))
    let fx = x - floor(x), fy = y - floor(y)
    let ux = fx * fx * (3 - 2 * fx)
    let uy = fy * fy * (3 - 2 * fy)
    let a = hash01(cx, cy), b = hash01(cx + 1, cy)
    let c = hash01(cx, cy + 1), d = hash01(cx + 1, cy + 1)
    let top = a + (b - a) * ux
    let bottom = c + (d - c) * ux
    return top + (bottom - top) * uy
}

func fbm(_ x: Double, _ y: Double) -> Double {
    var total = 0.0, amplitude = 0.5, frequency = 1.0, norm = 0.0
    for _ in 0..<4 {
        total += valueNoise(x * frequency, y * frequency) * amplitude
        norm += amplitude
        amplitude *= 0.5
        frequency *= 2
    }
    return total / norm
}

func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
    let t = max(0, min(1, (x - edge0) / (edge1 - edge0)))
    return t * t * (3 - 2 * t)
}

// MARK: - Render

func render(scale: Double, to path: String) {
    let width = Int(canvasW * scale)
    let height = Int(canvasH * scale)

    guard let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ), let buffer = context.data else { return }

    let pixels = buffer.bindMemory(to: UInt8.self, capacity: width * height * 4)

    let discR = discRadius * scale
    let coronaR = coronaRadius * scale
    let groupTop = (canvasH - groupHeight) / 2 * scale
    let cx = Double(width) / 2
    let cy = groupTop + discCentreInGroup * scale
    let baseline = groupTop + groupHeight * scale

    for y in 0..<height {
        let dy = Double(y) - cy
        for x in 0..<width {
            var (red, green, blue) = ground
            let dx = Double(x) - cx
            let r = (dx * dx + dy * dy).squareRoot()

            // One curve all the way out, and laid down under the disc as well
            // as around it. Split into a corona plus a separate far wash, the
            // two meet at different values and stamp a hard circle; skipped
            // inside the disc, the disc's antialiased edge blends onto bare
            // background instead of onto lit ground and gets outlined.
            let beyond = max(0, (r - discR) / (coronaR - discR))
            let halo = 0.50 * exp(-2.2 * beyond)
            if halo > 0.0008 {
                red = min(255, red + tint.0 * 255 * halo)
                green = min(255, green + tint.1 * 255 * halo)
                blue = min(255, blue + tint.2 * 255 * halo)
            }

            if r < discR {
                let normalised = r / discR
                // Limb darkening: the rim reads dimmer because a sightline
                // there passes through cooler, thinner gas. It's what makes a
                // flat circle look like a sphere.
                let mu = max(0, 1 - normalised * normalised).squareRoot()
                let limb = 0.18 + 0.82 * pow(mu, 0.72)
                // Granulation, sampled on the sphere so cells compress toward
                // the edge the way they actually do. The offsets keep the noise
                // grid off dx=0 and dy=0, where its cell boundaries would
                // stamp a cross through the middle of the disc.
                let spread = 1 / max(mu, 0.52)
                let texture = fbm(
                    dx / discR * 6.0 * spread + 37.31,
                    dy / discR * 6.0 * spread + 18.77
                )
                let lanes = smoothstep(0.52, 0.84, texture)
                let brightness = limb * (0.82 + 0.30 * texture + 0.26 * lanes)
                let blowout = lanes * 0.26 * limb
                let edge = 1 - smoothstep(0.982, 1.0, normalised)

                for channel in 0..<3 {
                    let base = [tint.0, tint.1, tint.2][channel]
                    var value = base * brightness
                    value = value + (1 - value) * blowout
                    let lit = max(0, min(255, value * 255))
                    let prior = [red, green, blue][channel]
                    let blended = prior + (lit - prior) * edge
                    if channel == 0 { red = blended }
                    else if channel == 1 { green = blended }
                    else { blue = blended }
                }
            }

            let offset = (y * width + x) * 4
            pixels[offset] = UInt8(max(0, min(255, red.rounded())))
            pixels[offset + 1] = UInt8(max(0, min(255, green.rounded())))
            pixels[offset + 2] = UInt8(max(0, min(255, blue.rounded())))
            pixels[offset + 3] = 255
        }
    }

    // Drawn at each scale rather than rendered once and resampled, so the
    // glyphs are hinted for the size they actually appear at.
    let font = NSFont.systemFont(ofSize: typeSize * scale, weight: .light)
    let attributed = NSAttributedString(string: "ASTRA", attributes: [
        .font: font,
        .kern: kerning * scale,
        .foregroundColor: NSColor(cgColor: starlight)!,
    ])
    let line = CTLineCreateWithAttributedString(attributed)
    // Kerning is applied after the last letter too, so the run measures that
    // much wider than it looks. Centre on the ink, not on the advance.
    let inked = CTLineGetTypographicBounds(line, nil, nil, nil) - kerning * scale

    context.textPosition = CGPoint(x: (Double(width) - inked) / 2,
                                   y: Double(height) - baseline)
    CTLineDraw(line, context)

    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(
              URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil
          ) else { return }
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
    print("  \(path)  \(width)x\(height)")
}

let directory = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
try? FileManager.default.createDirectory(
    atPath: directory, withIntermediateDirectories: true
)

print("canvas \(Int(canvasW))x\(Int(canvasH))pt")
render(scale: 1, to: "\(directory)/mark.png")
render(scale: 2, to: "\(directory)/mark@2x.png")
render(scale: 3, to: "\(directory)/mark@3x.png")

let contents = """
{
  "images" : [
    { "filename" : "mark.png", "idiom" : "universal", "scale" : "1x" },
    { "filename" : "mark@2x.png", "idiom" : "universal", "scale" : "2x" },
    { "filename" : "mark@3x.png", "idiom" : "universal", "scale" : "3x" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}

"""
try? contents.write(toFile: "\(directory)/Contents.json", atomically: true, encoding: .utf8)

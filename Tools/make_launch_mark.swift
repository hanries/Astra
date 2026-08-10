// Render the launch screen's mark.
//
//     swift Tools/make_launch_mark.swift Astra/Assets.xcassets
//
// Swift rather than Python, unlike the icon, for one reason: the wordmark has
// to be real San Francisco at the weight and kerning the onboarding already
// sets, and only the system can draw that. The sun is the same arithmetic as
// `make_icon.py` and the in-app star portraits.
//
// Two assets rather than one composite, because two surfaces draw this mark:
// the launch screen, which the system shows before any code runs, and the
// opening of onboarding, which has to continue from exactly that still. Onboarding
// then fades the sun out on its own while the word stays put, so the word
// arrives once rather than twice.
//
// Both carry alpha. The launch screen composites them over a flat colour where
// opaque tiles would have done, but onboarding composites them over a starfield,
// where an opaque tile would punch a starless rectangle out of the sky.
//
// The offsets printed at the end are the contract between this file,
// LaunchScreen.storyboard and LaunchMark.swift. Change the design here and all
// three have to move together.

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
/// Breathing room round the word, so antialiasing isn't clipped by the canvas.
let wordPadding: Double = 2

let starlight = CGColor(red: 0.93, green: 0.94, blue: 0.97, alpha: 1)
let tint: (Double, Double, Double) = (1.00, 0.80, 0.45)      // a ~5,300 K surface

let discRadius = sunDiameter / 2
let coronaRadius = discRadius * (0.40 / 0.235)

/// Where the glow has decayed below half a step of 8-bit colour, so the canvas
/// can be cut there without leaving an edge.
let glowRadius: Double = {
    let faintest = 0.002
    return discRadius + (log(0.50 / faintest) / 2.2) * (coronaRadius - discRadius)
}()

let capHeight = Double(NSFont.systemFont(ofSize: CGFloat(typeSize), weight: .light).capHeight)
let groupHeight = sunDiameter + gap + capHeight

/// Distance from the centre of the whole lockup to the centre of each asset.
/// Positive is down the screen.
let sunOffset = -groupHeight / 2 + discRadius
let wordOffset = groupHeight / 2 - capHeight / 2

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

// MARK: - Writing

func write(_ image: CGImage, to path: String) {
    guard let destination = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil
    ) else { return }
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
    print("  \(path)  \(image.width)x\(image.height)")
}

func imageset(_ name: String, in root: String, render: (Double, String) -> Void) {
    let directory = "\(root)/\(name).imageset"
    try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    render(1, "\(directory)/\(name.lowercased()).png")
    render(2, "\(directory)/\(name.lowercased())@2x.png")
    render(3, "\(directory)/\(name.lowercased())@3x.png")
    let contents = """
    {
      "images" : [
        { "filename" : "\(name.lowercased()).png", "idiom" : "universal", "scale" : "1x" },
        { "filename" : "\(name.lowercased())@2x.png", "idiom" : "universal", "scale" : "2x" },
        { "filename" : "\(name.lowercased())@3x.png", "idiom" : "universal", "scale" : "3x" }
      ],
      "info" : { "author" : "xcode", "version" : 1 }
    }

    """
    try? contents.write(toFile: "\(directory)/Contents.json", atomically: true, encoding: .utf8)
}

// MARK: - The sun

func renderSun(scale: Double, to path: String) {
    let side = Int((glowRadius * 2).rounded(.up) * scale)
    guard let context = CGContext(
        data: nil, width: side, height: side, bitsPerComponent: 8,
        bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ), let buffer = context.data else { return }

    let pixels = buffer.bindMemory(to: UInt8.self, capacity: side * side * 4)
    let discR = discRadius * scale
    let coronaR = coronaRadius * scale
    let centre = Double(side) / 2

    for y in 0..<side {
        let dy = Double(y) - centre
        for x in 0..<side {
            let dx = Double(x) - centre
            let r = (dx * dx + dy * dy).squareRoot()

            // Glow as emission: one curve all the way out, measured from the
            // disc's edge and clamped at the rim so it runs under the disc as
            // well as around it. Split into a corona plus a separate far wash,
            // the two meet at different values and stamp a hard circle.
            let beyond = max(0, (r - discR) / (coronaR - discR))
            let glowAlpha = 0.50 * exp(-2.2 * beyond)
            var (red, green, blue) = (tint.0 * 255, tint.1 * 255, tint.2 * 255)
            var alpha = glowAlpha

            if r < discR {
                let normalised = r / discR
                // Limb darkening: the rim reads dimmer because a sightline
                // there passes through cooler, thinner gas. It's what makes a
                // flat circle look like a sphere.
                let mu = max(0, 1 - normalised * normalised).squareRoot()
                let limb = 0.18 + 0.82 * pow(mu, 0.72)
                // Granulation, sampled on the sphere so cells compress toward
                // the edge the way they actually do. The offsets keep the noise
                // grid off dx=0 and dy=0, where its cell boundaries would stamp
                // a cross through the middle of the disc.
                let spread = 1 / max(mu, 0.52)
                let texture = fbm(dx / discR * 6.0 * spread + 37.31,
                                  dy / discR * 6.0 * spread + 18.77)
                let lanes = smoothstep(0.52, 0.84, texture)
                let brightness = limb * (0.82 + 0.30 * texture + 0.26 * lanes)
                let blowout = lanes * 0.26 * limb
                let discAlpha = 1 - smoothstep(0.982, 1.0, normalised)

                var disc = (0.0, 0.0, 0.0)
                for channel in 0..<3 {
                    let base = [tint.0, tint.1, tint.2][channel]
                    var value = base * brightness
                    value = value + (1 - value) * blowout
                    let lit = max(0, min(255, value * 255))
                    if channel == 0 { disc.0 = lit } else if channel == 1 { disc.1 = lit }
                    else { disc.2 = lit }
                }

                // The disc over the glow, both straight alpha.
                let out = discAlpha + glowAlpha * (1 - discAlpha)
                if out > 0 {
                    let carry = glowAlpha * (1 - discAlpha)
                    red = (disc.0 * discAlpha + red * carry) / out
                    green = (disc.1 * discAlpha + green * carry) / out
                    blue = (disc.2 * discAlpha + blue * carry) / out
                    alpha = out
                }
            }

            let offset = (y * side + x) * 4
            pixels[offset] = UInt8(max(0, min(255, (red * alpha).rounded())))
            pixels[offset + 1] = UInt8(max(0, min(255, (green * alpha).rounded())))
            pixels[offset + 2] = UInt8(max(0, min(255, (blue * alpha).rounded())))
            pixels[offset + 3] = UInt8(max(0, min(255, (alpha * 255).rounded())))
        }
    }

    guard let image = context.makeImage() else { return }
    write(image, to: path)
}

// MARK: - The word

/// Measured once so the canvas, the storyboard and onboarding agree.
func wordInk() -> Double {
    let font = NSFont.systemFont(ofSize: CGFloat(typeSize), weight: .light)
    let attributed = NSAttributedString(string: "ASTRA", attributes: [
        .font: font, .kern: kerning,
    ])
    // Kerning is applied after the last letter too, so the run measures that
    // much wider than it looks.
    return CTLineGetTypographicBounds(
        CTLineCreateWithAttributedString(attributed), nil, nil, nil
    ) - kerning
}

func renderWord(scale: Double, to path: String) {
    let width = Int(((wordInk() + wordPadding * 2).rounded(.up)) * scale)
    let height = Int(((capHeight + wordPadding * 2).rounded(.up)) * scale)

    guard let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return }

    // Drawn at each scale rather than rendered once and resampled, so the
    // glyphs are hinted for the size they actually appear at.
    let font = NSFont.systemFont(ofSize: CGFloat(typeSize * scale), weight: .light)
    let attributed = NSAttributedString(string: "ASTRA", attributes: [
        .font: font,
        .kern: kerning * scale,
        .foregroundColor: NSColor(cgColor: starlight)!,
    ])
    let line = CTLineCreateWithAttributedString(attributed)
    let inked = CTLineGetTypographicBounds(line, nil, nil, nil) - kerning * scale

    context.textPosition = CGPoint(x: (Double(width) - inked) / 2,
                                   y: wordPadding * scale)
    CTLineDraw(line, context)

    guard let image = context.makeImage() else { return }
    write(image, to: path)
}

// MARK: - The composite

/// Sun and word together, opaque, on the launch background.
///
/// The launch screen draws this one rather than the two pieces: an image view
/// in a launch storyboard will not render an asset that carries alpha. It lays
/// out and sizes correctly and then draws nothing, which is a difficult failure
/// to read, so the launch screen gets a flattened copy and only onboarding uses
/// the pieces.
///
/// Cut where the glow has fallen below one step of 8-bit colour, so its
/// rectangle is invisible against the same background colour behind it.
func renderComposite(scale: Double, to path: String) {
    let width = Int((glowRadius * 2).rounded(.up) * scale)
    let height: Int = {
        let centre = groupHeight / 2
        let top = discRadius - glowRadius
        let bottom = max(discRadius + glowRadius, groupHeight)
        return Int((max(centre - top, bottom - centre) * 2).rounded(.up) * scale)
    }()

    guard let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ), let buffer = context.data else { return }

    let pixels = buffer.bindMemory(to: UInt8.self, capacity: width * height * 4)
    let discR = discRadius * scale
    let coronaR = coronaRadius * scale
    let groupTop = (Double(height) / scale - groupHeight) / 2 * scale
    let cx = Double(width) / 2
    let cy = groupTop + discRadius * scale

    for y in 0..<height {
        let dy = Double(y) - cy
        for x in 0..<width {
            let dx = Double(x) - cx
            let r = (dx * dx + dy * dy).squareRoot()
            var (red, green, blue) = (10.0, 13.0, 20.0)          // Theme.background

            let beyond = max(0, (r - discR) / (coronaR - discR))
            let halo = 0.50 * exp(-2.2 * beyond)
            if halo > 0.0008 {
                red = min(255, red + tint.0 * 255 * halo)
                green = min(255, green + tint.1 * 255 * halo)
                blue = min(255, blue + tint.2 * 255 * halo)
            }

            if r < discR {
                let normalised = r / discR
                let mu = max(0, 1 - normalised * normalised).squareRoot()
                let limb = 0.18 + 0.82 * pow(mu, 0.72)
                let spread = 1 / max(mu, 0.52)
                let texture = fbm(dx / discR * 6.0 * spread + 37.31,
                                  dy / discR * 6.0 * spread + 18.77)
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

    let font = NSFont.systemFont(ofSize: CGFloat(typeSize * scale), weight: .light)
    let attributed = NSAttributedString(string: "ASTRA", attributes: [
        .font: font, .kern: kerning * scale,
        .foregroundColor: NSColor(cgColor: starlight)!,
    ])
    let line = CTLineCreateWithAttributedString(attributed)
    let inked = CTLineGetTypographicBounds(line, nil, nil, nil) - kerning * scale
    context.textPosition = CGPoint(x: (Double(width) - inked) / 2,
                                   y: Double(height) - (groupTop + groupHeight * scale))
    CTLineDraw(line, context)

    guard let image = context.makeImage() else { return }
    write(image, to: path)
}

// MARK: - Go

let root = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
imageset("LaunchMark", in: root) { renderComposite(scale: $0, to: $1) }
imageset("LaunchSun", in: root) { renderSun(scale: $0, to: $1) }
imageset("LaunchWord", in: root) { renderWord(scale: $0, to: $1) }

print("""

cap height   \(String(format: "%.2f", capHeight))pt
lockup       \(String(format: "%.2f", groupHeight))pt tall
sun offset   \(String(format: "%.2f", sunOffset))pt from the lockup's centre
word offset  \(String(format: "%+.2f", wordOffset))pt from the lockup's centre
""")

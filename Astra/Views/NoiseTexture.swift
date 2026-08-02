import CoreGraphics
import Foundation

/// Draws a star's face, pixel by pixel, from its measured properties.
///
/// This is the app's whole answer to "where do the pictures come from": it
/// makes them. Colour comes from the catalogued B−V index, granule size from
/// the temperature that index implies, and limb darkening from the geometry of
/// looking through a ball of gas. No image ships in the bundle, and two stars
/// differ because they *are* different.
///
/// Composited here rather than by stacking SwiftUI blend modes, which is how
/// this started and which produced a grey ball — `.overlay` and `.multiply`
/// against an already-tinted backdrop desaturate toward the middle instead of
/// letting the star's colour through.
enum StarImage {

    private static let cache = Cache()

    /// The star's disc, on a transparent square. Cached per appearance.
    ///
    /// - Parameters:
    ///   - rgb: the star's colour, 0...1 per channel.
    ///   - coarseness: 0 for a fine hot surface, 1 for huge cool convection cells.
    ///   - seed: keeps a star looking like itself between launches.
    static func disc(
        rgb: (Double, Double, Double),
        coarseness: Double,
        seed: UInt64,
        resolution: Int = 256
    ) -> CGImage? {
        let key = Key(
            // Bucketed so near-identical stars share one render.
            red: Int(rgb.0 * 32), green: Int(rgb.1 * 32), blue: Int(rgb.2 * 32),
            coarseness: Int(coarseness * 16),
            seed: seed % 512,
            resolution: resolution
        )
        if let hit = cache.value(for: key) { return hit }
        let made = render(rgb: rgb, coarseness: coarseness, seed: seed, resolution: resolution)
        if let made { cache.store(made, for: key) }
        return made
    }

    // MARK: - Rendering

    private static func render(
        rgb: (Double, Double, Double),
        coarseness: Double,
        seed: UInt64,
        resolution: Int
    ) -> CGImage? {
        // Cool stars have deep convection zones and correspondingly enormous
        // granules; hot stars have radiative envelopes and fine even surfaces.
        let cells = 3.5 + (1 - coarseness) * 22

        var pixels = [UInt8](repeating: 0, count: resolution * resolution * 4)
        let centre = Double(resolution) / 2

        for y in 0..<resolution {
            for x in 0..<resolution {
                let dx = (Double(x) - centre) / centre
                let dy = (Double(y) - centre) / centre
                let r = (dx * dx + dy * dy).squareRoot()
                let offset = (y * resolution + x) * 4

                guard r <= 1 else { continue }   // Already transparent.

                // Limb darkening. A star has no surface, so a sightline near
                // the rim passes through cooler, thinner gas and reads dimmer.
                // This is the whole reason a star looks spherical.
                let mu = max(0, 1 - r * r).squareRoot()
                let limb = 0.26 + 0.74 * pow(mu, 0.58)

                // Granulation, sampled on the sphere rather than the flat disc
                // so cells compress toward the edge as they actually do.
                let sphereScale = 1 / max(mu, 0.30)
                let texture = fbm(
                    x: dx * cells * sphereScale + Double(seed % 97),
                    y: dy * cells * sphereScale + Double(seed % 89)
                )
                // Bright lanes where hot material rises between cells.
                let lanes = smoothstep(0.50, 0.80, texture)
                let brightness = limb * (0.66 + 0.52 * texture + 0.42 * lanes)

                // Hottest patches blow out toward white, as they do in any
                // photograph of something this bright.
                let blowout = lanes * 0.34 * limb
                func channel(_ base: Double) -> UInt8 {
                    let value = base * brightness + (1 - base * brightness) * blowout
                    return UInt8(max(0, min(255, value * 255)))
                }

                // Feather the rim so the disc doesn't alias against the sky.
                let edge = 1 - smoothstep(0.975, 1.0, r)

                pixels[offset]     = channel(rgb.0)
                pixels[offset + 1] = channel(rgb.1)
                pixels[offset + 2] = channel(rgb.2)
                pixels[offset + 3] = UInt8(max(0, min(255, edge * 255)))
            }
        }

        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: resolution,
            height: resolution,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: resolution * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    // MARK: - Noise

    /// Layered value noise. Four octaves gives cells with structure inside them.
    private static func fbm(x: Double, y: Double) -> Double {
        var total = 0.0
        var amplitude = 0.5
        var fx = x, fy = y
        for _ in 0..<4 {
            total += valueNoise(x: fx, y: fy) * amplitude
            fx *= 2.03           // Not exactly 2, so octaves don't align.
            fy *= 2.03
            amplitude *= 0.5
        }
        return total
    }

    private static func valueNoise(x: Double, y: Double) -> Double {
        let cellX = floor(x), cellY = floor(y)
        let fx = x - cellX, fy = y - cellY
        // Smoothstep the interpolation so cells don't read as a grid.
        let ux = fx * fx * (3 - 2 * fx)
        let uy = fy * fy * (3 - 2 * fy)

        let a = hash(Int(cellX), Int(cellY))
        let b = hash(Int(cellX) + 1, Int(cellY))
        let c = hash(Int(cellX), Int(cellY) + 1)
        let d = hash(Int(cellX) + 1, Int(cellY) + 1)

        let top = a + (b - a) * ux
        let bottom = c + (d - c) * ux
        return top + (bottom - top) * uy
    }

    /// Splitmix64 finalizer — mixes far better than the usual `sin(dot(...))`
    /// trick, which bands visibly across a large smooth surface.
    private static func hash(_ x: Int, _ y: Int) -> Double {
        var z = UInt64(bitPattern: Int64(x &* 374_761_393)) &+ 0x9E37_79B9_7F4A_7C15
        z ^= UInt64(bitPattern: Int64(y &* 668_265_263))
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z = z ^ (z >> 31)
        return Double(z >> 11) / Double(UInt64(1) << 53)
    }

    private static func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        let t = max(0, min(1, (x - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }

    // MARK: - Cache

    private struct Key: Hashable {
        let red: Int, green: Int, blue: Int
        let coarseness: Int
        let seed: UInt64
        let resolution: Int
    }

    /// A few hundred kilobytes each, and only so many distinct appearances, so
    /// a small locked dictionary is enough.
    private final class Cache: @unchecked Sendable {
        private var storage: [Key: CGImage] = [:]
        private let lock = NSLock()

        func value(for key: Key) -> CGImage? {
            lock.lock(); defer { lock.unlock() }
            return storage[key]
        }

        func store(_ image: CGImage, for key: Key) {
            lock.lock(); defer { lock.unlock() }
            if storage.count > 32 { storage.removeAll() }
            storage[key] = image
        }
    }
}

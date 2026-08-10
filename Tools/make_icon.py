#!/usr/bin/env python3
"""Render Astra's app icon.

    python3 Tools/make_icon.py Astra/Assets.xcassets/AppIcon.appiconset/icon-1024.png

Same construction as the stars inside the app: a disc lit by limb darkening,
with convection granulation laid over it, and a colour taken from a real
spectral class. Nothing here is drawn by hand, which is the point. The icon and
the thing it stands for come out of the same arithmetic.

Composition is a single disc rather than a constellation. A four-star figure
with its joining lines looks better at 1024 and disappears at 60, where a home
screen actually renders it: the lines fall below a pixel and the fainter stars
vanish. One bright object survives any size.

Written as a PNG by hand because the machine has no imaging library, and adding
one for a single 1024x1024 file isn't worth the dependency.
"""

import math
import struct
import sys
import zlib

SIZE = 1024

# Ground. Not pure black: the same faint blue the app's background carries, so
# the icon sits in the same world as the screen behind it.
GROUND = (0x07, 0x09, 0x0E)

# A warm G-type surface, the colour the app gives a star of about 5,300 K.
# Gold on near-black stays legible at small sizes and stands apart on a home
# screen full of bright, saturated squares.
TINT = (1.00, 0.80, 0.45)

# Kept small on purpose. A disc that fills the frame has no darkness around it,
# and at the size a home screen actually draws this it stops being a star in a
# sky and becomes a beige square. The black margin is doing as much work as the
# star is.
DISC_RADIUS = 0.235        # Fraction of the icon's width.
CORONA_RADIUS = 0.40
GRANULE_CELLS = 6.0        # Coarse enough to still read once scaled down.
FIELD_STARS = 110


def hash01(x: int, y: int, seed: int = 0x9E3779B9) -> float:
    """Deterministic 0..1 hash. Splitmix-style finalizer."""
    z = (x * 374_761_393 + y * 668_265_263 + seed) & 0xFFFFFFFFFFFFFFFF
    z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & 0xFFFFFFFFFFFFFFFF
    z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & 0xFFFFFFFFFFFFFFFF
    z = z ^ (z >> 31)
    return (z >> 11) / float(1 << 53)


def value_noise(x: float, y: float) -> float:
    cx, cy = math.floor(x), math.floor(y)
    fx, fy = x - cx, y - cy
    ux = fx * fx * (3 - 2 * fx)
    uy = fy * fy * (3 - 2 * fy)
    a = hash01(cx, cy)
    b = hash01(cx + 1, cy)
    c = hash01(cx, cy + 1)
    d = hash01(cx + 1, cy + 1)
    return (a + (b - a) * ux) + ((c + (d - c) * ux) - (a + (b - a) * ux)) * uy


def fbm(x: float, y: float, octaves: int = 4) -> float:
    total, amplitude = 0.0, 0.5
    for _ in range(octaves):
        total += value_noise(x, y) * amplitude
        x, y = x * 2.03, y * 2.03
        amplitude *= 0.5
    return total


def smoothstep(edge0: float, edge1: float, x: float) -> float:
    t = max(0.0, min(1.0, (x - edge0) / (edge1 - edge0)))
    return t * t * (3 - 2 * t)


def render() -> bytearray:
    centre = SIZE / 2
    disc_r = SIZE * DISC_RADIUS
    corona_r = SIZE * CORONA_RADIUS

    # Background field, placed before the disc so the glow washes over it.
    field = {}
    for index in range(FIELD_STARS):
        fx = hash01(index, 11) * SIZE
        fy = hash01(index, 29) * SIZE
        if math.hypot(fx - centre, fy - centre) < corona_r * 0.92:
            continue
        field[(int(fx), int(fy))] = 0.25 + hash01(index, 47) * 0.5

    rows = bytearray()
    for y in range(SIZE):
        rows.append(0)                       # PNG filter: none
        row = bytearray()
        for x in range(SIZE):
            dx, dy = x - centre, y - centre
            r = math.hypot(dx, dy)

            red, green, blue = GROUND

            if (x, y) in field:
                level = field[(x, y)]
                red = int(red + (210 - red) * level)
                green = int(green + (215 - green) * level)
                blue = int(blue + (235 - blue) * level)

            # Corona, measured out from the disc's edge rather than from the
            # centre. Measured from the centre it has already decayed to
            # almost nothing by the time it clears the disc, which leaves a
            # hard-edged ball that reads as a moon instead of a star.
            #
            # One curve all the way out, rather than a corona plus a separate
            # far wash. Split in two they meet at CORONA_RADIUS at different
            # values -- the inner one has reached zero, the outer one starts at
            # 0.055 -- and that step draws a hard circle around the star,
            # visible at the size the App Store renders this. The exponential
            # passes through 0.055 where the old wash began, so the glow keeps
            # its reach without the seam.
            #
            # Applied inside the disc too. `beyond` clamps at the rim, so the
            # disc's antialiased edge blends down onto lit ground instead of
            # onto bare background, which would outline it.
            beyond = max(0.0, (r - disc_r) / (corona_r - disc_r))
            halo = 0.50 * math.exp(-2.2 * beyond)
            if halo > 0.0008:
                red = min(255, int(red + TINT[0] * 255 * halo))
                green = min(255, int(green + TINT[1] * 255 * halo))
                blue = min(255, int(blue + TINT[2] * 255 * halo))

            if r < disc_r:
                normalised = r / disc_r
                # Limb darkening: the rim reads dimmer because a sightline
                # there passes through cooler, thinner gas. It's what makes a
                # flat circle look like a sphere.
                mu = math.sqrt(max(0.0, 1 - normalised * normalised))
                limb = 0.18 + 0.82 * (mu ** 0.72)

                # Granulation, sampled on the sphere so cells compress toward
                # the edge the way they actually do. The offsets matter: with
                # the sample grid aligned to the centre, the noise cell
                # boundaries land exactly on dx=0 and dy=0 and stamp a cross
                # through the middle of the disc.
                # Clamped well above zero. Left near the true value the sphere
                # projection compresses the noise so hard at the rim that the
                # cells break into visible blocks.
                spread = 1 / max(mu, 0.52)
                texture = fbm(
                    dx / disc_r * GRANULE_CELLS * spread + 37.31,
                    dy / disc_r * GRANULE_CELLS * spread + 18.77,
                )
                lanes = smoothstep(0.52, 0.84, texture)
                # Lower contrast than the in-app portraits. At icon scale the
                # deep granulation reads as cratering rather than as light.
                brightness = limb * (0.82 + 0.30 * texture + 0.26 * lanes)
                blowout = lanes * 0.26 * limb

                edge = 1 - smoothstep(0.982, 1.0, normalised)
                for channel, base in enumerate(TINT):
                    value = base * brightness
                    value = value + (1 - value) * blowout
                    lit = int(max(0, min(255, value * 255)))
                    prior = (red, green, blue)[channel]
                    blended = int(prior + (lit - prior) * edge)
                    if channel == 0:
                        red = blended
                    elif channel == 1:
                        green = blended
                    else:
                        blue = blended

            row += bytes((red, green, blue))
        rows += row
    return rows


def write_png(path: str, pixels: bytearray) -> None:
    def chunk(kind: bytes, payload: bytes) -> bytes:
        body = kind + payload
        return struct.pack(">I", len(payload)) + body + struct.pack(">I", zlib.crc32(body))

    # Colour type 2 is truecolour with no alpha. App icons must be fully
    # opaque, so there is no alpha channel to get wrong.
    header = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)
    with open(path, "wb") as handle:
        handle.write(b"\x89PNG\r\n\x1a\n")
        handle.write(chunk(b"IHDR", header))
        handle.write(chunk(b"IDAT", zlib.compress(bytes(pixels), 9)))
        handle.write(chunk(b"IEND", b""))


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit(f"usage: {sys.argv[0]} <out.png>")
    write_png(sys.argv[1], render())
    print(f"wrote {sys.argv[1]} at {SIZE}x{SIZE}")


if __name__ == "__main__":
    main()

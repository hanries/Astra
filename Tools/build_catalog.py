#!/usr/bin/env python3
"""Turn the Yale Bright Star Catalogue into the JSON Astra ships.

    curl -O http://tdc-www.harvard.edu/catalogs/bsc5.dat.gz
    gunzip bsc5.dat.gz
    python3 Tools/build_catalog.py bsc5.dat Astra/Sky/Resources/stars.json

Source: Bright Star Catalogue, 5th Revised Edition (Hoffleit & Warren, 1991),
distributed by the Harvard-Smithsonian Center for Astrophysics. Institutional
astronomical data, free to use with citation — deliberately not the HYG
database, which is CC-BY-SA and whose ShareAlike term would follow a bundled
derivative into the app.

Committed so the JSON can be regenerated rather than trusted.
"""

import json
import sys

# Byte offsets are 1-based in the catalogue's own documentation; these are the
# 0-based Python slices, verified against stars whose values are independently
# known (Sirius -1.46, Rigel B-V -0.03, Polaris dec +89 15 51).
HR = slice(0, 4)
BAYER = slice(7, 10)
SUPERSCRIPT = slice(10, 11)
CONSTELLATION = slice(11, 14)
RA_H, RA_M, RA_S = slice(75, 77), slice(77, 79), slice(79, 83)
DEC_SIGN, DEC_D, DEC_M, DEC_S = slice(83, 84), slice(84, 86), slice(86, 88), slice(88, 90)
VMAG = slice(102, 107)
BV = slice(109, 114)
SPECTRAL = slice(127, 147)
PARALLAX = slice(161, 166)

# Below this the catalogue's ground-based parallaxes stop meaning anything.
#
# Calibrated against modern Hipparcos/Gaia distances for 29 bright stars: above
# 0.067" every one lands within 13%, and below it the error becomes a coin flip
# — Canopus off by -62%, Antares -75%, Rigel -71% (BSC5 says 251 ly against a
# modern 860), while two entries at 0.061" and 0.057" are already -44%.
#
# 0.070" is that boundary with a little margin, and it means distance is only
# offered inside about 47 light-years. That excludes nearly every famous star,
# which is a real gap — but a star with no distance still has a colour, a
# brightness, and a spectral class to say something true about, and a wrong
# number is worse than a missing one.
MIN_RELIABLE_PARALLAX = 0.070

# A star earns a place if it could appear in a constellation figure (it has a
# Bayer letter) or is bright enough to pick out unaided from a city.
MAX_MAGNITUDE_WITHOUT_BAYER = 4.0

PARSECS_TO_LIGHT_YEARS = 3.26156

# IAU-approved proper names, keyed by Bayer designation. The catalogue carries
# only designations; "Vega" is not in it.
PROPER_NAMES = {
    "Alp CMa": "Sirius",       "Alp Car": "Canopus",      "Alp Boo": "Arcturus",
    "Alp Lyr": "Vega",         "Alp Aur": "Capella",      "Bet Ori": "Rigel",
    "Alp CMi": "Procyon",      "Alp Ori": "Betelgeuse",   "Alp Eri": "Achernar",
    "Bet Cen": "Hadar",        "Alp Aql": "Altair",       "Alp Cru": "Acrux",
    "Alp Tau": "Aldebaran",    "Alp Sco": "Antares",      "Alp Vir": "Spica",
    "Bet Gem": "Pollux",       "Alp PsA": "Fomalhaut",    "Alp Cyg": "Deneb",
    "Bet Cru": "Mimosa",       "Alp Leo": "Regulus",      "Eps CMa": "Adhara",
    "Alp Gem": "Castor",       "Gam Cru": "Gacrux",       "Lam Sco": "Shaula",
    "Gam Ori": "Bellatrix",    "Bet Tau": "Elnath",       "Bet Car": "Miaplacidus",
    "Eps Ori": "Alnilam",      "Alp Gru": "Alnair",       "Zet Ori": "Alnitak",
    "Eps UMa": "Alioth",       "Alp UMa": "Dubhe",        "Alp Per": "Mirfak",
    "Del CMa": "Wezen",        "The Sco": "Sargas",       "Eps Sgr": "Kaus Australis",
    "Eps Car": "Avior",        "Eta UMa": "Alkaid",       "Bet Aur": "Menkalinan",
    "Alp TrA": "Atria",        "Gam Gem": "Alhena",       "Alp Pav": "Peacock",
    "Del Vel": "Alsephina",    "Bet CMa": "Mirzam",       "Alp Hya": "Alphard",
    "Alp UMi": "Polaris",      "Alp Ari": "Hamal",        "Gam Leo": "Algieba",
    "Bet Cet": "Diphda",       "Zet UMa": "Mizar",        "Sig Sgr": "Nunki",
    "The Cen": "Menkent",      "Bet And": "Mirach",       "Alp And": "Alpheratz",
    "Alp Oph": "Rasalhague",   "Bet UMi": "Kochab",       "Kap Ori": "Saiph",
    "Bet Leo": "Denebola",     "Bet Per": "Algol",        "Gam Cen": "Muhlifain",
    "Iot Car": "Aspidiske",    "Lam Vel": "Suhail",       "Alp CrB": "Alphecca",
    "Del Ori": "Mintaka",      "Gam Cyg": "Sadr",         "Gam Dra": "Eltanin",
    "Alp Cas": "Schedar",      "Zet Pup": "Naos",         "Gam And": "Almach",
    "Bet Cas": "Caph",         "Eps Boo": "Izar",         "Del Sco": "Dschubba",
    "Eps Sco": "Larawag",      "Bet UMa": "Merak",        "Alp Phe": "Ankaa",
    "Eps Peg": "Enif",         "Bet Peg": "Scheat",       "Eta Oph": "Sabik",
    "Gam UMa": "Phecda",       "Eta CMa": "Aludra",       "Alp Peg": "Markab",
    "Eps Cyg": "Aljanah",      "Bet Sco": "Acrab",        "Alp Cep": "Alderamin",
    "Gam Cas": "Navi",         "Alp Lup": "Kakkab",       "Bet Eri": "Cursa",
}

SUPERSCRIPT_DIGITS = {"1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵"}

GREEK = {
    "Alp": "Alpha",   "Bet": "Beta",    "Gam": "Gamma",   "Del": "Delta",
    "Eps": "Epsilon", "Zet": "Zeta",    "Eta": "Eta",     "The": "Theta",
    "Iot": "Iota",    "Kap": "Kappa",   "Lam": "Lambda",  "Mu ": "Mu",
    "Nu ": "Nu",      "Xi ": "Xi",      "Omi": "Omicron", "Pi ": "Pi",
    "Rho": "Rho",     "Sig": "Sigma",   "Tau": "Tau",     "Ups": "Upsilon",
    "Phi": "Phi",     "Chi": "Chi",     "Psi": "Psi",     "Ome": "Omega",
}


def parse_float(text):
    text = text.strip()
    if not text:
        return None
    try:
        return float(text)
    except ValueError:
        return None


def parse_star(line):
    hr = line[HR].strip()
    if not hr:
        return None

    magnitude = parse_float(line[VMAG])
    bayer = line[BAYER].strip()
    constellation = line[CONSTELLATION].strip()
    if magnitude is None or not constellation:
        return None
    if not bayer and magnitude > MAX_MAGNITUDE_WITHOUT_BAYER:
        return None

    ra_h, ra_m, ra_s = (parse_float(line[s]) for s in (RA_H, RA_M, RA_S))
    dec_d, dec_m, dec_s = (parse_float(line[s]) for s in (DEC_D, DEC_M, DEC_S))
    if None in (ra_h, ra_m, ra_s, dec_d, dec_m, dec_s):
        return None

    right_ascension = (ra_h + ra_m / 60 + ra_s / 3600) * 15
    declination = dec_d + dec_m / 60 + dec_s / 3600
    if line[DEC_SIGN] == "-":
        declination = -declination

    designation = f"{bayer} {constellation}" if bayer else ""
    superscript = line[SUPERSCRIPT].strip()

    star = {
        "hr": int(hr),
        "constellation": constellation,
        "ra": round(right_ascension, 5),
        "dec": round(declination, 5),
        "magnitude": round(magnitude, 2),
    }

    if bayer:
        greek = GREEK.get(bayer, bayer)
        # Bayer superscripts mark the components of a naked-eye pair — Acrux is
        # Alpha¹ and Alpha² Crucis — and belong on the letter, not trailing the
        # constellation.
        greek += SUPERSCRIPT_DIGITS.get(superscript, "")
        star["bayer"] = f"{greek} {constellation}"
    if designation in PROPER_NAMES:
        star["name"] = PROPER_NAMES[designation]

    colour = parse_float(line[BV])
    if colour is not None:
        star["bv"] = round(colour, 2)

    spectral = line[SPECTRAL].strip()
    if spectral:
        star["spectral"] = spectral

    parallax = parse_float(line[PARALLAX])
    if parallax is not None and parallax >= MIN_RELIABLE_PARALLAX:
        star["ly"] = round(PARSECS_TO_LIGHT_YEARS / parallax, 1)

    return star


def main():
    if len(sys.argv) != 3:
        sys.exit(f"usage: {sys.argv[0]} <bsc5.dat> <out.json>")

    source, destination = sys.argv[1], sys.argv[2]
    with open(source, encoding="latin-1") as handle:
        stars = [s for s in (parse_star(line) for line in handle) if s]

    stars.sort(key=lambda s: s["magnitude"])

    payload = {
        "source": "Yale Bright Star Catalogue, 5th Revised Ed. (Hoffleit & Warren, 1991)",
        "stars": stars,
    }
    with open(destination, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, separators=(",", ":"), ensure_ascii=False)

    named = sum(1 for s in stars if "name" in s)
    with_distance = sum(1 for s in stars if "ly" in s)
    constellations = len({s["constellation"] for s in stars})
    print(f"{len(stars)} stars across {constellations} constellations")
    print(f"  {named} with proper names")
    print(f"  {with_distance} with a distance we trust")


if __name__ == "__main__":
    main()

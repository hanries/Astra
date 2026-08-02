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

# Constellation figures, as edges between Bayer designations.
#
# Written as designations rather than HR numbers on purpose: "Orion's belt joins
# Zeta, Epsilon and Delta Ori" is a checkable claim, while a list of catalogue
# numbers is a list of things to mistype. The build resolves them against the
# catalogue and reports anything that doesn't land.
#
# Figures are a drawing convention rather than catalogue data — these are the
# common Western forms written out here, not copied from Stellarium, whose set
# is GPL. An edge may name a star in another constellation: Pegasus' Great
# Square borrows Alpha Andromedae, as the sky actually has it.
FIGURES = {
    "UMa": [("Eta","Zet"),("Zet","Eps"),("Eps","Del"),("Del","Gam"),
            ("Gam","Bet"),("Bet","Alp"),("Alp","Del")],
    "UMi": [("Alp","Del"),("Del","Eps"),("Eps","Zet"),("Zet","Bet"),
            ("Bet","Gam"),("Gam","Eta"),("Eta","Zet")],
    "Ori": [("Alp","Gam"),("Alp","Zet"),("Gam","Del"),("Zet","Eps"),
            ("Eps","Del"),("Zet","Kap"),("Del","Bet")],
    "Cas": [("Bet","Alp"),("Alp","Gam"),("Gam","Del"),("Del","Eps")],
    "Cyg": [("Alp","Gam"),("Gam","Eta"),("Eta","Bet"),("Gam","Del"),("Gam","Eps")],
    "Lyr": [("Alp","Zet"),("Zet","Del"),("Del","Gam"),("Gam","Bet"),("Bet","Zet")],
    "Cru": [("Alp","Gam"),("Bet","Del")],
    "Leo": [("Eps","Mu "),("Mu ","Zet"),("Zet","Gam"),("Gam","Eta"),("Eta","Alp"),
            ("Alp","The"),("The","Bet"),("The","Del"),("Del","Gam")],
    "Boo": [("Alp","Eps"),("Eps","Del"),("Del","Bet"),("Bet","Gam"),("Gam","Alp")],
    "Gem": [("Alp","Tau"),("Tau","Eps"),("Eps","Nu "),("Bet","Del"),
            ("Del","Zet"),("Zet","Gam"),("Tau","Del")],
    "Tau": [("Alp","The"),("The","Gam"),("Gam","Del"),("Del","Eps"),
            ("Eps","Alp"),("Alp","Bet"),("Gam","Lam")],
    "CMa": [("Alp","Bet"),("Alp","Del"),("Del","Eta"),("Del","Eps"),
            ("Eps","Sig"),("Sig","Alp")],
    "Aql": [("Alp","Bet"),("Alp","Gam"),("Gam","Del"),("Del","Eta"),("Del","The")],
    "Sco": [("Bet","Del"),("Del","Sig"),("Sig","Alp"),("Alp","Tau"),("Tau","Eps"),
            ("Eps","Mu "),("Mu ","Zet"),("Zet","Eta"),("Eta","The"),("The","Iot"),
            ("Iot","Kap"),("Kap","Lam"),("Lam","Ups")],
    "Peg": [("Alp","Bet"),("Bet","Gam"),("Gam","Alp And"),("Alp And","Alp"),
            ("Bet","Eta"),("Alp","The"),("The","Eps")],
    "And": [("Alp","Del"),("Del","Bet"),("Bet","Gam")],
    "Per": [("Alp","Gam"),("Gam","Eta"),("Alp","Del"),("Del","Eps"),
            ("Eps","Zet"),("Alp","Bet"),("Bet","Rho")],
    "Aur": [("Alp","Bet"),("Bet","The"),("The","Iot"),("Iot","Eps"),("Eps","Alp")],
    "Vir": [("Alp","Gam"),("Gam","Eta"),("Eta","Bet"),("Gam","Del"),
            ("Del","Eps"),("Alp","Zet"),("Zet","Del")],
    "Sgr": [("Zet","Eps"),("Eps","Del"),("Del","Lam"),("Lam","Phi"),("Phi","Sig"),
            ("Sig","Tau"),("Tau","Zet"),("Del","Gam"),("Sig","Zet")],
    "Cen": [("Alp","Bet"),("Bet","Eps"),("Eps","Zet"),("Zet","Gam"),("Gam","Eps")],
    "Car": [("Alp","Bet"),("Bet","Ome"),("Ome","The"),("The","Iot"),("Iot","Eps")],
    "Cap": [("Alp","Bet"),("Bet","The"),("The","Del"),("Del","Gam"),("Gam","Iot")],
    "Cnc": [("Alp","Del"),("Del","Gam"),("Del","Bet"),("Gam","Iot")],
    "CrB": [("Alp","Bet"),("Bet","The"),("Alp","Gam"),("Gam","Del"),("Del","Eps")],
    "Del": [("Alp","Bet"),("Bet","Gam"),("Gam","Del"),("Del","Bet"),("Bet","Eps")],
    "Lep": [("Alp","Bet"),("Bet","Gam"),("Gam","Del"),("Alp","Mu "),("Mu ","Eps")],
    "Cet": [("Alp","Gam"),("Gam","Del"),("Del","Omi"),("Omi","Zet"),
            ("Zet","Bet"),("Bet","Iot"),("Iot","Eta"),("Eta","Zet")],
    "Ari": [("Alp","Bet"),("Bet","Gam")],
    "Cep": [("Alp","Bet"),("Bet","Gam"),("Gam","Iot"),("Iot","Alp"),("Alp","Eta")],
    "Dra": [("Gam","Bet"),("Bet","Nu "),("Nu ","Xi "),("Xi ","Gam"),
            ("Xi ","Del"),("Del","Eps"),("Alp","Kap"),("Kap","Lam")],
    "Her": [("Alp","Bet"),("Bet","Zet"),("Zet","Eta"),("Eta","Pi "),
            ("Pi ","Eps"),("Eps","Zet"),("Bet","Gam")],
    "Oph": [("Alp","Bet"),("Bet","Kap"),("Alp","Kap"),("Kap","Eta"),("Eta","Zet")],
    "Pav": [("Alp","Bet"),("Bet","Del"),("Del","Lam")],
    "Gru": [("Alp","Bet"),("Bet","Del"),("Del","Gam")],
    "Phe": [("Alp","Bet"),("Bet","Gam"),("Gam","Del"),("Alp","Eps")],
    "Vel": [("Gam","Del"),("Del","Kap"),("Kap","Mu "),("Mu ","Lam"),("Lam","Gam")],
    "Pup": [("Zet","Pi "),("Pi ","Nu "),("Nu ","Tau"),("Zet","Rho")],
    "Hya": [("Alp","Eps"),("Eps","Del"),("Del","Eta"),("Eta","Zet"),
            ("Zet","Iot"),("Alp","Ups")],
    "PsA": [("Alp","Bet"),("Bet","Gam"),("Gam","Del"),("Del","Alp")],
    "Lup": [("Alp","Bet"),("Bet","Del"),("Del","Gam"),("Gam","Eta")],
    "TrA": [("Alp","Bet"),("Bet","Gam"),("Gam","Alp")],
    "Tuc": [("Alp","Gam"),("Gam","Bet")],
    "Mus": [("Alp","Bet"),("Alp","Del"),("Del","Gam")],
    "Lib": [("Alp","Bet"),("Bet","Gam"),("Gam","Alp")],
    "Aqr": [("Alp","Bet"),("Alp","Gam"),("Gam","Zet"),("Zet","Eta"),("Alp","The")],
    "Col": [("Alp","Bet"),("Bet","Gam"),("Bet","Eta")],
    "CMi": [("Alp","Bet")],
    "Sge": [("Alp","Del"),("Del","Gam"),("Bet","Del")],
    "Equ": [("Alp","Del"),("Del","Gam")],
    "Tri": [("Alp","Bet"),("Bet","Gam"),("Gam","Alp")],
    "Ser": [("Alp","Del"),("Del","Bet"),("Bet","Kap"),("Kap","Gam"),("Gam","Bet")],
    "CrA": [("Alp","Bet"),("Bet","Gam"),("Gam","Del")],
    "Ind": [("Alp","Bet"),("Bet","Del")],
    "Hyi": [("Alp","Bet"),("Bet","Gam")],
    "Dor": [("Alp","Bet"),("Bet","Del")],
    "Ret": [("Alp","Bet"),("Bet","Del"),("Del","Eps"),("Eps","Alp")],
    "Mon": [("Alp","Gam"),("Alp","Bet"),("Bet","Del"),("Del","Eps")],
    "Crv": [("Alp","Eps"),("Eps","Gam"),("Gam","Del"),("Del","Bet"),("Bet","Eps")],
    "Crt": [("Alp","Bet"),("Bet","Gam"),("Gam","Del"),("Del","Alp"),("Gam","Zet")],
    "Ara": [("Alp","Bet"),("Bet","Gam"),("Gam","Del"),("Alp","The")],
    "Cir": [("Alp","Bet"),("Alp","Gam")],
    "Aps": [("Alp","Gam"),("Gam","Bet")],
    "Cha": [("Alp","Gam"),("Gam","Bet")],
    "Vol": [("Alp","Bet"),("Bet","Eps"),("Eps","Gam")],
    "Men": [("Alp","Bet")],
    "CVn": [("Alp","Bet")],
    "Com": [("Alp","Bet"),("Bet","Gam")],
    "Sex": [("Alp","Gam")],
    "Psc": [("Alp","Omi"),("Omi","Eta"),("Alp","Nu "),("Nu ","Mu "),
            ("Mu ","Eps"),("Eps","Del"),("Del","Ome"),("Ome","Iot"),
            ("Iot","The"),("The","Gam"),("Gam","Kap"),("Kap","Lam"),
            ("Lam","Iot")],
    "Eri": [("Alp","Chi"),("Chi","Phi"),("Phi","Kap"),("Kap","Iot"),
            ("Iot","The"),("The","Ups"),("Ups","Tau"),("Tau","Eta"),
            ("Eta","Eps"),("Eps","Del"),("Del","Gam"),("Gam","Bet")],
    "Scl": [("Alp","Del"),("Del","Gam"),("Gam","Bet")],
    "Pic": [("Alp","Bet"),("Bet","Gam")],
    "Pyx": [("Alp","Bet"),("Alp","Gam")],
    "Sct": [("Alp","Bet"),("Alp","Gam")],
    "Nor": [("Gam","Eps"),("Eps","Del")],
    "Ant": [("Alp","Eps"),("Alp","Iot")],
    "Hor": [("Alp","Bet")],
    "For": [("Alp","Bet")],
    "Cae": [("Alp","Bet")],
    "Tel": [("Alp","Eps")],
    "Mic": [("Gam","Eps")],
    "Lac": [("Alp","Bet")],
    "Oct": [("Nu ","Bet"),("Bet","Del")],
    # No figures for Leo Minor, Lynx or Vulpecula: Bayer never assigned them the
    # letters a line would need — Leo Minor has no Alpha, Lynx and Vulpecula no
    # Beta. They stay as loose stars, which is how they look in the sky anyway.
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
        # Kept only for figure resolution; stripped before the JSON is written.
        star["_designation"] = designation
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


def resolve_figures(stars):
    """Turn Bayer-designation edges into HR-number pairs.

    An edge names either a bare Bayer letter (resolved inside its own
    constellation) or a full "Alp And" designation for the figures that reach
    across a boundary. Unresolvable edges are dropped and reported rather than
    silently omitted — a missing line is a missing line, and it should be
    visible in the build output.
    """
    by_designation = {}
    for star in stars:
        bayer = star.get("_designation")
        if bayer and bayer not in by_designation:
            by_designation[bayer] = star["hr"]

    figures, dropped = {}, []
    for constellation, edges in FIGURES.items():
        resolved = []
        for left, right in edges:
            keys = [
                key if " " in key.strip() and len(key.strip()) > 3
                else f"{key.strip()} {constellation}"
                for key in (left, right)
            ]
            hrs = [by_designation.get(key) for key in keys]
            if None in hrs:
                dropped.append(f"{constellation}: {keys[0]} - {keys[1]}")
                continue
            resolved.append(hrs)
        if resolved:
            figures[constellation] = resolved
    return figures, dropped


def main():
    if len(sys.argv) != 3:
        sys.exit(f"usage: {sys.argv[0]} <bsc5.dat> <out.json>")

    source, destination = sys.argv[1], sys.argv[2]
    with open(source, encoding="latin-1") as handle:
        stars = [s for s in (parse_star(line) for line in handle) if s]

    stars.sort(key=lambda s: s["magnitude"])
    figures, dropped = resolve_figures(stars)
    for star in stars:
        star.pop("_designation", None)

    payload = {
        "source": "Yale Bright Star Catalogue, 5th Revised Ed. (Hoffleit & Warren, 1991)",
        "stars": stars,
        "figures": figures,
    }
    with open(destination, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, separators=(",", ":"), ensure_ascii=False)

    named = sum(1 for s in stars if "name" in s)
    with_distance = sum(1 for s in stars if "ly" in s)
    constellations = len({s["constellation"] for s in stars})
    edges = sum(len(e) for e in figures.values())
    print(f"{len(stars)} stars across {constellations} constellations")
    print(f"  {named} with proper names")
    print(f"  {with_distance} with a distance we trust")
    print(f"{edges} figure edges across {len(figures)} constellations")
    if dropped:
        print(f"  {len(dropped)} edges dropped — no such star:")
        for entry in dropped:
            print(f"    {entry}")


if __name__ == "__main__":
    main()

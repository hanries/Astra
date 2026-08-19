# App Store Connect metadata — Astra 1.0

Kept in the repo because the first version of this lived only in a scratch file
and was gone when it was needed. Character counts are measured, not estimated.

## Rejection history

**19 August 2026, submission cd04b860, build 1.0 (2). Guideline 2.3.7.**
The screenshots referenced the price. Apple counts "free" as a price reference,
and the whole third panel was built on it: the label FREE, the headline "Free,
with nothing to buy inside", the line "No ads, no subscription", and "Every
feature, from the first day", which implies nothing sits behind a paywall.

Fixed by rebuilding that panel around privacy, which is a claim the guideline
does not touch: an account is not a price, and neither is an absent network
stack. The price information moved to the description, which is where Apple's
own resolution text says it belongs.

Guideline 4.3.0 was listed on the submission page but the Resolution Center
message did not describe it. See the note at the bottom.

## App Information

| Field | Value |
|---|---|
| Name | `Astra: Habits and Real Stars` (28/30) |
| Subtitle | `Keep a habit, light a star` (26/30) |
| Bundle ID | `com.hanryli.Astra` |
| SKU | `astra-ios-1` |
| Primary language | English (U.S.) |
| Category | Productivity, then Health & Fitness |
| Content rights | Contains third-party content: Yes (Yale Bright Star Catalogue) |
| Age rating | 4+, every answer None |
| Privacy Policy URL | https://hanries.github.io/Astra/privacy.html |

## Pricing

Free, all territories. No in-app purchases.

## Version 1.0

### Promotional text (136/170)

Contains no price reference on purpose. Promotional text is a separate field
from the description, and only the description is named as the safe place for
price information.

```
Every star is a real one, catalogued, with its own measured colour and temperature. No account, no analytics, and no network connection.
```

### Keywords (93/100)

Every word names something the app does. `streak`, `journal` and `stargazing`
were in the first submission and are gone: Astra has no streak counter by
design, no journalling, and no live sky view, so all three described features
that do not exist.

```
habit,tracker,routine,daily,goals,consistency,reminder,widget,offline,astronomy,constellation
```

### Description

The only metadata field where price information is allowed, so the free line
lives here and nowhere else.

```
Astra is a habit tracker with a real sky in it.

Pick up to five habits. Mark all of them on the same day and Astra lights one star in the patch of sky above the place you first opened the app. Miss a day and nothing is taken back. The stars you have already lit stay lit.

The stars are real ones. Positions, brightnesses and colours come from the Yale Bright Star Catalogue, and a star's colour on the map is worked out from its measured colour index. Tap any star for its surface temperature, its spectral class, and how its size compares to the Sun. Where the catalogue's distance is not reliable, Astra says nothing rather than printing a number that is wrong.

Constellations arrive nearest first and smallest first, so the early ones finish in a couple of days and the later ones take a couple of weeks. Keep everything for two months and that is sixty-one stars and around twenty completed figures.

NO STREAK TO BREAK

There is no streak counter. A number that resets to zero punishes you at the moment you are most likely to give up. The Log shows your longest run instead, which is a record you set rather than a thing you break, next to a month view and your consistency for each habit.

ON YOUR HOME SCREEN

The small widget shows the day's count and the star waiting. The medium widget marks a habit in one tap, without opening the app.

ONE REMINDER A DAY

At a time you pick, and never on a day you have already finished.

FREE, AND PRIVATE

Astra is free. There are no ads, no subscription, and no account to make. It contains no networking code at all, so nothing you record can leave your phone. The star catalogue ships inside the app, which is why the sky works with no connection.
```

### Other fields

| Field | Value |
|---|---|
| Support URL | https://hanries.github.io/Astra/ |
| Marketing URL | https://hanries.github.io/Astra/ |
| Copyright | `2026 Hanry Li` |
| Version release | Manually release this version |

### Screenshots

`Screenshots/6.9-inch/`, 1320x2868, in filename order. No panel contains a
price reference; `Tools/make_screenshots.swift` holds the copy, so grep it
before every submission.

## Still open: 4.3.0

The Resolution Center message covers 2.3.7 only. If 4.3 is raised again it is
almost certainly clause (b), a saturated category, answered with a reply rather
than a new build. The material for that reply: 1,584 catalogued stars shipped in
the binary, colour and temperature computed from each star's measured B-V index,
size compared against the Sun from spectral class, distances withheld where the
parallax is not reliable, every star portrait and the icon rendered
procedurally at run time, an azimuthal equidistant projection anchored once per
install, no streak counter and awards never revoked, and an interactive widget
over App Intents and a shared App Group.

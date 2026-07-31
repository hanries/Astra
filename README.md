# Astra

A habit tracker where showing up lights a star, and nothing you earn is ever
taken back.

Keeping a habit unlocks stars in the real night sky. Constellations complete as
their stars fill in, starting overhead where you live and spreading outward.
Each star carries its real distance, colour, and the times you can go outside
and see it.

App Store listing name: *Astra — Build Habits and Collect Stars*. The binary
shows as `Astra`.

## State

Core logic only. No visuals, and no sky yet — the map and the star catalog are
the next piece of work. `DebugHarnessView` is a plain list that exists so the
engine can be run on device; delete it when the real UI lands.

- iOS 26.4, Swift, SwiftUI, SwiftData
- 41 tests, no third-party dependencies

```bash
xcodebuild test -scheme Astra -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

## Layout

```
Astra/
├── Models/
│   ├── DayKey.swift      calendar day as yyyyMMdd
│   ├── Habit.swift       Habit + Completion
│   └── Award.swift       the unlock ledger + AwardRule
├── Services/
│   ├── HabitStore.swift  every mutation the app makes
│   └── Stats.swift       pure arithmetic over kept days
└── App/                  entry point + debug scaffolding
```

## The decisions worth knowing

**Days are integers, not dates.** A `Date` is an instant, so which day it falls
on depends on the timezone you ask in. Fly across a boundary and yesterday's log
moves. `DayKey` is decided once, in the user's calendar, at the moment they tap.

**The award ledger knows nothing about the artifact.** An `Award` records that
something was unlocked and in what order. Whatever the collectible turns out to
be maps `ordinal` to its own catalog. The reward system doesn't get rewritten
when that decision lands.

**Ordinals are discovery order, not date order.** Backfilling last Tuesday hands
out the *next* ordinal rather than inserting one in the middle. Renumbering
would silently change what the user already unlocked.

**Unlocks are never revoked.** Unchecking a day you already collected for keeps
the unlock. Re-checking it doesn't pay twice. A broken week costs future
unlocks, not past ones — the failure mode that kills habit trackers is people
who stop opening the app because a streak collapsed.

**`createdOn` is the anti-farming floor.** Because kept days pay out, a habit
that accepted arbitrary past dates would let a new user mark a year of history
on install and collect 365 unlocks. You can correct days you were tracking; you
can't claim days you weren't.

**There is no `currentStreak`.** Deliberately. A streak is a number whose only
move is down. `Stats.consistency` dips and recovers instead.

**Five active habits, hard cap.** People who add eight on day one have quit by
day seven.

## The sky

Settled, not yet built:

- One kept day lights one star. A constellation completes when its stars are
  all lit — 4 to 10 days depending on the figure, so pacing comes from the real
  sky rather than a counter.
- Progression starts with the constellation overhead at the user's position and
  spreads outward by angular distance. Constellations can't be ordered by
  distance in light-years — Orion's stars span 250 to 1,300 ly, which tears
  every figure apart.
- Position comes from `TimeZone.current`, which needs no permission and is
  accurate enough to order the sky and get rise/set within an hour. Precise
  location is opt-in, asked the first time someone taps "when can I see this?"
- Rule is `AnyKeptDayRule`: one star per day you showed up at all, so five
  habits and one habit fill the sky at the same rate.

Open:

- **Catalog sourcing.** HYG is CC-BY-SA 4.0 — the ShareAlike term makes it a bad
  fit for a bundled derivative. Plan is the Yale Bright Star Catalogue via
  CDS/VizieR (naked-eye stars only, which is all a figure needs) plus a
  hand-assembled set of constellation lines. Stellarium's line data is GPL;
  don't use it.
- Fun facts. Distance, spectral class, and magnitude come from the catalog.
  Anything genuinely interesting is written content — auto-generate the factual
  line for all ~600 stars, hand-write highlights for the famous ~50.
- The palette. `Habit.colorIndex` is an index into a palette that doesn't exist
  yet, because it's a visual decision.
- Reminders. One a day at a chosen time, worded as information ("Vega is
  overhead tonight"), never as loss.

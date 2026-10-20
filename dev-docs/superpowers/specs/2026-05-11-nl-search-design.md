# Natural-Language Search v2 — Design

**Date:** 2026-05-11
**Status:** Approved, ready for implementation plan
**Supersedes:** Tasks 17–18 (commit `8551d1e`) — the original Foundation Models query bar

## Problem

The existing query bar (`AvailabilityQuery.swift` + `ContentView.swift:166`) extracts only three fields (`dayHint`, `timeOfDay`, `durationMin`) and filters the already-loaded day list. Four concrete gaps:

1. **Narrow vocabulary.** No specific time bounds ("after 2pm"), no date ranges ("Monday–Wednesday"), no relative phrases beyond today/tomorrow/weekday ("next Tuesday", "this weekend", "end of next month"), no duration + purpose mixing.
2. **No date-window expansion.** A query like "any time end of next month" silently returns empty because those days are not in `filteredDays`.
3. **Silent failures.** Parse errors and empty matches both yield a blank result. The user cannot tell which.
4. **No discoverability.** Single static placeholder; no examples surfaced.

## Scope

- **Filter only.** No share-sheet triggering, no action verbs in this iteration.
- **Apple-Intelligence devices only.** The bar stays gated on `AvailabilityQuery.isAvailable`. No heuristic fallback for older devices in this pass.
- **Date window auto-expands up to 4 weeks** ahead of today. Past the cap, the query runs against the loaded subset and the banner reports the cap.

## Architecture

Three small, single-purpose units, communicating through pure data.

```
CalendarAvailability/Services/
  AvailabilityIntent.swift      // @Generable schema + summary(intent:now:)
  QueryParser.swift             // LanguageModelSession → AvailabilityIntent
  QueryFilter.swift             // pure filter (intent + days → matched)
  QuerySuggest.swift             // pure relaxation fallback (intent + days → one Suggestion)

CalendarAvailability/
  ContentView.swift             // owns query state; orchestrates parse → expand → filter → suggest

OpenTimeUI/Sources/OpenTimeUI/
  QueryBarView.swift            // text field + chips row + rotating placeholder
  QueryResultBanner.swift       // "Interpreted as: …  Earliest match: …"
```

The legacy `AvailabilityQuery` enum and its `dayHint`/`TimeOfDay` types are deleted. `AvailabilityQuery.isAvailable` moves to `QueryParser.isAvailable`.

## Intent schema

```swift
@Generable
struct AvailabilityIntent: Codable, Sendable {
    @Guide(description: "Start date (YYYY-MM-DD) of the range the user is asking about. Resolve relative phrases like 'next Tuesday' or 'end of next month' against the current date provided in instructions.")
    var startDate: String?

    @Guide(description: "End date (YYYY-MM-DD) of the range, inclusive. Equal to startDate for a single day. Nil if no date was mentioned.")
    var endDate: String?

    @Guide(description: "Earliest hour the slot may start (0-23). E.g., 'after 2pm' -> 14, 'morning' -> 8.")
    var startHour: Int?

    @Guide(description: "Latest hour the slot may end (1-24). E.g., 'before noon' -> 12, 'afternoon' -> 17.")
    var endHour: Int?

    @Guide(description: "Minimum free block length in minutes, if user mentioned a duration ('30 min', 'an hour', 'quick 15').")
    var durationMin: Int?

    @Guide(description: "Short free-text purpose if user gave one ('coffee', 'a call with Anna'). Optional, for display only.")
    var purposeHint: String?
}
```

### Parser rules

The `LanguageModelSession` instructions include:

- Today's date and weekday, injected at call time: `"Today is YYYY-MM-DD (Monday)."`
- Time-of-day mappings: morning = 8–12, afternoon = 12–17, evening = 17–22.
- "This week" = today through the coming Sunday; "next week" = Monday through Sunday of the following week; "weekend" = Saturday–Sunday.
- Ambiguous weekdays resolve to the **next future** occurrence.
- All fields independently nullable. A query of "30 min" produces only `durationMin = 30`.

## Date window expansion

In `ContentView.runQuery()`, after parsing and before filtering:

```swift
let intent = try await QueryParser.parse(text, now: Date())

if let needed = intent.requestedRange(now: Date()) {
    let cap = Calendar.current.date(byAdding: .weekOfYear, value: 4, to: Date())!
    let target = min(needed.end, cap)
    if target > manager.loadedRangeEnd {
        await manager.extendRange(to: target)
    }
}

let matched = QueryFilter.filter(days: manager.days, intent: intent, now: Date())
let suggestion = matched.isEmpty
    ? QuerySuggest.closest(days: manager.days, intent: intent, now: Date())
    : nil
```

- `requestedRange(now:)` returns `(start, end)` only when `startDate` is set; nil otherwise. Time-of-day-only queries do **not** trigger expansion.
- 4-week cap is hard. If `needed.end > cap`, the banner reports the cap.
- `CalendarManager.extendRange(to:)` is a new method that fetches and merges any missing days, deduplicating with the existing fetch and emitting one `objectWillChange`.
- Clearing the query keeps extended days in memory. They are discarded only when a preset changes.

## Filtering

```swift
enum QueryFilter {
    static func filter(days: [DayAvailability],
                       intent: AvailabilityIntent,
                       now: Date) -> [DayAvailability]
}
```

Each populated field is AND-composed:

- `startDate..endDate` — day inclusive.
- `startHour..endHour` — the slot is **intersected** with the time window. If the intersection is empty, the slot is excluded. Otherwise the intersection becomes the candidate slot returned by the filter. Example: free block 11:30–13:30 with bounds 12–17 yields a 12:00–13:30 candidate (1.5h).
- `durationMin` — the intersected slot's length ≥ requested minutes.
- `purposeHint` — display-only, never filtered on.
- Slots with `start <= now` are always excluded.
- Empty intent (all fields nil) returns input unchanged.

## Suggest (relaxation fallback)

```swift
enum QuerySuggest {
    struct Suggestion {
        let slot: FreeSlot
        let day: Date
        let relaxedFields: [RelaxedField]
    }
    enum RelaxedField { case date, timeOfDay, duration }

    static func closest(days: [DayAvailability],
                        intent: AvailabilityIntent,
                        now: Date) -> Suggestion?
}
```

Relaxation order (most specific dropped last). Each step keeps every other constraint:

1. **Relax `timeOfDay`** — drop `startHour`/`endHour`, keep date + duration.
2. **Relax `duration`** — drop `durationMin`, keep date + time bounds.
3. **Relax `date`** — drop `startDate`/`endDate`, keep time + duration; search forward from today only.

First step that produces a hit wins. Suggest never returns more than one slot. Suggest never returns a slot before the requested date.

## UI

### `QueryBarView` (OpenTimeUI)

Replaces the inline `queryBar` view-builder in `ContentView`. Same layout (ASK label · TextField · spinner/clear), plus:

- **Rotating placeholder.** `TimelineView(.periodic(every: 4))` cycles through a fixed list while the field is empty AND unfocused:
  - `WHEN AM I FREE?`
  - `ANY HOUR FRIDAY AFTERNOON`
  - `30 MIN TOMORROW MORNING`
  - `NEXT TUESDAY AFTER 2PM`
  - `COFFEE NEXT WEEK`
  - `ANY 2-HOUR BLOCK`
- **Example chips.** Three tappable chips below the field, visible only when `queryText.isEmpty && queryResult == nil`. Tap fills the field and runs the query. Examples are shuffled per session from the same list.

```
┌────────────────────────────────────────────┐
│ ASK   NEXT TUESDAY AFTER 2PM_              │
├────────────────────────────────────────────┤
│  [ HOUR FRIDAY PM ]  [ 30 MIN TMRW ]  [ … ]│
└────────────────────────────────────────────┘
```

### `QueryResultBanner` (OpenTimeUI)

Appears above `matchResultView` whenever a query is active.

- **Match:** `INTERPRETED: TUE APR 21 · AFTER 2PM · 60 MIN  ·  3 SLOTS` (count is matching slots across days, not days)
- **No match + suggestion:** `NO 1-HR BLOCKS TUE PM. EARLIEST: WED 1–2 PM (DATE RELAXED)` — tappable, scrolls the day list to that slot.
- **No match + no suggestion:** `NO MATCHES. TRY A WIDER WINDOW.`
- **Parse error:** `COULDN'T READ THAT QUERY — TRY REPHRASING`

Banner reads its strings from `AvailabilityIntent.summary(intent:now:)` so format lives in one place and tests cleanly.

### Behavior when AI unavailable

Same as today: the entire bar is hidden via `QueryParser.isAvailable`. No heuristic fallback in this iteration.

## Testing

Three pure-function test files. A new `CalendarAvailabilityTests` target is added — the project currently has none.

**`QueryFilterTests`**:
- date range: single-day, multi-day, range edges (inclusive), days outside range
- time bounds: `startHour`/`endHour` only, both, slot trimming across the boundary
- duration: pass, fail, exact-equal boundary
- AND composition with all four fields
- empty intent → input unchanged
- past slots excluded

**`QuerySuggestTests`**:
- relaxation priority is time → duration → date
- never returns a slot before the requested date
- returns nil when nothing loosely fits
- `Suggestion.relaxedFields` reports the right field

**`AvailabilityIntentTests`** for `summary(intent:now:)`:
- date-only / time-only / duration-only intents render readable strings
- `purposeHint` appears when present
- relative date labels ("TODAY", "TOMORROW", "TUE APR 21") chosen correctly given `now`

**Not unit-tested** (Apple Intelligence required, gated behind `#if canImport(FoundationModels)`):
- `ParserPlaygroundTests` — manual target running 8–10 canned phrases and printing decoded intents so we can eyeball drift after model updates. Excluded from CI.

## Out of scope

- Heuristic parser for non-AI devices.
- End-to-end LLM matching with calendar context in the prompt.
- Action triggers (share, create event).
- Persistence of recent queries.
- Localization beyond English query text.

## Open questions

None at design approval. Implementation plan will decide ordering and dependencies.

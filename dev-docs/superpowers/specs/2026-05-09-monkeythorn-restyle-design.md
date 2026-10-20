# OpenTime — MonkeyThorn-Style Restyle + Foundation Models Query Bar

**Date:** 2026-05-09
**Status:** Design — pending implementation plan
**Scope:** Single-sweep aesthetic restyle of all five OpenTime targets to match the MonkeyThorn web aesthetic (`~/monkeythorn-calendar`), plus a new on-device natural-language availability query bar powered by Apple Intelligence's Foundation Models framework.

## Goals

1. Bring OpenTime's visual language into lockstep with MonkeyThorn web (`monkeythorn-calendar/src/styles/global.css`) — editorial / Bloomberg-style typography, hard rules, square chips, single red accent, NHG Display typeface.
2. Replace the forced dark mode with a true adaptive theme (light + dark, system-controlled).
3. Add a long-press affordance on free-time chips that integrates with Apple Calendar.
4. Add an on-device natural-language query bar so the user can ask "when am I free Tuesday afternoon for 30 min?" and get a filtered result.
5. Keep all five surfaces (main iOS app, widgets + Live Activity, Apple Watch, iMessage extension, Share extension) brand-consistent — no half-restyled state ever ships.

## Non-Goals

- No new App Store screenshots or marketing copy in this work.
- No App Icon redesign.
- No data-model changes (`Models/CalendarModels.swift`, `Services/CalendarManager.swift` untouched).
- No port of the MonkeyThorn web booking form — OpenTime is a personal tool, not a public booking page.
- No Siri / Shortcuts intent UI restyle (system-rendered; no styling hook).
- The `GetAvailabilityIntent` Siri shortcut is not refactored to share the new query pipeline in this spec — flagged as follow-up.

## Decisions Captured During Brainstorming

| Decision | Choice |
|---|---|
| Color scheme | Adaptive (light + dark, system-controlled). Drop forced dark mode. |
| Typeface | Bundle NHG Display (5 weights: 400, 400i, 500, 700, 700i) across all iOS targets. Apple Watch uses SF Compact (NHG mushes at watch sizes). |
| Free vs busy display | Default chips-only (free chips). Toolbar toggle reveals busy events as restyled rows. |
| Long-press chip menu | Three items: **Open in Calendar**, **Create Event Here**, **Copy Time**. |
| Rollout | Single sweep — all 5 surfaces in one branch / one App Store release. |
| Foundation Models query bar | Folded into this spec. iOS 26 min target on main app only. |

## Architecture

### New shared module: `OpenTimeUI`

A new lightweight Swift package named `OpenTimeUI`, linked by the **iOS-family targets** (main app, widget extension, Messages extension, Share extension). The Apple Watch target gets a parallel `OpenTimeUIWatch` package that mirrors the public API but uses SF Compact in place of NHG and omits components that don't apply to watchOS (`BusyRowView`, `.contextMenu` long-press wiring on `SlotChip`).

`OpenTimeUI` contains:
- `Theme.swift` — color tokens, font factory, spacing constants.
- `FontRegistration.swift` — registers bundled NHG Display TTFs at launch via `CTFontManagerRegisterFontsForURL`. Each target's launch path calls `FontRegistration.registerNHG()`.
- `PageHeader` — the `AVAILABILITY` header with date meta and 4pt rule.
- `MTSquareButton` — square button replacing all `RoundedRectangle` / `Capsule` controls (duration chips, weekend toggle, Live Activity start, etc.).
- `DayRowView` — replaces `DayCardView`; no card, hard rules, ▶ today marker.
- `SlotChip` — square free-time chip with the `.contextMenu` long-press handler.
- `BusyRowView` — editorial-style busy event row, shown only when "Show busy" is on.
- `FlowLayout` — chip flow layout (iOS 16+ system or backport — confirm during implementation).

Centralizing these here is what makes the single-sweep approach economical: each target imports the same components, and a token change propagates to all five surfaces in one edit.

### Theme tokens

Colors (semantic, adaptive — defined as `Color(light:dark:)` pairs):

| Token | Light | Dark |
|---|---|---|
| `Theme.bg` | `#FFFFFF` | `#0A0A0A` |
| `Theme.fg` | `#000000` | `#FFFFFF` |
| `Theme.muted` | `#555555` | `#A0A0A0` |
| `Theme.dim` | `#888888` | `#666666` |
| `Theme.rule` | `#000000` | `#FFFFFF` |
| `Theme.accent` | `#D40000` | `#FF1F1F` |

The dark-mode accent is brightened from `#D40000` to `#FF1F1F` for legibility against `#0A0A0A` — matches MonkeyThorn's `.slot-chip:hover` color (`#ff1a1a`).

The old `Theme.green`, `Theme.greenBg`, `Theme.greenBorder`, `Theme.greenLight`, `Theme.redBg`, `Theme.redBorder`, `Theme.blue` tokens are deleted. Free vs busy is now communicated by chip vs row, not by color.

Typography:

- `Theme.Font.display(size:weight:)` — returns NHG Display at the given size/weight. Honors Dynamic Type by accepting a `relativeTo: UIFont.TextStyle`.
- `Theme.Font.tnum` — view modifier that enables tabular numerals (`font.monospacedDigit()`).
- Type rules from MonkeyThorn web:
  - Page title (`AVAILABILITY`): NHG 22pt 700, `kerning: -0.22pt` (≈ -0.01em), uppercase.
  - Day name: NHG 18pt 700, `kerning: -0.36pt` (≈ -0.02em).
  - Day date / total / micro-labels: NHG 10pt, `kerning: 1.8pt` (≈ 0.18em), uppercase, `Theme.muted`.
  - Slot chip: NHG 11pt 500, tabular numerals.
  - Busy row time: NHG 13pt 500, `Theme.muted`.

Spacing:

- Horizontal page padding: 20pt.
- Day row vertical padding: 10pt.
- Page header bottom margin: 14pt; rule above is 4pt thick (full `Theme.rule`).
- Day separator: 1pt rule, `Theme.rule`.
- Chip gap: 4pt; chip padding: 4×8pt.
- All `RoundedRectangle` / `Capsule` removed app-wide. No corner radius.

## Component-Level Changes

### `CalendarAvailability/ContentView.swift`

- Remove `Theme.bg.ignoresSafeArea()` and `.preferredColorScheme(.dark)`.
- Replace `.navigationTitle("Availability")` with the custom `PageHeader` (left: `AVAILABILITY`, right: date meta, 4pt rule below). The `NavigationStack` toolbar still hosts the action buttons.
- Toolbar buttons (copy, refresh, share) restyled from SF Symbol pill buttons to small uppercase text labels. Add a new **Show Busy** toggle in the toolbar overflow menu (default off; on reveals `BusyRowView`s in each day).
- "Live" / "Go Live" capsule and the weekends `Toggle` both replaced by `MTSquareButton` (active state inverted: bg = fg, fg = bg).
- Below `PageHeader`, insert the new **Foundation Models query bar** (see "Foundation Models query bar" section). Hidden on unsupported devices.

### `CalendarAvailability/Views/DayCardView.swift` → `DayRowView.swift` (in `OpenTimeUI`)

- Renamed and moved into the shared module.
- No card, no background, no border, no corner radius.
- Top: 1pt rule (`Theme.rule`). The bottom rule is rendered by the parent on the last row only.
- Header line: day name (NHG 18pt 700) + date (NHG 10pt caps muted) + total free (NHG 10pt caps, right-aligned).
- Today gets the red `▶` prefix glyph and `Theme.accent` on day-name + date; chip backgrounds also flip to `Theme.accent` for the today row.
- Chips below the header in `FlowLayout`. Each chip is a `SlotChip`.

### `OpenTimeUI/SlotChip.swift` (new)

- Square, 4×8pt padding, NHG 11pt tnum, `Theme.fg` background / `Theme.bg` foreground (or `Theme.accent` background for today's chips).
- 120ms linear color transition on press / hover (matches MT web).
- `.contextMenu` with three items:
  1. **Open in Calendar** — opens iOS Calendar at the slot's start (`calshow:<unix-timestamp>`). Guarded by `UIApplication.canOpenURL` with no fallback messaging — calendar is system-installed.
  2. **Create Event Here** — presents `EKEventEditViewController` with `event.startDate = slot.start`, `event.endDate = slot.end`. The EventKit save flow handles permission prompts.
  3. **Copy Time** — copies a formatted "9:00 AM – 9:30 AM" string to `UIPasteboard.general` and triggers a success haptic (mirrors the existing toolbar copy behavior).
- Tap on a chip in the main app does nothing new (chips were display-only). The long-press menu is the new interaction. (No inline booking form — that's MT web behavior, not applicable to a personal tool.)

### `OpenTimeUI/BusyRowView.swift` (new)

- Rendered only when "Show Busy" is on.
- Layout: time range left (NHG 13pt 500, `Theme.muted`), event title middle (NHG 13pt 500, `Theme.dim`, `lineLimit(1)`), no background.
- Thin 1pt rule between consecutive busy rows (rule color: `Theme.dim`, lighter than the day separator so the hierarchy reads).
- Squeezed below the chip flow, above the next day's top rule.

### `CalendarAvailability/Views/DateRangePickerView.swift`

- Buttons restyled to `MTSquareButton` pattern.
- Selected state inverted (bg = `Theme.fg`, fg = `Theme.bg`).
- Section labels in MT caps + kerning style.

## Foundation Models Query Bar

### Placement and visual

A single line input row between `PageHeader` and `DateRangePickerView`. Style mirrors MonkeyThorn's `.inline-form input` pattern:

- No box. 1pt bottom border in `Theme.fg`.
- Placeholder text: `ASK · WHEN AM I FREE?` in `Theme.muted`, NHG 10pt caps, 0.18em kerning.
- Right side: small `→` submit glyph; pressing return on the keyboard also submits.
- On submit, the bottom border flashes `Theme.accent` for 120ms (same transition timing as chips).

### Behavior

A new `Services/AvailabilityQuery.swift` wraps `LanguageModelSession` from the Foundation Models framework (iOS 26 SDK).

```swift
@Generable
struct AvailabilityIntent {
  let dayHint: String?       // "Tuesday", "tomorrow", "next Monday"
  let timeOfDay: TimeOfDay?  // .morning | .afternoon | .evening | nil
  let durationMin: Int?      // parsed minutes, nil = any
  let exact: DateRange?      // populated only for exact "Tuesday 2pm" form
}
```

`AvailabilityQuery.parse(_ text: String) async throws -> AvailabilityIntent` calls the on-device model with the raw input and the `@Generable` schema. All processing is on-device — no network calls, no telemetry, no per-token cost.

The parsed intent is then applied as a filter against `manager.days` (existing `DayAvailability` data — no model changes required). Matched slots are rendered as a single highlighted `DayRow` above the normal day list, prefixed by a `MATCH` micro-label and a `× CLEAR` button that dismisses the result and re-shows the full list.

Empty result shows `NO FREE SLOTS · TRY ANOTHER DAY` in MT caps style.

### Device support

- `LanguageModelSession.isSupported` (or the framework's equivalent availability check) gates the entire query bar row.
- Unsupported devices (older than iPhone 15 Pro / non-M iPad): row is hidden. No error, no nag, no fallback model. Rest of the app is unaffected.
- No `Info.plist` permission entry needed — Foundation Models has no per-app entitlement.

### Build / SDK

- Bumps the **main app target** minimum deployment target to **iOS 26.0**.
- Widget extension, Watch app, Messages extension, and Share extension stay at their current minimum (the framework is not used in any of those targets in this spec).
- This drops main-app support for users on iOS 17 / iOS 18 — accepted during brainstorming.

## Per-Surface Restyle

### Widgets (`CalendarWidget/`)

- Three sizes today (today / this week / next week) — all repainted in MT aesthetic.
- Background: `Theme.bg` adaptive — relies on widget's automatic light/dark behavior; no manual override.
- Header: `TODAY` / `THIS WEEK` / `NEXT WEEK` micro-label (NHG 9pt, 0.2em kerning) with date right-aligned. 2pt rule under (1pt looks too thin at widget DPI).
- Body: `DayRowView` reused with widget-density adjustments (chip 9pt, vertical padding 4pt). `FlowLayout` reused.
- Today's `▶` marker preserved; accent token shared.
- NHG bundled in the widget extension's `Resources/` and `UIAppFonts` (widgets are separate processes — they need their own font registration).
- Existing tap-to-refresh interactive button restyled to `MTSquareButton`.
- `.contextMenu` is not available in widgets — tapping a chip in a widget deep-links into the main app at that slot, where the long-press menu works. New URL scheme entry: **`opentime://slot?start=<unix>&end=<unix>`**, handled in `CalendarAvailabilityApp` to scroll the matching day into view and (optionally) auto-present the long-press menu on first tap.

### Live Activity (`CalendarWidget/AvailabilityLiveActivity.swift` + `AvailabilityActivityAttributes.swift`)

- Lock screen: `Theme.bg` (system-adaptive), 2-line layout — top is the `AVAILABILITY` micro-header + meta; bottom is the next free chip in inverted style with `→ <duration> free today` after it.
- Dynamic Island:
  - **Compact:** leading = small red `▶` glyph if there is currently a free window; trailing = next-free time in tnum (e.g. `2:30`).
  - **Minimal:** the `▶` glyph only — `Theme.accent` when free, `Theme.muted` when not.
  - **Expanded:** lock-screen layout, scaled.
- Update cadence and `LiveActivityManager` plumbing unchanged — purely a visual job.

### Apple Watch (`OpenTimeWatch/`)

- watchOS does not honor `UIAppFonts` the same way iOS does, and NHG Display compresses to mush at 24–28mm. **Watch uses SF Compact** plus the MonkeyThorn *layout rules* (caps, kerning, tnum, hard rules, square chips, red accent). The aesthetic still reads as MT because the structure does the work.
- Watch imports `OpenTimeUIWatch`, which provides the same `Theme` token names but resolves the font factory to SF Compact.
- Layout: vertical list of next 5 weekdays. Per row: `▶` if today, day abbreviation (TUE / WED), date, total free; below, the first 3 chips with a `+N` indicator if more.
- No `.contextMenu` on watchOS — tapping a chip copies the time and triggers a haptic confirm. Tapping a row opens detail.
- "Show Busy" toggle and `BusyRowView` are iOS-only; the Watch surface is always free-chips-only.

### iMessage extension (`MessagesExtension/`)

- Picker UI restyled with MT day rows + chips, compacted to fit the iMessage compact / expanded presentation modes.
  - Compact: shows next 3 days.
  - Expanded: shows the full 5-weekday flow.
- "Send" button: `MTSquareButton` in submit style — `Theme.accent` background, `Theme.bg` foreground, 10pt caps, 0.18em kerning.
- The composed `MSMessage` payload itself is unchanged — visual restyle only affects the in-app picker.
- NHG bundled in the extension target; `FontRegistration.registerNHG()` called from the extension's launch.

### Share extension (`ShareExtension/`)

- One-screen restyle: `PageHeader`, `DayRowView` list, chip selection, "Copy" / "Send" actions in `MTSquareButton` style. No new functionality.
- NHG bundled and registered.

## Testing

### Snapshot tests (new target: `OpenTimeUITests`)

- `DayRowView` — light + dark; today + non-today; chips only / no-availability / "Show Busy" on.
- `SlotChip` — default + today (accent) variants in both color schemes.
- `PageHeader`, `MTSquareButton` (default + selected), `BusyRowView`.
- **Open question (resolve before implementation plan):** zero-dep hand-rolled `UIView`-to-PNG diffs against committed reference images, or add `swift-snapshot-testing` as the only third-party dependency? User to confirm.

### Widget previews

- Each widget size gets `#Preview` blocks for both color schemes. Visually verified before each App Store submission, not gated.

### Unit tests

- `AvailabilityQuery.parse(_:)` golden tests with mocked `LanguageModelSession`:
  - "tuesday afternoon" → `{day: "Tuesday", timeOfDay: .afternoon}`
  - "thirty minutes wednesday" → `{day: "Wednesday", durationMin: 30}`
  - "next week monday morning" → `{day: "Monday", timeOfDay: .morning}` (with date math handled by the filter step, not the parser).
- Mock the framework so tests run on any Apple Silicon CI / sim, not just Apple-Intelligence-capable simulators.

### Manual verification checklist (run on device before App Store submission)

- Light + dark switching mid-session — header rule, chip inversion, accent all flip cleanly across all five surfaces.
- Today's `▶` marker present and accent-colored in main app + widget + Live Activity + Watch.
- Long-press a free chip → menu shows **Open in Calendar** + **Create Event Here** + **Copy Time**. Both Calendar paths actually open Apple Calendar with correct date/time.
- "Show Busy" toolbar toggle reveals/hides busy rows. Day's "free total" in header is unchanged by the toggle.
- Widget tap on a chip deep-links to the main app at the correct slot.
- Live Activity Dynamic Island compact + minimal + expanded all render with NHG.
- iMessage extension picker renders MT layout in both compact and expanded presentation modes.
- Share extension renders MT layout when invoked from Photos / Notes.
- Apple Watch: rows render with SF Compact + MT structure; chips tap-copy with haptic.
- NHG actually loaded in each target — log `UIFont.familyNames.contains("NHG Display")` at launch in main app + each extension during dev (remove logs before ship).
- Foundation Models query bar visible on iPhone 15 Pro+; hidden on iPhone 14 / older.
- Query bar parses representative inputs and returns the right slots.

## Open Items (Resolve in Implementation Plan)

1. **Snapshot test framework choice** — zero-dep hand-rolled, or `swift-snapshot-testing`?
2. **iOS 26 minimum deployment target on the main app** — confirm acceptable to drop users on iOS 17 / 18 for the main app (extensions stay at current min).
3. **Foundation Models availability gate** — exact API name (`LanguageModelSession.isSupported` vs equivalent). Verify at implementation time against shipping iOS 26 SDK.
4. **`FlowLayout`** for the chip flow — main app gets iOS 26's `Layout` protocol natively. The widget extension may stay on a lower min (its current value, to confirm during planning); if so, this needs a small `Layout`-conforming backport in `OpenTimeUI` shared with the widget. Resolve once widget min target is checked.

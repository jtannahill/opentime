# OpenTime — Pinned Queries + "In X Weeks/Months" Window

Date: 2026-05-21
Status: Design approved, awaiting plan

## Summary

Two related additions to the existing NL availability search in OpenTime:

1. Teach the FoundationModels-backed query parser to understand "in X weeks" and "in X months" phrasing, expanding it to a 2-week window centered on the target date.
2. Let users pin queries (from the query bar or by hand) into chips that persist via iCloud key-value sync, with a Settings screen to rename, reorder, and delete them.

The existing `QueryBarView` already covers the "search bar for availability" requirement; no separate search UI is added.

## Goals

- Natural phrases like "in 3 weeks am I free" produce a useful 14-day window without the user having to think in dates.
- Frequently asked questions ("any 2-hour block", "30 min tomorrow morning") become one-tap chips.
- Pinned chips survive reinstall and follow the user across their devices.

## Non-Goals

- Sharing pinned queries between users.
- Pinning surfaces in the Watch, Messages, or Share extensions (v1 is main app only; the entitlement can be extended later).
- Per-pin custom icons or colors.
- Auto-pinning based on usage frequency.

## 1. "In X weeks/months" parsing

### Behavior

| Query                       | Resolved range (today = 2026-05-21)          |
| --------------------------- | -------------------------------------------- |
| "in a week am I free"       | 2026-05-14 → 2026-05-28 (target 2026-05-28)  |
| "in 3 weeks"                | 2026-06-04 → 2026-06-18 (target 2026-06-11)  |
| "in 2 months when am I free"| target = 2026-07-21; range 2026-07-14 → 2026-07-28 |
| "in 6 months mornings"      | target = 2026-11-21; range 2026-11-14 → 2026-11-28, startHour 8, endHour 12 |

Modifiers (`mornings`, `after 2pm`, `60 min`, `coffee`) continue to compose with the new rule because they're parsed by the same `AvailabilityIntent` schema.

### Implementation

Extend the instructions string in `QueryParser.instructions(now:)` with one new rule, appended after the existing "Next week" / "Weekend" rules:

> "In N weeks" or "in N months" means: target date = today + N weeks (or N calendar months). Set startDate = target − 7 days and endDate = target + 7 days. Treat "in a week" / "in a month" as N = 1. Example: today is 2026-05-21, "in 3 weeks" → startDate 2026-06-04, endDate 2026-06-18.

No code changes needed in `AvailabilityIntent.requestedRange` — it already returns an inclusive (start, end) range. `CalendarManager.extendRange(to:)` already grows the loaded window when a query reaches past it.

### Tests

- New `AvailabilityIntentTests` cases that construct hand-built intents (mimicking model output) and assert `requestedRange(now:)` returns the expected centered 14-day window.
- The prompt-level behavior is non-deterministic, so the spec includes a manual smoke list (below) rather than an automated test against the model.

## 2. Pinned queries

### Data model

New file `OpenTimeUI/Sources/OpenTimeUI/Query/PinnedQuery.swift`:

```swift
public struct PinnedQuery: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public var label: String
    public var query: String
    public let createdAt: Date

    public init(id: UUID = UUID(), label: String, query: String, createdAt: Date = .now) {
        self.id = id
        self.label = label.isEmpty ? query : label
        self.query = query
        self.createdAt = createdAt
    }
}
```

### Storage

New `PinnedQueryStore` (`ObservableObject`) in `OpenTimeUI/Sources/OpenTimeUI/Query/PinnedQueryStore.swift`:

- Backing: `NSUbiquitousKeyValueStore.default` under key `opentime.pinnedQueries.v1`, JSON-encoded `[PinnedQuery]`.
- Mirror to `UserDefaults.standard` under the same key for instant local reads and offline fallback.
- Observes `NSUbiquitousKeyValueStore.didChangeExternallyNotification`. Merge policy: union by `id`; on conflicting `id`, the entry with the later `createdAt` wins. The mirror is rewritten after any merge.
- Cap at 20 entries. Adding past 20 silently drops the oldest by `createdAt` and sets a transient `didTrimAtCap = true` flag that the Settings screen reads to show a one-time alert.
- Public API:
  - `@Published var pinned: [PinnedQuery]`
  - `add(query: String, label: String? = nil)`
  - `rename(_ id: UUID, to label: String)`
  - `delete(_ id: UUID)`
  - `move(from: IndexSet, to: Int)`
  - `isPinned(query: String) -> Bool` (trimmed, case-insensitive)
  - `toggle(query: String)` — convenience for the pin button

### Entitlement

New `OpenTime/OpenTime.entitlements`:

```xml
<key>com.apple.developer.ubiquity-kvstore-identifier</key>
<string>$(TeamIdentifierPrefix)$(CFBundleIdentifier)</string>
```

iCloud capability is added on the main app target only. The `OpenTime.xcodeproj/project.pbxproj` change adds the entitlements file reference + the capability flag for that target.

### QueryBarView changes

`OpenTimeUI/Sources/OpenTimeUI/Components/QueryBarView.swift` gains:

- New props:
  - `pinnedQueries: [PinnedQuery]`
  - `isCurrentQueryPinned: Bool`
  - `onTogglePin: () -> Void`
  - `onRunPinned: (PinnedQuery) -> Void`
- When `hasResult` is true, a `★ PIN` / `★ PINNED` button appears in `barRow`, immediately before `× CLEAR`. Same typography as the clear button.
- The chip section becomes up to two rows:
  - **Row 1 (pinned):** rendered by a new `PinnedChipsView` component, shown whenever `pinnedQueries` is non-empty (regardless of focus / result state). Filled style: `Theme.fg` background, `Theme.bg` text, same 10pt display font.
  - **Row 2 (examples):** existing outline-style chip row, unchanged trigger (`text.isEmpty && !hasResult`).
- Tap a pinned chip → sets `text = pinned.query` and calls `onRunPinned(pinned)`, which routes through the same submit path used today by the example chips.
- Long-press a pinned chip → SwiftUI context menu with "Rename" (presents an inline `TextField` alert) and "Remove".

### Settings screen

New `OpenTime/Views/PinnedQueriesView.swift`:

- Standard SwiftUI `List` over `pinStore.pinned`.
- Each row: editable label (tap to edit inline), query string below in `Theme.muted`.
- `.onMove` for drag-reorder; `.onDelete` for swipe-delete.
- `EditButton` in the toolbar.
- "+" toolbar button presents a sheet with two fields (label, query). On save: run the query through `QueryParser.parse` to validate; reject (with inline error) if the parser returns an empty `AvailabilityIntent`.
- One-time alert if `pinStore.didTrimAtCap == true`.

Entry point: existing toolbar `Menu` in `ContentView.swift` (~line 429) gains a `NavigationLink("Pinned Queries") { PinnedQueriesView() }`.

### Wiring

`ContentView.swift`:

```swift
@StateObject private var pinStore = PinnedQueryStore()
```

Passed into `QueryBarView`:

```swift
QueryBarView(
    text: $queryText,
    isLoading: queryIsLoading,
    hasResult: queryResult != nil,
    pinnedQueries: pinStore.pinned,
    isCurrentQueryPinned: pinStore.isPinned(query: lastSubmittedQuery),
    onSubmit: runQuery,
    onClear: clearQuery,
    onTogglePin: { pinStore.toggle(query: lastSubmittedQuery) },
    onRunPinned: { pinned in
        queryText = pinned.query
        Task { await runQuery() }
    }
)
```

`lastSubmittedQuery` is a new `@State` on `ContentView` so the pin button reflects the query the user actually submitted, not their currently-typed text.

## File layout

### New
- `OpenTimeUI/Sources/OpenTimeUI/Query/PinnedQuery.swift`
- `OpenTimeUI/Sources/OpenTimeUI/Query/PinnedQueryStore.swift`
- `OpenTimeUI/Sources/OpenTimeUI/Components/PinnedChipsView.swift`
- `OpenTime/Views/PinnedQueriesView.swift`
- `OpenTime/OpenTime.entitlements`
- `OpenTimeUI/Tests/OpenTimeUITests/PinnedQueryStoreTests.swift`

### Modified
- `OpenTimeUI/Sources/OpenTimeUI/Query/QueryParser.swift` — append "in N weeks/months" rule
- `OpenTimeUI/Sources/OpenTimeUI/Components/QueryBarView.swift` — new props, pin button, two-row chips
- `OpenTime/ContentView.swift` — own `pinStore`, pass into `QueryBarView`, add NavigationLink in toolbar Menu, track `lastSubmittedQuery`
- `OpenTime.xcodeproj/project.pbxproj` — add iCloud KVS capability + entitlements file reference on main app target only
- `OpenTimeUI/Tests/OpenTimeUITests/AvailabilityIntentTests.swift` — centered-window cases

## Tests

### Automated
- `PinnedQueryStoreTests`:
  - add → persists to UserDefaults; observable; respects 20-cap (oldest dropped).
  - rename / delete / move propagate to the published array.
  - external KVS change notification triggers a union-merge by id, last-createdAt wins on collision.
  - `isPinned(query:)` is trimmed and case-insensitive.
- `AvailabilityIntent` tests for centered ranges:
  - hand-built intent with startDate = today+14, endDate = today+28 → `requestedRange` returns that span.
  - same for months (today+2 months ±7 days).

### Manual smoke (recorded in spec)
1. Say "in 3 weeks am I free" → calendar window shows the 14-day span centered three weeks out; `QueryResultBanner` summary reads as a range.
2. Pin that query → chip appears in row 1 with filled style; star reads `★ PINNED`.
3. Force-quit and relaunch → chip still present.
4. Toggle airplane mode → chip still present (UserDefaults mirror).
5. Open Settings → rename the chip → chip updates immediately in the bar.
6. Sign in to the same iCloud account on a second device → pinned chip appears within KVS sync window.
7. Add 21 chips manually → oldest is dropped; alert fires once.

## Out of scope (YAGNI)

- Sharing pinned queries between users.
- Pinning surfaces in the Watch / Messages / Share extensions.
- Custom icons / colors per pin.
- Smart auto-pinning based on usage frequency.
- CloudKit-backed storage (KVS is sufficient for ≤1 KB of pinned-query data).

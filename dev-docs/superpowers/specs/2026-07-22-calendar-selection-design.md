# Calendar Selection: Design

Date: 2026-07-22
Status: Approved

## Problem

Open Time shares availability computed from every calendar the device can see. All seven EventKit query sites pass `calendars: nil`:

- `OpenTime/Services/CalendarManager.swift:101`
- `OpenTime/Intents/IntentCalendarHelper.swift:83`
- `OpenTime/LiveActivity/LiveActivityManager.swift:119`
- `ShareExtension/ShareCalendarHelper.swift:83`
- `MessagesExtension/CalendarHelper.swift:83`
- `CalendarWidget/CalendarWidget.swift:66`
- `OpenTimeWatch/WatchCalendarHelper.swift:118` (out of scope, see below)

Users cannot exclude calendars (subscribed sports schedules, a partner's shared calendar, holidays) from the availability they share.

## Scope

All iOS surfaces honor the selection: main app, CalendarWidget, MessagesExtension, ShareExtension, Live Activity. The watch is explicitly out of scope: it has no App Group access and no WCSession layer exists; it continues to query all calendars. This is a documented gap alongside the existing watch-engine divergence (see 2.0.3 deferred-bugs list).

## Storage

- New App Group: `group.com.jamestannahill.CalendarAvailability`, added to the entitlements of the 4 iOS targets (OpenTime app, CalendarWidget, MessagesExtension, ShareExtension). Automatic signing regenerates provisioning profiles. Bundle IDs unchanged.
- One key in the group `UserDefaults`: `excludedCalendarIDs: [String]` (EKCalendar `calendarIdentifier` values).
- Exclude-list semantics:
  - Key missing or empty = all calendars included (current behavior; existing users see no change).
  - A newly added calendar or account is included by default. Safe failure mode for an availability app: a forgotten calendar makes the user look busy, never falsely free.
  - IDs of deleted calendars go stale harmlessly (they simply never match). No pruning required.

## Shared unit

New file `OpenTimeUI/Sources/OpenTimeUI/Calendar/CalendarSelection.swift`, in the package all four iOS targets already import.

Responsibilities:

- Read/write `excludedCalendarIDs` in the App Group defaults.
- `calendars(for store: EKEventStore) -> [EKCalendar]?`: returns `nil` when the excluded set is empty (callers pass it straight to `predicateForEvents`, preserving today's exact behavior) or the filtered `[EKCalendar]` otherwise.
- Core filtering is a pure function over (all calendar IDs, excluded ID set) so it is unit-testable without EventKit fakes.

The package must link EventKit for iOS. Watch target does not import OpenTimeUI; no watchOS constraint.

## UI

- New "Calendars…" item in the existing MORE toolbar menu in `ContentView.swift`.
- Opens a sheet listing calendars grouped by source/account (`EKSource`), one toggle per calendar, styled with `Theme`.
- The last enabled calendar cannot be toggled off (prevents accidentally sharing an all-free schedule).
- On dismiss after a change: reload availability (`manager.loadTodayAndTomorrow()`), `WidgetCenter.shared.reloadAllTimelines()`, and Live Activity `updateNow()`.

## Call-site changes

The 6 iOS query sites change `calendars: nil` to `calendars: CalendarSelection.calendars(for: store)`. No other engine changes. `EventEditSheet` (event creation) is unaffected.

## Testing

- OpenTimeUI package tests: pure filter logic; the empty-set-returns-nil contract; persistence round-trip against an injected `UserDefaults` suite.
- Clean release build of all 5 targets (watch unchanged but must still compile).

## Out of scope

- Watch support (needs WCSession sync layer).
- Unifying the three duplicated CalendarHelper files into OpenTimeUI.
- The 2.0.3 deferred bugs (multi-day events, elapsed slots, declined invites, all-day events).

# Configurable Work Hours

Date: 2026-07-30

## Problem

The workday is hardcoded to 9:00-17:00 in seven places. Users whose day
starts at 7 or ends at 19 see availability that does not match their life,
and there is no way to change it.

Current hardcoded sites:

| Site | Form |
| --- | --- |
| `OpenTime/Services/CalendarManager.swift:16-17` | `var workStartHour = 9` / `var workEndHour = 17` |
| `MessagesExtension/CalendarHelper.swift:50-51` | `private let workStart = 9` / `workEnd = 17` |
| `ShareExtension/ShareCalendarHelper.swift:50-51` | same |
| `OpenTime/Intents/IntentCalendarHelper.swift:19-20` | same |
| `OpenTimeWatch/WatchCalendarHelper.swift:92-93` | same |
| `CalendarWidget/CalendarWidget.swift:70` | implicit: relies on `AvailabilityEngine` default args |
| `OpenTime/LiveActivity/LiveActivityManager.swift:22,96-97` | `bySettingHour: 9` / `17`, plus literal string `"5:00 PM"` |

## Scope

Whole hours only, one window applied to every weekday. No minutes, no
per-day schedules. The engine already takes `Int` hours, so this is the
change that fits the existing shape.

## Storage

New shared unit `OpenTimeUI/Sources/OpenTimeUI/Settings/WorkHours.swift`,
modeled directly on the existing `CalendarSelection`:

- App Group `group.com.jamestannahill.CalendarAvailability`
- Keys `workStartHour`, `workEndHour` (Int)
- `groupDefaults()` falls back to `.standard` when the group container is
  unavailable, so reads never crash

API:

```swift
public enum WorkHours {
    public static func current(defaults: UserDefaults? = nil) -> (start: Int, end: Int)
    public static func set(start: Int, end: Int, defaults: UserDefaults? = nil)
    static func sanitize(start: Int?, end: Int?) -> (start: Int, end: Int)  // pure core
}
```

`sanitize` clamps both values to `0...23` and returns the 9/17 default
whenever the pair is missing, non-numeric, or `start >= end`. Same
philosophy as `CalendarSelection`: a stored value that cannot produce a
sensible window degrades to the known-good default rather than to a wrong
one. Missing keys therefore mean existing users see no behavior change.

`AvailabilityEngine`'s `workStartHour: Int = 9` / `workEndHour: Int = 17`
default arguments stay as they are. They are a library default, not the
app's source of truth; every call site starts passing explicitly.

## Call site changes

- `CalendarManager.workStartHour` / `workEndHour` become computed
  properties reading `WorkHours.current()`.
- `MessagesExtension`, `ShareExtension`, `IntentCalendarHelper`: the two
  `let` constants become `WorkHours.current()` reads.
- `CalendarWidget`: passes `workStartHour:` / `workEndHour:` explicitly
  from `WorkHours.current()` instead of relying on the engine defaults.
- `LiveActivityManager`: both the `bySettingHour:` calls and the
  `workdayEnd` attribute string derive from the setting. The string uses
  the same formatter the rest of the app uses for slot times, so a 19:00
  end renders as `7:00 PM`.
- `OpenTimeWatch/WatchCalendarHelper`: reads the watch's own
  `UserDefaults.standard` under the same keys, populated by sync (below).

## UI

New `OpenTime/Views/WorkHoursView.swift`, styled after
`CalendarSelectionView`, presented as a sheet from a "Work Hours" item
added to the existing overflow menu in `ContentView` next to "Calendars"
and "Refresh".

- Two wheel pickers, Start and End, hours only, rendered with the app's
  existing time formatting.
- The End picker offers only hours strictly after the selected Start, so
  an invalid window cannot be entered through the UI. `sanitize` remains
  the backstop for values that arrive any other way.
- On dismiss, run the same trio the Calendars sheet runs:
  `manager.refresh()`, `WidgetCenter.shared.reloadAllTimelines()`,
  `liveActivity.updateNow()`. Additionally push the new pair to the watch.

## Watch sync

There is no WatchConnectivity anywhere in the repo today, so this is new
on both sides. App Group defaults do not cross from iPhone to watch, which
is the same reason calendar selection is still `calendars: nil` on the
watch.

New `WorkHoursSync`, a thin wrapper over a `WCSession` singleton activated
at launch on both the phone and the watch.

- Phone: on save, write `["workStartHour": x, "workEndHour": y]` to
  `session.applicationContext`.
- Watch: implement `didReceiveApplicationContext`, write the pair into the
  watch's own `UserDefaults.standard` under the same keys, then refresh.

`applicationContext` is chosen over `transferUserInfo` because it is
latest-state-wins, so rapid edits do not queue stale values, and because
the system retains the most recent context and delivers it when the watch
app next activates. A watch that was off, unpaired, or not running at edit
time catches up on its own with no request/reply handshake.

Failure mode: if a context never arrives, the watch reads empty defaults
and gets 9/17. The fail-safe is unchanged.

## Testing

Unit tests in the `OpenTimeUI` package, against the pure cores:

- `sanitize`: missing keys, out-of-range values, `start == end`,
  `start > end`, valid pair passthrough.
- `WorkHours.current` / `set` round-trip through an injected
  `UserDefaults` instance.
- Context dictionary encode/decode for `WorkHoursSync`, including a
  malformed dictionary falling back to the default.
- `AvailabilityEngine` free-slot output for a non-default window
  (for example 7-19), confirming the window is actually honored rather
  than the defaults silently applying.

The `WCSession` plumbing itself is not unit-testable and a simulator run
does not exercise it. Verifying that a work-hours edit on the phone
reaches the watch is a manual step on a real paired device, and will be
listed as such rather than treated as covered.

## Out of scope

- Minute granularity, per-weekday schedules, timezone handling.
- Weekend inclusion (`CalendarManager.includeWeekends` already exists and
  is unrelated).
- Syncing calendar selection to the watch, which remains a separate known
  gap.

## Provisioning note

No new entitlements are added. `WorkHours` reuses the App Group already
registered on the four iOS targets. The watch target gains the
WatchConnectivity framework, which requires no entitlement, but the first
device build should still be run from Xcode or with
`-allowProvisioningUpdates`.

# Calendar Selection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users exclude calendars from availability across all iOS surfaces (app, widget, iMessage/share extensions, Live Activity) via a picker sheet backed by App Group defaults.

**Architecture:** A shared `CalendarSelection` enum in the OpenTimeUI package owns "which calendars count": it persists an exclude-list of `calendarIdentifier`s in App Group `UserDefaults` and converts it to the `[EKCalendar]?` argument every EventKit query site passes to `predicateForEvents`. `nil` (nothing excluded) preserves today's behavior bit-for-bit. A SwiftUI sheet in the main app edits the set.

**Tech Stack:** Swift 6 / SwiftUI, EventKit, WidgetKit, SwiftPM (OpenTimeUI package), XCTest.

## Global Constraints

- Spec: `dev-docs/superpowers/specs/2026-07-22-calendar-selection-design.md`.
- App Group ID is exactly `group.com.jamestannahill.CalendarAvailability`. Bundle IDs must NOT change.
- Defaults key is exactly `excludedCalendarIDs` (`[String]`).
- Exclude-list semantics: missing/empty = all calendars; new calendars included by default; stale IDs harmless.
- Watch target (`OpenTimeWatch`) is untouched but must still compile.
- Repo root: `/Users/jamest/open-time`. Package dir: `OpenTimeUI/`.
- No em-dashes in any file content (user house rule).

---

### Task 1: `CalendarSelection` shared unit (TDD)

**Files:**
- Create: `OpenTimeUI/Sources/OpenTimeUI/Calendar/CalendarSelection.swift`
- Test: `OpenTimeUI/Tests/OpenTimeUITests/CalendarSelectionTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces (used by Tasks 3 and 4):
  - `CalendarSelection.appGroupID: String`
  - `CalendarSelection.excludedIDs(defaults: UserDefaults? = nil) -> Set<String>`
  - `CalendarSelection.setExcludedIDs(_ ids: Set<String>, defaults: UserDefaults? = nil)`
  - `CalendarSelection.calendars(for store: EKEventStore, defaults: UserDefaults? = nil) -> [EKCalendar]?`
  - internal pure core `CalendarSelection.includedIDs(all: [String], excluded: Set<String>) -> [String]?`

- [ ] **Step 1: Write the failing tests**

```swift
// OpenTimeUI/Tests/OpenTimeUITests/CalendarSelectionTests.swift
import XCTest
@testable import OpenTimeUI

final class CalendarSelectionTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suite = "calendar-selection-tests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    // MARK: - Pure filtering core

    func testNoExclusionsMeansNil() {
        XCTAssertNil(CalendarSelection.includedIDs(all: ["a", "b"], excluded: []))
    }

    func testExclusionFilters() {
        XCTAssertEqual(CalendarSelection.includedIDs(all: ["a", "b", "c"], excluded: ["b"]), ["a", "c"])
    }

    func testStaleExclusionsOnlyMeansNil() {
        // Excluded IDs that no longer exist should not force a filtered query.
        XCTAssertNil(CalendarSelection.includedIDs(all: ["a", "b"], excluded: ["gone"]))
    }

    func testAllExcludedFallsBackToNil() {
        // An empty calendar list would make every hour look free; query all instead.
        XCTAssertNil(CalendarSelection.includedIDs(all: ["a", "b"], excluded: ["a", "b"]))
    }

    // MARK: - Persistence

    func testRoundTrip() {
        CalendarSelection.setExcludedIDs(["x", "y"], defaults: defaults)
        XCTAssertEqual(CalendarSelection.excludedIDs(defaults: defaults), ["x", "y"])
    }

    func testMissingKeyReadsEmpty() {
        XCTAssertEqual(CalendarSelection.excludedIDs(defaults: defaults), [])
    }

    func testEmptySetRemovesKey() {
        CalendarSelection.setExcludedIDs(["x"], defaults: defaults)
        CalendarSelection.setExcludedIDs([], defaults: defaults)
        XCTAssertNil(defaults.object(forKey: "excludedCalendarIDs"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/jamest/open-time/OpenTimeUI && swift test --filter CalendarSelectionTests`
Expected: compile error, `cannot find 'CalendarSelection' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// OpenTimeUI/Sources/OpenTimeUI/Calendar/CalendarSelection.swift
import EventKit
import Foundation

/// Which calendars count toward availability, shared by the app, widget,
/// and extensions through App Group defaults.
///
/// Exclude-list semantics: an empty set means all calendars, and calendars
/// added later are included by default. The safe failure mode for an
/// availability app is looking busy, never falsely free, so whenever the
/// stored exclusions cannot produce a sensible non-empty subset the
/// query falls back to all calendars (nil).
public enum CalendarSelection {

    public static let appGroupID = "group.com.jamestannahill.CalendarAvailability"
    static let excludedKey = "excludedCalendarIDs"

    /// Falls back to standard defaults if the group container is
    /// unavailable (e.g. entitlement missing) so reads never crash.
    static func groupDefaults() -> UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    public static func excludedIDs(defaults: UserDefaults? = nil) -> Set<String> {
        let d = defaults ?? groupDefaults()
        return Set(d.stringArray(forKey: excludedKey) ?? [])
    }

    public static func setExcludedIDs(_ ids: Set<String>, defaults: UserDefaults? = nil) {
        let d = defaults ?? groupDefaults()
        if ids.isEmpty {
            d.removeObject(forKey: excludedKey)
        } else {
            d.set(Array(ids).sorted(), forKey: excludedKey)
        }
    }

    /// The value to pass as the `calendars:` argument of
    /// `predicateForEvents(withStart:end:calendars:)`. Nil means
    /// "query all calendars" and preserves pre-feature behavior.
    public static func calendars(for store: EKEventStore, defaults: UserDefaults? = nil) -> [EKCalendar]? {
        let all = store.calendars(for: .event)
        guard let keep = includedIDs(
            all: all.map(\.calendarIdentifier),
            excluded: excludedIDs(defaults: defaults)
        ) else { return nil }
        let keepSet = Set(keep)
        return all.filter { keepSet.contains($0.calendarIdentifier) }
    }

    /// Pure core, order-preserving. Nil = no filtering: returned when
    /// nothing is excluded, when every exclusion is stale, and when
    /// exclusion would leave zero calendars.
    static func includedIDs(all: [String], excluded: Set<String>) -> [String]? {
        guard !excluded.isEmpty else { return nil }
        let kept = all.filter { !excluded.contains($0) }
        if kept.isEmpty || kept.count == all.count { return nil }
        return kept
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/jamest/open-time/OpenTimeUI && swift test`
Expected: all suites pass, 0 failures (7 new tests included).

- [ ] **Step 5: Commit**

```bash
cd /Users/jamest/open-time
git add OpenTimeUI/Sources/OpenTimeUI/Calendar/CalendarSelection.swift OpenTimeUI/Tests/OpenTimeUITests/CalendarSelectionTests.swift
git commit -m "Add CalendarSelection shared unit with App Group exclude-list"
```

---

### Task 2: App Group entitlements for the 4 iOS targets

**Files:**
- Create: `OpenTime/OpenTime.entitlements`
- Create: `CalendarWidget/CalendarWidget.entitlements`
- Create: `MessagesExtension/MessagesExtension.entitlements`
- Create: `ShareExtension/ShareExtension.entitlements`
- Modify: `OpenTime.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: nothing.
- Produces: the App Group container `group.com.jamestannahill.CalendarAvailability` becomes readable/writable by all 4 iOS targets, which Task 1's `groupDefaults()` relies on at runtime.

- [ ] **Step 1: Create the four entitlements files**

All four files have identical content (paths above):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.application-groups</key>
	<array>
		<string>group.com.jamestannahill.CalendarAvailability</string>
	</array>
</dict>
</plist>
```

- [ ] **Step 2: Wire entitlements into build settings**

Edit `OpenTime.xcodeproj/project.pbxproj` with the Edit tool, `replace_all: true` for each pair (each hits the target's Debug AND Release configurations; the trailing semicolons keep bundle-ID matches exact):

1. Widget (this string exists exactly twice, both in CalendarWidget configs):
   - old: `CODE_SIGN_ENTITLEMENTS = "";`
   - new: `CODE_SIGN_ENTITLEMENTS = CalendarWidget/CalendarWidget.entitlements;`
2. Main app:
   - old: `PRODUCT_BUNDLE_IDENTIFIER = com.jamestannahill.CalendarAvailability;`
   - new: `CODE_SIGN_ENTITLEMENTS = OpenTime/OpenTime.entitlements;\n\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.jamestannahill.CalendarAvailability;`
     (literal newline + four tabs, matching pbxproj indentation)
3. Messages extension:
   - old: `PRODUCT_BUNDLE_IDENTIFIER = com.jamestannahill.CalendarAvailability.MessagesExtension;`
   - new: `CODE_SIGN_ENTITLEMENTS = MessagesExtension/MessagesExtension.entitlements;\n\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.jamestannahill.CalendarAvailability.MessagesExtension;`
4. Share extension:
   - old: `PRODUCT_BUNDLE_IDENTIFIER = com.jamestannahill.CalendarAvailability.ShareExtension;`
   - new: `CODE_SIGN_ENTITLEMENTS = ShareExtension/ShareExtension.entitlements;\n\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.jamestannahill.CalendarAvailability.ShareExtension;`

Do NOT touch the watch target (`...watchapp`). Entitlements files need no PBXFileReference; `CODE_SIGN_ENTITLEMENTS` is a plain path setting.

- [ ] **Step 3: Verify wiring**

Run: `grep -c "CODE_SIGN_ENTITLEMENTS" OpenTime.xcodeproj/project.pbxproj`
Expected: `8` (4 targets x Debug/Release).

Run: `grep -A2 "com.apple.security.application-groups" OpenTime/OpenTime.entitlements`
Expected: shows the group ID string.

- [ ] **Step 4: Build to verify the project still compiles**

Run: `cd /Users/jamest/open-time && xcodebuild -project OpenTime.xcodeproj -scheme OpenTime -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`. (Simulator builds don't validate provisioning; the first DEVICE build must run from Xcode or with `-allowProvisioningUpdates` so automatic signing registers the App Group with the developer portal.)

- [ ] **Step 5: Commit**

```bash
git add OpenTime/OpenTime.entitlements CalendarWidget/CalendarWidget.entitlements MessagesExtension/MessagesExtension.entitlements ShareExtension/ShareExtension.entitlements OpenTime.xcodeproj/project.pbxproj
git commit -m "Add App Group entitlements to app, widget, and extensions"
```

---

### Task 3: Route the 6 iOS query sites through `CalendarSelection`

**Files:**
- Modify: `OpenTime/Services/CalendarManager.swift:101`
- Modify: `OpenTime/Intents/IntentCalendarHelper.swift:83`
- Modify: `OpenTime/LiveActivity/LiveActivityManager.swift:122`
- Modify: `ShareExtension/ShareCalendarHelper.swift:83`
- Modify: `MessagesExtension/CalendarHelper.swift:83`
- Modify: `CalendarWidget/CalendarWidget.swift:66`

**Interfaces:**
- Consumes: `CalendarSelection.calendars(for:)` from Task 1 and the App Group from Task 2.
- Produces: every iOS availability computation honors the exclude-list. `OpenTimeWatch/WatchCalendarHelper.swift` intentionally stays on `calendars: nil`.

- [ ] **Step 1: Apply the same one-line change at all 6 sites**

Every file already has `import OpenTimeUI` and a local `store: EKEventStore`. In each of the 5 single-line sites the predicate line becomes:

```swift
let predicate = store.predicateForEvents(withStart: /* existing args unchanged */, end: /* unchanged */, calendars: CalendarSelection.calendars(for: store))
```

i.e. replace exactly `calendars: nil` with `calendars: CalendarSelection.calendars(for: store)` in:
- `OpenTime/Services/CalendarManager.swift:101`
- `OpenTime/Intents/IntentCalendarHelper.swift:83`
- `ShareExtension/ShareCalendarHelper.swift:83`
- `MessagesExtension/CalendarHelper.swift:83`
- `CalendarWidget/CalendarWidget.swift:66`

In `OpenTime/LiveActivity/LiveActivityManager.swift` the call is multi-line; change only the last argument:

```swift
let predicate = store.predicateForEvents(
    withStart: now,
    end: we,
    calendars: CalendarSelection.calendars(for: store)
)
```

- [ ] **Step 2: Verify no iOS site still passes nil**

Run: `grep -rn "calendars: nil" /Users/jamest/open-time --include="*.swift"`
Expected: exactly one hit, `OpenTimeWatch/WatchCalendarHelper.swift:118` (the documented watch gap).

- [ ] **Step 3: Build all schemes**

Run: `cd /Users/jamest/open-time && xcodebuild -project OpenTime.xcodeproj -scheme OpenTime -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **` (this scheme builds the widget and both extensions as embedded targets; a `calendars: nil` regression in any of them fails here).

Run: `cd /Users/jamest/open-time/OpenTimeUI && swift test 2>&1 | grep -cE "failed"`
Expected: `0`.

- [ ] **Step 4: Commit**

```bash
cd /Users/jamest/open-time
git add OpenTime/Services/CalendarManager.swift OpenTime/Intents/IntentCalendarHelper.swift OpenTime/LiveActivity/LiveActivityManager.swift ShareExtension/ShareCalendarHelper.swift MessagesExtension/CalendarHelper.swift CalendarWidget/CalendarWidget.swift
git commit -m "Honor calendar exclude-list at all six iOS query sites"
```

---

### Task 4: Calendars picker sheet + MORE menu entry

**Files:**
- Create: `OpenTime/Views/CalendarSelectionView.swift`
- Modify: `OpenTime/ContentView.swift` (imports; state var near line 39; MORE menu around line 456; sheet modifiers around line 73)

**Interfaces:**
- Consumes: `CalendarSelection.excludedIDs()` / `setExcludedIDs(_:)` from Task 1; `manager.store` (an `EKEventStore` on `CalendarManager`); `liveActivity.updateNow()` (existing).
- Produces: user-facing feature; nothing downstream.

- [ ] **Step 1: Create the picker view**

```swift
// OpenTime/Views/CalendarSelectionView.swift
import EventKit
import OpenTimeUI
import SwiftUI

/// Toggle sheet for which calendars count toward availability.
/// Grouped by account (EKSource). The last enabled calendar cannot be
/// switched off so availability can never be computed from zero calendars.
struct CalendarSelectionView: View {
    let store: EKEventStore
    @Environment(\.dismiss) private var dismiss
    @State private var excluded: Set<String> = []

    private var allCalendars: [EKCalendar] {
        store.calendars(for: .event)
    }

    private var groups: [(source: String, calendars: [EKCalendar])] {
        let bySource = Dictionary(grouping: allCalendars) { $0.source?.title ?? "Other" }
        return bySource.keys.sorted().map { key in
            (key, bySource[key]!.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending })
        }
    }

    private var includedCount: Int {
        allCalendars.filter { !excluded.contains($0.calendarIdentifier) }.count
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(groups, id: \.source) { group in
                    Section {
                        ForEach(group.calendars, id: \.calendarIdentifier) { cal in
                            Toggle(isOn: binding(for: cal)) {
                                Text(cal.title)
                                    .font(Theme.Font.display(size: 14, weight: .regular))
                                    .foregroundStyle(Theme.fg)
                            }
                            .tint(Theme.accent)
                            .disabled(isLastEnabled(cal))
                        }
                    } header: {
                        Text(group.source.uppercased())
                            .font(Theme.Font.display(size: 10, weight: .regular))
                            .kerning(1.8)
                            .foregroundStyle(Theme.muted)
                    }
                }
            }
            .navigationTitle("Calendars")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear { excluded = CalendarSelection.excludedIDs() }
    }

    private func binding(for cal: EKCalendar) -> Binding<Bool> {
        Binding(
            get: { !excluded.contains(cal.calendarIdentifier) },
            set: { include in
                if include {
                    excluded.remove(cal.calendarIdentifier)
                } else {
                    excluded.insert(cal.calendarIdentifier)
                }
                CalendarSelection.setExcludedIDs(excluded)
            }
        )
    }

    private func isLastEnabled(_ cal: EKCalendar) -> Bool {
        !excluded.contains(cal.calendarIdentifier) && includedCount == 1
    }
}
```

- [ ] **Step 2: Wire into ContentView**

a. Add `import WidgetKit` to the import block at the top (currently `SwiftUI`, `ActivityKit`, `UIKit`, `OpenTimeUI`).

b. Add state near the other `@State`/`@AppStorage` vars (around line 39):

```swift
@State private var showCalendarPicker = false
```

c. In the MORE menu, insert between the "Slot Duration" Picker's closing brace and the Refresh `Button {`:

```swift
Button {
    showCalendarPicker = true
} label: {
    Label("Calendars", systemImage: "calendar")
}
```

d. After the existing `.sheet(item: $eventEditSlot) { ... }` block (around line 73), add:

```swift
.sheet(isPresented: $showCalendarPicker, onDismiss: {
    manager.refresh()
    WidgetCenter.shared.reloadAllTimelines()
    liveActivity.updateNow()
}) {
    CalendarSelectionView(store: manager.store)
}
```

(Refreshing unconditionally on dismiss is deliberate: it is cheap and avoids dirty-tracking state.)

- [ ] **Step 3: Build**

Run: `cd /Users/jamest/open-time && xcodebuild -project OpenTime.xcodeproj -scheme OpenTime -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Manual smoke test in the simulator**

Launch the app in an iPhone simulator, grant calendar access, then: MORE menu shows "Calendars"; the sheet lists calendars grouped by account; toggling one off and tapping Done removes its events' effect from availability; with a single calendar left enabled its toggle is disabled; re-enabling restores prior behavior. Relaunch the app: the selection persists.

- [ ] **Step 5: Commit**

```bash
cd /Users/jamest/open-time
git add OpenTime/Views/CalendarSelectionView.swift OpenTime/ContentView.swift
git commit -m "Add calendar picker sheet wired to MORE menu"
```

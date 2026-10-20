# Configurable Work Hours Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user choose the start and end hour of their workday, and have every OpenTime surface honor it instead of hardcoded 9-5.

**Architecture:** A shared `WorkHours` unit in the `OpenTimeUI` package stores a sanitized start/end hour pair in the existing App Group, exactly mirroring how `CalendarSelection` stores excluded calendar IDs. The app, widget, iMessage extension, Share extension, Intents helper, and Live Activity all read it. The watch is a separate device that cannot see App Group defaults, so a new `WorkHoursSync` pushes the pair over WatchConnectivity `applicationContext` into the watch's own `UserDefaults.standard`.

**Tech Stack:** Swift 6.2, SwiftUI, EventKit, ActivityKit, WatchConnectivity, swift-testing plus XCTest in the `OpenTimeUI` package.

## Global Constraints

- App Group identifier is `group.com.jamestannahill.CalendarAvailability`. Do not introduce a new one.
- Defaults keys are exactly `workStartHour` and `workEndHour`, Int values.
- The default window is 9 to 17. Missing or unusable stored values must produce exactly this, so existing users see no behavior change.
- `AvailabilityEngine`'s `workStartHour: Int = 9` / `workEndHour: Int = 17` default arguments stay unchanged. They are a library default; call sites start passing explicitly.
- `OpenTimeUI` is linked to four targets only: the main app, `CalendarWidget`, `MessagesExtension`, `ShareExtension`. It is NOT linked to `OpenTimeWatch`. The watch target must not import `OpenTimeUI`; it keeps its own small copy, the way `WatchAvailabilityEngine` already duplicates the engine.
- Bundle IDs must stay `com.jamestannahill.CalendarAvailability[.*]`.
- No em-dashes and no emoji in any file content, including comments and commit messages.
- Package tests run with `cd OpenTimeUI && swift test`. They are green before this work starts (29 tests, 3 suites, plus the XCTest suites).
- Whole hours only. No minutes, no per-weekday schedules, no timezone work.

---

### Task 1: `WorkHours` shared storage unit

**Files:**
- Create: `OpenTimeUI/Sources/OpenTimeUI/Settings/WorkHours.swift`
- Create: `OpenTimeUI/Tests/OpenTimeUITests/WorkHoursTests.swift`
- Modify: `OpenTimeUI/Tests/OpenTimeUITests/AvailabilityEngineTests.swift` (append one test)

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `WorkHours.current(defaults: UserDefaults? = nil) -> (start: Int, end: Int)`
  - `WorkHours.set(start: Int, end: Int, defaults: UserDefaults? = nil)`
  - `WorkHours.sanitize(start: Int?, end: Int?) -> (start: Int, end: Int)` (internal, testable)
  - `WorkHours.defaultStart = 9`, `WorkHours.defaultEnd = 17` (public)

- [ ] **Step 1: Write the failing tests**

Create `OpenTimeUI/Tests/OpenTimeUITests/WorkHoursTests.swift`. This follows the `CalendarSelectionTests` pattern: a throwaway `UserDefaults` suite, wiped in `setUp` and `tearDown`.

```swift
import XCTest
@testable import OpenTimeUI

final class WorkHoursTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suite = "work-hours-tests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    // MARK: - Pure sanitizing core

    func testValidPairPassesThrough() {
        let r = WorkHours.sanitize(start: 7, end: 19)
        XCTAssertEqual(r.start, 7)
        XCTAssertEqual(r.end, 19)
    }

    func testMissingValuesUseDefault() {
        let r = WorkHours.sanitize(start: nil, end: nil)
        XCTAssertEqual(r.start, 9)
        XCTAssertEqual(r.end, 17)
    }

    func testPartiallyMissingUsesDefault() {
        // A half-written pair is not a window; fall back rather than guess.
        let r = WorkHours.sanitize(start: 7, end: nil)
        XCTAssertEqual(r.start, 9)
        XCTAssertEqual(r.end, 17)
    }

    func testInvertedRangeUsesDefault() {
        let r = WorkHours.sanitize(start: 19, end: 7)
        XCTAssertEqual(r.start, 9)
        XCTAssertEqual(r.end, 17)
    }

    func testEqualBoundsUseDefault() {
        // A zero-width window would make every day look fully busy.
        let r = WorkHours.sanitize(start: 12, end: 12)
        XCTAssertEqual(r.start, 9)
        XCTAssertEqual(r.end, 17)
    }

    func testOutOfRangeValuesUseDefault() {
        let low = WorkHours.sanitize(start: -3, end: 17)
        XCTAssertEqual(low.start, 9)
        XCTAssertEqual(low.end, 17)

        let high = WorkHours.sanitize(start: 9, end: 24)
        XCTAssertEqual(high.start, 9)
        XCTAssertEqual(high.end, 17)
    }

    func testFullRangeBoundsAreAllowed() {
        let r = WorkHours.sanitize(start: 0, end: 23)
        XCTAssertEqual(r.start, 0)
        XCTAssertEqual(r.end, 23)
    }

    // MARK: - Persistence

    func testEmptyDefaultsReadAsDefaultWindow() {
        let r = WorkHours.current(defaults: defaults)
        XCTAssertEqual(r.start, 9)
        XCTAssertEqual(r.end, 17)
    }

    func testRoundTrip() {
        WorkHours.set(start: 6, end: 14, defaults: defaults)
        let r = WorkHours.current(defaults: defaults)
        XCTAssertEqual(r.start, 6)
        XCTAssertEqual(r.end, 14)
    }

    func testSetRejectsInvalidPairAndStoresDefault() {
        WorkHours.set(start: 20, end: 4, defaults: defaults)
        let r = WorkHours.current(defaults: defaults)
        XCTAssertEqual(r.start, 9)
        XCTAssertEqual(r.end, 17)
    }

    func testCorruptStoredValuesReadAsDefault() {
        defaults.set(30, forKey: "workStartHour")
        defaults.set(31, forKey: "workEndHour")
        let r = WorkHours.current(defaults: defaults)
        XCTAssertEqual(r.start, 9)
        XCTAssertEqual(r.end, 17)
    }
}
```

Then append this test to `OpenTimeUI/Tests/OpenTimeUITests/AvailabilityEngineTests.swift`. Read the top of that file first and match its existing style: if the file uses swift-testing (`@Test` / `#expect`), write it in that style instead of XCTest, and put it inside the existing suite. The XCTest form is shown here:

```swift
    func testNonDefaultWindowIsHonored() {
        // Proves the engine actually uses the passed window rather than
        // silently applying its 9-17 defaults.
        let cal = Calendar.current
        let day = cal.startOfDay(for: Date())
        let free = AvailabilityEngine.freeIntervals(
            events: [],
            on: day,
            workStartHour: 7,
            workEndHour: 19,
            calendar: cal
        )
        XCTAssertEqual(free.count, 1)
        XCTAssertEqual(cal.component(.hour, from: free[0].start), 7)
        XCTAssertEqual(cal.component(.hour, from: free[0].end), 19)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd OpenTimeUI && swift test`
Expected: compile failure, `cannot find 'WorkHours' in scope`. The appended engine test may already pass, which is fine; it is a regression guard.

- [ ] **Step 3: Write the implementation**

Create `OpenTimeUI/Sources/OpenTimeUI/Settings/WorkHours.swift`:

```swift
import Foundation

/// The user's workday window, shared by the app, widget, and extensions
/// through App Group defaults.
///
/// Whole hours only. The safe failure mode for an availability app is
/// looking busy, never falsely free, so whenever the stored pair cannot
/// produce a sensible window the read falls back to the 9-17 default
/// rather than to a partially applied one. That also means users who
/// never open the picker see exactly the previous behavior.
public enum WorkHours {

    public static let defaultStart = 9
    public static let defaultEnd = 17

    public static let appGroupID = "group.com.jamestannahill.CalendarAvailability"
    static let startKey = "workStartHour"
    static let endKey = "workEndHour"

    /// Falls back to standard defaults if the group container is
    /// unavailable (e.g. entitlement missing) so reads never crash.
    static func groupDefaults() -> UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    public static func current(defaults: UserDefaults? = nil) -> (start: Int, end: Int) {
        let d = defaults ?? groupDefaults()
        return sanitize(
            start: d.object(forKey: startKey) as? Int,
            end: d.object(forKey: endKey) as? Int
        )
    }

    public static func set(start: Int, end: Int, defaults: UserDefaults? = nil) {
        let d = defaults ?? groupDefaults()
        let clean = sanitize(start: start, end: end)
        d.set(clean.start, forKey: startKey)
        d.set(clean.end, forKey: endKey)
    }

    /// Pure core. Nil, out-of-range, or non-increasing pairs all collapse
    /// to the default window.
    static func sanitize(start: Int?, end: Int?) -> (start: Int, end: Int) {
        guard let start, let end,
              (0...23).contains(start),
              (0...23).contains(end),
              start < end
        else { return (defaultStart, defaultEnd) }
        return (start, end)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd OpenTimeUI && swift test`
Expected: PASS, including all previously green tests.

- [ ] **Step 5: Commit**

```bash
git add OpenTimeUI/Sources/OpenTimeUI/Settings/WorkHours.swift \
        OpenTimeUI/Tests/OpenTimeUITests/WorkHoursTests.swift \
        OpenTimeUI/Tests/OpenTimeUITests/AvailabilityEngineTests.swift
git commit -m "Add shared WorkHours setting backed by App Group defaults"
```

---

### Task 2: Read `WorkHours` on the four iOS availability surfaces

**Files:**
- Modify: `OpenTime/Services/CalendarManager.swift:16-17`
- Modify: `MessagesExtension/CalendarHelper.swift:50-51`
- Modify: `ShareExtension/ShareCalendarHelper.swift:50-51`
- Modify: `OpenTime/Intents/IntentCalendarHelper.swift:19-20`
- Modify: `CalendarWidget/CalendarWidget.swift:70`

**Interfaces:**
- Consumes: `WorkHours.current()` from Task 1.
- Produces: nothing new. Behavior only.

There is no unit test in this task: these are Xcode targets outside the Swift package and have no test target. The build is the check, and the behavior is covered by Task 1's tests plus the manual verification in Task 8.

- [ ] **Step 1: Replace the stored constants in `CalendarManager`**

In `OpenTime/Services/CalendarManager.swift`, replace lines 16-17:

```swift
    var workStartHour = 9
    var workEndHour = 17
```

with computed reads so a change made in the picker takes effect on the next refresh with no extra plumbing:

```swift
    var workStartHour: Int { WorkHours.current().start }
    var workEndHour: Int { WorkHours.current().end }
```

`computeAvailability` at line 119 already passes these into the engine, so no other change is needed in this file. The file already has `import OpenTimeUI`.

- [ ] **Step 2: Replace the constants in the three helpers**

In each of `MessagesExtension/CalendarHelper.swift`, `ShareExtension/ShareCalendarHelper.swift`, and `OpenTime/Intents/IntentCalendarHelper.swift`, replace the pair:

```swift
    private let workStart = 9
    private let workEnd = 17
```

with:

```swift
    private var workStart: Int { WorkHours.current().start }
    private var workEnd: Int { WorkHours.current().end }
```

In `IntentCalendarHelper.swift` the two constants are declared `nonisolated private let`. Keep that isolation attribute on the computed form:

```swift
    nonisolated private var workStart: Int { WorkHours.current().start }
    nonisolated private var workEnd: Int { WorkHours.current().end }
```

Each of these three files already calls `AvailabilityEngine.freeIntervals(... workStartHour: workStart, workEndHour: workEnd)`, so the call sites are unchanged. Confirm each file has `import OpenTimeUI` at the top and add it if missing.

- [ ] **Step 3: Make the widget pass the window explicitly**

In `CalendarWidget/CalendarWidget.swift` around line 70, the widget currently relies on the engine's default arguments:

```swift
        let free = AvailabilityEngine.freeIntervals(events: events, on: date)
```

Replace with an explicit read. Hoist the read above the `dates.map` so it is read once per timeline build rather than once per day:

```swift
    let hours = WorkHours.current()
    let days = dates.map { label, date in
```

and inside the closure:

```swift
        let free = AvailabilityEngine.freeIntervals(
            events: events,
            on: date,
            workStartHour: hours.start,
            workEndHour: hours.end
        )
```

- [ ] **Step 4: Build the affected targets**

Run:

```bash
xcodebuild -project OpenTime.xcodeproj -scheme OpenTime \
  -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -20
```

Expected: `BUILD SUCCEEDED`. If the named simulator does not exist, list options with `xcrun simctl list devices available` and substitute one.

- [ ] **Step 5: Commit**

```bash
git add OpenTime/Services/CalendarManager.swift \
        MessagesExtension/CalendarHelper.swift \
        ShareExtension/ShareCalendarHelper.swift \
        OpenTime/Intents/IntentCalendarHelper.swift \
        CalendarWidget/CalendarWidget.swift
git commit -m "Read configurable work hours on app, widget, and extensions"
```

---

### Task 3: Live Activity honors the configured window

**Files:**
- Modify: `OpenTime/LiveActivity/LiveActivityManager.swift:22, 75-81, 96-105`

**Interfaces:**
- Consumes: `WorkHours.current()` from Task 1, `TimeFormat.time(_:)` from `OpenTimeUI`.
- Produces: nothing new.

This file has three separate hardcodings: the `workdayEnd` display string, the off-hours guard, and the window used to compute state. All three must move together or the Live Activity will disagree with itself.

- [ ] **Step 1: Derive the `workdayEnd` attribute string**

At line 22, replace:

```swift
        let attributes = AvailabilityActivityAttributes(workdayEnd: "5:00 PM")
```

with a value derived from the setting, using the same formatter the rest of the app uses for slot times so a 19:00 end renders as `7:00 PM`:

```swift
        let attributes = AvailabilityActivityAttributes(workdayEnd: Self.workdayEndLabel)
```

and add this helper to the type:

```swift
    private static var workdayEndLabel: String {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let end = cal.date(bySettingHour: WorkHours.current().end, minute: 0, second: 0, of: today)!
        return TimeFormat.time(end)
    }
```

- [ ] **Step 2: Derive the off-hours guard**

Replace the body of `isOffHoursOrWeekend` at lines 75-81:

```swift
    private static var isOffHoursOrWeekend: Bool {
        let cal = Calendar.current
        let now = Date()
        let weekday = cal.component(.weekday, from: now)
        let hour = cal.component(.hour, from: now)
        return weekday == 1 || weekday == 7 || hour >= 17 || hour < 9
    }
```

with:

```swift
    private static var isOffHoursOrWeekend: Bool {
        let cal = Calendar.current
        let now = Date()
        let weekday = cal.component(.weekday, from: now)
        let hour = cal.component(.hour, from: now)
        let hours = WorkHours.current()
        return weekday == 1 || weekday == 7 || hour >= hours.end || hour < hours.start
    }
```

- [ ] **Step 3: Derive the computed window and its off-hours copy**

In `computeCurrentState()` at lines 96-105, replace:

```swift
        let ws = cal.date(bySettingHour: 9, minute: 0, second: 0, of: today)!
        let we = cal.date(bySettingHour: 17, minute: 0, second: 0, of: today)!
```

with:

```swift
        let hours = WorkHours.current()
        let ws = cal.date(bySettingHour: hours.start, minute: 0, second: 0, of: today)!
        let we = cal.date(bySettingHour: hours.end, minute: 0, second: 0, of: today)!
```

Then replace the hardcoded off-hours detail string in the same function:

```swift
                statusDetail: "Work hours: 9 AM - 5 PM",
```

with:

```swift
                statusDetail: "Work hours: \(TimeFormat.time(ws)) - \(TimeFormat.time(we))",
```

- [ ] **Step 4: Confirm no 9-5 literals remain in the file**

Run:

```bash
grep -n "bySettingHour: 9\|bySettingHour: 17\|5:00 PM\|9 AM" OpenTime/LiveActivity/LiveActivityManager.swift
```

Expected: no output.

- [ ] **Step 5: Build**

Run:

```bash
xcodebuild -project OpenTime.xcodeproj -scheme OpenTime \
  -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -20
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 6: Commit**

```bash
git add OpenTime/LiveActivity/LiveActivityManager.swift
git commit -m "Live Activity uses configured work hours for window, guard, and labels"
```

---

### Task 4: Work Hours picker sheet

**Files:**
- Create: `OpenTime/Views/WorkHoursView.swift`
- Modify: `OpenTime/ContentView.swift:33` (new `@State`), `:87` region (new `.sheet`), `:470-474` region (new menu button)

**Interfaces:**
- Consumes: `WorkHours.current()` and `WorkHours.set(start:end:)` from Task 1.
- Produces: `struct WorkHoursView: View` with an `onSaved: () -> Void` closure, called after the setting is written.

The new file must be added to the `OpenTime` target in Xcode. Creating the file on disk is not enough; if the build reports `cannot find 'WorkHoursView' in scope`, the file is not a target member.

- [ ] **Step 1: Create the view**

Create `OpenTime/Views/WorkHoursView.swift`, styled after `OpenTime/Views/CalendarSelectionView.swift`:

```swift
// OpenTime/Views/WorkHoursView.swift
import OpenTimeUI
import SwiftUI

/// Picker sheet for the start and end hour of the workday.
/// Whole hours only. The end picker offers only hours after the selected
/// start, so an invalid window cannot be entered here. `WorkHours.sanitize`
/// remains the backstop for values arriving any other way.
struct WorkHoursView: View {
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var start = WorkHours.defaultStart
    @State private var end = WorkHours.defaultEnd

    private var endOptions: [Int] { Array((start + 1)...23) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Start", selection: $start) {
                        ForEach(0...22, id: \.self) { hour in
                            Text(Self.label(hour)).tag(hour)
                        }
                    }
                    .pickerStyle(.wheel)
                } header: {
                    Text("START")
                        .font(Theme.Font.display(size: 10, weight: .regular))
                        .kerning(1.8)
                        .foregroundStyle(Theme.muted)
                }

                Section {
                    Picker("End", selection: $end) {
                        ForEach(endOptions, id: \.self) { hour in
                            Text(Self.label(hour)).tag(hour)
                        }
                    }
                    .pickerStyle(.wheel)
                } header: {
                    Text("END")
                        .font(Theme.Font.display(size: 10, weight: .regular))
                        .kerning(1.8)
                        .foregroundStyle(Theme.muted)
                }
            }
            .navigationTitle("Work Hours")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            let hours = WorkHours.current()
            start = hours.start
            end = hours.end
        }
        .onChange(of: start) { _, newStart in
            // Keep the window valid when the start moves past the end.
            if end <= newStart { end = min(newStart + 1, 23) }
            save()
        }
        .onChange(of: end) { _, _ in save() }
    }

    private func save() {
        WorkHours.set(start: start, end: end)
        onSaved()
    }

    /// Hour-of-day label using the device's 12- or 24-hour convention.
    private static func label(_ hour: Int) -> String {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let date = cal.date(bySettingHour: hour, minute: 0, second: 0, of: today)!
        return TimeFormat.time(date)
    }
}
```

- [ ] **Step 2: Wire it into `ContentView`**

Near line 33, alongside `@State private var showCalendarPicker = false`, add:

```swift
    @State private var showWorkHours = false
```

In the menu, immediately after the existing "Calendars" button (around line 470-474), add:

```swift
                    Button {
                        showWorkHours = true
                    } label: {
                        Label("Work Hours", systemImage: "clock")
                    }
```

Next to the existing `.sheet(isPresented: $showCalendarPicker ...)` around line 87, add:

```swift
            .sheet(isPresented: $showWorkHours) {
                WorkHoursView(onSaved: {
                    manager.refresh()
                    WidgetCenter.shared.reloadAllTimelines()
                    liveActivity.updateNow()
                })
            }
```

This is the same refresh trio the Calendars sheet already runs. `ContentView` already imports `WidgetKit` for that call; confirm and add the import if it is missing.

- [ ] **Step 3: Build and run in the simulator**

Run:

```bash
xcodebuild -project OpenTime.xcodeproj -scheme OpenTime \
  -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -20
```

Expected: `BUILD SUCCEEDED`.

Then launch in the simulator and verify by hand:
1. MORE menu shows "Work Hours" under "Calendars".
2. Setting start to 7 and end to 19 immediately widens the listed free slots.
3. Moving start to 20 forces end to 21 rather than allowing an inverted window.
4. Force-quitting and reopening the app preserves the setting.

- [ ] **Step 4: Commit**

```bash
git add OpenTime/Views/WorkHoursView.swift OpenTime/ContentView.swift OpenTime.xcodeproj
git commit -m "Add Work Hours picker sheet to the MORE menu"
```

---

### Task 5: Watch sync payload codec

**Files:**
- Create: `OpenTimeUI/Sources/OpenTimeUI/Settings/WorkHoursPayload.swift`
- Create: `OpenTimeUI/Tests/OpenTimeUITests/WorkHoursPayloadTests.swift`

**Interfaces:**
- Consumes: `WorkHours.sanitize(start:end:)` from Task 1.
- Produces:
  - `WorkHoursPayload.encode(start: Int, end: Int) -> [String: Any]`
  - `WorkHoursPayload.decode(_ context: [String: Any]) -> (start: Int, end: Int)`

This is the pure, testable half of the WatchConnectivity work. Task 6 and Task 7 add the untestable `WCSession` plumbing around it. Splitting them means the codec is verified by `swift test` before any device is involved.

- [ ] **Step 1: Write the failing tests**

Create `OpenTimeUI/Tests/OpenTimeUITests/WorkHoursPayloadTests.swift`:

```swift
import XCTest
@testable import OpenTimeUI

final class WorkHoursPayloadTests: XCTestCase {

    func testRoundTrip() {
        let context = WorkHoursPayload.encode(start: 7, end: 19)
        let r = WorkHoursPayload.decode(context)
        XCTAssertEqual(r.start, 7)
        XCTAssertEqual(r.end, 19)
    }

    func testEmptyContextDecodesToDefault() {
        let r = WorkHoursPayload.decode([:])
        XCTAssertEqual(r.start, 9)
        XCTAssertEqual(r.end, 17)
    }

    func testMalformedContextDecodesToDefault() {
        let r = WorkHoursPayload.decode(["workStartHour": "seven", "workEndHour": 19])
        XCTAssertEqual(r.start, 9)
        XCTAssertEqual(r.end, 17)
    }

    func testInvalidPairDecodesToDefault() {
        let r = WorkHoursPayload.decode(["workStartHour": 19, "workEndHour": 7])
        XCTAssertEqual(r.start, 9)
        XCTAssertEqual(r.end, 17)
    }

    func testEncodeSanitizesBeforeSending() {
        // Never put a window on the wire that the receiver would reject.
        let context = WorkHoursPayload.encode(start: 30, end: 4)
        XCTAssertEqual(context["workStartHour"] as? Int, 9)
        XCTAssertEqual(context["workEndHour"] as? Int, 17)
    }

    func testKeysMatchDefaultsKeys() {
        // The watch writes the received values straight into its own
        // UserDefaults under these names, so they must not drift.
        let context = WorkHoursPayload.encode(start: 8, end: 16)
        XCTAssertNotNil(context["workStartHour"])
        XCTAssertNotNil(context["workEndHour"])
        XCTAssertEqual(context.count, 2)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd OpenTimeUI && swift test`
Expected: compile failure, `cannot find 'WorkHoursPayload' in scope`.

- [ ] **Step 3: Write the implementation**

Create `OpenTimeUI/Sources/OpenTimeUI/Settings/WorkHoursPayload.swift`:

```swift
import Foundation

/// Wire format for the work-hours pair sent to the watch over
/// WatchConnectivity `applicationContext`.
///
/// Kept separate from the `WCSession` plumbing so the encoding is unit
/// testable without a paired device. Both directions sanitize: a window
/// that would be rejected on arrival is never sent in the first place.
public enum WorkHoursPayload {

    public static func encode(start: Int, end: Int) -> [String: Any] {
        let clean = WorkHours.sanitize(start: start, end: end)
        return [
            WorkHours.startKey: clean.start,
            WorkHours.endKey: clean.end
        ]
    }

    public static func decode(_ context: [String: Any]) -> (start: Int, end: Int) {
        WorkHours.sanitize(
            start: context[WorkHours.startKey] as? Int,
            end: context[WorkHours.endKey] as? Int
        )
    }
}
```

`WorkHours.startKey` and `endKey` are `internal`, which is fine: `WorkHoursPayload` lives in the same module.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd OpenTimeUI && swift test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add OpenTimeUI/Sources/OpenTimeUI/Settings/WorkHoursPayload.swift \
        OpenTimeUI/Tests/OpenTimeUITests/WorkHoursPayloadTests.swift
git commit -m "Add work-hours WatchConnectivity payload codec"
```

---

### Task 6: Phone side of the watch sync

**Files:**
- Create: `OpenTime/Services/WorkHoursSync.swift`
- Modify: `OpenTime/OpenTimeApp.swift` (activate the session at launch)
- Modify: `OpenTime/Views/WorkHoursView.swift` (push after save)

**Interfaces:**
- Consumes: `WorkHoursPayload.encode(start:end:)` from Task 5, `WorkHours.current()` from Task 1.
- Produces: `WorkHoursSync.shared.activate()` and `WorkHoursSync.shared.push()`.

There is no WatchConnectivity anywhere in this repo today, so this is new on both sides. The new file must be added to the `OpenTime` target in Xcode.

- [ ] **Step 1: Create the phone sync unit**

Create `OpenTime/Services/WorkHoursSync.swift`:

```swift
// OpenTime/Services/WorkHoursSync.swift
import Foundation
import OpenTimeUI
import WatchConnectivity

/// Pushes the work-hours pair to the watch.
///
/// `applicationContext` rather than `transferUserInfo`: it is
/// latest-state-wins, so rapid edits in the picker do not queue stale
/// values, and the system retains the most recent context and delivers it
/// when the watch app next activates. A watch that was off or not running
/// at edit time therefore catches up on its own with no handshake.
///
/// If a context never arrives the watch reads its empty defaults and gets
/// the 9-17 default, which is the same fail-safe as everywhere else.
final class WorkHoursSync: NSObject {
    static let shared = WorkHoursSync()

    private override init() { super.init() }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// Sends the currently stored window. Safe to call before activation
    /// completes; the send is skipped and the next call will carry it.
    func push() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        let hours = WorkHours.current()
        try? session.updateApplicationContext(
            WorkHoursPayload.encode(start: hours.start, end: hours.end)
        )
    }
}

extension WorkHoursSync: WCSessionDelegate {
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        // Send the current window as soon as the session is usable so a
        // watch that missed earlier edits is brought up to date.
        guard activationState == .activated else { return }
        push()
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // Required on iOS for watch switching; reactivate for the new watch.
        session.activate()
    }
}
```

- [ ] **Step 2: Activate at launch**

In `OpenTime/OpenTimeApp.swift`, extend `init()`:

```swift
    init() {
        FontRegistration.registerNHG()
        WorkHoursSync.shared.activate()
    }
```

- [ ] **Step 3: Push after every save**

In `OpenTime/Views/WorkHoursView.swift`, extend `save()`:

```swift
    private func save() {
        WorkHours.set(start: start, end: end)
        WorkHoursSync.shared.push()
        onSaved()
    }
```

- [ ] **Step 4: Build**

Run:

```bash
xcodebuild -project OpenTime.xcodeproj -scheme OpenTime \
  -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -20
```

Expected: `BUILD SUCCEEDED`. WatchConnectivity needs no entitlement, so no signing change is expected here.

- [ ] **Step 5: Commit**

```bash
git add OpenTime/Services/WorkHoursSync.swift OpenTime/OpenTimeApp.swift \
        OpenTime/Views/WorkHoursView.swift OpenTime.xcodeproj
git commit -m "Push work hours to the watch over WatchConnectivity"
```

---

### Task 7: Watch side of the sync

**Files:**
- Create: `OpenTimeWatch/WatchWorkHours.swift`
- Modify: `OpenTimeWatch/OpenTimeWatchApp.swift`
- Modify: `OpenTimeWatch/WatchCalendarHelper.swift:92-93`

**Interfaces:**
- Consumes: the two defaults keys `workStartHour` / `workEndHour`, and the payload shape from Task 5.
- Produces: `WatchWorkHours.current() -> (start: Int, end: Int)`, `WatchWorkHours.shared.activate()`.

`OpenTimeUI` is deliberately not linked to `OpenTimeWatch`, so this target cannot import it. It keeps its own small copy of the sanitize rule, the same way `WatchAvailabilityEngine` already duplicates the engine. Keep the key strings and the 9-17 default identical to `WorkHours`. New files must be added to the `OpenTimeWatch` target in Xcode.

- [ ] **Step 1: Create the watch-side storage and receiver**

Create `OpenTimeWatch/WatchWorkHours.swift`:

```swift
// OpenTimeWatch/WatchWorkHours.swift
import Foundation
import WatchConnectivity

/// Watch-local copy of the work-hours setting.
///
/// App Group defaults do not cross from the iPhone to the watch, so the
/// phone pushes the pair over WatchConnectivity and this type stores it in
/// the watch's own standard defaults. Duplicated rather than shared
/// because OpenTimeUI is not linked to the watch target, the same reason
/// WatchAvailabilityEngine exists. Keys and default must stay identical to
/// OpenTimeUI's WorkHours.
enum WatchWorkHours {
    static let defaultStart = 9
    static let defaultEnd = 17
    static let startKey = "workStartHour"
    static let endKey = "workEndHour"

    /// Posted after a new window arrives so the UI can refresh.
    static let didChange = Notification.Name("WatchWorkHoursDidChange")

    static func current(defaults: UserDefaults = .standard) -> (start: Int, end: Int) {
        sanitize(
            start: defaults.object(forKey: startKey) as? Int,
            end: defaults.object(forKey: endKey) as? Int
        )
    }

    static func store(_ context: [String: Any], defaults: UserDefaults = .standard) {
        let clean = sanitize(
            start: context[startKey] as? Int,
            end: context[endKey] as? Int
        )
        defaults.set(clean.start, forKey: startKey)
        defaults.set(clean.end, forKey: endKey)
    }

    static func sanitize(start: Int?, end: Int?) -> (start: Int, end: Int) {
        guard let start, let end,
              (0...23).contains(start),
              (0...23).contains(end),
              start < end
        else { return (defaultStart, defaultEnd) }
        return (start, end)
    }
}

/// Receives the phone's application context.
final class WatchWorkHoursSync: NSObject {
    static let shared = WatchWorkHoursSync()

    private override init() { super.init() }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }
}

extension WatchWorkHoursSync: WCSessionDelegate {
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        // The system retains the phone's most recent context, so an edit
        // made while this app was not running is available right here.
        guard activationState == .activated else { return }
        let context = session.receivedApplicationContext
        guard !context.isEmpty else { return }
        apply(context)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        apply(applicationContext)
    }

    private func apply(_ context: [String: Any]) {
        WatchWorkHours.store(context)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: WatchWorkHours.didChange, object: nil)
        }
    }
}
```

- [ ] **Step 2: Activate at watch launch**

Replace `OpenTimeWatch/OpenTimeWatchApp.swift` with:

```swift
import SwiftUI

@main
struct OpenTimeWatchApp: App {
    init() {
        WatchWorkHoursSync.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            WatchContentView()
        }
    }
}
```

- [ ] **Step 3: Read the stored window in the helper**

In `OpenTimeWatch/WatchCalendarHelper.swift`, replace lines 92-93:

```swift
    private let workStart = 9
    private let workEnd = 17
```

with:

```swift
    private var workStart: Int { WatchWorkHours.current().start }
    private var workEnd: Int { WatchWorkHours.current().end }
```

Then, so an incoming change is reflected without waiting for the next manual load, add an observer to the same class. Place it after the `days` property:

```swift
    private var workHoursObserver: NSObjectProtocol?

    init() {
        workHoursObserver = NotificationCenter.default.addObserver(
            forName: WatchWorkHours.didChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.accessGranted else { return }
                self.loadWeek()
            }
        }
    }

    deinit {
        if let workHoursObserver {
            NotificationCenter.default.removeObserver(workHoursObserver)
        }
    }
```

This mirrors the `EKEventStoreChanged` observer pattern already used in `OpenTime/Services/CalendarManager.swift:23-38`.

- [ ] **Step 4: Build the watch target**

Run:

```bash
xcodebuild -project OpenTime.xcodeproj -scheme OpenTimeWatch \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)' build 2>&1 | tail -20
```

Expected: `BUILD SUCCEEDED`. If the named simulator does not exist, list options with `xcrun simctl list devices available` and substitute one. If the scheme name differs, list schemes with `xcodebuild -project OpenTime.xcodeproj -list`.

- [ ] **Step 5: Commit**

```bash
git add OpenTimeWatch/WatchWorkHours.swift OpenTimeWatch/OpenTimeWatchApp.swift \
        OpenTimeWatch/WatchCalendarHelper.swift OpenTime.xcodeproj
git commit -m "Watch reads work hours pushed from the phone"
```

---

### Task 8: Full verification sweep

**Files:**
- Modify: none expected. Fix whatever this task uncovers.

**Interfaces:**
- Consumes: everything above.
- Produces: a verified feature.

- [ ] **Step 1: Confirm no hardcoded workday literals survive**

Run:

```bash
grep -rn "workStart = 9\|workEnd = 17\|workStartHour = 9\|workEndHour = 17\|bySettingHour: 9," --include="*.swift" . \
  | grep -v "OpenTimeUI/Sources/OpenTimeUI/Engine/AvailabilityEngine.swift" \
  | grep -v "/Tests/"
```

Expected: no output. The engine's default arguments are the one intentional survivor, and they are excluded above. `WorkHours.defaultStart`/`defaultEnd` and `WatchWorkHours.defaultStart`/`defaultEnd` do not match these patterns.

- [ ] **Step 2: Run the package tests**

Run: `cd OpenTimeUI && swift test`
Expected: PASS, with the pre-existing 29 tests plus the new `WorkHoursTests`, `WorkHoursPayloadTests`, and the engine window test.

- [ ] **Step 3: Build every target**

Run:

```bash
xcodebuild -project OpenTime.xcodeproj -scheme OpenTime \
  -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5
xcodebuild -project OpenTime.xcodeproj -scheme OpenTimeWatch \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)' build 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED` for both. Commit 2588817 in this repo's history shipped with three of five targets not compiling, so do not treat a green main-app build as covering the extensions.

- [ ] **Step 4: Simulator behavior check**

With the setting at 7 to 19, confirm each surface agrees:
1. Main app day rows start at 7:00 and end at 19:00.
2. Widget (add it to the simulator home screen) shows the same slots.
3. iMessage extension, opened from a conversation, shows the same slots.
4. Share extension shows the same slots.
5. Live Activity, started from the MORE menu toggle during the widened window, shows the workday end as `7:00 PM` and does not report "Off Hours" at 18:00.

Reset to 9 to 17 and confirm everything returns to the previous behavior.

- [ ] **Step 5: Manual device verification of the watch sync**

`WCSession` is not exercised by a simulator run and has no unit test. On a real paired iPhone and Apple Watch:
1. Build and run both apps from Xcode, or archive with `-allowProvisioningUpdates`.
2. Change work hours on the phone to 7 to 19.
3. Open the watch app and confirm its slots start at 7:00 and end at 19:00.
4. Force-quit the watch app, change the phone to 8 to 16, then reopen the watch app and confirm it picks up 8 to 16 from the retained context.

If this cannot be run now, say so explicitly rather than marking the task complete. The rest of the feature is independently shippable; only the watch leg is unverified.

- [ ] **Step 6: Commit any fixes**

```bash
git add -A
git commit -m "Fixes from configurable work hours verification sweep"
```

---

## Deliberately out of scope

- Minute granularity, per-weekday schedules, timezone handling.
- Weekend inclusion (`CalendarManager.includeWeekends` already exists and is unrelated).
- Syncing calendar selection to the watch, which remains a separate known gap.
- The pre-existing deferred bugs listed in the project notes (multi-day events blocking only their first day, elapsed slots still shown, declined invites still blocking). None are touched here.

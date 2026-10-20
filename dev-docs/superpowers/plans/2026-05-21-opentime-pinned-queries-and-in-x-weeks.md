# OpenTime — Pinned Queries + "In X Weeks/Months" Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the OpenTime NL query bar to (a) interpret "in N weeks/months" as a 14-day window centered on the target date and (b) let users pin frequently-used queries as chips that sync via iCloud KVS, with a Settings screen to manage them.

**Architecture:** Prompt-level change in `QueryParser.instructions(now:)` for the new phrase. A new `PinnedQueryStore` (ObservableObject) backed by `NSUbiquitousKeyValueStore` with a `UserDefaults` mirror, surfaced as a filled-chip row above the existing example chips, a star button on the query bar, and a `PinnedQueriesView` reached from the existing toolbar Menu.

**Tech Stack:** Swift 6.2, SwiftUI, Swift Testing (`import Testing` + `@Suite`/`@Test`/`#expect`), FoundationModels (iOS 26+), `NSUbiquitousKeyValueStore` for iCloud sync.

**Spec:** `docs/superpowers/specs/2026-05-21-opentime-pinned-queries-and-in-x-weeks-design.md`

---

## Working Branch

Before Task 1, create a feature branch:

```bash
cd /Users/jamest/open-time
git checkout -b feature/pinned-queries-and-in-x-weeks
```

---

## Task 1: Centered-window cases in `AvailabilityIntentTests`

Adds unit tests that lock in the expected `(start, end)` range when an intent carries the dates the new prompt rule should emit. These tests don't run the model — they confirm that downstream `requestedRange(now:)` produces the right span when given the prompt's intended output. Serves as a contract reference for the prompt change in Task 2.

**Files:**
- Modify: `OpenTimeUI/Tests/OpenTimeUITests/AvailabilityIntentTests.swift`

- [ ] **Step 1: Add the centered-window tests to the existing suite**

Open the file and append these tests inside the `@Suite struct AvailabilityIntentTests { … }` body, before the closing brace:

```swift
@Test("in 3 weeks → 14-day window centered on day +21")
func centeredWindowThreeWeeks() {
    let now = Self.date(2026, 5, 21)
    var intent = AvailabilityIntent()
    intent.startDate = "2026-06-04"  // now + 14d
    intent.endDate   = "2026-06-18"  // now + 28d
    let range = intent.requestedRange(now: now)
    #expect(range != nil)
    #expect(Calendar.current.isDate(range!.start, inSameDayAs: Self.date(2026, 6, 4)))
    #expect(Calendar.current.isDate(range!.end,   inSameDayAs: Self.date(2026, 6, 18)))
}

@Test("in a week → 14-day window centered on day +7")
func centeredWindowOneWeek() {
    let now = Self.date(2026, 5, 21)
    var intent = AvailabilityIntent()
    intent.startDate = "2026-05-21"  // now + 0d
    intent.endDate   = "2026-06-04"  // now + 14d
    let range = intent.requestedRange(now: now)
    #expect(range != nil)
    #expect(Calendar.current.isDate(range!.start, inSameDayAs: Self.date(2026, 5, 21)))
    #expect(Calendar.current.isDate(range!.end,   inSameDayAs: Self.date(2026, 6, 4)))
}

@Test("in 2 months → 14-day window centered on day +2 months")
func centeredWindowTwoMonths() {
    let now = Self.date(2026, 5, 21)
    var intent = AvailabilityIntent()
    intent.startDate = "2026-07-14"  // target 2026-07-21 minus 7d
    intent.endDate   = "2026-07-28"  // target plus 7d
    let range = intent.requestedRange(now: now)
    #expect(range != nil)
    #expect(Calendar.current.isDate(range!.start, inSameDayAs: Self.date(2026, 7, 14)))
    #expect(Calendar.current.isDate(range!.end,   inSameDayAs: Self.date(2026, 7, 28)))
}

@Test("centered window summary reads as a range")
func centeredWindowSummary() {
    let now = Self.date(2026, 5, 21)
    var intent = AvailabilityIntent()
    intent.startDate = "2026-06-04"
    intent.endDate   = "2026-06-18"
    let summary = intent.summary(now: now)
    #expect(summary.contains("–"))   // en-dash from dateLabel
    #expect(summary.uppercased() == summary)
}
```

- [ ] **Step 2: Run the new tests, confirm they pass**

```bash
cd /Users/jamest/open-time
swift test --package-path OpenTimeUI --filter "AvailabilityIntentTests/centeredWindow"
```

Expected: 4 tests pass. These should already work because `requestedRange` already handles arbitrary start/end dates.

- [ ] **Step 3: Commit**

```bash
git add OpenTimeUI/Tests/OpenTimeUITests/AvailabilityIntentTests.swift
git commit -m "test(intent): lock in centered 14-day window cases for in-N-weeks/months"
```

---

## Task 2: Extend `QueryParser` prompt for "in N weeks/months"

Adds one rule to the FoundationModels instruction string. No automated test here — the prompt behavior is non-deterministic. A manual smoke at the end verifies the model honors the rule.

**Files:**
- Modify: `OpenTimeUI/Sources/OpenTimeUI/Query/QueryParser.swift` (the `instructions(now:)` returned string)

- [ ] **Step 1: Add the new rule to the instructions string**

In `QueryParser.swift`, locate the multi-line `return """..."""` inside `instructions(now:)`. Insert the new rule between the existing "Weekend" rule and the "startHour / endHour" rule:

```swift
return """
You parse a user's free-form question about their calendar availability \
into a structured intent. Today is \(today) (\(weekday)).

Rules:
- startDate / endDate: absolute YYYY-MM-DD dates. Resolve "today", "tomorrow", \
"next Tuesday", "this weekend", "end of next month", etc. against today's date. \
Ambiguous weekdays mean the NEXT future occurrence. Single-day queries set both fields equal.
- "This week" = today through the coming Sunday.
- "Next week" = Monday through Sunday of the following week.
- "Weekend" = Saturday–Sunday.
- "In N weeks" or "in N months" means a 14-day window CENTERED on the target date: \
target = today + N weeks (or N calendar months); set startDate = target − 7 days and \
endDate = target + 7 days. Treat "in a week" / "in a month" as N = 1. \
Example: today is \(today), "in 3 weeks" -> startDate is target − 7 days, endDate is target + 7 days.
- startHour / endHour: 24-hour integers. "Morning" = 8–12, "afternoon" = 12–17, \
"evening" = 17–22. "After 2pm" -> startHour 14. "Before noon" -> endHour 12.
- durationMin: minutes the user wants free. "An hour" = 60. "Quick 15" = 15.
- purposeHint: short label like "coffee" or "call with Anna" if the user gave one. \
Display only — don't infer it from a duration alone.
- If the user said no date at all, leave startDate and endDate nil.
- Respond with the structured intent only.
"""
```

- [ ] **Step 2: Build to verify no Swift errors**

```bash
swift build --package-path /Users/jamest/open-time/OpenTimeUI
```

Expected: build succeeds.

- [ ] **Step 3: Run the full UI test suite to confirm nothing regressed**

```bash
swift test --package-path /Users/jamest/open-time/OpenTimeUI
```

Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add OpenTimeUI/Sources/OpenTimeUI/Query/QueryParser.swift
git commit -m "feat(query): teach parser \"in N weeks/months\" → centered 14-day window"
```

Manual smoke happens in Task 12.

---

## Task 3: `PinnedQuery` model

New file holding the value type. Codable, Identifiable, Sendable, Equatable.

**Files:**
- Create: `OpenTimeUI/Sources/OpenTimeUI/Query/PinnedQuery.swift`
- Test: `OpenTimeUI/Tests/OpenTimeUITests/PinnedQueryTests.swift`

- [ ] **Step 1: Write the failing test**

Create `OpenTimeUI/Tests/OpenTimeUITests/PinnedQueryTests.swift`:

```swift
import Testing
import Foundation
@testable import OpenTimeUI

@Suite struct PinnedQueryTests {

    @Test("label defaults to query when empty")
    func labelDefaultsToQuery() {
        let p = PinnedQuery(label: "", query: "when am i free next week")
        #expect(p.label == "when am i free next week")
    }

    @Test("explicit label is preserved")
    func explicitLabelPreserved() {
        let p = PinnedQuery(label: "Mornings", query: "tomorrow morning")
        #expect(p.label == "Mornings")
    }

    @Test("round-trips through JSONEncoder/Decoder")
    func roundTripsJSON() throws {
        let original = PinnedQuery(label: "Coffee", query: "30 min tomorrow morning")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PinnedQuery.self, from: data)
        #expect(decoded == original)
    }
}
```

- [ ] **Step 2: Run test to verify it fails (model doesn't exist yet)**

```bash
swift test --package-path /Users/jamest/open-time/OpenTimeUI --filter PinnedQueryTests
```

Expected: FAIL with "Cannot find 'PinnedQuery' in scope".

- [ ] **Step 3: Implement the model**

Create `OpenTimeUI/Sources/OpenTimeUI/Query/PinnedQuery.swift`:

```swift
import Foundation

public struct PinnedQuery: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public var label: String
    public var query: String
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        label: String,
        query: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.label = label.isEmpty ? query : label
        self.query = query
        self.createdAt = createdAt
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
swift test --package-path /Users/jamest/open-time/OpenTimeUI --filter PinnedQueryTests
```

Expected: 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add OpenTimeUI/Sources/OpenTimeUI/Query/PinnedQuery.swift OpenTimeUI/Tests/OpenTimeUITests/PinnedQueryTests.swift
git commit -m "feat(query): PinnedQuery model"
```

---

## Task 4: `PinnedQueryStore` — local-only add/delete/rename/move

ObservableObject with a `UserDefaults`-backed array. iCloud merge logic comes in Task 6 so this task stays small and testable.

**Files:**
- Create: `OpenTimeUI/Sources/OpenTimeUI/Query/PinnedQueryStore.swift`
- Test: `OpenTimeUI/Tests/OpenTimeUITests/PinnedQueryStoreTests.swift`

- [ ] **Step 1: Write failing tests for the basic mutators**

Create `OpenTimeUI/Tests/OpenTimeUITests/PinnedQueryStoreTests.swift`:

```swift
import Testing
import Foundation
@testable import OpenTimeUI

@Suite struct PinnedQueryStoreTests {

    /// Each test gets a fresh suite-scoped UserDefaults to avoid cross-test bleed.
    private func makeDefaults() -> UserDefaults {
        let name = "opentime.tests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test("add appends a new pin")
    func addAppends() {
        let store = PinnedQueryStore(defaults: makeDefaults(), useICloud: false)
        store.add(query: "when am i free next week")
        #expect(store.pinned.count == 1)
        #expect(store.pinned[0].query == "when am i free next week")
        #expect(store.pinned[0].label == "when am i free next week")
    }

    @Test("add with explicit label")
    func addWithLabel() {
        let store = PinnedQueryStore(defaults: makeDefaults(), useICloud: false)
        store.add(query: "30 min tomorrow morning", label: "Quick AM")
        #expect(store.pinned[0].label == "Quick AM")
    }

    @Test("isPinned is trimmed and case-insensitive")
    func isPinnedNormalization() {
        let store = PinnedQueryStore(defaults: makeDefaults(), useICloud: false)
        store.add(query: "Coffee Next Week")
        #expect(store.isPinned(query: "  coffee next week  "))
        #expect(!store.isPinned(query: "tea next week"))
    }

    @Test("toggle adds then removes")
    func toggle() {
        let store = PinnedQueryStore(defaults: makeDefaults(), useICloud: false)
        store.toggle(query: "any 2 hour block")
        #expect(store.pinned.count == 1)
        store.toggle(query: "any 2 hour block")
        #expect(store.pinned.isEmpty)
    }

    @Test("rename updates the label only")
    func rename() {
        let store = PinnedQueryStore(defaults: makeDefaults(), useICloud: false)
        store.add(query: "30 min tomorrow morning")
        let id = store.pinned[0].id
        store.rename(id, to: "Quick AM")
        #expect(store.pinned[0].label == "Quick AM")
        #expect(store.pinned[0].query == "30 min tomorrow morning")
    }

    @Test("delete removes the entry")
    func delete() {
        let store = PinnedQueryStore(defaults: makeDefaults(), useICloud: false)
        store.add(query: "a")
        store.add(query: "b")
        let id = store.pinned[0].id
        store.delete(id)
        #expect(store.pinned.count == 1)
        #expect(store.pinned[0].query == "b")
    }

    @Test("move reorders in place")
    func move() {
        let store = PinnedQueryStore(defaults: makeDefaults(), useICloud: false)
        store.add(query: "a")
        store.add(query: "b")
        store.add(query: "c")
        store.move(from: IndexSet(integer: 0), to: 3)
        #expect(store.pinned.map(\.query) == ["b", "c", "a"])
    }

    @Test("persists across instances via UserDefaults")
    func persistsToDefaults() {
        let defaults = makeDefaults()
        let a = PinnedQueryStore(defaults: defaults, useICloud: false)
        a.add(query: "coffee next week")
        let b = PinnedQueryStore(defaults: defaults, useICloud: false)
        #expect(b.pinned.count == 1)
        #expect(b.pinned[0].query == "coffee next week")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --package-path /Users/jamest/open-time/OpenTimeUI --filter PinnedQueryStoreTests
```

Expected: FAIL with "Cannot find 'PinnedQueryStore' in scope".

- [ ] **Step 3: Implement the store (local-only)**

Create `OpenTimeUI/Sources/OpenTimeUI/Query/PinnedQueryStore.swift`:

```swift
import Foundation
import Combine

@MainActor
public final class PinnedQueryStore: ObservableObject {

    public static let storageKey = "opentime.pinnedQueries.v1"

    @Published public private(set) var pinned: [PinnedQuery] = []

    /// Set by `add` when the entry count exceeds `Self.cap` and the oldest
    /// gets dropped. The Settings screen reads this to fire a one-time alert.
    @Published public var didTrimAtCap: Bool = false

    public static let cap = 20

    private let defaults: UserDefaults
    private let useICloud: Bool

    public init(defaults: UserDefaults = .standard, useICloud: Bool = true) {
        self.defaults = defaults
        self.useICloud = useICloud
        loadFromDefaults()
    }

    // MARK: - Public API

    public func add(query: String, label: String? = nil) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !isPinned(query: trimmed) else { return }
        let entry = PinnedQuery(label: label ?? "", query: trimmed)
        pinned.append(entry)
        enforceCap()
        persist()
    }

    public func rename(_ id: UUID, to label: String) {
        guard let i = pinned.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        pinned[i].label = trimmed.isEmpty ? pinned[i].query : trimmed
        persist()
    }

    public func delete(_ id: UUID) {
        pinned.removeAll { $0.id == id }
        persist()
    }

    public func move(from offsets: IndexSet, to destination: Int) {
        pinned.move(fromOffsets: offsets, toOffset: destination)
        persist()
    }

    public func isPinned(query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        return pinned.contains { $0.query.lowercased() == needle }
    }

    public func toggle(query: String) {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        if let match = pinned.first(where: { $0.query.lowercased() == needle }) {
            delete(match.id)
        } else {
            add(query: query)
        }
    }

    // MARK: - Persistence

    private func enforceCap() {
        guard pinned.count > Self.cap else { return }
        let overflow = pinned.count - Self.cap
        pinned = Array(pinned.sorted(by: { $0.createdAt < $1.createdAt }).dropFirst(overflow))
        // Re-stable-sort by createdAt asc; UI cares about user-controlled order
        // only after the cap is satisfied, so this is acceptable.
        didTrimAtCap = true
    }

    private func loadFromDefaults() {
        guard let data = defaults.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([PinnedQuery].self, from: data) else {
            return
        }
        pinned = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(pinned) else { return }
        defaults.set(data, forKey: Self.storageKey)
        // iCloud handling lives in a subsequent task.
        _ = useICloud
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --package-path /Users/jamest/open-time/OpenTimeUI --filter PinnedQueryStoreTests
```

Expected: all 8 tests pass.

- [ ] **Step 5: Commit**

```bash
git add OpenTimeUI/Sources/OpenTimeUI/Query/PinnedQueryStore.swift OpenTimeUI/Tests/OpenTimeUITests/PinnedQueryStoreTests.swift
git commit -m "feat(query): PinnedQueryStore with local UserDefaults persistence"
```

---

## Task 5: `PinnedQueryStore` — cap at 20 + `didTrimAtCap` test

The cap logic is already in Task 4's implementation; this task locks it in with explicit tests.

**Files:**
- Modify: `OpenTimeUI/Tests/OpenTimeUITests/PinnedQueryStoreTests.swift`

- [ ] **Step 1: Add failing tests for cap behavior**

Append inside the `@Suite struct PinnedQueryStoreTests { … }` body:

```swift
@Test("adding past cap drops the oldest")
func capDropsOldest() {
    let store = PinnedQueryStore(defaults: makeDefaults(), useICloud: false)
    for i in 0..<21 {
        store.add(query: "query \(i)")
    }
    #expect(store.pinned.count == PinnedQueryStore.cap)
    // Oldest ("query 0") is gone; newest ("query 20") is present.
    #expect(!store.pinned.contains { $0.query == "query 0" })
    #expect(store.pinned.contains { $0.query == "query 20" })
}

@Test("didTrimAtCap is set when cap exceeded")
func didTrimFlag() {
    let store = PinnedQueryStore(defaults: makeDefaults(), useICloud: false)
    for i in 0..<PinnedQueryStore.cap {
        store.add(query: "query \(i)")
    }
    #expect(store.didTrimAtCap == false)
    store.add(query: "one too many")
    #expect(store.didTrimAtCap == true)
}
```

- [ ] **Step 2: Run tests — they should already pass**

```bash
swift test --package-path /Users/jamest/open-time/OpenTimeUI --filter PinnedQueryStoreTests
```

Expected: all tests pass (10 total).

- [ ] **Step 3: Commit**

```bash
git add OpenTimeUI/Tests/OpenTimeUITests/PinnedQueryStoreTests.swift
git commit -m "test(store): lock in 20-entry cap and didTrimAtCap flag"
```

---

## Task 6: `PinnedQueryStore` — iCloud KVS persistence + external-change merge

Add `NSUbiquitousKeyValueStore` writes and observation behind the `useICloud` flag. Merge policy: union by `id`; on conflicting `id`, the entry with the later `createdAt` wins.

**Files:**
- Modify: `OpenTimeUI/Sources/OpenTimeUI/Query/PinnedQueryStore.swift`
- Modify: `OpenTimeUI/Tests/OpenTimeUITests/PinnedQueryStoreTests.swift`

- [ ] **Step 1: Write a failing test for the merge function**

The full KVS observer is hard to unit-test (it requires entitlements + a sync round-trip). Instead, expose the merge logic as a pure static helper and test that directly.

Append to `PinnedQueryStoreTests.swift`:

```swift
@Test("merge unions by id")
func mergeUnion() {
    let now = Date()
    let a = PinnedQuery(id: UUID(), label: "A", query: "a", createdAt: now)
    let b = PinnedQuery(id: UUID(), label: "B", query: "b", createdAt: now)
    let merged = PinnedQueryStore.merge(local: [a], remote: [b])
    #expect(merged.count == 2)
    #expect(merged.contains(where: { $0.id == a.id }))
    #expect(merged.contains(where: { $0.id == b.id }))
}

@Test("merge prefers later createdAt on id conflict")
func mergeLastWriteWins() {
    let id = UUID()
    let older = PinnedQuery(id: id, label: "Old", query: "x", createdAt: Date(timeIntervalSince1970: 1_000))
    let newer = PinnedQuery(id: id, label: "New", query: "x", createdAt: Date(timeIntervalSince1970: 2_000))
    let merged = PinnedQueryStore.merge(local: [older], remote: [newer])
    #expect(merged.count == 1)
    #expect(merged[0].label == "New")
    let reversed = PinnedQueryStore.merge(local: [newer], remote: [older])
    #expect(reversed[0].label == "New")
}

@Test("merge preserves local order when there is no remote change")
func mergePreservesOrder() {
    let a = PinnedQuery(id: UUID(), label: "a", query: "a", createdAt: Date(timeIntervalSince1970: 1))
    let b = PinnedQuery(id: UUID(), label: "b", query: "b", createdAt: Date(timeIntervalSince1970: 2))
    let merged = PinnedQueryStore.merge(local: [a, b], remote: [])
    #expect(merged.map(\.label) == ["a", "b"])
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --package-path /Users/jamest/open-time/OpenTimeUI --filter PinnedQueryStoreTests
```

Expected: FAIL with "Type 'PinnedQueryStore' has no member 'merge'".

- [ ] **Step 3: Add the merge helper + KVS integration**

In `PinnedQueryStore.swift`, replace the existing class with:

```swift
import Foundation
import Combine

@MainActor
public final class PinnedQueryStore: ObservableObject {

    public static let storageKey = "opentime.pinnedQueries.v1"
    public static let cap = 20

    @Published public private(set) var pinned: [PinnedQuery] = []
    @Published public var didTrimAtCap: Bool = false

    private let defaults: UserDefaults
    private let useICloud: Bool
    private var observer: NSObjectProtocol?

    public init(defaults: UserDefaults = .standard, useICloud: Bool = true) {
        self.defaults = defaults
        self.useICloud = useICloud
        loadFromDefaults()
        if useICloud {
            loadFromICloud(merging: true)
            startObservingICloud()
            NSUbiquitousKeyValueStore.default.synchronize()
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    // MARK: - Public API

    public func add(query: String, label: String? = nil) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !isPinned(query: trimmed) else { return }
        let entry = PinnedQuery(label: label ?? "", query: trimmed)
        pinned.append(entry)
        enforceCap()
        persist()
    }

    public func rename(_ id: UUID, to label: String) {
        guard let i = pinned.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        pinned[i].label = trimmed.isEmpty ? pinned[i].query : trimmed
        persist()
    }

    public func delete(_ id: UUID) {
        pinned.removeAll { $0.id == id }
        persist()
    }

    public func move(from offsets: IndexSet, to destination: Int) {
        pinned.move(fromOffsets: offsets, toOffset: destination)
        persist()
    }

    public func isPinned(query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        return pinned.contains { $0.query.lowercased() == needle }
    }

    public func toggle(query: String) {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        if let match = pinned.first(where: { $0.query.lowercased() == needle }) {
            delete(match.id)
        } else {
            add(query: query)
        }
    }

    // MARK: - Merge (pure, testable)

    /// Unions `local` and `remote` by `id`. On id conflict, the entry with the
    /// later `createdAt` wins. New remote entries are appended after local
    /// entries to preserve user-controlled ordering on the originating device.
    public static func merge(local: [PinnedQuery], remote: [PinnedQuery]) -> [PinnedQuery] {
        var byId: [UUID: PinnedQuery] = [:]
        var order: [UUID] = []

        for entry in local {
            byId[entry.id] = entry
            order.append(entry.id)
        }
        for entry in remote {
            if let existing = byId[entry.id] {
                if entry.createdAt > existing.createdAt {
                    byId[entry.id] = entry
                }
            } else {
                byId[entry.id] = entry
                order.append(entry.id)
            }
        }
        return order.compactMap { byId[$0] }
    }

    // MARK: - Persistence

    private func enforceCap() {
        guard pinned.count > Self.cap else { return }
        let sorted = pinned.sorted(by: { $0.createdAt < $1.createdAt })
        let drop = Set(sorted.prefix(pinned.count - Self.cap).map(\.id))
        pinned.removeAll { drop.contains($0.id) }
        didTrimAtCap = true
    }

    private func loadFromDefaults() {
        guard let data = defaults.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([PinnedQuery].self, from: data) else {
            return
        }
        pinned = decoded
    }

    private func loadFromICloud(merging: Bool) {
        let kvs = NSUbiquitousKeyValueStore.default
        guard let data = kvs.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([PinnedQuery].self, from: data) else {
            return
        }
        if merging {
            pinned = Self.merge(local: pinned, remote: decoded)
        } else {
            pinned = decoded
        }
        // Mirror merged state back to defaults so offline reads are current.
        writeToDefaults()
    }

    private func startObservingICloud() {
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.loadFromICloud(merging: true)
            }
        }
    }

    private func writeToDefaults() {
        guard let data = try? JSONEncoder().encode(pinned) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(pinned) else { return }
        defaults.set(data, forKey: Self.storageKey)
        if useICloud {
            NSUbiquitousKeyValueStore.default.set(data, forKey: Self.storageKey)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --package-path /Users/jamest/open-time/OpenTimeUI --filter PinnedQueryStoreTests
```

Expected: all tests pass (13 total).

- [ ] **Step 5: Commit**

```bash
git add OpenTimeUI/Sources/OpenTimeUI/Query/PinnedQueryStore.swift OpenTimeUI/Tests/OpenTimeUITests/PinnedQueryStoreTests.swift
git commit -m "feat(store): iCloud KVS persistence with union+last-write-wins merge"
```

---

## Task 7: iCloud KVS entitlement on main app target

`NSUbiquitousKeyValueStore` requires the `com.apple.developer.ubiquity-kvstore-identifier` entitlement and an iCloud capability on the target. This is fastest done through Xcode's UI; scripting `project.pbxproj` is brittle.

**Files:**
- Create: `OpenTime/OpenTime.entitlements`
- Modify: `OpenTime.xcodeproj/project.pbxproj` (via Xcode UI)

- [ ] **Step 1: Add iCloud KVS via Xcode UI**

1. Open `/Users/jamest/open-time/OpenTime.xcodeproj` in Xcode.
2. Select the `OpenTime` project in the navigator → select the `OpenTime` target (the main app, not the extensions).
3. Go to the **Signing & Capabilities** tab.
4. Click **+ Capability** → choose **iCloud**.
5. Under iCloud Services, check **Key-value storage**. Leave CloudKit / Documents unchecked.
6. Xcode will create `OpenTime/OpenTime.entitlements` automatically and wire it via `CODE_SIGN_ENTITLEMENTS` in `project.pbxproj`.

- [ ] **Step 2: Verify the entitlements file contents**

Open `OpenTime/OpenTime.entitlements`. It should contain:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.ubiquity-kvstore-identifier</key>
    <string>$(TeamIdentifierPrefix)$(CFBundleIdentifier)</string>
</dict>
</plist>
```

If Xcode wrote a different string format, adjust to match.

- [ ] **Step 3: Build the app to confirm entitlement is recognized**

In Xcode: Product → Build (⌘B). Or from terminal:

```bash
xcodebuild -project /Users/jamest/open-time/OpenTime.xcodeproj \
  -scheme OpenTime \
  -destination 'generic/platform=iOS Simulator' \
  build 2>&1 | tail -20
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add OpenTime/OpenTime.entitlements OpenTime.xcodeproj/project.pbxproj
git commit -m "feat(app): enable iCloud key-value storage entitlement"
```

---

## Task 8: `PinnedChipsView` component

Filled-style horizontal scroll row that renders pinned query chips. Lifted out of `QueryBarView` so the bar stays focused.

**Files:**
- Create: `OpenTimeUI/Sources/OpenTimeUI/Components/PinnedChipsView.swift`

- [ ] **Step 1: Implement the component**

Create `OpenTimeUI/Sources/OpenTimeUI/Components/PinnedChipsView.swift`:

```swift
import SwiftUI

public struct PinnedChipsView: View {
    public let pinned: [PinnedQuery]
    public let onTap: (PinnedQuery) -> Void
    public let onRename: (PinnedQuery) -> Void
    public let onRemove: (PinnedQuery) -> Void

    public init(
        pinned: [PinnedQuery],
        onTap: @escaping (PinnedQuery) -> Void,
        onRename: @escaping (PinnedQuery) -> Void,
        onRemove: @escaping (PinnedQuery) -> Void
    ) {
        self.pinned = pinned
        self.onTap = onTap
        self.onRename = onRename
        self.onRemove = onRemove
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(pinned) { pin in
                    Button {
                        onTap(pin)
                    } label: {
                        Text(pin.label.uppercased())
                            .font(Theme.Font.display(size: 10, weight: .bold))
                            .kerning(1.4)
                            .foregroundStyle(Theme.bg)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Theme.fg)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Rename") { onRename(pin) }
                        Button("Remove", role: .destructive) { onRemove(pin) }
                    }
                }
            }
        }
    }
}

#Preview("Two pinned, Light") {
    FontRegistration.registerNHG()
    return PinnedChipsView(
        pinned: [
            PinnedQuery(label: "Quick AM", query: "30 min tomorrow morning"),
            PinnedQuery(label: "Coffee", query: "coffee next week")
        ],
        onTap: { _ in },
        onRename: { _ in },
        onRemove: { _ in }
    )
    .padding(20)
    .preferredColorScheme(.light)
}
```

- [ ] **Step 2: Build to verify**

```bash
swift build --package-path /Users/jamest/open-time/OpenTimeUI
```

Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add OpenTimeUI/Sources/OpenTimeUI/Components/PinnedChipsView.swift
git commit -m "feat(ui): PinnedChipsView — filled horizontal-scroll chip row"
```

---

## Task 9: `QueryBarView` — pin button + pinned-chips row

Add pin/unpin button next to `× CLEAR` when `hasResult`. Slot `PinnedChipsView` above the existing example chips.

**Files:**
- Modify: `OpenTimeUI/Sources/OpenTimeUI/Components/QueryBarView.swift`

- [ ] **Step 1: Update the initializer + body**

Replace the existing `QueryBarView` body with the version below. The diff is large enough that a full rewrite is clearer than spot edits.

```swift
import SwiftUI

public struct QueryBarView: View {

    public static let exampleQueries: [String] = [
        "WHEN AM I FREE?",
        "ANY HOUR FRIDAY AFTERNOON",
        "30 MIN TOMORROW MORNING",
        "NEXT TUESDAY AFTER 2PM",
        "COFFEE NEXT WEEK",
        "ANY 2-HOUR BLOCK"
    ]

    @Binding public var text: String
    public var isLoading: Bool
    public var hasResult: Bool
    public var pinnedQueries: [PinnedQuery]
    public var isCurrentQueryPinned: Bool
    public var onSubmit: () async -> Void
    public var onClear: () -> Void
    public var onTogglePin: () -> Void
    public var onRunPinned: (PinnedQuery) -> Void
    public var onRenamePinned: (PinnedQuery) -> Void
    public var onRemovePinned: (PinnedQuery) -> Void

    @FocusState private var focused: Bool
    private let chips: [String]

    public init(
        text: Binding<String>,
        isLoading: Bool,
        hasResult: Bool,
        pinnedQueries: [PinnedQuery] = [],
        isCurrentQueryPinned: Bool = false,
        onSubmit: @escaping () async -> Void,
        onClear: @escaping () -> Void,
        onTogglePin: @escaping () -> Void = {},
        onRunPinned: @escaping (PinnedQuery) -> Void = { _ in },
        onRenamePinned: @escaping (PinnedQuery) -> Void = { _ in },
        onRemovePinned: @escaping (PinnedQuery) -> Void = { _ in }
    ) {
        self._text = text
        self.isLoading = isLoading
        self.hasResult = hasResult
        self.pinnedQueries = pinnedQueries
        self.isCurrentQueryPinned = isCurrentQueryPinned
        self.onSubmit = onSubmit
        self.onClear = onClear
        self.onTogglePin = onTogglePin
        self.onRunPinned = onRunPinned
        self.onRenamePinned = onRenamePinned
        self.onRemovePinned = onRemovePinned
        self.chips = Array(Self.exampleQueries.dropFirst().shuffled().prefix(3))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            barRow
            Rectangle().fill(Theme.fg).frame(height: 1)
            if !pinnedQueries.isEmpty {
                PinnedChipsView(
                    pinned: pinnedQueries,
                    onTap: { pin in
                        text = pin.query
                        onRunPinned(pin)
                    },
                    onRename: onRenamePinned,
                    onRemove: onRemovePinned
                )
                .padding(.top, 8)
                .padding(.bottom, showExampleChips ? 0 : 4)
            }
            if showExampleChips {
                exampleChipRow
                    .padding(.top, pinnedQueries.isEmpty ? 8 : 4)
                    .padding(.bottom, 4)
            }
        }
    }

    private var showExampleChips: Bool { text.isEmpty && !hasResult }

    private var barRow: some View {
        HStack(spacing: 8) {
            Text("ASK")
                .font(Theme.Font.display(size: 10, weight: .bold))
                .kerning(1.8)
                .foregroundStyle(Theme.muted)

            TimelineView(.periodic(from: .now, by: 4.0)) { ctx in
                placeholderField(at: ctx.date)
            }

            if isLoading {
                ProgressView().controlSize(.small)
            } else if hasResult {
                Button(action: onTogglePin) {
                    Text(isCurrentQueryPinned ? "★ PINNED" : "★ PIN")
                        .font(Theme.Font.display(size: 10, weight: .bold))
                        .kerning(1.8)
                        .foregroundStyle(isCurrentQueryPinned ? Theme.accent : Theme.fg)
                }
                .buttonStyle(.plain)

                Button {
                    onClear()
                    focused = false
                } label: {
                    Text("× CLEAR")
                        .font(Theme.Font.display(size: 10, weight: .bold))
                        .kerning(1.8)
                        .foregroundStyle(Theme.fg)
                }
                .buttonStyle(.plain)
            } else if !text.isEmpty {
                Button {
                    onClear()
                    focused = false
                } label: {
                    Text("× CLEAR")
                        .font(Theme.Font.display(size: 10, weight: .bold))
                        .kerning(1.8)
                        .foregroundStyle(Theme.fg)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
    }

    private var exampleChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(chips, id: \.self) { chip in
                    Button {
                        text = chip
                        Task { await onSubmit() }
                    } label: {
                        Text(chip)
                            .font(Theme.Font.display(size: 10, weight: .bold))
                            .kerning(1.4)
                            .foregroundStyle(Theme.fg)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .overlay(Rectangle().stroke(Theme.fg, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func placeholderIdx(at date: Date) -> Int {
        if focused || !text.isEmpty { return 0 }
        let sec = Int(date.timeIntervalSinceReferenceDate)
        return (sec / 4) % Self.exampleQueries.count
    }

    @ViewBuilder
    private func placeholderField(at date: Date) -> some View {
        let idx = placeholderIdx(at: date)
        #if os(iOS)
        TextField(Self.exampleQueries[idx], text: $text)
            .focused($focused)
            .textFieldStyle(.plain)
            .font(Theme.Font.display(size: 13, weight: .regular))
            .foregroundStyle(Theme.fg)
            .submitLabel(.search)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .onSubmit { Task { await onSubmit() } }
        #else
        TextField(Self.exampleQueries[idx], text: $text)
            .focused($focused)
            .textFieldStyle(.plain)
            .font(Theme.Font.display(size: 13, weight: .regular))
            .foregroundStyle(Theme.fg)
            .submitLabel(.search)
            .autocorrectionDisabled()
            .onSubmit { Task { await onSubmit() } }
        #endif
    }
}

#Preview("Empty, Light") {
    FontRegistration.registerNHG()
    return QueryBarView(
        text: .constant(""),
        isLoading: false,
        hasResult: false,
        onSubmit: {},
        onClear: {}
    )
    .padding(20)
    .preferredColorScheme(.light)
}

#Preview("With pinned, Dark") {
    FontRegistration.registerNHG()
    return QueryBarView(
        text: .constant("next tuesday after 2pm"),
        isLoading: false,
        hasResult: true,
        pinnedQueries: [
            PinnedQuery(label: "Quick AM", query: "30 min tomorrow morning"),
            PinnedQuery(label: "Coffee", query: "coffee next week")
        ],
        isCurrentQueryPinned: false,
        onSubmit: {},
        onClear: {}
    )
    .padding(20)
    .background(Theme.bg)
    .preferredColorScheme(.dark)
}
```

- [ ] **Step 2: Build to verify**

```bash
swift build --package-path /Users/jamest/open-time/OpenTimeUI
```

Expected: build succeeds.

- [ ] **Step 3: Verify all existing callers still compile**

```bash
swift build --package-path /Users/jamest/open-time/OpenTimeUI 2>&1 | grep -i "error\|warning"
```

The new arguments all have defaults, so existing call sites in the package itself are unaffected. The app-target call site is updated in Task 11.

- [ ] **Step 4: Commit**

```bash
git add OpenTimeUI/Sources/OpenTimeUI/Components/QueryBarView.swift
git commit -m "feat(ui): QueryBarView pin button + pinned-chips row"
```

---

## Task 10: `PinnedQueriesView` Settings screen

List with edit/move/delete + add sheet that validates with `QueryParser`.

**Files:**
- Create: `OpenTime/Views/PinnedQueriesView.swift`

- [ ] **Step 1: Implement the screen**

Create `OpenTime/Views/PinnedQueriesView.swift`:

```swift
import SwiftUI
import OpenTimeUI

struct PinnedQueriesView: View {

    @EnvironmentObject private var store: PinnedQueryStore
    @State private var showingAdd = false
    @State private var renameTarget: PinnedQuery?
    @State private var renameText: String = ""
    @State private var showCapAlert = false

    var body: some View {
        List {
            if store.pinned.isEmpty {
                Text("Pin a query from the search bar (★ PIN) to keep it here.")
                    .font(Theme.Font.display(size: 12, weight: .regular))
                    .foregroundStyle(Theme.muted)
                    .listRowBackground(Theme.bg)
            } else {
                ForEach(store.pinned) { pin in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pin.label.uppercased())
                            .font(Theme.Font.display(size: 13, weight: .bold))
                            .kerning(1.2)
                            .foregroundStyle(Theme.fg)
                        Text(pin.query)
                            .font(Theme.Font.display(size: 11, weight: .regular))
                            .foregroundStyle(Theme.muted)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        renameTarget = pin
                        renameText = pin.label
                    }
                    .listRowBackground(Theme.bg)
                }
                .onDelete { offsets in
                    for index in offsets {
                        store.delete(store.pinned[index].id)
                    }
                }
                .onMove { offsets, destination in
                    store.move(from: offsets, to: destination)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle("Pinned Queries")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddPinnedQuerySheet { label, query in
                store.add(query: query, label: label.isEmpty ? nil : label)
            }
        }
        .alert("Rename", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("Label", text: $renameText)
            Button("Save") {
                if let pin = renameTarget {
                    store.rename(pin.id, to: renameText)
                }
                renameTarget = nil
            }
            Button("Cancel", role: .cancel) { renameTarget = nil }
        }
        .alert("Pinned-query limit reached",
               isPresented: Binding(
                get: { store.didTrimAtCap },
                set: { if !$0 { store.didTrimAtCap = false } }
               )) {
            Button("OK", role: .cancel) { store.didTrimAtCap = false }
        } message: {
            Text("Maximum of 20 pinned queries. Oldest entries were removed.")
        }
    }
}

private struct AddPinnedQuerySheet: View {

    var onSave: (_ label: String, _ query: String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var query = ""
    @State private var validationError: String?
    @State private var validating = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Label (optional)") {
                    TextField("e.g. Quick AM", text: $label)
                        .autocorrectionDisabled()
                }
                Section("Query") {
                    TextField("e.g. 30 min tomorrow morning", text: $query)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                if let validationError {
                    Section { Text(validationError).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Add Pinned Query")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || validating)
                }
            }
        }
    }

    private func save() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        validating = true
        defer { validating = false }
        do {
            let intent = try await QueryParser.parse(trimmed, now: .now)
            // Reject if the parser produced no dates AND no duration AND no hour bounds —
            // those queries match nothing useful.
            if intent.startDate == nil
                && intent.durationMin == nil
                && intent.startHour == nil
                && intent.endHour == nil {
                validationError = "We couldn't make sense of that query. Try \"30 min tomorrow morning\" or \"coffee next week\"."
                return
            }
            onSave(label, trimmed)
            dismiss()
        } catch {
            validationError = "Couldn't validate that query. Try again."
        }
    }
}
```

- [ ] **Step 2: Build the app target**

```bash
xcodebuild -project /Users/jamest/open-time/OpenTime.xcodeproj \
  -scheme OpenTime \
  -destination 'generic/platform=iOS Simulator' \
  build 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add OpenTime/Views/PinnedQueriesView.swift
git commit -m "feat(app): PinnedQueriesView — list, rename, reorder, delete, add+validate"
```

---

## Task 11: Wire `pinStore` into `ContentView`

Add the `PinnedQueryStore` ownership, track `lastSubmittedQuery`, pass everything into `QueryBarView`, and add the NavigationLink to the toolbar Menu.

**Files:**
- Modify: `OpenTime/ContentView.swift`

- [ ] **Step 1: Add the store and submitted-query tracking**

In `ContentView.swift`, near the other `@State` declarations around line 32–33, add:

```swift
@StateObject private var pinStore = PinnedQueryStore()
@State private var lastSubmittedQuery: String = ""
@State private var renameTarget: PinnedQuery?
@State private var renameText: String = ""
```

- [ ] **Step 2: Update `runQuery()` to record the submitted text**

Find `private func runQuery() async` (around line 185) and after the existing `let text = queryText.trimmingCharacters(in: .whitespaces)` line, add:

```swift
lastSubmittedQuery = text
```

(Place it before any `guard text.isEmpty` early-out so we always remember the most recent attempt.)

- [ ] **Step 3: Update `clearQuery()` to clear the tracked value**

In `clearQuery()` (around line 219), after `queryResult = nil`, add:

```swift
lastSubmittedQuery = ""
```

- [ ] **Step 4: Update the `QueryBarView` call site**

Replace the existing `QueryBarView(…)` block (around lines 125–131) with:

```swift
QueryBarView(
    text: $queryText,
    isLoading: queryIsLoading,
    hasResult: queryResult != nil || queryError,
    pinnedQueries: pinStore.pinned,
    isCurrentQueryPinned: pinStore.isPinned(query: lastSubmittedQuery),
    onSubmit: { await runQuery() },
    onClear: clearQuery,
    onTogglePin: {
        guard !lastSubmittedQuery.isEmpty else { return }
        pinStore.toggle(query: lastSubmittedQuery)
    },
    onRunPinned: { pin in
        queryText = pin.query
        Task { await runQuery() }
    },
    onRenamePinned: { pin in
        renameTarget = pin
        renameText = pin.label
    },
    onRemovePinned: { pin in
        pinStore.delete(pin.id)
    }
)
```

Then attach a rename alert next to the existing `.toolbar { toolbarContent }` modifier (same nesting level as `.environmentObject(pinStore)` in Step 5):

```swift
.alert("Rename", isPresented: Binding(
    get: { renameTarget != nil },
    set: { if !$0 { renameTarget = nil } }
)) {
    TextField("Label", text: $renameText)
    Button("Save") {
        if let pin = renameTarget {
            pinStore.rename(pin.id, to: renameText)
        }
        renameTarget = nil
    }
    Button("Cancel", role: .cancel) { renameTarget = nil }
}
```

- [ ] **Step 5: Inject the store as an environment object for `PinnedQueriesView`**

Find the outermost view in `ContentView`'s body that the `NavigationStack` wraps. After the existing `.toolbar { toolbarContent }` (around line 67), add:

```swift
.environmentObject(pinStore)
```

- [ ] **Step 6: Add the Settings NavigationLink to the toolbar Menu**

Find the `Menu { … }` block in `toolbarContent` (around line 429). Inside the menu, after the `Picker("Slot Duration", …) { … }` block and before the existing "Refresh" `Button`, add:

```swift
NavigationLink {
    PinnedQueriesView()
} label: {
    Label("Pinned Queries", systemImage: "star")
}
```

- [ ] **Step 7: Build the app**

```bash
xcodebuild -project /Users/jamest/open-time/OpenTime.xcodeproj \
  -scheme OpenTime \
  -destination 'generic/platform=iOS Simulator' \
  build 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 8: Commit**

```bash
git add OpenTime/ContentView.swift
git commit -m "feat(app): wire PinnedQueryStore into ContentView + toolbar entry"
```

---

## Task 12: Manual smoke + verification

End-to-end check on a simulator and (if available) a device on a personal iCloud account. No commit unless a regression is found and fixed.

- [ ] **Step 1: Run the app on the iOS 26 simulator**

```bash
xcodebuild -project /Users/jamest/open-time/OpenTime.xcodeproj \
  -scheme OpenTime \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  build 2>&1 | tail -5
```

Then launch through Xcode (Product → Run). Grant calendar access when prompted.

- [ ] **Step 2: Smoke "in X weeks"**

Type "in 3 weeks am I free" into the ASK bar and submit.

Expected:
- `QueryResultBanner` displays a date range (en-dash between two short dates).
- The visible calendar window covers roughly 14 days centered three weeks out.
- No error banner.

Repeat with "in a week" and "in 2 months".

- [ ] **Step 3: Smoke pinning**

After the "in 3 weeks" result is visible:
- Tap `★ PIN`. Confirm the button reads `★ PINNED` (in accent color).
- Tap `× CLEAR`. Confirm a filled chip appears with the query text in uppercase.
- Tap the chip. Confirm the query re-runs and shows the same result.

- [ ] **Step 4: Smoke persistence**

Force-quit the app (swipe up). Re-launch. Confirm the pinned chip is still present.

- [ ] **Step 5: Smoke airplane mode**

Toggle airplane mode on the simulator host. Re-launch. Confirm pinned chip is still present (loaded from UserDefaults mirror).

- [ ] **Step 6: Smoke Settings**

Open the toolbar Menu → "Pinned Queries". Confirm the list shows the pinned entry. Tap the row → rename → save. Confirm the chip in the bar updates immediately. Swipe-delete the row → confirm chip disappears.

- [ ] **Step 7: Smoke add-from-Settings + validation**

In `PinnedQueriesView`, tap "+". Enter label "Garbage", query "asdfqwer". Tap Save. Expected: inline error "We couldn't make sense of that query…".

Re-try with label "Coffee", query "coffee next week". Expected: sheet dismisses and a new chip appears.

- [ ] **Step 8: (Optional, device-only) Smoke iCloud sync**

Install on a second iCloud-signed device. Wait ~30s. Confirm pinned chips appear there too. Change a label on Device A → confirm Device B updates within the sync window.

- [ ] **Step 9: Smoke the cap**

In `PinnedQueriesView`, add 21 entries (use any text that parses, e.g. "tomorrow 1", "tomorrow 2", …). Confirm:
- List has 20 entries.
- A "Pinned-query limit reached" alert appears once.
- Oldest entry is gone.

- [ ] **Step 10: If any smoke fails, fix inline and re-test**

For each failure, write a minimal regression test if reasonable, fix, run `swift test`, and commit with a `fix(...)` message.

- [ ] **Step 11: Open a PR**

```bash
git push -u origin feature/pinned-queries-and-in-x-weeks
gh pr create --title "feat(opentime): pinned queries + \"in N weeks/months\"" --body "$(cat <<'EOF'
## Summary
- Teaches `QueryParser` to interpret "in N weeks/months" as a 14-day window centered on the target date.
- Adds `PinnedQueryStore` (iCloud KVS + UserDefaults mirror) and lets users pin queries from the search bar.
- Adds `PinnedQueriesView` settings screen (rename, reorder, delete, add-with-validation).

## Test plan
- [ ] Type "in 3 weeks am I free" → 14-day window centered three weeks out.
- [ ] Pin the query → chip persists across force-quit and airplane mode.
- [ ] Rename / reorder / delete from Settings.
- [ ] Validation rejects nonsense queries in the add sheet.
- [ ] (Device) Confirm pin syncs to a second iCloud device.

Spec: `docs/superpowers/specs/2026-05-21-opentime-pinned-queries-and-in-x-weeks-design.md`

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

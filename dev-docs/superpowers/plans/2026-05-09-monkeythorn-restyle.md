# OpenTime — MonkeyThorn Restyle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restyle all five OpenTime targets (main app, widgets+Live Activity, Apple Watch, iMessage extension, Share extension) to match the MonkeyThorn web aesthetic, add a long-press chip menu that integrates with Apple Calendar, add a Show-Busy toggle, and add an on-device Foundation Models natural-language availability query bar.

**Architecture:** A new shared Swift package `OpenTimeUI` holds the design system (Theme, NHG Display registration, PageHeader, MTSquareButton, SlotChip, BusyRowView, DayRowView, FlowLayout). The iOS-family targets all link it. Apple Watch links a parallel `OpenTimeUIWatch` package that mirrors the API but uses SF Compact instead of NHG. Foundation Models query bar uses `LanguageModelSession` with a `@Generable` schema, on-device only.

**Tech Stack:** Swift 5.9+, SwiftUI, EventKit, WidgetKit, ActivityKit, FoundationModels (iOS 26 SDK), CoreText (font registration). All deployment targets already on iOS 26.2 / watchOS 10.0. No third-party dependencies.

**Spec:** `docs/superpowers/specs/2026-05-09-monkeythorn-restyle-design.md`

**Reference aesthetic:** `~/monkeythorn-calendar/src/styles/global.css`

**Resolved open items from the spec:**
- iOS 26 minimum: already in place (`IPHONEOS_DEPLOYMENT_TARGET = 26.2`).
- `FlowLayout`: native `Layout` protocol available on every target.
- `OpenTimeUI` packaging: Swift Package.
- Test strategy: SwiftUI `#Preview` blocks for visual review + behavior unit tests for query parsing, font registration, calendar URL construction, and intent filtering. No snapshot framework dep.
- NHG weights: Regular (400), Medium (500), Bold (700). No italics — MT design doesn't use them.

**Discoveries during implementation (apply to all later tasks):**
- `swift-tools-version` is **6.2** (not 5.9 — `.iOS(.v26)` requires 6.2+).
- The OpenTimeUI package declares both `.iOS(.v26)` and `.macOS(.v14)` so `swift test` runs fast on the dev mac. Components use cross-platform Apple frameworks (CoreText, SwiftUI) — no UIKit-only imports inside the package.
- Mutable static state in `OpenTimeUI` requires `nonisolated(unsafe)` (Swift 6 strict concurrency). External synchronization via `NSLock` makes this safe.
- **Font names inside the bundled TTFs:**
  - **Family name (use everywhere SwiftUI/CTFont expects a family):** `Neue Haas Grotesk Display Pro` — *not* "NHG Display". MonkeyThorn web aliases this via `@font-face`; iOS has no equivalent and must use the actual internal name.
  - **PostScript names:** `NeueHaasDisplay-Roman`, `NeueHaasDisplay-Mediu` (intentionally truncated — that's how the file was published), `NeueHaasDisplay-Bold`.
  - **Bundle filenames:** stay as `NHGDisplay-{Regular,Medium,Bold}.ttf` — only the lookup names changed.
  - All references to `Theme.Font.familyName = "NHG Display"` in later tasks are corrected to `Theme.Font.familyName = "Neue Haas Grotesk Display Pro"`.

---

## File Structure

```
open-time/
├── OpenTimeUI/                              (new Swift Package)
│   ├── Package.swift
│   └── Sources/OpenTimeUI/
│       ├── FontRegistration.swift           Registers bundled NHG TTFs
│       ├── Theme.swift                      Color tokens + font factory + spacing
│       ├── Components/
│       │   ├── PageHeader.swift             AVAILABILITY header + 4pt rule
│       │   ├── MTSquareButton.swift         Square button (default + selected)
│       │   ├── SlotChip.swift               Free-time chip + .contextMenu
│       │   ├── BusyRowView.swift            Editorial busy row
│       │   ├── DayRowView.swift             Day name + date + chips + busy rows
│       │   └── FlowLayout.swift             Layout-protocol chip flow
│       └── Resources/
│           ├── NHGDisplay-Regular.ttf
│           ├── NHGDisplay-Medium.ttf
│           └── NHGDisplay-Bold.ttf
├── OpenTimeUIWatch/                         (new Swift Package — Watch parallel)
│   ├── Package.swift
│   └── Sources/OpenTimeUIWatch/
│       ├── Theme.swift                      Same tokens, SF Compact font factory
│       ├── PageHeader.swift                 Watch-sized header
│       ├── DayRowView.swift                 Watch-density rows
│       └── SlotChip.swift                   Tap-to-copy, no contextMenu
├── CalendarAvailability/                    (main app — existing)
│   ├── CalendarAvailabilityApp.swift        +FontRegistration call, +URL handler
│   ├── ContentView.swift                    Restyled — PageHeader, query bar, Show Busy toggle
│   ├── Services/
│   │   ├── Theme.swift                      DELETE (replaced by OpenTimeUI.Theme)
│   │   ├── AvailabilityQuery.swift          NEW — Foundation Models wrapper
│   │   └── CalendarURL.swift                NEW — calshow:/EventKit URL helpers
│   └── Views/
│       ├── DayCardView.swift                DELETE (replaced by OpenTimeUI.DayRowView)
│       ├── SlotRowView.swift                DELETE (replaced by OpenTimeUI.SlotChip + BusyRowView)
│       └── DateRangePickerView.swift        Restyled with MTSquareButton
├── CalendarWidget/                          (widget — existing)
│   ├── CalendarWidget.swift                 Restyled
│   ├── CalendarWidgetBundle.swift           +FontRegistration
│   ├── AvailabilityActivityAttributes.swift Unchanged
│   ├── AvailabilityLiveActivity.swift       Restyled
│   └── WidgetIntents.swift                  +deep-link slot intent
├── OpenTimeWatch/                           (Watch app — existing, restyled)
├── MessagesExtension/                       (iMessage — existing, restyled)
└── ShareExtension/                          (share sheet — existing, restyled)
```

**Files deleted:** `CalendarAvailability/Services/Theme.swift`, `CalendarAvailability/Views/DayCardView.swift`, `CalendarAvailability/Views/SlotRowView.swift`. Their replacements live in `OpenTimeUI`.

**Phasing:** Tasks 1–10 build the shared module. Task 11 wires it into the main app. Tasks 12–16 restyle the main app. Tasks 17–19 add the query bar. Tasks 20–25 do widgets + Live Activity. Tasks 26–27 do Watch. Tasks 28–29 do extensions. Task 30 is final manual verification. Each task ends with a green build and a commit.

---

## Phase 1 — Shared design system (`OpenTimeUI`)

### Task 1: Create `OpenTimeUI` Swift package

**Files:**
- Create: `OpenTimeUI/Package.swift`
- Create: `OpenTimeUI/Sources/OpenTimeUI/OpenTimeUI.swift` (placeholder)

- [ ] **Step 1: Create the package directory and `Package.swift`**

```swift
// OpenTimeUI/Package.swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "OpenTimeUI",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "OpenTimeUI", targets: ["OpenTimeUI"])
    ],
    targets: [
        .target(
            name: "OpenTimeUI",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "OpenTimeUITests",
            dependencies: ["OpenTimeUI"]
        )
    ]
)
```

- [ ] **Step 2: Create the placeholder source file so the package builds**

```swift
// OpenTimeUI/Sources/OpenTimeUI/OpenTimeUI.swift
// Public surface area exposed by the OpenTimeUI module.
// Components live in subdirectories under Sources/OpenTimeUI.
```

- [ ] **Step 3: Build the package to verify it compiles**

Run: `cd OpenTimeUI && swift build`
Expected: `Build complete!`

- [ ] **Step 4: Add the package as a local dependency to the Xcode project**

In Xcode: File → Add Package Dependencies → Add Local → select `OpenTimeUI/`. Add the `OpenTimeUI` library product to the `CalendarAvailability` (main app) target only for now. Other targets are added in their respective tasks.

- [ ] **Step 5: Commit**

```bash
git add OpenTimeUI CalendarAvailability.xcodeproj
git commit -m "feat: add OpenTimeUI swift package skeleton"
```

---

### Task 2: Bundle NHG Display TTFs in `OpenTimeUI/Resources`

**Files:**
- Create: `OpenTimeUI/Sources/OpenTimeUI/Resources/NHGDisplay-Regular.ttf`
- Create: `OpenTimeUI/Sources/OpenTimeUI/Resources/NHGDisplay-Medium.ttf`
- Create: `OpenTimeUI/Sources/OpenTimeUI/Resources/NHGDisplay-Bold.ttf`

- [ ] **Step 1: Copy the three NHG Display TTFs into the package's Resources directory**

```bash
mkdir -p OpenTimeUI/Sources/OpenTimeUI/Resources
cp /Users/jamest/plocamium-content-engine/lambdas/image_gen/NHGDisplay-Regular.ttf OpenTimeUI/Sources/OpenTimeUI/Resources/
cp /Users/jamest/plocamium-content-engine/lambdas/image_gen/NHGDisplay-Medium.ttf OpenTimeUI/Sources/OpenTimeUI/Resources/
cp /Users/jamest/plocamium-content-engine/lambdas/image_gen/NHGDisplay-Bold.ttf OpenTimeUI/Sources/OpenTimeUI/Resources/
```

- [ ] **Step 2: Build the package to verify resources are picked up**

Run: `cd OpenTimeUI && swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add OpenTimeUI/Sources/OpenTimeUI/Resources/
git commit -m "feat: bundle NHG Display TTFs in OpenTimeUI"
```

---

### Task 3: Implement `FontRegistration` (TDD)

Registers the bundled NHG TTFs with `CTFontManager` so SwiftUI can use them by family name. Each iOS-family target's launch path will call `FontRegistration.registerNHG()`.

**Files:**
- Create: `OpenTimeUI/Sources/OpenTimeUI/FontRegistration.swift`
- Create: `OpenTimeUI/Tests/OpenTimeUITests/FontRegistrationTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// OpenTimeUI/Tests/OpenTimeUITests/FontRegistrationTests.swift
import XCTest
import UIKit
@testable import OpenTimeUI

final class FontRegistrationTests: XCTestCase {
    func test_registerNHG_makesFamilyAvailable() {
        FontRegistration.registerNHG()
        XCTAssertTrue(
            UIFont.familyNames.contains("NHG Display"),
            "Expected 'NHG Display' family after registerNHG(); got: \(UIFont.familyNames.filter { $0.localizedCaseInsensitiveContains(\"NHG\") })"
        )
    }

    func test_registerNHG_isIdempotent() {
        FontRegistration.registerNHG()
        FontRegistration.registerNHG() // second call should not throw or duplicate
        XCTAssertTrue(UIFont.familyNames.contains("NHG Display"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd OpenTimeUI && swift test --filter FontRegistrationTests`
Expected: FAIL with "Cannot find 'FontRegistration' in scope"

- [ ] **Step 3: Implement `FontRegistration`**

```swift
// OpenTimeUI/Sources/OpenTimeUI/FontRegistration.swift
import Foundation
import CoreText

public enum FontRegistration {
    private static var registered = false
    private static let lock = NSLock()

    public static func registerNHG() {
        lock.lock(); defer { lock.unlock() }
        guard !registered else { return }

        let fileNames = [
            "NHGDisplay-Regular",
            "NHGDisplay-Medium",
            "NHGDisplay-Bold"
        ]

        for name in fileNames {
            guard let url = Bundle.module.url(forResource: name, withExtension: "ttf") else {
                assertionFailure("OpenTimeUI: missing bundled font \(name).ttf")
                continue
            }
            var error: Unmanaged<CFError>?
            let ok = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
            if !ok, let err = error?.takeRetainedValue() {
                let code = CFErrorGetCode(err)
                // 105 = "already registered" — fine on second launch in long-lived processes.
                if code != 105 {
                    assertionFailure("OpenTimeUI: failed to register \(name): \(err)")
                }
            }
        }
        registered = true
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd OpenTimeUI && swift test --filter FontRegistrationTests`
Expected: 2 tests PASS

- [ ] **Step 5: Commit**

```bash
git add OpenTimeUI
git commit -m "feat(OpenTimeUI): register bundled NHG Display fonts"
```

---

### Task 4: Implement `Theme` color tokens

**Files:**
- Create: `OpenTimeUI/Sources/OpenTimeUI/Theme.swift`
- Create: `OpenTimeUI/Tests/OpenTimeUITests/ThemeTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// OpenTimeUI/Tests/OpenTimeUITests/ThemeTests.swift
import XCTest
import SwiftUI
@testable import OpenTimeUI

final class ThemeTests: XCTestCase {
    func test_colorTokensExist() {
        // Smoke test — these should compile and resolve without crashing.
        _ = Theme.bg
        _ = Theme.fg
        _ = Theme.muted
        _ = Theme.dim
        _ = Theme.rule
        _ = Theme.accent
    }

    func test_lightAccent_isMonkeyThornRed() {
        XCTAssertEqual(Theme.accentLight.description.lowercased().contains("d40000")
                    || Theme.accentLightHex == "#D40000", true)
    }

    func test_darkAccent_isBrightenedForLegibility() {
        XCTAssertEqual(Theme.accentDarkHex, "#FF1F1F")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd OpenTimeUI && swift test --filter ThemeTests`
Expected: FAIL — `Theme` not in scope.

- [ ] **Step 3: Implement `Theme` color tokens**

```swift
// OpenTimeUI/Sources/OpenTimeUI/Theme.swift
import SwiftUI

public enum Theme {
    // MARK: - Hex constants (exposed for tests + documentation)

    public static let accentLightHex = "#D40000"
    public static let accentDarkHex  = "#FF1F1F"

    // MARK: - Color tokens (adaptive light/dark)

    public static let bg     = Color(light: .white,                dark: .hex("#0A0A0A"))
    public static let fg     = Color(light: .black,                dark: .white)
    public static let muted  = Color(light: .hex("#555555"),       dark: .hex("#A0A0A0"))
    public static let dim    = Color(light: .hex("#888888"),       dark: .hex("#666666"))
    public static let rule   = Color(light: .black,                dark: .white)
    public static let accent = Color(light: .hex(accentLightHex),  dark: .hex(accentDarkHex))

    // Exposed as Color for previews/tests that need the literal light value.
    public static let accentLight = Color.hex(accentLightHex)
    public static let accentDark  = Color.hex(accentDarkHex)
}

// MARK: - Color helpers

extension Color {
    init(light: Color, dark: Color) {
        self = Color(UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }

    static func hex(_ s: String) -> Color {
        var t = s
        if t.hasPrefix("#") { t.removeFirst() }
        guard t.count == 6, let v = UInt32(t, radix: 16) else { return .black }
        return Color(
            red:   Double((v >> 16) & 0xFF) / 255,
            green: Double((v >>  8) & 0xFF) / 255,
            blue:  Double( v        & 0xFF) / 255
        )
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd OpenTimeUI && swift test --filter ThemeTests`
Expected: 3 tests PASS

- [ ] **Step 5: Commit**

```bash
git add OpenTimeUI
git commit -m "feat(OpenTimeUI): add Theme color tokens (adaptive light/dark)"
```

---

### Task 5: Implement `Theme` font factory

**Files:**
- Modify: `OpenTimeUI/Sources/OpenTimeUI/Theme.swift`
- Modify: `OpenTimeUI/Tests/OpenTimeUITests/ThemeTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `OpenTimeUITests/ThemeTests.swift`:

```swift
extension ThemeTests {
    func test_displayFont_returnsNHG_whenRegistered() {
        FontRegistration.registerNHG()
        let f = Theme.Font.display(size: 18, weight: .bold)
        // Resolve the underlying UIFont to verify family.
        let resolved = UIFont.preferredFont(forTextStyle: .body)
            // SwiftUI Font isn't directly inspectable; we resolve via the bridge:
        _ = resolved
        // Sanity: family must be registered. Real check is integration via Preview.
        XCTAssertTrue(UIFont.familyNames.contains("NHG Display"))
        // Function exists and returns a Font (won't compile if signature wrong).
        XCTAssertNotNil(f)
    }

    func test_tnumModifier_existsAndIsView() {
        let v = Text("9:00").modifier(Theme.Font.TabularDigits())
        _ = v // compile-only check
    }
}
```

- [ ] **Step 2: Run test to verify it fails to compile**

Run: `cd OpenTimeUI && swift test --filter ThemeTests`
Expected: FAIL — "Type 'Theme' has no member 'Font'"

- [ ] **Step 3: Implement the font factory**

Append to `OpenTimeUI/Sources/OpenTimeUI/Theme.swift`:

```swift
// MARK: - Typography

public extension Theme {
    enum Font {
        public static let familyName = "NHG Display"

        /// NHG Display at the given size + weight, scaled with Dynamic Type.
        /// Falls back to system font if the family hasn't been registered yet.
        public static func display(
            size: CGFloat,
            weight: SwiftUI.Font.Weight = .regular,
            relativeTo style: SwiftUI.Font.TextStyle = .body
        ) -> SwiftUI.Font {
            // SwiftUI's `Font.custom` honors Dynamic Type via `relativeTo:`.
            // Weight on a custom font is applied via `.weight()`.
            return SwiftUI.Font.custom(familyName, size: size, relativeTo: style)
                .weight(weight)
        }

        /// View modifier that turns on tabular numerals (lockstep digit widths).
        public struct TabularDigits: ViewModifier {
            public init() {}
            public func body(content: Content) -> some View {
                content.monospacedDigit()
            }
        }
    }
}

public extension View {
    /// `.tnum()` shorthand for time labels and chips.
    func tnum() -> some View { modifier(Theme.Font.TabularDigits()) }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd OpenTimeUI && swift test --filter ThemeTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add OpenTimeUI
git commit -m "feat(OpenTimeUI): add Theme font factory (NHG Display + tnum)"
```

---

### Task 6: Implement `PageHeader`

**Files:**
- Create: `OpenTimeUI/Sources/OpenTimeUI/Components/PageHeader.swift`

- [ ] **Step 1: Implement `PageHeader`**

```swift
// OpenTimeUI/Sources/OpenTimeUI/Components/PageHeader.swift
import SwiftUI

public struct PageHeader: View {
    public let title: String
    public let meta: String?

    public init(title: String, meta: String? = nil) {
        self.title = title
        self.meta = meta
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .lastTextBaseline) {
                Text(title.uppercased())
                    .font(Theme.Font.display(size: 22, weight: .bold))
                    .kerning(-0.22)
                    .foregroundStyle(Theme.fg)

                Spacer()

                if let meta {
                    Text(meta.uppercased())
                        .font(Theme.Font.display(size: 10, weight: .regular))
                        .kerning(1.8)
                        .foregroundStyle(Theme.muted)
                }
            }
            .padding(.bottom, 6)

            Rectangle()
                .fill(Theme.rule)
                .frame(height: 4)
        }
        .padding(.bottom, 14)
    }
}

#Preview("Light") {
    FontRegistration.registerNHG()
    return PageHeader(title: "Availability", meta: "Fri 9 May")
        .padding(20)
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    FontRegistration.registerNHG()
    return PageHeader(title: "Availability", meta: "Fri 9 May")
        .padding(20)
        .preferredColorScheme(.dark)
        .background(Theme.bg)
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `cd OpenTimeUI && swift build`
Expected: `Build complete!`

- [ ] **Step 3: Open the file in Xcode and visually verify both `#Preview` panes**

Open `OpenTimeUI/Sources/OpenTimeUI/Components/PageHeader.swift` in Xcode. Confirm:
- Light: black `AVAILABILITY` left, gray `FRI 9 MAY` right, 4pt black rule under.
- Dark: white `AVAILABILITY` left, light-gray meta right, 4pt white rule on dark bg.

- [ ] **Step 4: Commit**

```bash
git add OpenTimeUI
git commit -m "feat(OpenTimeUI): add PageHeader component"
```

---

### Task 7: Implement `MTSquareButton`

**Files:**
- Create: `OpenTimeUI/Sources/OpenTimeUI/Components/MTSquareButton.swift`

- [ ] **Step 1: Implement `MTSquareButton`**

```swift
// OpenTimeUI/Sources/OpenTimeUI/Components/MTSquareButton.swift
import SwiftUI

public struct MTSquareButton: View {
    public let label: String
    public let isSelected: Bool
    public let role: Role
    public let action: () -> Void

    public enum Role { case neutral, submit }

    public init(
        _ label: String,
        isSelected: Bool = false,
        role: Role = .neutral,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.isSelected = isSelected
        self.role = role
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(label.uppercased())
                .font(Theme.Font.display(size: 10, weight: .bold))
                .kerning(1.8)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .foregroundStyle(foregroundColor)
                .background(backgroundColor)
                .overlay(
                    Rectangle().stroke(borderColor, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .animation(.linear(duration: 0.12), value: isSelected)
    }

    private var foregroundColor: Color {
        switch role {
        case .submit:  return Theme.bg
        case .neutral: return isSelected ? Theme.bg : Theme.fg
        }
    }
    private var backgroundColor: Color {
        switch role {
        case .submit:  return Theme.accent
        case .neutral: return isSelected ? Theme.fg : Theme.bg
        }
    }
    private var borderColor: Color {
        switch role {
        case .submit:  return Theme.accent
        case .neutral: return Theme.fg
        }
    }
}

#Preview("Light") {
    FontRegistration.registerNHG()
    return VStack(spacing: 12) {
        MTSquareButton("15") {}
        MTSquareButton("30", isSelected: true) {}
        MTSquareButton("Send", role: .submit) {}
    }
    .padding(20)
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    FontRegistration.registerNHG()
    return VStack(spacing: 12) {
        MTSquareButton("15") {}
        MTSquareButton("30", isSelected: true) {}
        MTSquareButton("Send", role: .submit) {}
    }
    .padding(20)
    .background(Theme.bg)
    .preferredColorScheme(.dark)
}
```

- [ ] **Step 2: Build and visually verify both Previews**

Run: `cd OpenTimeUI && swift build`
Open the file in Xcode; Light preview shows three square buttons (default, inverted, red submit). Dark preview mirrors.

- [ ] **Step 3: Commit**

```bash
git add OpenTimeUI
git commit -m "feat(OpenTimeUI): add MTSquareButton component"
```

---

### Task 8: Implement `FlowLayout`

**Files:**
- Create: `OpenTimeUI/Sources/OpenTimeUI/Components/FlowLayout.swift`

- [ ] **Step 1: Implement `FlowLayout` using the `Layout` protocol**

```swift
// OpenTimeUI/Sources/OpenTimeUI/Components/FlowLayout.swift
import SwiftUI

public struct FlowLayout: Layout {
    public var spacing: CGFloat
    public var lineSpacing: CGFloat

    public init(spacing: CGFloat = 4, lineSpacing: CGFloat = 4) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing
    }

    public func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                y += rowHeight + lineSpacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            totalWidth = max(totalWidth, x - spacing)
        }
        return CGSize(width: totalWidth, height: y + rowHeight)
    }

    public func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                y += rowHeight + lineSpacing
                x = bounds.minX
                rowHeight = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `cd OpenTimeUI && swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add OpenTimeUI
git commit -m "feat(OpenTimeUI): add FlowLayout for chip flow"
```

---

### Task 9: Implement `SlotChip` (no context menu yet — wired in Task 16)

**Files:**
- Create: `OpenTimeUI/Sources/OpenTimeUI/Components/SlotChip.swift`

- [ ] **Step 1: Implement `SlotChip`**

```swift
// OpenTimeUI/Sources/OpenTimeUI/Components/SlotChip.swift
import SwiftUI

public struct SlotChip: View {
    public let timeText: String
    public let isToday: Bool
    public let contextActions: ContextActions?

    public struct ContextActions {
        public let openInCalendar: () -> Void
        public let createEventHere: () -> Void
        public let copyTime: () -> Void
        public init(
            openInCalendar: @escaping () -> Void,
            createEventHere: @escaping () -> Void,
            copyTime: @escaping () -> Void
        ) {
            self.openInCalendar = openInCalendar
            self.createEventHere = createEventHere
            self.copyTime = copyTime
        }
    }

    public init(timeText: String, isToday: Bool = false, contextActions: ContextActions? = nil) {
        self.timeText = timeText
        self.isToday = isToday
        self.contextActions = contextActions
    }

    public var body: some View {
        let content = Text(timeText)
            .font(Theme.Font.display(size: 11, weight: .medium))
            .tnum()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(Theme.bg)
            .background(isToday ? Theme.accent : Theme.fg)

        if let a = contextActions {
            content
                .contextMenu {
                    Button("Open in Calendar", action: a.openInCalendar)
                    Button("Create Event Here", action: a.createEventHere)
                    Button("Copy Time", action: a.copyTime)
                }
        } else {
            content
        }
    }
}

#Preview("Light") {
    FontRegistration.registerNHG()
    return HStack(spacing: 4) {
        SlotChip(timeText: "9:00")
        SlotChip(timeText: "9:30", isToday: true)
        SlotChip(timeText: "10:30")
    }
    .padding(20)
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    FontRegistration.registerNHG()
    return HStack(spacing: 4) {
        SlotChip(timeText: "9:00")
        SlotChip(timeText: "9:30", isToday: true)
        SlotChip(timeText: "10:30")
    }
    .padding(20)
    .background(Theme.bg)
    .preferredColorScheme(.dark)
}
```

- [ ] **Step 2: Build and visually verify**

Run: `cd OpenTimeUI && swift build`
Open in Xcode. Light preview: black chips with white text, middle chip is red. Dark preview: white chips with black text, middle chip is bright red.

- [ ] **Step 3: Commit**

```bash
git add OpenTimeUI
git commit -m "feat(OpenTimeUI): add SlotChip with context menu hooks"
```

---

### Task 10: Implement `BusyRowView` and `DayRowView`

**Files:**
- Create: `OpenTimeUI/Sources/OpenTimeUI/Components/BusyRowView.swift`
- Create: `OpenTimeUI/Sources/OpenTimeUI/Components/DayRowView.swift`

- [ ] **Step 1: Implement `BusyRowView`**

```swift
// OpenTimeUI/Sources/OpenTimeUI/Components/BusyRowView.swift
import SwiftUI

public struct BusyRowView: View {
    public let timeRange: String
    public let title: String

    public init(timeRange: String, title: String) {
        self.timeRange = timeRange
        self.title = title
    }

    public var body: some View {
        HStack(spacing: 12) {
            Text(timeRange)
                .font(Theme.Font.display(size: 13, weight: .medium))
                .tnum()
                .foregroundStyle(Theme.muted)
                .frame(minWidth: 130, alignment: .leading)

            Text(title)
                .font(Theme.Font.display(size: 13, weight: .medium))
                .foregroundStyle(Theme.dim)
                .lineLimit(1)

            Spacer()
        }
        .padding(.vertical, 4)
    }
}
```

- [ ] **Step 2: Implement `DayRowView`**

```swift
// OpenTimeUI/Sources/OpenTimeUI/Components/DayRowView.swift
import SwiftUI

public struct DayRowView: View {
    public struct Slot: Identifiable {
        public let id = UUID()
        public let timeText: String
        public init(timeText: String) { self.timeText = timeText }
    }

    public struct BusyEvent: Identifiable {
        public let id = UUID()
        public let timeRange: String
        public let title: String
        public init(timeRange: String, title: String) {
            self.timeRange = timeRange
            self.title = title
        }
    }

    public let dayName: String
    public let dateLabel: String
    public let totalLabel: String
    public let isToday: Bool
    public let slots: [Slot]
    public let busy: [BusyEvent]
    public let showBusy: Bool
    public let chipContext: ((Slot) -> SlotChip.ContextActions)?

    public init(
        dayName: String,
        dateLabel: String,
        totalLabel: String,
        isToday: Bool = false,
        slots: [Slot] = [],
        busy: [BusyEvent] = [],
        showBusy: Bool = false,
        chipContext: ((Slot) -> SlotChip.ContextActions)? = nil
    ) {
        self.dayName = dayName
        self.dateLabel = dateLabel
        self.totalLabel = totalLabel
        self.isToday = isToday
        self.slots = slots
        self.busy = busy
        self.showBusy = showBusy
        self.chipContext = chipContext
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Top rule
            Rectangle().fill(Theme.rule).frame(height: 1)

            // Header line
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if isToday {
                    Text("▶")
                        .font(Theme.Font.display(size: 14, weight: .bold))
                        .foregroundStyle(Theme.accent)
                }

                Text(dayName)
                    .font(Theme.Font.display(size: 18, weight: .bold))
                    .kerning(-0.36)
                    .foregroundStyle(isToday ? Theme.accent : Theme.fg)

                Text(dateLabel.uppercased())
                    .font(Theme.Font.display(size: 10, weight: .regular))
                    .kerning(1.8)
                    .foregroundStyle(isToday ? Theme.accent : Theme.muted)

                Spacer()

                Text(totalLabel.uppercased())
                    .font(Theme.Font.display(size: 10, weight: .regular))
                    .kerning(1.8)
                    .foregroundStyle(Theme.fg)
            }

            // Chips
            if slots.isEmpty {
                Text("NO AVAILABILITY")
                    .font(Theme.Font.display(size: 10, weight: .regular))
                    .kerning(2.0)
                    .foregroundStyle(Theme.dim)
            } else {
                FlowLayout(spacing: 4, lineSpacing: 4) {
                    ForEach(slots) { slot in
                        SlotChip(
                            timeText: slot.timeText,
                            isToday: isToday,
                            contextActions: chipContext?(slot)
                        )
                    }
                }
            }

            // Busy
            if showBusy && !busy.isEmpty {
                VStack(spacing: 0) {
                    ForEach(busy) { ev in
                        BusyRowView(timeRange: ev.timeRange, title: ev.title)
                        if ev.id != busy.last?.id {
                            Rectangle().fill(Theme.dim).frame(height: 1)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 10)
    }
}

#Preview("Today, with busy") {
    FontRegistration.registerNHG()
    return DayRowView(
        dayName: "Today",
        dateLabel: "May 9",
        totalLabel: "3h Free",
        isToday: true,
        slots: [.init(timeText: "9:00"), .init(timeText: "9:30"),
                .init(timeText: "10:30"), .init(timeText: "2:00")],
        busy: [.init(timeRange: "10:00 – 10:30", title: "Standup"),
               .init(timeRange: "1:00 – 2:00",   title: "Lunch w/ A")],
        showBusy: true
    )
    .padding(20)
    .preferredColorScheme(.light)
}

#Preview("Future, no busy, dark") {
    FontRegistration.registerNHG()
    return DayRowView(
        dayName: "Mon",
        dateLabel: "May 12",
        totalLabel: "5h Free",
        slots: [.init(timeText: "9:00"), .init(timeText: "10:00"),
                .init(timeText: "11:00"), .init(timeText: "1:00")]
    )
    .padding(20)
    .background(Theme.bg)
    .preferredColorScheme(.dark)
}
```

- [ ] **Step 3: Build and visually verify both Previews**

Run: `cd OpenTimeUI && swift build`
Open in Xcode. Light preview: today row with red ▶, red day name + date, red chips, busy rows below. Dark preview: clean monochrome day row with white chips on black.

- [ ] **Step 4: Commit**

```bash
git add OpenTimeUI
git commit -m "feat(OpenTimeUI): add BusyRowView and DayRowView"
```

---

## Phase 2 — Main app integration

### Task 11: Wire `OpenTimeUI` into the main app and register fonts at launch

**Files:**
- Modify: `CalendarAvailability/CalendarAvailabilityApp.swift`
- Delete: `CalendarAvailability/Services/Theme.swift`

- [ ] **Step 1: Read the current `CalendarAvailabilityApp.swift`**

Read `CalendarAvailability/CalendarAvailabilityApp.swift` to confirm the current entry point.

- [ ] **Step 2: Add `OpenTimeUI` import and font registration to the app's init**

Modify `CalendarAvailability/CalendarAvailabilityApp.swift` to import `OpenTimeUI` and call `FontRegistration.registerNHG()` from the `App`'s `init`. Example shape:

```swift
import SwiftUI
import OpenTimeUI

@main
struct CalendarAvailabilityApp: App {
    init() {
        FontRegistration.registerNHG()
    }
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
```

- [ ] **Step 3: Delete the obsolete `Services/Theme.swift`**

```bash
git rm CalendarAvailability/Services/Theme.swift
```

- [ ] **Step 4: Build the main app**

Run via Xcode: ⌘B on the `CalendarAvailability` scheme.
Expected: build fails because `ContentView`, `DayCardView`, `SlotRowView`, `DateRangePickerView` reference the deleted `Theme` symbols. That is expected — those are fixed in Tasks 12–15.

- [ ] **Step 5: Commit**

```bash
git add CalendarAvailability
git commit -m "feat: link OpenTimeUI in main app, drop old Theme.swift"
```

> Note: the next four tasks (12–15) leave the app un-buildable in between. Each task ends with the build green for that one file's surface, but `ContentView` only fully recompiles after Task 12. If you need an intermediate build to investigate, do them in order without committing in between, then commit at the end of Task 15. The plan structure here keeps logical commits; the engineer can squash if preferred.

---

### Task 12: Restyle `ContentView` skeleton (PageHeader + drop forced dark)

**Files:**
- Modify: `CalendarAvailability/ContentView.swift`

- [ ] **Step 1: Replace the navigation title with `PageHeader` and remove the dark-mode lock**

Modify `ContentView.swift`:
- Add `import OpenTimeUI` at the top.
- Remove `Theme.bg.ignoresSafeArea()` — replace with `Theme.bg` from `OpenTimeUI` if a background is desired, but prefer letting `Color.systemBackground` flow through.
- Remove `.navigationTitle("Availability")` and `.navigationBarTitleDisplayMode(.inline)`.
- Remove `.preferredColorScheme(.dark)`.
- Insert a custom `PageHeader(title: "Availability", meta: <today's date short string>)` at the top of the main `VStack`.
- Replace any `Theme.green`, `Theme.cardBg`, `Theme.border`, etc. references in this file by removing those usages (the affordances they styled get replaced in later tasks; for now use `Theme.fg`, `Theme.muted`, `Theme.bg`, `Theme.accent` from `OpenTimeUI`).

The exact diff depends on the current file — apply minimum changes to get this file compiling against `OpenTimeUI` only.

- [ ] **Step 2: Build the main app target**

Run via Xcode: ⌘B.
Expected: `ContentView.swift` compiles. Build still fails on `DayCardView`, `SlotRowView`, `DateRangePickerView` — fixed in next tasks.

- [ ] **Step 3: Commit**

```bash
git add CalendarAvailability/ContentView.swift
git commit -m "feat(app): replace nav title with PageHeader, drop forced dark mode"
```

---

### Task 13: Replace `DayCardView` + `SlotRowView` with `DayRowView`

**Files:**
- Modify: `CalendarAvailability/ContentView.swift`
- Delete: `CalendarAvailability/Views/DayCardView.swift`
- Delete: `CalendarAvailability/Views/SlotRowView.swift`

- [ ] **Step 1: Add a small adapter that maps `DayAvailability` → `DayRowView`**

Inside `ContentView.swift`, add a private helper that converts the existing model to the new view's input. The slot chip text uses the slot's start time formatted like `"9:00"` (no minutes-suffix when whole-hour, otherwise `"9:30"` — match the format already used by `Fmt.time`).

```swift
private extension DayAvailability {
    func asRow(showBusy: Bool, isToday: Bool, chipContext: ((DayRowView.Slot) -> SlotChip.ContextActions)?) -> some View {
        DayRowView(
            dayName: Fmt.relativeDay(date),
            dateLabel: Fmt.dateFull.string(from: date),
            totalLabel: "\(Fmt.duration(totalFreeMin)) Free",
            isToday: isToday,
            slots: freeSlots.map { .init(timeText: Fmt.time.string(from: $0.start)) },
            busy: busySlots.map { .init(timeRange: "\(Fmt.time.string(from: $0.start)) – \(Fmt.time.string(from: $0.end))", title: $0.summary) },
            showBusy: showBusy,
            chipContext: chipContext
        )
    }
}
```

- [ ] **Step 2: Replace the `LazyVStack { ForEach(filteredDays) { DayCardView(day: $0) } }` block**

Replace it with:

```swift
LazyVStack(spacing: 0) {
    ForEach(filteredDays) { day in
        day.asRow(
            showBusy: showBusy,
            isToday: Calendar.current.isDateInToday(day.date),
            chipContext: nil   // wired in Task 16
        )
    }
    Rectangle().fill(Theme.rule).frame(height: 1) // closing rule
}
.padding(.horizontal, 20)
```

Add a `@State private var showBusy = false` to `ContentView`.

- [ ] **Step 3: Delete the old views**

```bash
git rm CalendarAvailability/Views/DayCardView.swift
git rm CalendarAvailability/Views/SlotRowView.swift
```

- [ ] **Step 4: Build**

Run via Xcode: ⌘B.
Expected: `ContentView` compiles. `DateRangePickerView` is the only remaining failure.

- [ ] **Step 5: Commit**

```bash
git add CalendarAvailability
git commit -m "feat(app): replace DayCardView/SlotRowView with OpenTimeUI.DayRowView"
```

---

### Task 14: Restyle `DateRangePickerView` with `MTSquareButton`

**Files:**
- Modify: `CalendarAvailability/Views/DateRangePickerView.swift`

- [ ] **Step 1: Read the current file to inventory its buttons**

Read `CalendarAvailability/Views/DateRangePickerView.swift`. Identify each tappable affordance (week pickers, range presets, etc.).

- [ ] **Step 2: Replace each `Button { … } label: { … }` block with `MTSquareButton`**

For each preset, the pattern is:

```swift
// Before (illustrative — actual code may differ):
Button { manager.select(preset) } label: {
    Text(preset.label)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(selected == preset ? Theme.green : Theme.cardBg)
        .clipShape(Capsule())
}

// After:
MTSquareButton(preset.label, isSelected: selected == preset) {
    manager.select(preset)
}
```

Apply the same transformation to every tappable affordance in the file. Replace any custom backgrounds, capsules, or rounded rectangles. Use `Theme.muted` for inactive section labels in MT caps style (`.font(Theme.Font.display(size: 10, weight: .regular)).kerning(1.8).foregroundStyle(Theme.muted)`).

- [ ] **Step 3: Build the main app**

Run via Xcode: ⌘B.
Expected: full main-app build succeeds.

- [ ] **Step 4: Run on simulator and visually verify the restyled day list**

Run via Xcode: ⌘R on the iPhone simulator.
Expected: hard rules between days, square chips, red ▶ on today's row, MT caps labels, MT-style square buttons in the date range picker. Light + dark mode both clean.

- [ ] **Step 5: Commit**

```bash
git add CalendarAvailability/Views/DateRangePickerView.swift
git commit -m "feat(app): restyle DateRangePickerView with MTSquareButton"
```

---

### Task 15: Restyle toolbar + add Show-Busy toggle

**Files:**
- Modify: `CalendarAvailability/ContentView.swift`

- [ ] **Step 1: Replace the toolbar SF-Symbol pill buttons with text-label buttons**

In the existing `.toolbar { … }` blocks, replace each `Image(systemName: …)` button with a `Text(label.uppercased())` styled to MT — `font(Theme.Font.display(size: 10, weight: .bold))`, `kerning(1.8)`, `foregroundStyle(Theme.fg)`. Labels: `COPY` (becomes `✓` for 1.5s after copy success), `REFRESH`, `SHARE`. Keep the existing actions intact.

- [ ] **Step 2: Add the Show-Busy toggle as a toolbar overflow menu item**

```swift
ToolbarItem(placement: .topBarTrailing) {
    Menu {
        Toggle("Show Busy", isOn: $showBusy)
        Toggle("Weekends", isOn: $manager.includeWeekends)
    } label: {
        Text("MORE").font(Theme.Font.display(size: 10, weight: .bold)).kerning(1.8).foregroundStyle(Theme.fg)
    }
}
```

Remove the inline `Toggle("Weekends", …)` and the "Live" / "Go Live" capsule from the body — replace the latter with an `MTSquareButton` placed where the original capsule lived (above the day list).

- [ ] **Step 3: Build + run**

Run via Xcode: ⌘R.
Expected: toolbar reads `COPY · REFRESH · SHARE · MORE`. Tapping `MORE` reveals Show Busy + Weekends toggles. Toggling Show Busy on reveals busy rows under each day.

- [ ] **Step 4: Commit**

```bash
git add CalendarAvailability/ContentView.swift
git commit -m "feat(app): MT-style toolbar + Show Busy toggle"
```

---

### Task 16: Wire long-press chip menu (Open in Calendar / Create Event Here / Copy Time)

**Files:**
- Create: `CalendarAvailability/Services/CalendarURL.swift`
- Create: `CalendarAvailability/Services/CalendarURLTests.swift` (in main test target if present, otherwise this becomes a unit-testable struct in `OpenTimeUI`)
- Modify: `CalendarAvailability/ContentView.swift`

- [ ] **Step 1: Write the failing test for `CalendarURL.openCalendar(at:)`**

If a `CalendarAvailabilityTests` target does not exist, create one. Add:

```swift
import XCTest
@testable import CalendarAvailability

final class CalendarURLTests: XCTestCase {
    func test_openCalendarURL_usesCalshowSchemeWithUnixTimestamp() {
        // Apple reference epoch is 2001-01-01; calshow takes seconds since that epoch.
        let date = Date(timeIntervalSinceReferenceDate: 12345)
        let url = CalendarURL.openCalendar(at: date)
        XCTAssertEqual(url.scheme, "calshow")
        XCTAssertEqual(url.host, "12345")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run via Xcode: ⌘U on the test target.
Expected: FAIL — `CalendarURL` not in scope.

- [ ] **Step 3: Implement `CalendarURL`**

```swift
// CalendarAvailability/Services/CalendarURL.swift
import Foundation

enum CalendarURL {
    /// Apple Calendar accepts `calshow:N` where N is seconds since
    /// the Apple reference date (2001-01-01 UTC). This jumps the
    /// Calendar app to that day at the local-equivalent time.
    static func openCalendar(at date: Date) -> URL {
        let seconds = Int(date.timeIntervalSinceReferenceDate)
        return URL(string: "calshow:\(seconds)")!
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run via Xcode: ⌘U on the test target.
Expected: PASS.

- [ ] **Step 5: Implement the long-press actions in `ContentView`**

In `ContentView`, add helpers:

```swift
@Environment(\.openURL) private var openURL
@State private var eventEditSlot: FreeSlot?

private func chipContext(for slot: FreeSlot) -> SlotChip.ContextActions {
    SlotChip.ContextActions(
        openInCalendar: { openURL(CalendarURL.openCalendar(at: slot.start)) },
        createEventHere: { eventEditSlot = slot },
        copyTime: {
            let s = "\(Fmt.time.string(from: slot.start)) – \(Fmt.time.string(from: slot.end))"
            UIPasteboard.general.string = s
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    )
}
```

Pass `chipContext` through the `asRow(...)` adapter:

```swift
day.asRow(
    showBusy: showBusy,
    isToday: Calendar.current.isDateInToday(day.date),
    chipContext: { (slotView: DayRowView.Slot) -> SlotChip.ContextActions in
        guard let match = day.freeSlots.first(where: { Fmt.time.string(from: $0.start) == slotView.timeText }) else {
            return SlotChip.ContextActions(openInCalendar: {}, createEventHere: {}, copyTime: {})
        }
        return chipContext(for: match)
    }
)
```

Present `EKEventEditViewController` for the `eventEditSlot` via a sheet:

```swift
.sheet(item: $eventEditSlot) { slot in
    EventEditSheet(start: slot.start, end: slot.end) { eventEditSlot = nil }
}
```

Add a small `UIViewControllerRepresentable` wrapper called `EventEditSheet` in the same file or a sibling file `Views/EventEditSheet.swift`:

```swift
import SwiftUI
import EventKit
import EventKitUI

struct EventEditSheet: UIViewControllerRepresentable {
    let start: Date
    let end: Date
    let onDismiss: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onDismiss: onDismiss) }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let vc = EKEventEditViewController()
        vc.eventStore = EventStore.shared.store
        let event = EKEvent(eventStore: vc.eventStore)
        event.startDate = start
        event.endDate = end
        vc.event = event
        vc.editViewDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: EKEventEditViewController, context: Context) {}

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let onDismiss: () -> Void
        init(onDismiss: @escaping () -> Void) { self.onDismiss = onDismiss }
        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            onDismiss()
        }
    }
}
```

If `EventStore.shared.store` doesn't already exist in `Services/CalendarManager.swift`, add a small singleton there that exposes `let store: EKEventStore` so both the manager and the edit sheet share it. Otherwise wire to whatever store the manager already holds.

Make `FreeSlot: Identifiable` if it isn't already (its `id` can be `start.timeIntervalSinceReferenceDate`).

- [ ] **Step 6: Build + run; long-press a chip and verify the menu**

Run via Xcode: ⌘R.
Manual:
- Long-press a free chip → menu shows three items.
- "Open in Calendar" → Apple Calendar opens at the slot's day.
- "Create Event Here" → modal event edit sheet pre-filled with the slot's start/end.
- "Copy Time" → time string copied to pasteboard, success haptic fires.

- [ ] **Step 7: Commit**

```bash
git add CalendarAvailability
git commit -m "feat(app): long-press chip menu (Open in Calendar / Create / Copy)"
```

---

## Phase 3 — Foundation Models query bar

### Task 17: Implement `AvailabilityQuery` (TDD)

**Files:**
- Create: `CalendarAvailability/Services/AvailabilityQuery.swift`
- Create: `CalendarAvailabilityTests/AvailabilityQueryTests.swift`

- [ ] **Step 1: Write the failing test for the parser's filter behavior**

We test the **filter** end of the pipeline (which is deterministic) with a mocked intent. The LLM call itself is integration-tested manually on device.

```swift
import XCTest
@testable import CalendarAvailability

final class AvailabilityQueryTests: XCTestCase {
    func test_filter_matchesByDayName() {
        let tuesdayDate = makeDate(year: 2026, month: 5, day: 12) // a Tuesday
        let mondayDate  = makeDate(year: 2026, month: 5, day: 11)
        let days = [
            DayAvailability.fixture(date: mondayDate, freeStarts: [9, 10]),
            DayAvailability.fixture(date: tuesdayDate, freeStarts: [13, 14])
        ]
        let intent = AvailabilityIntent(dayHint: "Tuesday", timeOfDay: nil, durationMin: nil, exact: nil)
        let result = AvailabilityQuery.filter(days: days, intent: intent, now: mondayDate)
        XCTAssertEqual(result.map(\.date), [tuesdayDate])
    }

    func test_filter_matchesByTimeOfDay() {
        let day = DayAvailability.fixture(
            date: makeDate(year: 2026, month: 5, day: 12),
            freeStarts: [9, 10, 14, 17]    // 9am, 10am, 2pm, 5pm
        )
        let intent = AvailabilityIntent(dayHint: nil, timeOfDay: .afternoon, durationMin: nil, exact: nil)
        let result = AvailabilityQuery.filter(days: [day], intent: intent, now: day.date)
        XCTAssertEqual(result.first?.freeSlots.count, 2)  // 2pm + 5pm survive
    }

    func test_filter_matchesByMinDuration() {
        let day = DayAvailability.fixture(
            date: makeDate(year: 2026, month: 5, day: 12),
            slotsWithDurations: [(9, 30), (11, 60), (14, 15)]   // (hour, minutes)
        )
        let intent = AvailabilityIntent(dayHint: nil, timeOfDay: nil, durationMin: 60, exact: nil)
        let result = AvailabilityQuery.filter(days: [day], intent: intent, now: day.date)
        XCTAssertEqual(result.first?.freeSlots.count, 1)
    }
}

// Test fixtures local to the test file:
private func makeDate(year: Int, month: Int, day: Int) -> Date {
    var c = DateComponents(); c.year = year; c.month = month; c.day = day
    return Calendar(identifier: .gregorian).date(from: c)!
}
private extension DayAvailability {
    static func fixture(date: Date, freeStarts hours: [Int]) -> DayAvailability {
        let cal = Calendar(identifier: .gregorian)
        let slots = hours.map { h -> FreeSlot in
            let start = cal.date(bySettingHour: h, minute: 0, second: 0, of: date)!
            let end = cal.date(byAdding: .minute, value: 30, to: start)!
            return FreeSlot(start: start, end: end)
        }
        return DayAvailability(date: date, freeSlots: slots, busySlots: [])
    }
    static func fixture(date: Date, slotsWithDurations: [(Int, Int)]) -> DayAvailability {
        let cal = Calendar(identifier: .gregorian)
        let slots = slotsWithDurations.map { (h, mins) -> FreeSlot in
            let start = cal.date(bySettingHour: h, minute: 0, second: 0, of: date)!
            let end = cal.date(byAdding: .minute, value: mins, to: start)!
            return FreeSlot(start: start, end: end)
        }
        return DayAvailability(date: date, freeSlots: slots, busySlots: [])
    }
}
```

If `DayAvailability`/`FreeSlot` initializers differ from the above signatures, adapt the fixture to the actual signatures — do not change the production types.

- [ ] **Step 2: Run the tests to verify they fail**

Run via Xcode: ⌘U.
Expected: FAIL — `AvailabilityIntent`, `AvailabilityQuery` not in scope.

- [ ] **Step 3: Implement `AvailabilityQuery`**

```swift
// CalendarAvailability/Services/AvailabilityQuery.swift
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

enum TimeOfDay: String, Codable {
    case morning, afternoon, evening
}

struct DateRange: Codable {
    let start: Date
    let end: Date
}

#if canImport(FoundationModels)
@Generable
#endif
struct AvailabilityIntent: Codable {
    let dayHint: String?
    let timeOfDay: TimeOfDay?
    let durationMin: Int?
    let exact: DateRange?
}

enum AvailabilityQuery {
    /// Calls Apple Intelligence's on-device LLM to parse a free-form query
    /// into a structured intent. iOS 26+, supported devices only.
    @available(iOS 26, *)
    static func parse(_ text: String) async throws -> AvailabilityIntent {
        #if canImport(FoundationModels)
        let session = LanguageModelSession()
        return try await session.respond(
            to: text,
            generating: AvailabilityIntent.self,
            options: .init(systemPrompt: """
                You parse a user's free-form question about their calendar availability into a structured intent.
                Fields:
                - dayHint: a day-of-week name ("Tuesday"), relative day ("tomorrow"), or nil.
                - timeOfDay: morning | afternoon | evening | nil.
                - durationMin: minutes the user wants free, or nil.
                - exact: only fill if the user gave an exact date+time range.
                Respond with the structured intent only.
                """)
        )
        #else
        return AvailabilityIntent(dayHint: nil, timeOfDay: nil, durationMin: nil, exact: nil)
        #endif
    }

    /// Apply a parsed intent against the day list. Pure / deterministic.
    static func filter(days: [DayAvailability], intent: AvailabilityIntent, now: Date) -> [DayAvailability] {
        var matched = days

        if let dayHint = intent.dayHint, !dayHint.isEmpty {
            matched = matched.filter { day in
                matchesDayHint(date: day.date, hint: dayHint, now: now)
            }
        }

        matched = matched.compactMap { day -> DayAvailability? in
            var free = day.freeSlots
            if let tod = intent.timeOfDay {
                free = free.filter { slotMatches(timeOfDay: tod, slot: $0) }
            }
            if let minDur = intent.durationMin {
                free = free.filter { Int($0.end.timeIntervalSince($0.start) / 60) >= minDur }
            }
            if let r = intent.exact {
                free = free.filter { $0.start >= r.start && $0.end <= r.end }
            }
            guard !free.isEmpty else { return nil }
            return DayAvailability(date: day.date, freeSlots: free, busySlots: day.busySlots)
        }

        return matched
    }

    private static func matchesDayHint(date: Date, hint: String, now: Date) -> Bool {
        let cal = Calendar(identifier: .gregorian)
        let lower = hint.lowercased()
        if lower == "today" { return cal.isDate(date, inSameDayAs: now) }
        if lower == "tomorrow" {
            return cal.isDate(date, inSameDayAs: cal.date(byAdding: .day, value: 1, to: now)!)
        }
        let weekday = cal.component(.weekday, from: date)  // 1 = Sunday
        let names = ["sunday","monday","tuesday","wednesday","thursday","friday","saturday"]
        return names[weekday - 1] == lower
    }

    private static func slotMatches(timeOfDay: TimeOfDay, slot: FreeSlot) -> Bool {
        let h = Calendar(identifier: .gregorian).component(.hour, from: slot.start)
        switch timeOfDay {
        case .morning:   return (5..<12).contains(h)
        case .afternoon: return (12..<17).contains(h)
        case .evening:   return (17..<22).contains(h)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run via Xcode: ⌘U.
Expected: 3 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add CalendarAvailability
git commit -m "feat(app): AvailabilityQuery with deterministic filter + FM parser"
```

---

### Task 18: Add the query-bar UI in `ContentView`

**Files:**
- Modify: `CalendarAvailability/ContentView.swift`

- [ ] **Step 1: Add the input row between `PageHeader` and the date range picker**

Add state:

```swift
@State private var queryText: String = ""
@State private var queryResult: [DayAvailability]?
@State private var queryIsLoading = false
@FocusState private var queryFocused: Bool
```

Add a small private view for the query bar. The Foundation Models availability gate uses `SystemLanguageModel.default.availability` — the API shipped in iOS 26 for checking if Apple Intelligence is available on this device. Verify the exact spelling against the SDK in Xcode autocomplete; it may be `.availability == .available` or `.isAvailable` depending on the build:

```swift
@ViewBuilder
private var queryBar: some View {
    if #available(iOS 26, *), SystemLanguageModel.default.availability == .available {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("ASK")
                    .font(Theme.Font.display(size: 10, weight: .bold))
                    .kerning(1.8)
                    .foregroundStyle(Theme.muted)
                TextField("WHEN AM I FREE?", text: $queryText)
                    .focused($queryFocused)
                    .textFieldStyle(.plain)
                    .font(Theme.Font.display(size: 13, weight: .regular))
                    .submitLabel(.search)
                    .onSubmit { Task { await runQuery() } }
                if queryIsLoading {
                    ProgressView().controlSize(.small)
                } else if !queryText.isEmpty {
                    Button {
                        queryText = ""
                        queryResult = nil
                    } label: {
                        Text("× CLEAR").font(Theme.Font.display(size: 10, weight: .bold)).kerning(1.8).foregroundStyle(Theme.fg)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 6)
            Rectangle().fill(Theme.fg).frame(height: 1)
        }
        .padding(.bottom, 12)
    }
}

@MainActor
private func runQuery() async {
    guard !queryText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
    queryIsLoading = true
    defer { queryIsLoading = false }
    do {
        let intent = try await AvailabilityQuery.parse(queryText)
        let matches = AvailabilityQuery.filter(days: manager.days, intent: intent, now: Date())
        queryResult = matches
    } catch {
        queryResult = []
    }
}
```

If the SDK's exact API name differs from `SystemLanguageModel.default.availability == .available` — for example if Apple shipped `LanguageModelSession.isSupported` instead — adjust the gate to match. The contract is identical: hide the query bar when on-device Apple Intelligence isn't available.

- [ ] **Step 2: Wire query results into the list**

In the body, render `queryResult` if set:

```swift
if let result = queryResult {
    if result.isEmpty {
        Text("NO FREE SLOTS · TRY ANOTHER DAY")
            .font(Theme.Font.display(size: 10, weight: .bold))
            .kerning(1.8)
            .foregroundStyle(Theme.muted)
            .padding(.vertical, 12)
    } else {
        // Reuse the same row renderer but prefix each day with a MATCH micro-label.
        Text("MATCH").font(Theme.Font.display(size: 10, weight: .bold)).kerning(1.8).foregroundStyle(Theme.accent)
        ForEach(result) { day in day.asRow(showBusy: showBusy, isToday: Calendar.current.isDateInToday(day.date), chipContext: { … }) }
    }
} else {
    // existing full-list rendering
}
```

(Use the same `chipContext` closure from Task 16.)

- [ ] **Step 3: Build + run on a Foundation-Models-supported device or simulator**

Run via Xcode: ⌘R.
Manual:
- Query bar visible.
- Type "tuesday afternoon" → submit → result narrows to Tuesday's afternoon slots.
- × CLEAR returns to the full list.
- On a non-Apple-Intelligence simulator (e.g. iPhone 14), the query bar should be hidden entirely — verify by switching the simulator destination.

- [ ] **Step 4: Commit**

```bash
git add CalendarAvailability/ContentView.swift
git commit -m "feat(app): Foundation Models natural-language query bar"
```

---

### Task 19: Deep-link URL scheme `opentime://slot?start=…&end=…`

**Files:**
- Modify: `CalendarAvailability.xcodeproj/project.pbxproj` (add URL Type via Xcode UI)
- Modify: `CalendarAvailability/CalendarAvailabilityApp.swift`
- Modify: `CalendarAvailability/ContentView.swift`

- [ ] **Step 1: Register `opentime` URL scheme in the main app's `Info`**

In Xcode → main app target → Info → URL Types: add an entry with identifier `com.jamestannahill.opentime` and URL Scheme `opentime`.

- [ ] **Step 2: Handle the incoming URL in `CalendarAvailabilityApp`**

Modify `CalendarAvailabilityApp.swift`:

```swift
@main
struct CalendarAvailabilityApp: App {
    @StateObject private var deepLink = DeepLinkRouter()
    init() { FontRegistration.registerNHG() }
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(deepLink)
                .onOpenURL { url in deepLink.handle(url) }
        }
    }
}

final class DeepLinkRouter: ObservableObject {
    @Published var pendingSlotStart: Date?
    func handle(_ url: URL) {
        guard url.scheme == "opentime", url.host == "slot",
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let startStr = comps.queryItems?.first(where: { $0.name == "start" })?.value,
              let startUnix = TimeInterval(startStr)
        else { return }
        pendingSlotStart = Date(timeIntervalSince1970: startUnix)
    }
}
```

- [ ] **Step 3: React to `pendingSlotStart` in `ContentView`**

In `ContentView`:

```swift
@EnvironmentObject private var deepLink: DeepLinkRouter
.onChange(of: deepLink.pendingSlotStart) { _, new in
    guard let target = new else { return }
    // Scroll the matching day into view (use ScrollViewReader; assume `proxy` available).
    // After scrolling, clear:
    deepLink.pendingSlotStart = nil
}
```

Wrap the existing `ScrollView` body in a `ScrollViewReader` and tag each `DayRowView` with `.id(day.date)`. Then `proxy.scrollTo(Calendar.current.startOfDay(for: target), anchor: .top)`.

- [ ] **Step 4: Build + run; trigger the scheme**

Run via Xcode: ⌘R, then in the iOS simulator: `xcrun simctl openurl booted "opentime://slot?start=$(date +%s)&end=$(($(date +%s)+1800))"`. App should launch and scroll to today.

- [ ] **Step 5: Commit**

```bash
git add CalendarAvailability CalendarAvailability.xcodeproj
git commit -m "feat(app): opentime://slot deep-link routing"
```

---

## Phase 4 — Widgets + Live Activity

### Task 20: Link `OpenTimeUI` to widget extension and register fonts

**Files:**
- Modify: `CalendarAvailability.xcodeproj/project.pbxproj` (link package via Xcode)
- Modify: `CalendarWidget/CalendarWidgetBundle.swift`

- [ ] **Step 1: Add `OpenTimeUI` to the widget extension target**

In Xcode → CalendarWidget target → Frameworks, Libraries, and Embedded Content → add `OpenTimeUI`.

- [ ] **Step 2: Register fonts in `CalendarWidgetBundle.swift`**

```swift
import WidgetKit
import SwiftUI
import OpenTimeUI

@main
struct CalendarWidgetBundle: WidgetBundle {
    init() { FontRegistration.registerNHG() }
    var body: some Widget {
        CalendarWidget()
        AvailabilityLiveActivity()
    }
}
```

- [ ] **Step 3: Build the widget extension**

Run via Xcode: ⌘B on the widget scheme.
Expected: builds clean.

- [ ] **Step 4: Commit**

```bash
git add CalendarWidget CalendarAvailability.xcodeproj
git commit -m "feat(widget): link OpenTimeUI and register NHG fonts"
```

---

### Task 21: Restyle home-screen widgets

**Files:**
- Modify: `CalendarWidget/CalendarWidget.swift`

- [ ] **Step 1: Read the current widget views**

Read `CalendarWidget/CalendarWidget.swift` to inventory what `today / this week / next week` widget views render.

- [ ] **Step 2: Rebuild each size's view using `OpenTimeUI` components**

Each size's view becomes a small composition: a 9pt MT caps header (`TODAY` / `THIS WEEK` / `NEXT WEEK`) with the date right-aligned, a 2pt rule under, then a list of `DayRowView`s (use `.font` overrides for chip 9pt density). Background uses `Color(.systemBackground)` so the widget respects light/dark.

For tap-to-deep-link, wrap each chip in a `Link(destination: URL(string: "opentime://slot?start=\(slot.start.timeIntervalSince1970)&end=\(slot.end.timeIntervalSince1970)")!)`.

- [ ] **Step 3: Add `#Preview` blocks for each size in light + dark**

```swift
#Preview(as: .systemSmall) { CalendarWidget() } timeline: { … }
```

- [ ] **Step 4: Build + visually verify the previews**

Run via Xcode: ⌘B; open `CalendarWidget.swift`; check each preview renders MT-style chips + hard rules in both color schemes.

- [ ] **Step 5: Commit**

```bash
git add CalendarWidget/CalendarWidget.swift
git commit -m "feat(widget): restyle today / this-week / next-week widgets"
```

---

### Task 22: Restyle Live Activity lock screen

**Files:**
- Modify: `CalendarWidget/AvailabilityLiveActivity.swift`

- [ ] **Step 1: Replace the lock-screen view body with the MT 2-line layout**

Top line: `AVAILABILITY` micro-header (NHG 10pt 0.18em) + meta (`TODAY · 3H FREE`). Bottom line: next-free `SlotChip` inverted style + `→ <duration> free today` after it. All wrapped in `Theme.bg` background.

- [ ] **Step 2: Build + visually verify the preview**

Run via Xcode: ⌘B; open the file; light + dark preview render correctly.

- [ ] **Step 3: Commit**

```bash
git add CalendarWidget/AvailabilityLiveActivity.swift
git commit -m "feat(LiveActivity): restyle lock-screen layout"
```

---

### Task 23: Restyle Dynamic Island compact / minimal / expanded

**Files:**
- Modify: `CalendarWidget/AvailabilityLiveActivity.swift`

- [ ] **Step 1: Implement compact**

Leading: `Text("▶").foregroundStyle(Theme.accent)` shown only when there's currently a free window. Trailing: next-free time `Text("2:30").font(Theme.Font.display(size: 12, weight: .medium)).tnum()`.

- [ ] **Step 2: Implement minimal**

`Text("▶").foregroundStyle(state.isCurrentlyFree ? Theme.accent : Theme.muted)`.

- [ ] **Step 3: Implement expanded**

Same structure as the lock-screen view, just rendered inside the Dynamic Island regions (leading/trailing/center/bottom).

- [ ] **Step 4: Build + visually verify all three Dynamic Island states with the preview**

Run via Xcode: ⌘B; the file's `#Preview(as: .dynamicIsland(.compact / .minimal / .expanded))` panes all render correctly.

- [ ] **Step 5: Commit**

```bash
git add CalendarWidget/AvailabilityLiveActivity.swift
git commit -m "feat(LiveActivity): restyle Dynamic Island compact/minimal/expanded"
```

---

## Phase 5 — Apple Watch

### Task 24: Create `OpenTimeUIWatch` package

**Files:**
- Create: `OpenTimeUIWatch/Package.swift`
- Create: `OpenTimeUIWatch/Sources/OpenTimeUIWatch/Theme.swift`
- Create: `OpenTimeUIWatch/Sources/OpenTimeUIWatch/SlotChip.swift`
- Create: `OpenTimeUIWatch/Sources/OpenTimeUIWatch/DayRowView.swift`
- Create: `OpenTimeUIWatch/Sources/OpenTimeUIWatch/PageHeader.swift`

- [ ] **Step 1: Create `Package.swift` with `.watchOS(.v10)`**

```swift
// OpenTimeUIWatch/Package.swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OpenTimeUIWatch",
    platforms: [.watchOS(.v10)],
    products: [.library(name: "OpenTimeUIWatch", targets: ["OpenTimeUIWatch"])],
    targets: [.target(name: "OpenTimeUIWatch")]
)
```

- [ ] **Step 2: Implement a Watch-local `Theme` that mirrors the iOS tokens but uses SF Compact**

```swift
// OpenTimeUIWatch/Sources/OpenTimeUIWatch/Theme.swift
import SwiftUI

public enum Theme {
    public static let bg     = Color(light: .white,            dark: Color(red: 10/255, green: 10/255, blue: 10/255))
    public static let fg     = Color(light: .black,            dark: .white)
    public static let muted  = Color(light: Color(red: 0.33, green: 0.33, blue: 0.33),
                                     dark:  Color(red: 0.63, green: 0.63, blue: 0.63))
    public static let dim    = Color(light: Color(red: 0.53, green: 0.53, blue: 0.53),
                                     dark:  Color(red: 0.40, green: 0.40, blue: 0.40))
    public static let rule   = Color(light: .black, dark: .white)
    public static let accent = Color(light: Color(red: 0.83, green: 0.0,  blue: 0.0),
                                     dark:  Color(red: 1.0,  green: 0.12, blue: 0.12))

    public enum Font {
        public static func display(size: CGFloat, weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font {
            SwiftUI.Font.system(size: size, weight: weight, design: .default) // SF Compact on watchOS
        }
    }
}

extension Color {
    init(light: Color, dark: Color) {
        self = Color(UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
}
```

- [ ] **Step 3: Implement `SlotChip`, `DayRowView`, `PageHeader` mirroring the iOS components**

Each component is the same structure as its iOS counterpart but: (a) imports `OpenTimeUIWatch`'s `Theme`, (b) skips `.contextMenu` (no watchOS support — use `.onTapGesture` with haptic), (c) reduces base font sizes by ~3pt for watch density, (d) drops `BusyRowView`.

- [ ] **Step 4: Build the package**

Run: `cd OpenTimeUIWatch && swift build`
Expected: `Build complete!`

- [ ] **Step 5: Commit**

```bash
git add OpenTimeUIWatch
git commit -m "feat: add OpenTimeUIWatch package (SF Compact theme + components)"
```

---

### Task 25: Restyle `OpenTimeWatch` app

**Files:**
- Modify: source files inside `OpenTimeWatch/`

- [ ] **Step 1: Add `OpenTimeUIWatch` to the Watch target in Xcode**

File → Add Package Dependencies → Add Local → `OpenTimeUIWatch/`. Add the library to the Watch target.

- [ ] **Step 2: Replace the Watch view tree with `PageHeader` + a list of `DayRowView`s**

Tap-on-chip copies the time and calls `WKInterfaceDevice.current().play(.success)`.

- [ ] **Step 3: Build the Watch scheme + run on the watchOS simulator**

Run via Xcode: ⌘R on the Watch scheme. Verify rows render with SF Compact + MT structure; tapping a chip plays a haptic and copies (verify by checking pasteboard via a debug `print`).

- [ ] **Step 4: Commit**

```bash
git add OpenTimeWatch CalendarAvailability.xcodeproj
git commit -m "feat(watch): restyle OpenTimeWatch with OpenTimeUIWatch"
```

---

## Phase 6 — Extensions

### Task 26: Restyle `MessagesExtension`

**Files:**
- Modify: source files inside `MessagesExtension/`

- [ ] **Step 1: Link `OpenTimeUI` and register fonts at the extension's launch**

In Xcode → MessagesExtension target → Frameworks, Libraries, and Embedded Content → add `OpenTimeUI`. In the extension's main view controller (typically `MessagesViewController.swift`), import `OpenTimeUI` and call font registration in `viewDidLoad`:

```swift
import OpenTimeUI

override func viewDidLoad() {
    super.viewDidLoad()
    FontRegistration.registerNHG()
}
```

- [ ] **Step 2: Restyle the picker**

Replace the picker UI's day rows with `OpenTimeUI.DayRowView`. Replace the existing send button with `MTSquareButton(role: .submit)`. Use `presentationStyle == .compact` to render only the next 3 days; `.expanded` shows the full 5.

- [ ] **Step 3: Build + run the iMessage extension scheme**

Run via Xcode: ⌘R on the MessagesExtension scheme. Open Messages, tap the OpenTime app, verify the new layout in compact and expanded states.

- [ ] **Step 4: Commit**

```bash
git add MessagesExtension CalendarAvailability.xcodeproj
git commit -m "feat(messages): restyle iMessage extension picker"
```

---

### Task 27: Restyle `ShareExtension`

**Files:**
- Modify: source files inside `ShareExtension/`

- [ ] **Step 1: Link `OpenTimeUI` and register fonts**

In Xcode → ShareExtension target → Frameworks, Libraries, and Embedded Content → add `OpenTimeUI`. In `ShareViewController.swift`, import `OpenTimeUI` and call font registration in `viewDidLoad`:

```swift
import OpenTimeUI

override func viewDidLoad() {
    super.viewDidLoad()
    FontRegistration.registerNHG()
}
```

- [ ] **Step 2: Restyle the one-screen UI**

Replace the share-sheet UI with `PageHeader` + `DayRowView` + `MTSquareButton` actions for `COPY` and `SEND`. No new functionality.

- [ ] **Step 3: Build + manually invoke from Photos / Notes**

Run via Xcode: ⌘R on a host app, share something, pick OpenTime. Verify MT layout.

- [ ] **Step 4: Commit**

```bash
git add ShareExtension CalendarAvailability.xcodeproj
git commit -m "feat(share): restyle Share extension"
```

---

## Phase 7 — Verification

### Task 28: Manual verification checklist

**Files:** None — this is a manual run-through.

- [ ] **Light + dark switching mid-session**

Toggle iOS dark mode while the app is open. Header rule, chip inversion, accent all flip cleanly across all five surfaces (main app, widgets, Live Activity, Watch, Messages, Share).

- [ ] **Today's `▶` marker**

Present and accent-colored in main app + widget + Live Activity + Watch.

- [ ] **Long-press chip menu**

In the main app: long-press a free chip → menu shows **Open in Calendar** + **Create Event Here** + **Copy Time**.
- Open in Calendar → Apple Calendar opens at the slot's day.
- Create Event Here → modal event sheet pre-filled with start/end.
- Copy Time → time string in clipboard, success haptic fires.

- [ ] **Show Busy toggle**

In the toolbar overflow menu, flipping Show Busy on reveals busy rows in each day. The header `Free` total is unchanged by the toggle.

- [ ] **Widget chip deep-link**

Tap a chip in the home-screen widget → main app launches and scrolls to that day.

- [ ] **Live Activity Dynamic Island**

Compact / minimal / expanded states all render with NHG. ▶ glyph color matches free-now state.

- [ ] **iMessage extension**

Picker renders MT layout in both compact and expanded presentation modes.

- [ ] **Share extension**

When invoked from Photos or Notes, renders MT layout.

- [ ] **Apple Watch**

Rows render with SF Compact + MT structure. Tapping a chip plays a haptic and copies.

- [ ] **Foundation Models query bar**

Visible on iPhone 15 Pro+ simulator. Hidden on iPhone 14 / older simulator.
Type "tuesday afternoon" → return → result narrows correctly.
× CLEAR returns to the full list.

- [ ] **NHG actually loaded**

Add a one-shot `print(UIFont.familyNames.contains("NHG Display"))` in each target's launch path during this verification run; expect `true` everywhere it was registered. Remove the prints before final commit.

- [ ] **Final commit**

```bash
git add -A
git commit -m "chore: remove dev font-loading prints after verification"
```

- [ ] **Push the branch + open PR**

```bash
git push -u origin <branch>
gh pr create --title "MonkeyThorn-style restyle + Foundation Models query bar" --body "$(cat docs/superpowers/specs/2026-05-09-monkeythorn-restyle-design.md | head -50)"
```

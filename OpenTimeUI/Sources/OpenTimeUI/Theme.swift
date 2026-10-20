import SwiftUI

#if canImport(UIKit)
import UIKit
typealias PlatformColor = UIColor
#elseif canImport(AppKit)
import AppKit
typealias PlatformColor = NSColor
#endif

public enum Theme {
    // MARK: - Hex constants (exposed for tests + documentation)

    public static let accentLightHex = "#D40000"
    public static let accentDarkHex  = "#FF1F1F"

    // MARK: - Color tokens (adaptive light/dark)

    public static let bg     = Color(light: .white,                  dark: .hex("#0A0A0A"))
    public static let fg     = Color(light: .black,                  dark: .white)
    public static let muted  = Color(light: .hex("#555555"),         dark: .hex("#A0A0A0"))
    public static let dim    = Color(light: .hex("#888888"),         dark: .hex("#666666"))
    public static let rule   = Color(light: .black,                  dark: .white)
    public static let accent = Color(light: .hex(accentLightHex),    dark: .hex(accentDarkHex))

    // Literal light/dark accents exposed for previews + tests that
    // need a specific color scheme regardless of system setting.
    public static let accentLight = Color.hex(accentLightHex)
    public static let accentDark  = Color.hex(accentDarkHex)
}

// MARK: - Color helpers

public extension Color {
    init(light: Color, dark: Color) {
        #if canImport(UIKit)
        self = Color(UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
        #elseif canImport(AppKit)
        self = Color(NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(dark) : NSColor(light)
        })
        #else
        self = light
        #endif
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

// MARK: - Typography

public extension Theme {
    enum Font {
        /// Family name as reported by the bundled TTFs. The MonkeyThorn web
        /// stylesheet aliases this to "NHG Display" via @font-face — iOS has
        /// no equivalent alias, so we use the real internal family name.
        public static let familyName = "Neue Haas Grotesk Display Pro"

        /// NHG Display at the given size + weight, scaled with Dynamic Type.
        /// Falls back to the system font if the family hasn't been registered yet.
        public static func display(
            size: CGFloat,
            weight: SwiftUI.Font.Weight = .regular,
            relativeTo style: SwiftUI.Font.TextStyle = .body
        ) -> SwiftUI.Font {
            SwiftUI.Font.custom(familyName, size: size, relativeTo: style)
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

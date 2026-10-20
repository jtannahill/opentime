import XCTest
import SwiftUI
@testable import OpenTimeUI

final class ThemeTests: XCTestCase {
    func test_colorTokensExist() {
        // Smoke test — these resolve without crashing.
        _ = Theme.bg
        _ = Theme.fg
        _ = Theme.muted
        _ = Theme.dim
        _ = Theme.rule
        _ = Theme.accent
    }

    func test_lightAccentHex_isMonkeyThornRed() {
        XCTAssertEqual(Theme.accentLightHex, "#D40000")
    }

    func test_darkAccentHex_isBrightenedForLegibility() {
        XCTAssertEqual(Theme.accentDarkHex, "#FF1F1F")
    }

    func test_fontFactory_returnsCustomNHGFont() {
        // Compile-only check that the factory returns a Font.
        let f = Theme.Font.display(size: 18, weight: .bold)
        _ = f
    }

    func test_fontFamilyName_matchesBundledTTFFamily() {
        XCTAssertEqual(Theme.Font.familyName, "Neue Haas Grotesk Display Pro")
    }
}

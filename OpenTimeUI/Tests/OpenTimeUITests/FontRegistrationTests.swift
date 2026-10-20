import XCTest
import CoreText
@testable import OpenTimeUI

final class FontRegistrationTests: XCTestCase {
    /// PostScript names inside the bundled TTFs (from the original
    /// Neue Haas Grotesk Display Pro release). The bundle filenames are
    /// NHGDisplay-* but the internal PostScript names use NeueHaasDisplay-*.
    private static let postScriptNames = [
        "NeueHaasDisplay-Roman",
        "NeueHaasDisplay-Mediu", // intentionally truncated — that's how the file names it
        "NeueHaasDisplay-Bold"
    ]
    private static let expectedFamily = "Neue Haas Grotesk Display Pro"

    /// Returns the family name CoreText resolves for a given PostScript name.
    /// If the font is registered, this is the expected family. Otherwise
    /// CoreText falls back to a system font like Helvetica.
    private func familyName(forPostScript ps: String) -> String? {
        let font = CTFontCreateWithName(ps as CFString, 12, nil)
        return CTFontCopyFamilyName(font) as String
    }

    func test_registerNHG_makesFontAvailable() {
        FontRegistration.registerNHG()
        XCTAssertEqual(
            familyName(forPostScript: "NeueHaasDisplay-Roman"),
            Self.expectedFamily
        )
    }

    func test_registerNHG_registersAllThreeWeights() {
        FontRegistration.registerNHG()
        for ps in Self.postScriptNames {
            XCTAssertEqual(
                familyName(forPostScript: ps),
                Self.expectedFamily,
                "Expected \(ps) to resolve to family '\(Self.expectedFamily)'."
            )
        }
    }

    func test_registerNHG_isIdempotent() {
        FontRegistration.registerNHG()
        FontRegistration.registerNHG()
        XCTAssertEqual(familyName(forPostScript: "NeueHaasDisplay-Bold"), Self.expectedFamily)
    }
}

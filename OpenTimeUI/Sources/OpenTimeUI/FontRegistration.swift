import Foundation
import CoreText

public enum FontRegistration {
    nonisolated(unsafe) private static var registered = false
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
            // The NHG files are licensed and not in the public repo; without them
            // Font.custom falls back to the system font.
            guard let url = Bundle.module.url(forResource: name, withExtension: "ttf") else { continue }
            var error: Unmanaged<CFError>?
            let ok = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
            if !ok, let err = error?.takeRetainedValue() {
                let code = CFErrorGetCode(err)
                // 105 = kCTFontManagerErrorAlreadyRegistered — fine on hot reload.
                if code != 105 {
                    assertionFailure("OpenTimeUI: failed to register \(name): \(err)")
                }
            }
        }
        registered = true
    }
}

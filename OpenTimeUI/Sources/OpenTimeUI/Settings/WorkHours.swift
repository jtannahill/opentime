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

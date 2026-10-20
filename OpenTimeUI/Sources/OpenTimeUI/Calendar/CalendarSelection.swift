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

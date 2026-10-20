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

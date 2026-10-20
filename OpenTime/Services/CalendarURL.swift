import Foundation

enum CalendarURL {
    /// Apple Calendar accepts `calshow:N` where N is seconds since the
    /// Apple reference date (2001-01-01 UTC). Opens iOS Calendar at that
    /// day in the user's local timezone.
    static func openCalendar(at date: Date) -> URL {
        let seconds = Int(date.timeIntervalSinceReferenceDate)
        return URL(string: "calshow:\(seconds)")!
    }
}

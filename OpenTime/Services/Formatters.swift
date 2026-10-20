import Foundation
import OpenTimeUI

enum Fmt {
    static let dayName: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f
    }()

    static let shortDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    static let dateFull: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    static func time(_ date: Date) -> String {
        TimeFormat.time(date)
    }

    static func duration(_ min: Int) -> String {
        if min < 60 { return "\(min)m" }
        let h = min / 60
        let m = min % 60
        return m > 0 ? "\(h)h \(m)m" : "\(h)h"
    }

    static func relativeDay(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInTomorrow(date) { return "Tomorrow" }
        return dayName.string(from: date)
    }
}

import Foundation

public struct FreeSlot: Identifiable, Sendable {
    public let id = UUID()
    public let start: Date
    public let end: Date
    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }
    public var durationMin: Int { Int(end.timeIntervalSince(start) / 60) }
}

public struct DayAvailability: Identifiable, Sendable {
    public let id = UUID()
    public let date: Date
    public let freeSlots: [FreeSlot]
    public let busySlots: [BusySlotInfo]
    public init(date: Date, freeSlots: [FreeSlot], busySlots: [BusySlotInfo]) {
        self.date = date
        self.freeSlots = freeSlots
        self.busySlots = busySlots
    }
    public var totalFreeMin: Int { freeSlots.reduce(0) { $0 + $1.durationMin } }
    public var isWeekend: Bool {
        let weekday = Calendar.current.component(.weekday, from: date)
        return weekday == 1 || weekday == 7
    }
}

public struct BusySlotInfo: Identifiable, Sendable {
    public let id = UUID()
    public let start: Date
    public let end: Date
    public let summary: String
    public let calendar: String
    public init(start: Date, end: Date, summary: String, calendar: String) {
        self.start = start
        self.end = end
        self.summary = summary
        self.calendar = calendar
    }
}

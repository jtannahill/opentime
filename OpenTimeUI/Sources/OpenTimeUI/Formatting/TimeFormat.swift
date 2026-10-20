import Foundation

public enum TimeFormat {
    public static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    public static func timeRange(from start: Date, to end: Date) -> String {
        "\(time(start)) – \(time(end))"
    }
}

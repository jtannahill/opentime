import SwiftUI
import WatchKit

// MARK: - Watch-local theme (mirrors OpenTimeUI tokens, SF Compact font)

enum WatchTheme {
    static let bg     = Color(.black)
    static let fg     = Color(.white)
    static let muted  = Color(red: 0.63, green: 0.63, blue: 0.63)
    static let dim    = Color(red: 0.40, green: 0.40, blue: 0.40)
    static let rule   = Color(.white)
    static let accent = Color(red: 1.0, green: 0.12, blue: 0.12) // bright variant for legibility on near-black

    enum Font {
        static func display(size: CGFloat, weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font {
            // SF Compact is the system face on watchOS — Apple-tuned for small displays.
            SwiftUI.Font.system(size: size, weight: weight, design: .default)
        }
    }
}

// MARK: - Slot subdivision (30-min default)

private func subdivide(slot: WatchFreeSlot, durationMin: Int = 30) -> [Date] {
    var starts: [Date] = []
    var cursor = slot.start
    let durSec = TimeInterval(durationMin * 60)
    while cursor.addingTimeInterval(durSec) <= slot.end {
        starts.append(cursor)
        cursor = cursor.addingTimeInterval(durSec)
    }
    return starts
}

private func chipTime(_ date: Date) -> String {
    date.formatted(date: .omitted, time: .shortened)
}

// MARK: - Views

struct WatchContentView: View {
    @StateObject private var helper = WatchCalendarHelper()

    var body: some View {
        NavigationStack {
            ZStack {
                WatchTheme.bg.ignoresSafeArea()

                if !helper.accessGranted {
                    accessView
                } else if helper.days.isEmpty {
                    ProgressView().tint(WatchTheme.fg)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            header
                            ForEach(helper.days) { day in
                                WatchDayRow(day: day)
                            }
                            Rectangle().fill(WatchTheme.rule).frame(height: 0.5)
                        }
                        .padding(.horizontal, 8)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .task {
            await helper.requestAccess()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .lastTextBaseline) {
                Text("AVAILABILITY")
                    .font(WatchTheme.Font.display(size: 12, weight: .bold))
                    .kerning(1.2)
                    .foregroundStyle(WatchTheme.fg)
                Spacer()
                Text(headerMeta.uppercased())
                    .font(WatchTheme.Font.display(size: 8, weight: .regular))
                    .kerning(1.6)
                    .foregroundStyle(WatchTheme.muted)
            }
            .padding(.bottom, 4)
            Rectangle().fill(WatchTheme.rule).frame(height: 2)
        }
        .padding(.bottom, 6)
    }

    private var headerMeta: String {
        let f = DateFormatter(); f.dateFormat = "EEE d MMM"
        return f.string(from: Date())
    }

    private var accessView: some View {
        VStack(spacing: 6) {
            Text("CALENDAR")
                .font(WatchTheme.Font.display(size: 9, weight: .bold))
                .kerning(1.6)
                .foregroundStyle(WatchTheme.muted)
            Text("Access\nRequired")
                .font(WatchTheme.Font.display(size: 14, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(WatchTheme.fg)
        }
        .padding(.horizontal, 12)
    }
}

private struct WatchDayRow: View {
    let day: WatchDayInfo

    private var isToday: Bool {
        Calendar.current.isDateInToday(day.date)
    }

    private var chipStarts: [Date] {
        day.freeSlots.flatMap { subdivide(slot: $0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Rectangle().fill(WatchTheme.rule).frame(height: 0.5)

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                if isToday {
                    Rectangle().fill(WatchTheme.accent).frame(width: 2, height: 12)
                }
                Text(day.label)
                    .font(WatchTheme.Font.display(size: 13, weight: .bold))
                    .foregroundStyle(isToday ? WatchTheme.accent : WatchTheme.fg)
                Spacer()
                Text(day.freeSummary.uppercased())
                    .font(WatchTheme.Font.display(size: 8, weight: .regular))
                    .kerning(1.4)
                    .foregroundStyle(WatchTheme.fg)
            }

            if chipStarts.isEmpty {
                Text("—")
                    .font(WatchTheme.Font.display(size: 10, weight: .regular))
                    .foregroundStyle(WatchTheme.dim)
            } else {
                // Chip flow: scroll horizontally if too many.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        ForEach(Array(chipStarts.enumerated()), id: \.offset) { _, start in
                            Button {
                                // watchOS has no clipboard — tap is feedback only.
                                WKInterfaceDevice.current().play(.success)
                            } label: {
                                Text(chipTime(start))
                                    .font(WatchTheme.Font.display(size: 10, weight: .medium))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .foregroundStyle(WatchTheme.bg)
                                    .background(isToday ? WatchTheme.accent : WatchTheme.fg)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }
}

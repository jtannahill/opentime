import SwiftUI

public struct DayRowView: View {
    public struct Slot: Identifiable {
        public let id = UUID()
        public let timeText: String
        public init(timeText: String) { self.timeText = timeText }
    }

    public struct BusyEvent: Identifiable {
        public let id = UUID()
        public let timeRange: String
        public let title: String
        public init(timeRange: String, title: String) {
            self.timeRange = timeRange
            self.title = title
        }
    }

    public struct DayActions {
        public let copyDay: () -> Void
        public let shareDay: () -> Void
        public init(copyDay: @escaping () -> Void, shareDay: @escaping () -> Void) {
            self.copyDay = copyDay
            self.shareDay = shareDay
        }
    }

    public let dayName: String
    public let dateLabel: String
    public let totalLabel: String
    public let isToday: Bool
    public let isPast: Bool
    public let slots: [Slot]
    public let busy: [BusyEvent]
    public let showBusy: Bool
    public let chipContext: ((Slot) -> SlotChip.ContextActions)?
    public let dayActions: DayActions?

    public init(
        dayName: String,
        dateLabel: String,
        totalLabel: String,
        isToday: Bool = false,
        isPast: Bool = false,
        slots: [Slot] = [],
        busy: [BusyEvent] = [],
        showBusy: Bool = false,
        chipContext: ((Slot) -> SlotChip.ContextActions)? = nil,
        dayActions: DayActions? = nil
    ) {
        self.dayName = dayName
        self.dateLabel = dateLabel
        self.totalLabel = totalLabel
        self.isToday = isToday
        self.isPast = isPast
        self.slots = slots
        self.busy = busy
        self.showBusy = showBusy
        self.chipContext = chipContext
        self.dayActions = dayActions
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Rectangle().fill(Theme.rule).frame(height: 1)

            headerLine
                .modifier(DayHeaderContextMenu(actions: dayActions))

            if slots.isEmpty {
                Text("NO AVAILABILITY")
                    .font(Theme.Font.display(size: 10, weight: .regular))
                    .kerning(2.0)
                    .foregroundStyle(Theme.dim)
            } else {
                FlowLayout(spacing: 4, lineSpacing: 4) {
                    ForEach(slots) { slot in
                        SlotChip(
                            timeText: slot.timeText,
                            isToday: isToday,
                            contextActions: chipContext?(slot)
                        )
                    }
                }
            }

            if showBusy && !busy.isEmpty {
                VStack(spacing: 0) {
                    ForEach(busy) { ev in
                        BusyRowView(timeRange: ev.timeRange, title: ev.title)
                        if ev.id != busy.last?.id {
                            Rectangle().fill(Theme.dim).frame(height: 1)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .opacity(isPast ? 0.45 : 1)
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(dayName), \(dateLabel), \(totalLabel)")
    }

    private var headerLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if isToday {
                Rectangle()
                    .fill(Theme.accent)
                    .frame(width: 3, height: 16)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            }

            Text(dayName)
                .font(Theme.Font.display(size: 18, weight: .bold))
                .kerning(-0.36)
                .foregroundStyle(isToday ? Theme.accent : Theme.fg)

            Text(dateLabel.uppercased())
                .font(Theme.Font.display(size: 10, weight: .regular))
                .kerning(1.8)
                .foregroundStyle(isToday ? Theme.accent : Theme.muted)

            Spacer()

            Text(totalLabel.uppercased())
                .font(Theme.Font.display(size: 10, weight: .regular))
                .kerning(1.8)
                .foregroundStyle(Theme.fg)
        }
        .contentShape(Rectangle()) // make the whole row long-pressable, not just the text
    }
}

private struct DayHeaderContextMenu: ViewModifier {
    let actions: DayRowView.DayActions?

    func body(content: Content) -> some View {
        if let a = actions {
            content.contextMenu {
                Button("Share Day", action: a.shareDay)
                Button("Copy Day", action: a.copyDay)
            }
        } else {
            content
        }
    }
}

#Preview("Today, with busy") {
    FontRegistration.registerNHG()
    return DayRowView(
        dayName: "Today",
        dateLabel: "May 9",
        totalLabel: "3h Free",
        isToday: true,
        slots: [.init(timeText: "9:00"), .init(timeText: "9:30"),
                .init(timeText: "10:30"), .init(timeText: "2:00")],
        busy: [.init(timeRange: "10:00 – 10:30", title: "Standup"),
               .init(timeRange: "1:00 – 2:00",   title: "Lunch w/ A")],
        showBusy: true
    )
    .padding(20)
    .preferredColorScheme(.light)
}

#Preview("Future, no busy, dark") {
    FontRegistration.registerNHG()
    return DayRowView(
        dayName: "Mon",
        dateLabel: "May 12",
        totalLabel: "5h Free",
        slots: [.init(timeText: "9:00"), .init(timeText: "10:00"),
                .init(timeText: "11:00"), .init(timeText: "1:00")]
    )
    .padding(20)
    .background(Theme.bg)
    .preferredColorScheme(.dark)
}

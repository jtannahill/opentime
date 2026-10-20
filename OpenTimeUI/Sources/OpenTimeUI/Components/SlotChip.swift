import SwiftUI

public struct SlotChip: View {
    public let timeText: String
    public let isToday: Bool
    public let contextActions: ContextActions?

    public struct ContextActions {
        public let openInCalendar: () -> Void
        public let createEventHere: () -> Void
        public let copyTime: () -> Void

        public init(
            openInCalendar: @escaping () -> Void,
            createEventHere: @escaping () -> Void,
            copyTime: @escaping () -> Void
        ) {
            self.openInCalendar = openInCalendar
            self.createEventHere = createEventHere
            self.copyTime = copyTime
        }
    }

    public init(timeText: String, isToday: Bool = false, contextActions: ContextActions? = nil) {
        self.timeText = timeText
        self.isToday = isToday
        self.contextActions = contextActions
    }

    public var body: some View {
        let content = Text(timeText)
            .font(Theme.Font.display(size: 11, weight: .medium))
            .tnum()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(Theme.bg)
            .background(isToday ? Theme.accent : Theme.fg)

        if let a = contextActions {
            content
                .accessibilityLabel("Free at \(timeText)")
                .accessibilityHint("Opens actions to create an event or copy this time")
                .contextMenu {
                    Button("Open in Calendar", action: a.openInCalendar)
                    Button("Create Event Here", action: a.createEventHere)
                    Button("Copy Time", action: a.copyTime)
                }
        } else {
            content
                .accessibilityLabel("Free at \(timeText)")
        }
    }
}

#Preview("Light") {
    FontRegistration.registerNHG()
    return HStack(spacing: 4) {
        SlotChip(timeText: "9:00")
        SlotChip(timeText: "9:30", isToday: true)
        SlotChip(timeText: "10:30")
    }
    .padding(20)
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    FontRegistration.registerNHG()
    return HStack(spacing: 4) {
        SlotChip(timeText: "9:00")
        SlotChip(timeText: "9:30", isToday: true)
        SlotChip(timeText: "10:30")
    }
    .padding(20)
    .background(Theme.bg)
    .preferredColorScheme(.dark)
}

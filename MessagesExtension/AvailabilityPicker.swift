import SwiftUI
import OpenTimeUI

struct AvailabilityPicker: View {
    let isCompact: Bool
    let onExpand: () -> Void
    let onSend: (String) -> Void

    @StateObject private var helper = CalendarHelper()
    @State private var selectedDays: Set<UUID> = []
    @State private var pendingSelectAll = false

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            if isCompact {
                compactBody
            } else {
                expandedBody
            }
        }
        .task { await helper.requestAccess() }
        .onChange(of: helper.days) { _, days in
            guard pendingSelectAll else { return }
            selectedDays = Set(days.map(\.id))
            pendingSelectAll = false
        }
    }

    // MARK: - Compact

    private var compactBody: some View {
        Button(action: onExpand) {
            HStack(alignment: .center, spacing: 12) {
                Rectangle().fill(Theme.accent).frame(width: 3, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("OPEN TIME")
                        .font(Theme.Font.display(size: 10, weight: .bold))
                        .kerning(1.8)
                        .foregroundStyle(Theme.muted)
                    Text("Share Availability")
                        .font(Theme.Font.display(size: 17, weight: .bold))
                        .kerning(-0.18)
                        .foregroundStyle(Theme.fg)
                }
                Spacer()
                Text("OPEN")
                    .font(Theme.Font.display(size: 10, weight: .bold))
                    .kerning(1.8)
                    .foregroundStyle(Theme.fg)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Expanded

    private var expandedBody: some View {
        VStack(spacing: 0) {
            header

            HStack(spacing: 6) {
                MTSquareButton("This Week") {
                    pendingSelectAll = true
                    helper.loadThisWeek()
                }
                MTSquareButton("Next Week") {
                    pendingSelectAll = true
                    helper.loadNextWeek()
                }
                MTSquareButton("Next 14") {
                    pendingSelectAll = true
                    helper.loadNext14Days()
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            content
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .lastTextBaseline) {
                Text("SHARE AVAILABILITY")
                    .font(Theme.Font.display(size: 16, weight: .bold))
                    .kerning(-0.16)
                    .foregroundStyle(Theme.fg)
                Spacer()
                if !selectedDays.isEmpty {
                    // A link lets them tap a time; text sends the list itself.
                    if let link = helper.pickLink(selectedDays) {
                        MTSquareButton("Link", role: .submit) {
                            onSend(link.absoluteString)
                        }
                        .accessibilityLabel("Send a pick-a-time link")
                    }
                    MTSquareButton("Text") {
                        onSend(helper.formatSelected(selectedDays))
                    }
                    .accessibilityLabel("Send as text")
                }
            }
            .padding(.bottom, 6)
            Rectangle().fill(Theme.rule).frame(height: 4)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var content: some View {
        if !helper.accessGranted {
            Spacer()
            VStack(alignment: .leading, spacing: 6) {
                Text("CALENDAR ACCESS")
                    .font(Theme.Font.display(size: 10, weight: .bold))
                    .kerning(2.0)
                    .foregroundStyle(Theme.muted)
                Text("Open the main app to grant access.")
                    .font(Theme.Font.display(size: 13, weight: .regular))
                    .foregroundStyle(Theme.fg)
            }
            .padding(.horizontal, 20)
            Spacer()
        } else if helper.days.isEmpty {
            Spacer()
            Text("TAP A RANGE ABOVE")
                .font(Theme.Font.display(size: 10, weight: .regular))
                .kerning(1.8)
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 20)
            Spacer()
        } else {
            dayList
        }
    }

    private var dayList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(helper.days) { day in
                    PickerDayRow(
                        label: day.label,
                        slotsDescription: day.slotsDescription,
                        freeSummary: day.freeSummary,
                        hasFree: day.totalFreeMin > 0,
                        isSelected: selectedDays.contains(day.id)
                    ) {
                        if selectedDays.contains(day.id) {
                            selectedDays.remove(day.id)
                        } else {
                            selectedDays.insert(day.id)
                        }
                    }
                }
                Rectangle().fill(Theme.rule).frame(height: 1)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }
}

// MARK: - Shared row

struct PickerDayRow: View {
    let label: String
    let slotsDescription: String
    let freeSummary: String
    let hasFree: Bool
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                Rectangle().fill(Theme.rule).frame(height: 1)

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    // Selection square: filled when selected, outlined otherwise.
                    ZStack {
                        Rectangle().stroke(Theme.fg, lineWidth: 1)
                        if isSelected {
                            Rectangle().fill(Theme.accent).padding(2)
                        }
                    }
                    .frame(width: 14, height: 14)

                    Text(label)
                        .font(Theme.Font.display(size: 16, weight: .bold))
                        .kerning(-0.16)
                        .foregroundStyle(isSelected ? Theme.accent : Theme.fg)

                    Spacer()

                    Text(freeSummary.uppercased())
                        .font(Theme.Font.display(size: 10, weight: .regular))
                        .kerning(1.8)
                        .foregroundStyle(hasFree ? Theme.fg : Theme.dim)
                }

                Text(slotsDescription)
                    .font(Theme.Font.display(size: 11, weight: .regular))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .padding(.leading, 24)
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}

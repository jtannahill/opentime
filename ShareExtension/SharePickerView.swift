import SwiftUI
import EventKit
import OpenTimeUI

struct SharePickerView: View {
    let onDone: (String) -> Void
    let onCancel: () -> Void

    @StateObject private var helper = ShareCalendarHelper()
    @State private var selectedDays: Set<UUID> = []
    @State private var copied = false
    @State private var pendingSelectAll = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()

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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        onCancel()
                    } label: {
                        Text("CANCEL")
                            .font(Theme.Font.display(size: 10, weight: .bold))
                            .kerning(1.8)
                            .foregroundStyle(Theme.fg)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        let text = "Here's my availability:\n" + helper.formatSelected(selectedDays)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            onDone(text)
                        }
                    } label: {
                        Text(copied ? "COPIED" : "COPY")
                            .font(Theme.Font.display(size: 10, weight: .bold))
                            .kerning(1.8)
                            .foregroundStyle(selectedDays.isEmpty ? Theme.dim : (copied ? Theme.accent : Theme.fg))
                    }
                    .disabled(selectedDays.isEmpty)
                }
            }
            .toolbarBackground(Theme.bg, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { await helper.requestAccess() }
        .onChange(of: helper.days) { _, days in
            guard pendingSelectAll else { return }
            selectedDays = Set(days.map(\.id))
            pendingSelectAll = false
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
            }
            .padding(.bottom, 6)
            Rectangle().fill(Theme.rule).frame(height: 4)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
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
}

// MARK: - Shared row (mirrors the one in MessagesExtension)

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

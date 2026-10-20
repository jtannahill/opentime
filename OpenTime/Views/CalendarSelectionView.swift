// OpenTime/Views/CalendarSelectionView.swift
import EventKit
import OpenTimeUI
import SwiftUI

/// Toggle sheet for which calendars count toward availability.
/// Grouped by account (EKSource). The last enabled calendar cannot be
/// switched off so availability can never be computed from zero calendars.
struct CalendarSelectionView: View {
    let store: EKEventStore
    @Environment(\.dismiss) private var dismiss
    @State private var excluded: Set<String> = []

    private var allCalendars: [EKCalendar] {
        store.calendars(for: .event)
    }

    private var groups: [(source: String, calendars: [EKCalendar])] {
        let bySource = Dictionary(grouping: allCalendars) { $0.source?.title ?? "Other" }
        return bySource.keys.sorted().map { key in
            (key, bySource[key]!.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending })
        }
    }

    private var includedCount: Int {
        allCalendars.filter { !excluded.contains($0.calendarIdentifier) }.count
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(groups, id: \.source) { group in
                    Section {
                        ForEach(group.calendars, id: \.calendarIdentifier) { cal in
                            Toggle(isOn: binding(for: cal)) {
                                Text(cal.title)
                                    .font(Theme.Font.display(size: 14, weight: .regular))
                                    .foregroundStyle(Theme.fg)
                            }
                            .tint(Theme.accent)
                            .disabled(isLastEnabled(cal))
                        }
                    } header: {
                        Text(group.source.uppercased())
                            .font(Theme.Font.display(size: 10, weight: .regular))
                            .kerning(1.8)
                            .foregroundStyle(Theme.muted)
                    }
                }
            }
            .navigationTitle("Calendars")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear { excluded = CalendarSelection.excludedIDs() }
    }

    private func binding(for cal: EKCalendar) -> Binding<Bool> {
        Binding(
            get: { !excluded.contains(cal.calendarIdentifier) },
            set: { include in
                if include {
                    excluded.remove(cal.calendarIdentifier)
                } else {
                    excluded.insert(cal.calendarIdentifier)
                }
                CalendarSelection.setExcludedIDs(excluded)
            }
        )
    }

    private func isLastEnabled(_ cal: EKCalendar) -> Bool {
        !excluded.contains(cal.calendarIdentifier) && includedCount == 1
    }
}

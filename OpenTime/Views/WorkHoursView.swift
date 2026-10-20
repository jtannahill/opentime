// OpenTime/Views/WorkHoursView.swift
import OpenTimeUI
import SwiftUI

/// Picker sheet for the start and end hour of the workday.
/// Whole hours only. The end picker offers only hours after the selected
/// start, so an invalid window cannot be entered here. WorkHours.sanitize
/// remains the backstop for values arriving any other way.
struct WorkHoursView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var start = WorkHours.defaultStart
    @State private var end = WorkHours.defaultEnd
    /// False until onAppear has seeded the pickers, so the seeding
    /// assignments do not write back to the App Group.
    @State private var didLoad = false

    private var endOptions: [Int] { Array((start + 1)...23) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Start", selection: $start) {
                        ForEach(0...22, id: \.self) { hour in
                            Text(Self.label(hour)).tag(hour)
                        }
                    }
                    .pickerStyle(.wheel)
                } header: {
                    Text("START")
                        .font(Theme.Font.display(size: 10, weight: .regular))
                        .kerning(1.8)
                        .foregroundStyle(Theme.muted)
                }

                Section {
                    Picker("End", selection: $end) {
                        ForEach(endOptions, id: \.self) { hour in
                            Text(Self.label(hour)).tag(hour)
                        }
                    }
                    .pickerStyle(.wheel)
                } header: {
                    Text("END")
                        .font(Theme.Font.display(size: 10, weight: .regular))
                        .kerning(1.8)
                        .foregroundStyle(Theme.muted)
                }
            }
            .navigationTitle("Work Hours")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            let hours = WorkHours.current()
            start = hours.start
            end = hours.end
            didLoad = true
        }
        .onChange(of: start) { _, newStart in
            // Ignore the writes that populating the pickers itself triggers.
            guard didLoad else { return }
            // Keep the window valid when the start moves past the end.
            if end <= newStart { end = min(newStart + 1, 23) }
            save()
        }
        .onChange(of: end) { _, _ in
            guard didLoad else { return }
            save()
        }
    }

    private func save() {
        WorkHours.set(start: start, end: end)
    }

    /// Hour-of-day label using the device's 12- or 24-hour convention.
    private static func label(_ hour: Int) -> String {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let date = cal.date(bySettingHour: hour, minute: 0, second: 0, of: today)!
        return TimeFormat.time(date)
    }
}

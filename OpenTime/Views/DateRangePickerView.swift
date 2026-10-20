import SwiftUI
import OpenTimeUI

struct DateRangePickerView: View {
    @ObservedObject var manager: CalendarManager
    @State private var startDate = Date()
    @State private var endDate = Calendar.current.date(byAdding: .day, value: 4, to: Date())!
    @State private var showPicker = false
    @State private var selectedPreset: Preset? = CalendarManager.opensOnNextWeek ? .nextWeek : .thisWeek
    var onRangeChange: (() -> Void)? = nil

    enum Preset: String { case thisWeek, nextWeek, next14, custom }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("RANGE")
                .font(Theme.Font.display(size: 10, weight: .regular))
                .kerning(1.8)
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    MTSquareButton("This Week", isSelected: selectedPreset == .thisWeek) {
                        let cal = Calendar.current
                        let today = Date()
                        let weekday = cal.component(.weekday, from: today)
                        let monday = cal.date(byAdding: .day, value: weekday == 1 ? -6 : 2 - weekday, to: today)!
                        // Load Mon–Sun so the Weekends toggle has data to reveal.
                        let sunday = cal.date(byAdding: .day, value: 6, to: monday)!
                        startDate = monday
                        endDate = sunday
                        selectedPreset = .thisWeek
                        showPicker = false
                        manager.loadRange(from: monday, to: sunday)
                        onRangeChange?()
                    }

                    MTSquareButton("Next Week", isSelected: selectedPreset == .nextWeek) {
                        let cal = Calendar.current
                        let today = Date()
                        let weekday = cal.component(.weekday, from: today)
                        let nextMonday = cal.date(byAdding: .day, value: weekday == 1 ? 1 : 9 - weekday, to: today)!
                        let nextSunday = cal.date(byAdding: .day, value: 6, to: nextMonday)!
                        startDate = nextMonday
                        endDate = nextSunday
                        selectedPreset = .nextWeek
                        showPicker = false
                        manager.loadRange(from: nextMonday, to: nextSunday)
                        onRangeChange?()
                    }

                    MTSquareButton("Next 14 Days", isSelected: selectedPreset == .next14) {
                        let end = Calendar.current.date(byAdding: .day, value: 13, to: Date())!
                        startDate = Date()
                        endDate = end
                        selectedPreset = .next14
                        showPicker = false
                        manager.loadRange(from: Date(), to: end)
                        onRangeChange?()
                    }

                    MTSquareButton("Custom", isSelected: showPicker) {
                        withAnimation { showPicker.toggle() }
                        selectedPreset = .custom
                    }
                }
                .padding(.horizontal, 20)
            }

            if showPicker {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("FROM")
                                .font(Theme.Font.display(size: 10, weight: .regular))
                                .kerning(1.8)
                                .foregroundStyle(Theme.muted)
                            DatePicker("", selection: $startDate, displayedComponents: .date)
                                .labelsHidden()
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("TO")
                                .font(Theme.Font.display(size: 10, weight: .regular))
                                .kerning(1.8)
                                .foregroundStyle(Theme.muted)
                            DatePicker("", selection: $endDate, in: startDate..., displayedComponents: .date)
                                .labelsHidden()
                        }

                        Spacer()

                        MTSquareButton("Find", role: .submit) {
                            manager.loadRange(from: startDate, to: endDate)
                            onRangeChange?()
                            withAnimation { showPicker = false }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
}

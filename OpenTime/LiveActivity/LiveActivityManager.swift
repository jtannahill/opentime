import ActivityKit
import Combine
import EventKit
import Foundation
import OpenTimeUI

@MainActor
class LiveActivityManager: ObservableObject {
    static let shared = LiveActivityManager()
    @Published var isActive = false

    private var currentActivity: Activity<AvailabilityActivityAttributes>?
    private let store = EKEventStore()
    private var updateTimer: Timer?

    func startTracking() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard Self.hasCalendarAccess else { return }
        guard !Self.isOffHoursOrWeekend else { return }
        stopTracking()

        let attributes = AvailabilityActivityAttributes(workdayEnd: Self.workdayEndLabel)
        let state = computeCurrentState()

        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
            isActive = true
            scheduleUpdates()
        } catch {
            isActive = false
        }
    }

    func stopTracking() {
        Task { [activity = currentActivity] in
            await activity?.end(nil, dismissalPolicy: .immediate)
        }
        currentActivity = nil
        isActive = false
        updateTimer?.invalidate()
        updateTimer = nil
    }

    func updateNow() {
        guard let activity = currentActivity else { return }
        guard Self.hasCalendarAccess else {
            stopTracking()
            return
        }
        if Self.isOffHoursOrWeekend {
            stopTracking()
            return
        }
        let state = computeCurrentState()
        Task {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    // MARK: - Private

    private static var hasCalendarAccess: Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized:
            return true
        default:
            return false
        }
    }

    private static var isOffHoursOrWeekend: Bool {
        let cal = Calendar.current
        let now = Date()
        let weekday = cal.component(.weekday, from: now)
        let hour = cal.component(.hour, from: now)
        let hours = WorkHours.current()
        return weekday == 1 || weekday == 7 || hour >= hours.end || hour < hours.start
    }

    private static var workdayEndLabel: String {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let end = cal.date(bySettingHour: WorkHours.current().end, minute: 0, second: 0, of: today)!
        return TimeFormat.time(end)
    }

    private func scheduleUpdates() {
        updateTimer?.invalidate()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor [weak self] in
                self?.updateNow()
            }
        }
    }

    private func computeCurrentState() -> AvailabilityActivityAttributes.ContentState {
        let cal = Calendar.current
        let now = Date()
        let today = cal.startOfDay(for: now)
        let hours = WorkHours.current()
        let ws = cal.date(bySettingHour: hours.start, minute: 0, second: 0, of: today)!
        let we = cal.date(bySettingHour: hours.end, minute: 0, second: 0, of: today)!

        guard now >= ws && now < we else {
            return AvailabilityActivityAttributes.ContentState(
                currentStatus: "Off Hours",
                statusDetail: "Work hours: \(TimeFormat.time(ws)) - \(TimeFormat.time(we))",
                nextSlotLabel: "",
                nextSlotTime: "",
                totalFreeMinRemaining: 0
            )
        }

        guard Self.hasCalendarAccess else {
            return AvailabilityActivityAttributes.ContentState(
                currentStatus: "No Access",
                statusDetail: "Calendar permission required",
                nextSlotLabel: "",
                nextSlotTime: "",
                totalFreeMinRemaining: 0
            )
        }

        let predicate = store.predicateForEvents(
            withStart: now,
            end: we,
            calendars: CalendarSelection.calendars(for: store)
        )
        let events = BusyRules.blocking(store.events(matching: predicate), on: today)

        let freeIntervals = AvailabilityEngine.freeIntervals(
            events: events,
            on: today,
            workStartHour: hours.start,
            workEndHour: hours.end
        )
        let freeSlots = freeIntervals.filter { $0.end > now }
        let merged = AvailabilityEngine.mergedBusyIntervals(
            events: events,
            on: today,
            workStartHour: hours.start,
            workEndHour: hours.end
        )
        .filter { $0.end > now && $0.start < we }

        let totalFreeMin = freeSlots.reduce(0) {
            $0 + Int($1.end.timeIntervalSince(max($1.start, now)) / 60)
        }

        let inMeeting = merged.contains { $0.start <= now && now < $0.end }

        if inMeeting {
            let currentMeeting = merged.first { $0.start <= now && now < $0.end }!
            let nextFree = freeSlots.first
            return AvailabilityActivityAttributes.ContentState(
                currentStatus: "Busy",
                statusDetail: "Until \(TimeFormat.time(currentMeeting.end))",
                nextSlotLabel: nextFree != nil ? "Next free" : "No more free time",
                nextSlotTime: nextFree.map { TimeFormat.timeRange(from: max($0.start, now), to: $0.end) } ?? "",
                totalFreeMinRemaining: totalFreeMin
            )
        }

        let currentFree = freeSlots.first { $0.start <= now && now < $0.end }
        let nextBusy = merged.first { $0.start > now }
        return AvailabilityActivityAttributes.ContentState(
            currentStatus: "Free",
            statusDetail: currentFree.map { "Until \(TimeFormat.time($0.end))" } ?? "",
            nextSlotLabel: nextBusy != nil ? "Next meeting" : "Free rest of day",
            nextSlotTime: nextBusy.map { TimeFormat.time($0.start) } ?? "",
            totalFreeMinRemaining: totalFreeMin
        )
    }
}

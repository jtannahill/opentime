import SwiftUI
import ActivityKit
import EventKit
import UIKit
import WidgetKit
import OpenTimeUI

enum AppearancePreference: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

struct ContentView: View {
    @StateObject private var manager = CalendarManager()
    @StateObject private var liveActivity = LiveActivityManager.shared
    @State private var copied = false
    @State private var showBusy = false
    @State private var eventEditSlot: FreeSlot?
    @State private var shareText: ShareText?
    @State private var showCalendarPicker = false
    @State private var showWorkHours = false
    @State private var pickLinkToShare: PickLinkShare?
    @AppStorage("pickLinkName") private var pickLinkName = ""
    @AppStorage("pickLinkReplyTo") private var pickLinkReplyTo = ""
    /// Set once the link sheet has been seen, so SHARE can go straight to
    /// the share sheet after that.
    @AppStorage("pickLinkSheetSeen") private var pickLinkSheetSeen = false
    @State private var queryText: String = ""
    @State private var queryResult: [DayAvailability]?
    @State private var queryIntent: AvailabilityIntent?
    @State private var querySuggestion: QuerySuggest.Suggestion?
    @State private var queryError: Bool = false
    @State private var queryIsLoading = false
    @Environment(\.openURL) private var openURL
    @AppStorage("appearancePreference") private var appearanceRaw = AppearancePreference.system.rawValue
    @AppStorage("slotDurationMin") private var slotDurationMin = 30
    @AppStorage("liveActivityOptIn") private var liveActivityOptIn = false
    @EnvironmentObject private var deepLink: DeepLinkRouter

    private var appearance: AppearancePreference {
        AppearancePreference(rawValue: appearanceRaw) ?? .system
    }

    var filteredDays: [DayAvailability] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let base = manager.includeWeekends ? manager.days : manager.days.filter { !$0.isWeekend }
        return base.filter { cal.startOfDay(for: $0.date) >= today }
    }

    var headerMeta: String {
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM"
        return f.string(from: Date())
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !manager.accessGranted {
                    grantAccessView
                } else {
                    mainContent
                }
            }
            .background(Theme.bg)
            .toolbar { toolbarContent }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.bg, for: .navigationBar)
            .sheet(item: $eventEditSlot) { slot in
                EventEditSheet(
                    store: manager.store,
                    start: slot.start,
                    end: slot.end,
                    onSaved: {
                        manager.refresh()
                        liveActivity.updateNow()
                    },
                    onDismiss: { eventEditSlot = nil }
                )
            }
            .sheet(isPresented: $showCalendarPicker, onDismiss: {
                manager.refresh()
                WidgetCenter.shared.reloadAllTimelines()
                liveActivity.updateNow()
            }) {
                CalendarSelectionView(store: manager.store)
            }
            .sheet(isPresented: $showWorkHours, onDismiss: {
                manager.refresh()
                WidgetCenter.shared.reloadAllTimelines()
                // One push per editing session, carrying the final window.
                WorkHoursSync.shared.push()
                // ActivityKit attributes are immutable after request, so the
                // workday-end label can only pick up a new window by tearing
                // the activity down and requesting a fresh one. Starting
                // unconditionally also brings an activity back when a widened
                // window means the off-hours guard no longer applies. The
                // restart is gated on the stored opt-in because a user who
                // never started a Live Activity, or who stopped one, should
                // not get one merely by opening and closing this sheet.
                if liveActivityOptIn {
                    if liveActivity.isActive {
                        liveActivity.stopTracking()
                    }
                    liveActivity.startTracking()
                }
            }) {
                WorkHoursView()
            }
            .sheet(item: $shareText) { item in
                ActivityShareSheet(text: item.text)
            }
            .sheet(item: $pickLinkToShare) { item in
                PickLinkSheet(days: item.days, meetingMinutes: slotDurationMin,
                              name: $pickLinkName, replyTo: $pickLinkReplyTo)
                    .onAppear { pickLinkSheetSeen = true }
            }
            .sheet(item: $deepLink.incomingPick) { pick in
                PickTimeView(link: pick.link)
                    .presentationDragIndicator(.visible)
            }
            .sheet(item: $deepLink.incomingReply) { item in
                PickReplyView(reply: item.reply, save: manager.saveMeeting)
                    .presentationDragIndicator(.visible)
            }
            #if DEBUG
            // -showLinkSheet: open the pick-a-time link sheet, for simulator screenshots.
            .task {
                guard CommandLine.arguments.contains("-showLinkSheet") else { return }
                try? await Task.sleep(for: .seconds(1.5))
                pickLinkToShare = PickLinkShare(days: filteredDays)
            }
            #endif
        }
        .preferredColorScheme(appearance.colorScheme)
        .task {
            await manager.requestAccess()
        }
    }

    // MARK: - Access prompt

    private var grantAccessView: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("CALENDAR ACCESS")
                .font(Theme.Font.display(size: 10, weight: .bold))
                .kerning(2.0)
                .foregroundStyle(Theme.muted)
            Text("Required")
                .font(Theme.Font.display(size: 28, weight: .bold))
                .kerning(-0.28)
                .foregroundStyle(Theme.fg)
            Text("Grant access to see your availability")
                .font(Theme.Font.display(size: 13, weight: .regular))
                .foregroundStyle(Theme.muted)
            MTSquareButton("Grant Access", role: .submit) {
                Task { await manager.requestAccess() }
            }
            .padding(.top, 8)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
    }

    // MARK: - Main content

    private var mainContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    PageHeader(title: "Availability", meta: headerMeta)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    settingsLine
                        .padding(.horizontal, 20)
                        .padding(.bottom, 2)

                    if QueryParser.isAvailable {
                        QueryBarView(
                            text: $queryText,
                            isLoading: queryIsLoading,
                            hasResult: queryResult != nil || queryError,
                            onSubmit: { await runQuery() },
                            onClear: clearQuery
                        )
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)

                        if let intent = queryIntent {
                            QueryResultBanner(state: bannerState(for: intent))
                                .padding(.horizontal, 20)
                                .padding(.bottom, 4)
                        } else if queryError {
                            QueryResultBanner(state: .error)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 4)
                        }
                    }

                    DateRangePickerView(manager: manager, onRangeChange: clearQuery)

                    if manager.isLoading {
                        loadingView
                    } else if manager.days.isEmpty {
                        emptyView
                    } else if let result = queryResult, !result.isEmpty {
                        matchResultView(result)
                    } else if filteredDays.isEmpty {
                        nothingLeftView
                    } else {
                        dayList

                        if let refreshed = manager.lastRefreshed {
                            let f = DateFormatter()
                            let _ = f.dateFormat = "h:mm a"
                            Text("UPDATED \(f.string(from: refreshed))".uppercased())
                                .font(Theme.Font.display(size: 10, weight: .regular))
                                .kerning(1.8)
                                .foregroundStyle(Theme.dim)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 12)
                                .padding(.bottom, 20)
                        }
                    }
                }
            }
            .refreshable {
                manager.refresh()
                liveActivity.updateNow()
            }
            .onChange(of: deepLink.pendingSlot) { _, slot in
                guard let s = slot else { return }
                let dayKey = Calendar.current.startOfDay(for: s.start)
                withAnimation { proxy.scrollTo(dayKey, anchor: .top) }
                DispatchQueue.main.async { deepLink.pendingSlot = nil }
            }
        }
    }

    @MainActor
    private func runQuery() async {
        let text = queryText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        queryIsLoading = true
        queryError = false
        defer { queryIsLoading = false }

        do {
            let now = Date()
            let intent = try await QueryParser.parse(text, now: now)

            // Auto-expand the loaded date range up to the 4-week cap.
            if let needed = intent.requestedRange(now: now) {
                let cap = Calendar.current.date(byAdding: .weekOfYear, value: 4, to: now)!
                let target = min(needed.end, cap)
                if let currentEnd = manager.loadedRangeEnd, target > currentEnd {
                    await manager.extendRange(to: target)
                }
            }

            let matched = QueryFilter.filter(days: filteredDays, intent: intent, now: now)
            queryIntent = intent
            queryResult = matched
            querySuggestion = matched.isEmpty
                ? QuerySuggest.closest(days: filteredDays, intent: intent, now: now)
                : nil
        } catch {
            queryError = true
            queryResult = nil
            queryIntent = nil
            querySuggestion = nil
        }
    }

    private func clearQuery() {
        queryText = ""
        queryResult = nil
        queryIntent = nil
        querySuggestion = nil
        queryError = false
    }

    private func bannerState(for intent: AvailabilityIntent) -> QueryResultBanner.State {
        let summary = intent.summary(now: Date())
        if let matches = queryResult, !matches.isEmpty {
            let count = matches.reduce(0) { $0 + $1.freeSlots.count }
            return .match(summary: summary, slotCount: count)
        }
        if let s = querySuggestion {
            return .suggestion(
                summary: summary,
                suggestionText: Self.formatSuggestion(s),
                onTap: { deepLink.pendingSlot = DeepLinkRouter.PendingSlot(start: s.slot.start, end: s.slot.end) }
            )
        }
        return .noMatch(summary: summary)
    }

    private static let suggestionFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE h:mm a"
        return f
    }()

    private static func formatSuggestion(_ s: QuerySuggest.Suggestion) -> String {
        let when = suggestionFormatter.string(from: s.slot.start).uppercased()
        let relaxed = s.relaxedFields.map { Self.relaxLabel($0) }.joined(separator: ", ")
        return "\(when) (\(relaxed) RELAXED)"
    }

    private static func relaxLabel(_ field: QuerySuggest.RelaxedField) -> String {
        switch field {
        case .date:      return "DATE"
        case .timeOfDay: return "TIME"
        case .duration:  return "DURATION"
        }
    }

    private func matchResultView(_ result: [DayAvailability]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("MATCH")
                    .font(Theme.Font.display(size: 10, weight: .bold))
                    .kerning(1.8)
                    .foregroundStyle(Theme.accent)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 4)

            VStack(spacing: 0) {
                ForEach(result) { day in
                    day.asRow(
                        showBusy: showBusy,
                        isToday: Calendar.current.isDateInToday(day.date),
                        durationMin: slotDurationMin,
                        chipContext: { rowSlot in chipContext(for: day, rowSlot: rowSlot) },
                        dayActions: dayActions(for: day)
                    )
                }
                Rectangle().fill(Theme.rule).frame(height: 1)
            }
            .padding(.horizontal, 20)
        }
    }

    private var loadingView: some View {
        VStack {
            Spacer().frame(height: 40)
            ProgressView()
                .tint(Theme.fg)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyView: some View {
        VStack {
            Spacer().frame(height: 40)
            Text("SELECT A RANGE")
                .font(Theme.Font.display(size: 10, weight: .regular))
                .kerning(1.8)
                .foregroundStyle(Theme.muted)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var dayList: some View {
        VStack(spacing: 0) {
            ForEach(filteredDays) { day in
                day.asRow(
                    showBusy: showBusy,
                    isToday: Calendar.current.isDateInToday(day.date),
                    durationMin: slotDurationMin,
                    chipContext: { rowSlot in chipContext(for: day, rowSlot: rowSlot) },
                    dayActions: dayActions(for: day)
                )
                .id(Calendar.current.startOfDay(for: day.date))
            }
            // Closing rule for the last row
            Rectangle().fill(Theme.rule).frame(height: 1)
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    // MARK: - Slot subdivision + chip context menu wiring

    /// Subdivide a continuous free block into slot starts of `duration` minutes.
    /// e.g. free 9:00–10:30 at 30-min duration → [9:00, 9:30, 10:00].
    private static func subdivide(_ slot: FreeSlot, duration: Int) -> [Date] {
        var starts: [Date] = []
        var cursor = slot.start
        let durSec = TimeInterval(duration * 60)
        while cursor.addingTimeInterval(durSec) <= slot.end {
            starts.append(cursor)
            cursor = cursor.addingTimeInterval(durSec)
        }
        return starts
    }

    /// Resolve a chip's display string back to its concrete start Date for the day.
    private func resolveChipStart(day: DayAvailability, timeText: String) -> Date? {
        for slot in day.freeSlots {
            for start in Self.subdivide(slot, duration: slotDurationMin) {
                if Fmt.time(start) == timeText {
                    return start
                }
            }
        }
        return nil
    }

    // MARK: - Day-row context menu wiring

    private func dayActions(for day: DayAvailability) -> DayRowView.DayActions {
        DayRowView.DayActions(
            copyDay: {
                let text = manager.availabilityText(for: [day])
                UIPasteboard.general.string = text
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            },
            shareDay: {
                shareText = ShareText(text: manager.availabilityText(for: [day]))
            }
        )
    }

    private func chipContext(for day: DayAvailability, rowSlot: DayRowView.Slot) -> SlotChip.ContextActions {
        guard let start = resolveChipStart(day: day, timeText: rowSlot.timeText) else {
            return SlotChip.ContextActions(openInCalendar: {}, createEventHere: {}, copyTime: {})
        }
        let end = start.addingTimeInterval(TimeInterval(slotDurationMin * 60))
        return SlotChip.ContextActions(
            openInCalendar: {
                openURL(CalendarURL.openCalendar(at: start))
            },
            createEventHere: {
                eventEditSlot = FreeSlot(start: start, end: end)
            },
            copyTime: {
                let s = TimeFormat.timeRange(from: start, to: end)
                UIPasteboard.general.string = s
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        )
    }

    // MARK: - Settings line and empty week

    /// What the list is built from, always in view and one tap from changing.
    private var settingsLine: some View {
        let hours = WorkHours.current()
        let all = manager.store.calendars(for: .event).count
        let used = CalendarSelection.calendars(for: manager.store)?.count ?? all
        let calendars = used == all ? "All calendars" : "\(used) of \(all) calendars"
        return HStack(spacing: 0) {
            Button {
                showWorkHours = true
            } label: {
                settingsLabel(Self.hourRange(hours.start, hours.end))
            }
            .accessibilityLabel("Work hours \(Self.hourRange(hours.start, hours.end))")
            .accessibilityHint("Change the hours that count")
            Text(" · ")
                .font(Theme.Font.display(size: 13, relativeTo: .footnote))
                .foregroundStyle(Theme.dim)
                .accessibilityHidden(true)
            Button {
                showCalendarPicker = true
            } label: {
                settingsLabel(calendars)
            }
            .accessibilityHint("Choose which calendars count")
            Spacer(minLength: 0)
        }
    }

    private func settingsLabel(_ text: String) -> some View {
        Text(text)
            .font(Theme.Font.display(size: 13, weight: .medium, relativeTo: .footnote))
            .foregroundStyle(Theme.muted)
            .underline(color: Theme.dim)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
    }

    private static func hourRange(_ start: Int, _ end: Int) -> String {
        let cal = Calendar.current
        let day = cal.startOfDay(for: Date())
        let s = cal.date(bySettingHour: start, minute: 0, second: 0, of: day)!
        let e = cal.date(bySettingHour: end % 24, minute: 0, second: 0, of: day)!
        return TimeFormat.timeRange(from: s, to: e)
    }

    /// The range has no days left to show: usually a weekend with
    /// weekends hidden, or the end of the week.
    private var nothingLeftView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Rectangle().fill(Theme.rule).frame(height: 1)
            Text("Nothing left in this range")
                .font(Theme.Font.display(size: 20, weight: .bold, relativeTo: .title3))
                .foregroundStyle(Theme.fg)
            Text(manager.includeWeekends
                 ? "Every day in it has already passed. Choose another range above."
                 : "The days that remain are a weekend, and weekends are hidden. Choose another range above, or show weekends.")
                .font(Theme.Font.display(size: 14, relativeTo: .body))
                .foregroundStyle(Theme.muted)
            if !manager.includeWeekends {
                MTSquareButton("Show Weekends", role: .submit) { manager.includeWeekends = true }
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: - Toolbar

    /// The first time, the link sheet explains the link and asks for a name;
    /// after that SHARE goes straight to the share sheet with the link.
    private func sharePickLink() {
        guard pickLinkSheetSeen else {
            pickLinkToShare = PickLinkShare(days: filteredDays)
            return
        }
        let link = PickLink.from(days: filteredDays, meetingMinutes: slotDurationMin, name: pickLinkName,
                                 replyTo: PickLink.ReplyTo(pickLinkReplyTo))
        guard !link.slots.isEmpty else {
            pickLinkToShare = PickLinkShare(days: filteredDays)
            return
        }
        SharePresenter.present([PickLinkSheet.message, link.url])
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if manager.accessGranted && !filteredDays.isEmpty {
                Button {
                    let text = manager.availabilityText(for: filteredDays)
                    UIPasteboard.general.string = text
                    copied = true
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Text(copied ? "COPIED" : "COPY")
                        .font(Theme.Font.display(size: 10, weight: .bold))
                        .kerning(1.8)
                        .foregroundStyle(copied ? Theme.accent : Theme.fg)
                }
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            if manager.accessGranted && !filteredDays.isEmpty {
                // Tap shares the link at once; press and hold for the rest.
                Menu {
                    Button {
                        pickLinkToShare = PickLinkShare(days: filteredDays)
                    } label: {
                        Label("Link Settings", systemImage: "slider.horizontal.3")
                    }
                    ShareLink(item: manager.availabilityText(for: filteredDays)) {
                        Label("Send as Text", systemImage: "text.alignleft")
                    }
                } label: {
                    Text("SHARE")
                        .font(Theme.Font.display(size: 10, weight: .bold))
                        .kerning(1.8)
                        .foregroundStyle(Theme.fg)
                } primaryAction: {
                    sharePickLink()
                }
                .accessibilityHint("Shares a pick-a-time link. Press and hold for link settings or to send as text.")
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            if manager.accessGranted {
                Menu {
                    Toggle("Show Busy", isOn: $showBusy)
                    Toggle("Weekends", isOn: $manager.includeWeekends)
                    Toggle(liveActivity.isActive ? "Stop Live Activity" : "Start Live Activity",
                           isOn: Binding(
                            get: { liveActivity.isActive },
                            set: { _ in
                                if liveActivity.isActive {
                                    liveActivity.stopTracking()
                                    liveActivityOptIn = false
                                } else {
                                    liveActivity.startTracking()
                                    liveActivityOptIn = true
                                }
                            }
                           )
                    )
                    Picker("Appearance", selection: $appearanceRaw) {
                        ForEach(AppearancePreference.allCases) { mode in
                            Text(mode.label).tag(mode.rawValue)
                        }
                    }
                    Picker("Slot Duration", selection: $slotDurationMin) {
                        Text("15 min").tag(15)
                        Text("30 min").tag(30)
                        Text("60 min").tag(60)
                    }
                    Button {
                        showCalendarPicker = true
                    } label: {
                        Label("Calendars", systemImage: "calendar")
                    }
                    Button {
                        showWorkHours = true
                    } label: {
                        Label("Work Hours", systemImage: "clock")
                    }
                    Button {
                        manager.loadTodayAndTomorrow()
                        liveActivity.updateNow()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                } label: {
                    Text("MORE")
                        .font(Theme.Font.display(size: 10, weight: .bold))
                        .kerning(1.8)
                        .foregroundStyle(Theme.fg)
                }
            }
        }
    }
}

// MARK: - Adapter from DayAvailability to DayRowView

private extension DayAvailability {
    @ViewBuilder
    func asRow(
        showBusy: Bool,
        isToday: Bool,
        durationMin: Int,
        chipContext: ((DayRowView.Slot) -> SlotChip.ContextActions)?,
        dayActions: DayRowView.DayActions? = nil
    ) -> some View {
        let chipStarts: [Date] = freeSlots.flatMap { slot -> [Date] in
            var starts: [Date] = []
            var cursor = slot.start
            let durSec = TimeInterval(durationMin * 60)
            while cursor.addingTimeInterval(durSec) <= slot.end {
                starts.append(cursor)
                cursor = cursor.addingTimeInterval(durSec)
            }
            return starts
        }
        let cal = Calendar.current
        let isPast = cal.startOfDay(for: date) < cal.startOfDay(for: Date())
        DayRowView(
            dayName: Fmt.relativeDay(date),
            dateLabel: Fmt.dateFull.string(from: date),
            totalLabel: "\(Fmt.duration(totalFreeMin)) Free",
            isToday: isToday,
            isPast: isPast,
            slots: chipStarts.map { .init(timeText: Fmt.time($0)) },
            busy: busySlots.map {
                .init(
                    timeRange: TimeFormat.timeRange(from: $0.start, to: $0.end),
                    title: $0.summary
                )
            },
            showBusy: showBusy,
            chipContext: chipContext,
            dayActions: dayActions
        )
    }
}

// MARK: - Share helpers

struct PickLinkShare: Identifiable {
    let id = UUID()
    let days: [DayAvailability]
}

/// Builds a pick-a-time link from the days on screen. The optional name is
/// remembered so the next link needs no typing.
struct PickLinkSheet: View {
    static let message = "Pick the times that work for you:"

    let days: [DayAvailability]
    let meetingMinutes: Int
    @Binding var name: String
    @Binding var replyTo: String
    @Environment(\.dismiss) private var dismiss

    private var parsedReplyTo: PickLink.ReplyTo? { PickLink.ReplyTo(replyTo) }

    private var link: PickLink {
        PickLink.from(days: days, meetingMinutes: meetingMinutes, name: name, replyTo: parsedReplyTo)
    }

    private var replyToFooter: String {
        let typed = !replyTo.trimmingCharacters(in: .whitespaces).isEmpty
        if typed && parsedReplyTo == nil {
            return "That doesn\u{2019}t look like a phone number or email, so it is left out of the link."
        }
        if let to = parsedReplyTo {
            return "Their Send button opens \(to.appName) addressed to you. Anyone with the link can see it."
        }
        return "Add your number or email and their Send button opens Messages or Mail addressed to you. Anyone with the link can see it."
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Your first name (optional)", text: $name)
                        .textContentType(.givenName)
                        .submitLabel(.done)
                } footer: {
                    Text(name.isEmpty
                         ? "Without a name they see \u{201C}These times are free.\u{201D}"
                         : "They see \u{201C}\(name) shared these free times.\u{201D}")
                }
                Section {
                    TextField("Your number or email (optional)", text: $replyTo)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                } footer: {
                    Text(replyToFooter)
                }
                Section {
                    LabeledContent("Meeting length", value: "\(meetingMinutes) min")
                    LabeledContent("Free times", value: "\(link.choices().count)")
                } footer: {
                    Text("They choose up to \(PickReply.maxPicks) times in their own time zone, on iPhone or in any browser, and send them back to you as a reply link that opens here. The times travel inside the links, so nothing passes through a server. Your events stay private; only free times are shared. Next time, SHARE sends the link straight away; press and hold it to come back here.")
                }
            }
            .navigationTitle("Pick-a-Time Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    ShareLink(item: link.url, message: Text(Self.message)) {
                        Text("Share")
                    }
                    .disabled(link.slots.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct ShareText: Identifiable {
    let id = UUID()
    let text: String
}

struct ActivityShareSheet: UIViewControllerRepresentable {
    let text: String
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [text], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

#Preview {
    ContentView()
}

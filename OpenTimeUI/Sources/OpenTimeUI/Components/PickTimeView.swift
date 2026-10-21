import SwiftUI

/// What someone sees after opening a pick-a-time link: the sender's free
/// times in their own time zone. They choose up to five, then send a reply
/// link back; nothing is sent anywhere until they share it themselves.
public struct PickTimeView: View {
    public let link: PickLink?
    /// Shown under the times, for the App Clip's "get the app" prompt.
    public var footer: AnyView?

    @State private var selected: [Date] = []
    @State private var limitHint = 0
    @AppStorage("pickReplyName") private var replyName = ""
    @AppStorage("pickReplyContact") private var replyContact = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(link: PickLink?, footer: AnyView? = nil) {
        self.link = link
        self.footer = footer
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(title: "Pick a time", meta: link.map { "\($0.meetingMinutes) MIN" })
                    .padding(.top, 8)
                if let link {
                    intro(link)
                    let days = Self.group(link.choices())
                    if days.isEmpty {
                        message("These times have passed",
                                detail: "Ask for a fresh link with times that are still ahead.")
                    } else {
                        ForEach(days, id: \.day) { day in
                            dayRow(day.day, day.times, link: link)
                        }
                        Rectangle().fill(Theme.rule).frame(height: 1)
                    }
                } else {
                    message("This link has no times in it",
                            detail: "It may have been cut short when it was copied. Ask for the link again.")
                }
                if let footer {
                    footer.padding(.top, 28)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(Theme.bg)
        .safeAreaInset(edge: .bottom) {
            if !selected.isEmpty, let link {
                choiceBar(selected, link: link)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: selected)
        .sensoryFeedback(.selection, trigger: selected)
        .sensoryFeedback(.warning, trigger: limitHint)
        #if DEBUG
        // -pickSelect <n>: preselect every fourth time, for simulator screenshots.
        .onAppear {
            if let i = CommandLine.arguments.firstIndex(of: "-pickSelect"), i + 1 < CommandLine.arguments.count,
               let n = Int(CommandLine.arguments[i + 1]), let link {
                selected = Array(link.choices().enumerated().filter { $0.offset % 4 == 2 }.map(\.element).prefix(n))
            }
        }
        #endif
    }

    // MARK: - Pieces

    private func intro(_ link: PickLink) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(link.name.map { "\($0) shared these free times." } ?? "These times are free.")
                .font(Theme.Font.display(size: 17, weight: .medium, relativeTo: .body))
                .foregroundStyle(Theme.fg)
            Text(Self.zoneNote(link) + " Choose up to \(PickReply.maxPicks) that suit you.")
                .font(Theme.Font.display(size: 13, relativeTo: .footnote))
                .foregroundStyle(Theme.muted)
        }
        .padding(.top, 16)
        .padding(.bottom, 20)
    }

    private func dayRow(_ day: Date, _ times: [Date], link: PickLink) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Rectangle().fill(Theme.rule).frame(height: 1)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Self.dayName(day))
                    .font(Theme.Font.display(size: 22, weight: .bold, relativeTo: .title2))
                    .foregroundStyle(Theme.fg)
                Text(Self.dateLabel(day).uppercased())
                    .font(Theme.Font.display(size: 10, relativeTo: .caption))
                    .kerning(1.8)
                    .foregroundStyle(Theme.muted)
            }
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(times, id: \.self) { t in
                    let isOn = selected.contains(t)
                    Button {
                        toggle(t)
                    } label: {
                        Text(TimeFormat.time(t))
                            .font(Theme.Font.display(size: 13, weight: .medium, relativeTo: .callout))
                            .tnum()
                            .padding(.horizontal, 10)
                            .frame(minHeight: 44)
                            .foregroundStyle(Theme.bg)
                            .background(isOn ? Theme.accent : Theme.fg)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(Self.dayName(day)) at \(TimeFormat.time(t))")
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            .padding(.bottom, 14)
        }
    }

    private func toggle(_ t: Date) {
        if let i = selected.firstIndex(of: t) {
            selected.remove(at: i)
        } else if selected.count < PickReply.maxPicks {
            selected = (selected + [t]).sorted()
        } else {
            limitHint += 1
        }
    }

    private func choiceBar(_ picks: [Date], link: PickLink) -> some View {
        let contact = PickLink.ReplyTo(replyContact)
        let reply = PickReply(link: link, picks: picks, name: replyName, contact: contact)
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(picks, id: \.self) { t in
                    Text(Self.when(t, minutes: link.meetingMinutes))
                        .font(Theme.Font.display(size: 15, weight: .bold, relativeTo: .headline))
                        .tnum()
                        .foregroundStyle(Theme.fg)
                }
                Text(picks.count < PickReply.maxPicks
                     ? "\(picks.count) of \(PickReply.maxPicks) chosen"
                     : "\(PickReply.maxPicks) of \(PickReply.maxPicks) chosen. Tap one to swap it.")
                    .font(Theme.Font.display(size: 12, relativeTo: .caption))
                    .foregroundStyle(Theme.muted)
            }
            TextField("Your name (optional)", text: $replyName)
                .font(Theme.Font.display(size: 15, relativeTo: .body))
                .textContentType(.givenName)
                .submitLabel(.done)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .overlay(Rectangle().stroke(Theme.rule, lineWidth: 1))
            VStack(alignment: .leading, spacing: 4) {
                contactField(link)
                Text(contact == nil && !replyContact.trimmingCharacters(in: .whitespaces).isEmpty
                     ? "That is not a phone number or email, so it is left out."
                     : "So \(link.name ?? "they") can send the confirmation straight to you.")
                    .font(Theme.Font.display(size: 12, relativeTo: .caption))
                    .foregroundStyle(Theme.muted)
            }
            let direct = link.replyTo.flatMap { to in
                to.url(message: Self.replyMessage(picks.count), link: reply.url).map { (to, $0) }
            }
            HStack(spacing: 10) {
                if let (to, url) = direct {
                    // Already addressed to the sender, so only Send is left to tap.
                    Link(destination: url) {
                        actionLabel("Send in \(to.appName)", filled: true)
                    }
                    .accessibilityHint("Opens \(to.appName) with your times, addressed to \(link.name ?? "them")")
                } else {
                    ShareLink(item: reply.url, message: Text(Self.replyMessage(picks.count))) {
                        actionLabel("Send my times", filled: true)
                    }
                }
                if picks.count == 1, let start = picks.first,
                   let ics = Self.icsFile(title: link.name.map { "Meeting with \($0)" } ?? "Meeting",
                                          start: start,
                                          end: start.addingTimeInterval(TimeInterval(link.meetingMinutes * 60))) {
                    ShareLink(item: ics) {
                        actionLabel("Add to Calendar", filled: false)
                    }
                }
            }
            if direct != nil {
                ShareLink(item: reply.url, message: Text(Self.replyMessage(picks.count))) {
                    Text("Send another way")
                        .font(Theme.Font.display(size: 13, weight: .medium, relativeTo: .footnote))
                        .underline()
                        .foregroundStyle(Theme.muted)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .overlay(alignment: .top) { Rectangle().fill(Theme.rule).frame(height: 1) }
    }

    /// Their number or email. AutoFill offers whichever the link's own
    /// reply-to is, since that is the way they are about to send.
    @ViewBuilder
    private func contactField(_ link: PickLink) -> some View {
        let field = TextField("Your number or email (optional)", text: $replyContact)
            .font(Theme.Font.display(size: 15, relativeTo: .body))
            .autocorrectionDisabled()
            .submitLabel(.done)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .overlay(Rectangle().stroke(Theme.rule, lineWidth: 1))
        #if canImport(UIKit)
        if case .email = link.replyTo {
            field.textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never)
        } else {
            field.textContentType(.telephoneNumber).keyboardType(.numbersAndPunctuation).textInputAutocapitalization(.never)
        }
        #else
        field
        #endif
    }

    private func actionLabel(_ text: String, filled: Bool) -> some View {
        Text(text.uppercased())
            .font(Theme.Font.display(size: 11, weight: .bold, relativeTo: .footnote))
            .kerning(1.4)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(filled ? Theme.bg : Theme.fg)
            .background(filled ? Theme.fg : Color.clear)
            .overlay(Rectangle().stroke(Theme.fg, lineWidth: 1))
    }

    private func message(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle().fill(Theme.rule).frame(height: 1)
            Text(title)
                .font(Theme.Font.display(size: 20, weight: .bold, relativeTo: .title3))
                .foregroundStyle(Theme.fg)
            Text(detail)
                .font(Theme.Font.display(size: 14, relativeTo: .body))
                .foregroundStyle(Theme.muted)
        }
        .padding(.top, 8)
    }

    // MARK: - Logic

    static func dayName(_ date: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        return date.formatted(.dateTime.weekday(.wide))
    }

    static func dateLabel(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    static func group(_ times: [Date], calendar: Calendar = .current) -> [(day: Date, times: [Date])] {
        Dictionary(grouping: times) { calendar.startOfDay(for: $0) }
            .map { (day: $0.key, times: $0.value.sorted()) }
            .sorted { $0.day < $1.day }
    }

    static func zoneNote(_ link: PickLink, here: TimeZone = .current) -> String {
        let local = here.localizedName(for: .shortGeneric, locale: .current) ?? here.identifier
        guard let theirs = TimeZone(identifier: link.timeZoneID),
              theirs.secondsFromGMT() != here.secondsFromGMT() else {
            return "Times are in your time zone (\(local))."
        }
        let theirName = theirs.localizedName(for: .generic, locale: .current) ?? theirs.identifier
        return "Times are in your time zone (\(local)). Sent from \(theirName)."
    }

    static func when(_ start: Date, minutes: Int) -> String {
        let end = start.addingTimeInterval(TimeInterval(minutes * 60))
        return "\(dayName(start)), \(dateLabel(start)) · \(TimeFormat.timeRange(from: start, to: end))"
    }

    static func replyMessage(_ count: Int) -> String {
        count == 1 ? "This time works for me:" : "These times work for me:"
    }

    static func icsFile(title: String, start: Date, end: Date) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Open Time meeting.ics")
        do {
            try ICSFile.event(title: title, start: start, end: end).write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}

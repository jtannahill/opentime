import SwiftUI

/// What the sender sees after opening a reply to their pick-a-time link:
/// the times the other person chose, in the sender's time zone, each with a
/// way to confirm it and put it on the calendar.
public struct PickReplyView: View {
    public let reply: PickReply?
    /// Saves a meeting straight to the calendar, for an app that already has
    /// calendar access. With it, Confirm is one tap: the event is saved and
    /// the share sheet opens with the confirmation. Without it, Confirm opens
    /// the system new-event sheet instead.
    public var save: (@MainActor (_ title: String, _ start: Date, _ end: Date) -> Bool)?
    /// The time whose new-event sheet is open.
    @State private var inviting: Invite?
    /// Times added to the calendar here, so their row can say so.
    @State private var added: Set<Date> = []

    public init(reply: PickReply?, save: (@MainActor (_ title: String, _ start: Date, _ end: Date) -> Bool)? = nil) {
        self.reply = reply
        self.save = save
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(title: "Times picked", meta: reply.map { "\($0.meetingMinutes) MIN" })
                    .padding(.top, 8)
                if let reply {
                    intro(reply)
                    ForEach(reply.picks, id: \.self) { t in
                        row(t, reply: reply)
                    }
                    Rectangle().fill(Theme.rule).frame(height: 1)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Rectangle().fill(Theme.rule).frame(height: 1)
                        Text("This reply has no times in it")
                            .font(Theme.Font.display(size: 20, weight: .bold, relativeTo: .title3))
                            .foregroundStyle(Theme.fg)
                        Text("It may have been cut short when it was copied. Ask them to send it again.")
                            .font(Theme.Font.display(size: 14, relativeTo: .body))
                            .foregroundStyle(Theme.muted)
                    }
                    .padding(.top, 8)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(Theme.bg)
        #if canImport(EventKitUI)
        .sheet(item: $inviting) { invite in
            EventEditSheet(title: invite.title, start: invite.start, end: invite.end) { saved in
                if saved { added.insert(invite.start) }
                inviting = nil
            }
            .ignoresSafeArea()
        }
        #endif
    }

    private struct Invite: Identifiable {
        let title: String
        let start: Date
        let end: Date
        var id: Date { start }
    }

    private func intro(_ reply: PickReply) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Self.headline(reply))
                .font(Theme.Font.display(size: 17, weight: .medium, relativeTo: .body))
                .foregroundStyle(Theme.fg)
            Text(Self.zoneNote(reply))
                .font(Theme.Font.display(size: 13, relativeTo: .footnote))
                .foregroundStyle(Theme.muted)
        }
        .padding(.top, 16)
        .padding(.bottom, 20)
    }

    private func row(_ start: Date, reply: PickReply) -> some View {
        let end = start.addingTimeInterval(TimeInterval(reply.meetingMinutes * 60))
        let passed = end < Date()
        return VStack(alignment: .leading, spacing: 10) {
            Rectangle().fill(Theme.rule).frame(height: 1)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(PickTimeView.dayName(start))
                    .font(Theme.Font.display(size: 22, weight: .bold, relativeTo: .title2))
                    .foregroundStyle(passed ? Theme.muted : Theme.fg)
                Text(PickTimeView.dateLabel(start).uppercased())
                    .font(Theme.Font.display(size: 10, relativeTo: .caption))
                    .kerning(1.8)
                    .foregroundStyle(Theme.muted)
            }
            Text(TimeFormat.timeRange(from: start, to: end) + (passed ? " · passed" : ""))
                .font(Theme.Font.display(size: 15, weight: .medium, relativeTo: .callout))
                .tnum()
                .foregroundStyle(passed ? Theme.muted : Theme.fg)
            if !passed {
                let title = reply.name.map { "Meeting with \($0)" } ?? "Meeting"
                let confirmLink = ConfirmLink(reply: reply, start: start)
                let isAdded = added.contains(start)
                if isAdded {
                    Text("On your calendar. Send \(reply.name ?? "them") the confirmation so it goes on theirs too.")
                        .font(Theme.Font.display(size: 13, relativeTo: .footnote))
                        .foregroundStyle(Theme.muted)
                }
                HStack(spacing: 10) {
                    #if canImport(EventKitUI)
                    if !isAdded {
                        if let save {
                            Button {
                                confirm(title: title, start: start, end: end, link: confirmLink.url, save: save)
                            } label: {
                                actionLabel("Confirm", filled: true)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Adds it to your calendar and opens the share sheet to tell \(reply.name ?? "them")")
                            Button {
                                inviting = Invite(title: title, start: start, end: end)
                            } label: {
                                actionLabel("Edit and invite", filled: false)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Button {
                                inviting = Invite(title: title, start: start, end: end)
                            } label: {
                                actionLabel("Confirm and invite", filled: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    #else
                    if let ics = PickTimeView.icsFile(title: title, start: start, end: end) {
                        ShareLink(item: ics) { actionLabel("Add to Calendar", filled: true) }
                    }
                    #endif
                    if isAdded || save == nil {
                        ShareLink(item: Self.confirmation(start: start, end: end, link: confirmLink.url)) {
                            actionLabel("Send confirmation", filled: isAdded)
                        }
                    }
                }
            }
        }
        .padding(.bottom, 14)
    }

    /// One tap: save the meeting, then hand the confirmation to the share
    /// sheet. If the save fails, fall back to the new-event sheet so the
    /// tap still gets somewhere.
    private func confirm(title: String, start: Date, end: Date, link: URL,
                         save: @MainActor (String, Date, Date) -> Bool) {
        guard save(title, start, end) else {
            inviting = Invite(title: title, start: start, end: end)
            return
        }
        added.insert(start)
        #if canImport(UIKit)
        SharePresenter.present([Self.confirmation(start: start, end: end, link: link)])
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

    // MARK: - Logic

    static func headline(_ reply: PickReply) -> String {
        let who = reply.name ?? "They"
        let count = reply.picks.count
        return count == 1 ? "\(who) picked this time." : "\(who) picked \(count) times. Confirm the one you want."
    }

    static func zoneNote(_ reply: PickReply, here: TimeZone = .current) -> String {
        let local = here.localizedName(for: .shortGeneric, locale: .current) ?? here.identifier
        guard let theirs = TimeZone(identifier: reply.timeZoneID),
              theirs.secondsFromGMT() != here.secondsFromGMT() else {
            return "Times are in your time zone (\(local))."
        }
        let theirName = theirs.localizedName(for: .generic, locale: .current) ?? theirs.identifier
        return "Times are in your time zone (\(local)). They are in \(theirName)."
    }

    static func confirmation(start: Date, end: Date, link: URL? = nil, here: TimeZone = .current) -> String {
        let zone = here.abbreviation(for: start) ?? ""
        let text = "\(PickTimeView.dayName(start)), \(PickTimeView.dateLabel(start)) at \(TimeFormat.timeRange(from: start, to: end)) \(zone) it is. See you then."
            .replacingOccurrences(of: "  ", with: " ")
        return link.map { text + " Add it to your calendar: \($0.absoluteString)" } ?? text
    }
}

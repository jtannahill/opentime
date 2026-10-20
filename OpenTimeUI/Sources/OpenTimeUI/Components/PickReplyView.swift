import SwiftUI

/// What the sender sees after opening a reply to their pick-a-time link:
/// the times the other person chose, in the sender's time zone, each with a
/// way to confirm it and put it on the calendar.
public struct PickReplyView: View {
    public let reply: PickReply?

    public init(reply: PickReply?) {
        self.reply = reply
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
                HStack(spacing: 10) {
                    ShareLink(item: Self.confirmation(start: start, end: end)) {
                        actionLabel("Confirm this time", filled: true)
                    }
                    if let ics = PickTimeView.icsFile(title: reply.name.map { "Meeting with \($0)" } ?? "Meeting",
                                                      start: start, end: end) {
                        ShareLink(item: ics) {
                            actionLabel("Add to Calendar", filled: false)
                        }
                    }
                }
            }
        }
        .padding(.bottom, 14)
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

    static func confirmation(start: Date, end: Date, here: TimeZone = .current) -> String {
        let zone = here.abbreviation(for: start) ?? ""
        return "\(PickTimeView.dayName(start)), \(PickTimeView.dateLabel(start)) at \(TimeFormat.timeRange(from: start, to: end)) \(zone) it is. See you then."
            .replacingOccurrences(of: "  ", with: " ")
    }
}

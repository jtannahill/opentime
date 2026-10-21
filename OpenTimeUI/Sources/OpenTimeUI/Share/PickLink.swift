import Foundation

/// A pick-a-time link: the sender's free times travel inside the URL's
/// fragment, so the recipient's App Clip or browser reads them without any
/// server ever seeing them (a fragment is never sent in a request).
///
/// https://lulls.app/pick#<base64url JSON>
public struct PickLink: Equatable, Sendable {
    public static let host = "lulls.app"
    public static let path = "/pick"
    public static let maxSlots = 80

    public struct Slot: Equatable, Sendable, Hashable {
        public let start: Date
        public let minutes: Int
        public init(start: Date, minutes: Int) {
            self.start = start
            self.minutes = minutes
        }
        public var end: Date { start.addingTimeInterval(TimeInterval(minutes * 60)) }
    }

    /// Where the reply should go, if the sender chose to say: a phone
    /// number or an email address. The pick page then opens Messages or Mail
    /// already addressed, so the reply needs one tap to send.
    public enum ReplyTo: Equatable, Sendable, Hashable {
        case phone(String)
        case email(String)

        /// Reads what someone typed: digits with the usual punctuation, or an
        /// address with an @ in it. Anything else is nil.
        public init?(_ text: String?) {
            guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty,
                  trimmed.count <= 80 else { return nil }
            if trimmed.contains("@") {
                let parts = trimmed.split(separator: "@", omittingEmptySubsequences: false)
                guard parts.count == 2, !parts[0].isEmpty, parts[1].contains("."),
                      trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return nil }
                self = .email(trimmed)
                return
            }
            let digits = trimmed.filter { $0.isNumber }
            guard digits.count >= 5, digits.count <= 15,
                  trimmed.allSatisfy({ $0.isNumber || "+-() .".contains($0) }) else { return nil }
            self = .phone((trimmed.hasPrefix("+") ? "+" : "") + digits)
        }

        /// The number or address as it goes in the link.
        public var text: String {
            switch self {
            case .phone(let n): return n
            case .email(let e): return e
            }
        }

        /// The app that opens: shown on the button so they know what to expect.
        public var appName: String {
            switch self {
            case .phone: return "Messages"
            case .email: return "Mail"
            }
        }

        /// A URL that opens Messages or Mail addressed to the sender with the
        /// message and the reply link in the body, leaving only Send to tap.
        public func url(message: String, link: URL) -> URL? {
            var allowed = CharacterSet.alphanumerics
            allowed.insert(charactersIn: "-._~")
            let body = (message + "\n" + link.absoluteString).addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
            switch self {
            case .phone(let n):
                // "?&body=" is the form both iOS and Android accept.
                return URL(string: "sms:\(n)?&body=\(body)")
            case .email(let e):
                let subject = "Times that work for me".addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
                return URL(string: "mailto:\(e)?subject=\(subject)&body=\(body)")
            }
        }
    }

    /// Optional first name the sender chose to show.
    public let name: String?
    /// The sender's time zone, shown as a hint; times are absolute.
    public let timeZoneID: String
    /// How long the meeting is; every slot is at least this long.
    public let meetingMinutes: Int
    public let slots: [Slot]
    /// Optional phone number or email the reply should go to.
    public let replyTo: ReplyTo?

    public init(name: String?, timeZoneID: String, meetingMinutes: Int, slots: [Slot], replyTo: ReplyTo? = nil) {
        self.name = Self.clean(name)
        self.timeZoneID = timeZoneID
        self.meetingMinutes = meetingMinutes
        self.slots = Array(slots.sorted { $0.start < $1.start }.prefix(Self.maxSlots))
        self.replyTo = replyTo
    }

    /// The free stretches of a set of days, cut to whole meetings. A slot
    /// shorter than the meeting is left out.
    public static func from(days: [DayAvailability], meetingMinutes: Int, name: String?,
                            replyTo: ReplyTo? = nil, timeZone: TimeZone = .current) -> PickLink {
        let slots = days.flatMap(\.freeSlots).compactMap { free -> Slot? in
            let minutes = Int(free.end.timeIntervalSince(free.start) / 60)
            return minutes >= meetingMinutes ? Slot(start: free.start, minutes: minutes) : nil
        }
        return PickLink(name: name, timeZoneID: timeZone.identifier, meetingMinutes: meetingMinutes,
                        slots: slots, replyTo: replyTo)
    }

    // MARK: - Wire format

    private struct Wire: Codable {
        var v: Int
        var n: String?
        var z: String
        var d: Int
        /// [start in minutes since 1970, length in minutes] pairs.
        var s: [[Int]]
        /// Reply-to phone number or email, if given.
        var r: String?
    }

    public var url: URL {
        let wire = Wire(v: 1, n: name, z: timeZoneID, d: meetingMinutes,
                        s: slots.map { [Int($0.start.timeIntervalSince1970 / 60), $0.minutes] },
                        r: replyTo?.text)
        let data = (try? JSONEncoder().encode(wire)) ?? Data()
        var c = URLComponents()
        c.scheme = "https"
        c.host = Self.host
        c.path = Self.path
        c.fragment = Self.base64url(data)
        return c.url!
    }

    /// Reads a link, dropping anything malformed rather than failing on it.
    /// Nil for a URL that is not a pick link at all.
    public init?(url: URL) {
        guard url.host == Self.host || url.host == "www.\(Self.host)",
              url.path == Self.path || url.path == Self.path + "/",
              let fragment = url.fragment, let data = Self.data(base64url: fragment),
              let wire = try? JSONDecoder().decode(Wire.self, from: data), wire.v == 1,
              (5...480).contains(wire.d) else { return nil }
        let slots = wire.s.prefix(Self.maxSlots).compactMap { pair -> Slot? in
            guard pair.count == 2, pair[1] >= wire.d, pair[1] <= 24 * 60 else { return nil }
            return Slot(start: Date(timeIntervalSince1970: TimeInterval(pair[0] * 60)), minutes: pair[1])
        }
        self.init(name: wire.n, timeZoneID: TimeZone(identifier: wire.z)?.identifier ?? "UTC",
                  meetingMinutes: wire.d, slots: slots, replyTo: ReplyTo(wire.r))
    }

    /// Meeting start times the recipient can still choose, every
    /// `step` minutes inside each free stretch and not in the past.
    public func choices(now: Date = Date(), step: Int? = nil) -> [Date] {
        let stride = TimeInterval((step ?? min(meetingMinutes, 30)) * 60)
        let length = TimeInterval(meetingMinutes * 60)
        return slots.flatMap { slot -> [Date] in
            var out: [Date] = []
            var t = slot.start
            while t.addingTimeInterval(length) <= slot.end {
                if t >= now { out.append(t) }
                t = t.addingTimeInterval(stride)
            }
            return out
        }
    }

    static func clean(_ name: String?) -> String? {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty ?? true) ? nil : String(trimmed!.prefix(40))
    }

    // MARK: - base64url

    static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func data(base64url s: String) -> Data? {
        var b = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b += "=" }
        return Data(base64Encoded: b)
    }
}

/// The answer to a pick-a-time link: up to five meeting times the
/// recipient chose, sent back to whoever shared the link. Like the link
/// itself, the times travel in the fragment and never reach a server.
///
/// https://lulls.app/reply#<base64url JSON>
public struct PickReply: Equatable, Sendable {
    public static let path = "/reply"
    public static let maxPicks = 5

    /// Optional name of the person who picked.
    public let name: String?
    /// The name on the original link, so the reply can say who it is for.
    public let forName: String?
    /// The picker's time zone, shown as a hint; times are absolute.
    public let timeZoneID: String
    public let meetingMinutes: Int
    /// Meeting start times, earliest first, at most `maxPicks`.
    public let picks: [Date]

    public init(name: String?, forName: String?, timeZoneID: String, meetingMinutes: Int, picks: [Date]) {
        self.name = PickLink.clean(name)
        self.forName = PickLink.clean(forName)
        self.timeZoneID = timeZoneID
        self.meetingMinutes = meetingMinutes
        let minutes = Set(picks.map { Int(($0.timeIntervalSince1970 / 60).rounded()) })
        self.picks = Array(minutes.sorted().prefix(Self.maxPicks))
            .map { Date(timeIntervalSince1970: TimeInterval($0 * 60)) }
    }

    /// A reply to `link` with the chosen start times.
    public init(link: PickLink, picks: [Date], name: String?, timeZone: TimeZone = .current) {
        self.init(name: name, forName: link.name, timeZoneID: timeZone.identifier,
                  meetingMinutes: link.meetingMinutes, picks: picks)
    }

    private struct Wire: Codable {
        var v: Int
        var n: String?
        var f: String?
        var z: String
        var d: Int
        /// Start times in minutes since 1970.
        var p: [Int]
    }

    public var url: URL {
        let wire = Wire(v: 1, n: name, f: forName, z: timeZoneID, d: meetingMinutes,
                        p: picks.map { Int($0.timeIntervalSince1970 / 60) })
        let data = (try? JSONEncoder().encode(wire)) ?? Data()
        var c = URLComponents()
        c.scheme = "https"
        c.host = PickLink.host
        c.path = Self.path
        c.fragment = PickLink.base64url(data)
        return c.url!
    }

    /// Nil for a URL that is not a reply, or one with no times left in it.
    public init?(url: URL) {
        guard url.host == PickLink.host || url.host == "www.\(PickLink.host)",
              url.path == Self.path || url.path == Self.path + "/",
              let fragment = url.fragment, let data = PickLink.data(base64url: fragment),
              let wire = try? JSONDecoder().decode(Wire.self, from: data), wire.v == 1,
              (5...480).contains(wire.d), !wire.p.isEmpty else { return nil }
        self.init(name: wire.n, forName: wire.f,
                  timeZoneID: TimeZone(identifier: wire.z)?.identifier ?? "UTC",
                  meetingMinutes: wire.d,
                  picks: wire.p.prefix(Self.maxPicks).map { Date(timeIntervalSince1970: TimeInterval($0 * 60)) })
    }
}

/// One agreed meeting time, sent back once a time is confirmed. The other
/// person opens it to add the meeting to their calendar in one tap. Like the
/// link and the reply, the time travels in the fragment.
///
/// https://lulls.app/confirmed#<base64url JSON>
public struct ConfirmLink: Equatable, Sendable {
    public static let path = "/confirmed"

    public let start: Date
    public let meetingMinutes: Int
    /// Optional name of the person confirming.
    public let name: String?
    /// Optional name of the person it is for.
    public let forName: String?
    public let timeZoneID: String

    public init(start: Date, meetingMinutes: Int, name: String?, forName: String?, timeZone: TimeZone = .current) {
        self.start = Date(timeIntervalSince1970: TimeInterval(Int((start.timeIntervalSince1970 / 60).rounded()) * 60))
        self.meetingMinutes = meetingMinutes
        self.name = PickLink.clean(name)
        self.forName = PickLink.clean(forName)
        self.timeZoneID = timeZone.identifier
    }

    /// The confirmation for one of the times in a reply, from the person who shared the link.
    public init(reply: PickReply, start: Date, timeZone: TimeZone = .current) {
        self.init(start: start, meetingMinutes: reply.meetingMinutes, name: reply.forName, forName: reply.name, timeZone: timeZone)
    }

    private struct Wire: Codable {
        var v: Int
        var t: Int
        var d: Int
        var z: String
        var n: String?
        var f: String?
    }

    public var url: URL {
        let wire = Wire(v: 1, t: Int(start.timeIntervalSince1970 / 60), d: meetingMinutes, z: timeZoneID, n: name, f: forName)
        let data = (try? JSONEncoder().encode(wire)) ?? Data()
        var c = URLComponents()
        c.scheme = "https"
        c.host = PickLink.host
        c.path = Self.path
        c.fragment = PickLink.base64url(data)
        return c.url!
    }

    public init?(url: URL) {
        guard url.host == PickLink.host || url.host == "www.\(PickLink.host)",
              url.path == Self.path || url.path == Self.path + "/",
              let fragment = url.fragment, let data = PickLink.data(base64url: fragment),
              let wire = try? JSONDecoder().decode(Wire.self, from: data), wire.v == 1,
              (5...480).contains(wire.d) else { return nil }
        self.init(start: Date(timeIntervalSince1970: TimeInterval(wire.t * 60)), meetingMinutes: wire.d,
                  name: wire.n, forName: wire.f, timeZone: TimeZone(identifier: wire.z) ?? TimeZone(identifier: "UTC")!)
    }
}

/// A calendar file for one chosen time, for "Add to Calendar".
public enum ICSFile {
    public static func event(title: String, start: Date, end: Date, now: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let safe = title.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ",", with: "\\,").replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: "\n", with: " ")
        return [
            "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Open Time//Pick a time//EN",
            "BEGIN:VEVENT",
            "UID:\(UUID().uuidString)@lulls.app",
            "DTSTAMP:\(f.string(from: now))",
            "DTSTART:\(f.string(from: start))",
            "DTEND:\(f.string(from: end))",
            "SUMMARY:\(safe)",
            "END:VEVENT", "END:VCALENDAR",
        ].joined(separator: "\r\n") + "\r\n"
    }
}

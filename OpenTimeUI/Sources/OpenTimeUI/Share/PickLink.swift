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

    /// Optional first name the sender chose to show.
    public let name: String?
    /// The sender's time zone, shown as a hint; times are absolute.
    public let timeZoneID: String
    /// How long the meeting is; every slot is at least this long.
    public let meetingMinutes: Int
    public let slots: [Slot]

    public init(name: String?, timeZoneID: String, meetingMinutes: Int, slots: [Slot]) {
        self.name = Self.clean(name)
        self.timeZoneID = timeZoneID
        self.meetingMinutes = meetingMinutes
        self.slots = Array(slots.sorted { $0.start < $1.start }.prefix(Self.maxSlots))
    }

    /// The free stretches of a set of days, cut to whole meetings. A slot
    /// shorter than the meeting is left out.
    public static func from(days: [DayAvailability], meetingMinutes: Int, name: String?,
                            timeZone: TimeZone = .current) -> PickLink {
        let slots = days.flatMap(\.freeSlots).compactMap { free -> Slot? in
            let minutes = Int(free.end.timeIntervalSince(free.start) / 60)
            return minutes >= meetingMinutes ? Slot(start: free.start, minutes: minutes) : nil
        }
        return PickLink(name: name, timeZoneID: timeZone.identifier, meetingMinutes: meetingMinutes, slots: slots)
    }

    // MARK: - Wire format

    private struct Wire: Codable {
        var v: Int
        var n: String?
        var z: String
        var d: Int
        /// [start in minutes since 1970, length in minutes] pairs.
        var s: [[Int]]
    }

    public var url: URL {
        let wire = Wire(v: 1, n: name, z: timeZoneID, d: meetingMinutes,
                        s: slots.map { [Int($0.start.timeIntervalSince1970 / 60), $0.minutes] })
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
                  meetingMinutes: wire.d, slots: slots)
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

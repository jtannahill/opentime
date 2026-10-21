import Foundation
import Testing
@testable import OpenTimeUI

@Suite struct PickLinkTests {
    let base = Date(timeIntervalSince1970: 1_792_400_400) // a whole minute

    @Test func roundTripsThroughTheURL() {
        let link = PickLink(name: "  Jamie ", timeZoneID: "America/New_York", meetingMinutes: 30,
                            slots: [.init(start: base.addingTimeInterval(7200), minutes: 90),
                                    .init(start: base, minutes: 60)])
        let url = link.url
        #expect(url.host == "lulls.app")
        #expect(url.path == "/pick")
        #expect(url.query == nil, "times live in the fragment, never in a query a server would see")
        let back = PickLink(url: url)
        #expect(back == link)
        #expect(back?.name == "Jamie")
        #expect(back?.slots.first?.start == base, "slots come back sorted")
    }

    @Test func rejectsOtherURLsAndJunk() {
        #expect(PickLink(url: URL(string: "https://example.com/pick#abc")!) == nil)
        #expect(PickLink(url: URL(string: "https://lulls.app/pick#!!!")!) == nil)
        #expect(PickLink(url: URL(string: "https://lulls.app/privacy")!) == nil)
    }

    @Test func dropsSlotsShorterThanTheMeeting() {
        let wire = #"{"v":1,"z":"UTC","d":60,"s":[[29873340,30],[29873400,120],[1]]}"#
        let url = URL(string: "https://lulls.app/pick#" + PickLink.base64url(Data(wire.utf8)))!
        let link = PickLink(url: url)
        #expect(link?.slots.count == 1)
        #expect(link?.slots.first?.minutes == 120)
    }

    @Test func choicesStepThroughEachStretchAndSkipThePast() {
        let link = PickLink(name: nil, timeZoneID: "UTC", meetingMinutes: 30,
                            slots: [.init(start: base, minutes: 90)])
        #expect(link.choices(now: base.addingTimeInterval(-1)).count == 3) // :00 :30 :60
        #expect(link.choices(now: base.addingTimeInterval(1)).count == 2)
    }

    @Test func buildsFromDaysAndLeavesOutShortGaps() {
        let day = DayAvailability(date: base, freeSlots: [
            FreeSlot(start: base, end: base.addingTimeInterval(20 * 60)),
            FreeSlot(start: base.addingTimeInterval(3600), end: base.addingTimeInterval(3 * 3600)),
        ], busySlots: [])
        let link = PickLink.from(days: [day], meetingMinutes: 30, name: nil, timeZone: TimeZone(identifier: "UTC")!)
        #expect(link.slots == [.init(start: base.addingTimeInterval(3600), minutes: 120)])
    }

    @Test func icsHasTheEventInUTC() {
        let ics = ICSFile.event(title: "Coffee, with Jamie", start: base, end: base.addingTimeInterval(1800), now: base)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        #expect(ics.contains("DTSTART:\(f.string(from: base))\r\n"))
        #expect(ics.contains("DTEND:\(f.string(from: base.addingTimeInterval(1800)))\r\n"))
        #expect(ics.contains("SUMMARY:Coffee\\, with Jamie"))
        #expect(ics.hasPrefix("BEGIN:VCALENDAR\r\n"))
    }

    @Test func readsALinkMadeByTheMCPServer() {
        // Produced by mcp/pick.js createLink: 13:00-14:30 UTC on Oct 20 2026, 30 min, "Jamie".
        let link = PickLink(url: URL(string: "https://lulls.app/pick#eyJ2IjoxLCJ6IjoiRXVyb3BlL0xvbmRvbiIsImQiOjMwLCJzIjpbWzI5ODc1MDIwLDkwXV0sIm4iOiJKYW1pZSJ9")!)
        #expect(link?.name == "Jamie")
        #expect(link?.timeZoneID == "Europe/London")
        #expect(link?.meetingMinutes == 30)
        #expect(link?.slots.first?.start == ISO8601DateFormatter().date(from: "2026-10-20T13:00:00Z"))
        #expect(link?.slots.first?.minutes == 90)
    }

    @Test func replyRoundTripsAndKeepsAtMostFivePicks() {
        let link = PickLink(name: "Jamie", timeZoneID: "America/New_York", meetingMinutes: 30,
                            slots: [.init(start: base, minutes: 240)])
        let times = (0..<7).map { base.addingTimeInterval(TimeInterval($0) * 1800) }.reversed()
        let reply = PickReply(link: link, picks: Array(times) + [base], name: " Ana ",
                              timeZone: TimeZone(identifier: "Europe/London")!)
        #expect(reply.picks.count == PickReply.maxPicks)
        #expect(reply.picks.first == base, "earliest first, duplicates dropped")
        let url = reply.url
        #expect(url.path == "/reply")
        #expect(url.query == nil)
        let back = PickReply(url: url)
        #expect(back == reply)
        #expect(back?.name == "Ana")
        #expect(back?.forName == "Jamie")
        #expect(back?.timeZoneID == "Europe/London")
        #expect(back?.meetingMinutes == 30)
    }

    @Test func replyAndLinkDoNotReadEachOther() {
        let link = PickLink(name: nil, timeZoneID: "UTC", meetingMinutes: 30, slots: [.init(start: base, minutes: 60)])
        let reply = PickReply(link: link, picks: [base], name: nil)
        #expect(PickReply(url: link.url) == nil)
        #expect(PickLink(url: reply.url) == nil)
        let empty = #"{"v":1,"z":"UTC","d":30,"p":[]}"#
        #expect(PickReply(url: URL(string: "https://lulls.app/reply#" + PickLink.base64url(Data(empty.utf8)))!) == nil)
    }

    @Test func readsAReplyMadeByTheWebPage() {
        // The JSON lulls.app/pick builds for "Send my times": {v,n,f,z,d,p}.
        let wire = #"{"v":1,"n":"Ana","f":"Jamie","z":"Europe/London","d":30,"p":[29875020,29875080]}"#
        let reply = PickReply(url: URL(string: "https://lulls.app/reply#" + PickLink.base64url(Data(wire.utf8)))!)
        #expect(reply?.picks == [ISO8601DateFormatter().date(from: "2026-10-20T13:00:00Z")!,
                                 ISO8601DateFormatter().date(from: "2026-10-20T14:00:00Z")!])
        #expect(reply?.name == "Ana")
    }
}

@Test func confirmLinkRoundTrips() {
    let reply = PickReply(name: "Maya", forName: "Jamie", timeZoneID: "America/Chicago", meetingMinutes: 30,
                          picks: [Date(timeIntervalSince1970: 29885190 * 60)])
    let link = ConfirmLink(reply: reply, start: reply.picks[0], timeZone: TimeZone(identifier: "America/New_York")!)
    #expect(link.url.host == "lulls.app")
    #expect(link.url.path == "/confirmed")
    #expect(link.url.query == nil)
    let back = ConfirmLink(url: link.url)
    #expect(back == link)
    #expect(back?.name == "Jamie")
    #expect(back?.forName == "Maya")
    #expect(back?.meetingMinutes == 30)
}

@Test func confirmLinkReadsTheWebWireFormat() {
    // The JSON reply.html and the MCP server write: {v,t,d,z,n,f}.
    let wire = #"{"v":1,"t":29885190,"d":30,"z":"America/New_York","n":"Jamie","f":"Maya"}"#
    let url = URL(string: "https://lulls.app/confirmed#" + PickLink.base64url(Data(wire.utf8)))!
    let link = ConfirmLink(url: url)
    #expect(link?.start == Date(timeIntervalSince1970: 29885190 * 60))
    #expect(link?.timeZoneID == "America/New_York")
    #expect(ConfirmLink(url: URL(string: "https://lulls.app/confirmed")!) == nil)
}

@Suite struct ReplyToTests {
    let base = Date(timeIntervalSince1970: 1_792_400_400)

    @Test func phoneAndEmailAreRecognisedAndTidied() {
        #expect(PickLink.ReplyTo("(212) 555-0199") == .phone("2125550199"))
        #expect(PickLink.ReplyTo(" +44 20 7946 0958 ") == .phone("+442079460958"))
        #expect(PickLink.ReplyTo("Sam@Example.com ") == .email("Sam@Example.com"))
        #expect(PickLink.ReplyTo("sam at example") == nil)
        #expect(PickLink.ReplyTo("12") == nil, "too short to be a number")
        #expect(PickLink.ReplyTo("") == nil)
        #expect(PickLink.ReplyTo(nil) == nil)
    }

    @Test func rideInTheLinkAndComeBack() {
        let link = PickLink(name: "Jamie", timeZoneID: "UTC", meetingMinutes: 30,
                            slots: [.init(start: base, minutes: 60)], replyTo: .phone("+12125550199"))
        let back = PickLink(url: link.url)
        #expect(back?.replyTo == .phone("+12125550199"))
        let plain = PickLink(name: nil, timeZoneID: "UTC", meetingMinutes: 30, slots: [.init(start: base, minutes: 60)])
        #expect(PickLink(url: plain.url)?.replyTo == nil)
        #expect(!plain.url.fragment!.contains("\"r\""), "no field at all when there is no reply-to")
    }

    @Test func junkReplyToInAWireIsDropped() {
        let wire = #"{"v":1,"z":"UTC","d":30,"s":[[29873400,60]],"r":"not a number"}"#
        let url = URL(string: "https://lulls.app/pick#" + PickLink.base64url(Data(wire.utf8)))!
        #expect(PickLink(url: url)?.replyTo == nil)
    }

    @Test func opensMessagesOrMailWithTheReplyFilledIn() {
        let reply = URL(string: "https://lulls.app/reply#abc")!
        let sms = PickLink.ReplyTo.phone("+12125550199").url(message: "This time works for me:", link: reply)
        #expect(sms?.scheme == "sms")
        #expect(sms?.absoluteString == "sms:+12125550199?&body=This%20time%20works%20for%20me%3A%0Ahttps%3A%2F%2Flulls.app%2Freply%23abc")
        let mail = PickLink.ReplyTo.email("sam@example.com").url(message: "Hi", link: reply)
        #expect(mail?.absoluteString == "mailto:sam@example.com?subject=Times%20that%20work%20for%20me&body=Hi%0Ahttps%3A%2F%2Flulls.app%2Freply%23abc")
        #expect(PickLink.ReplyTo.phone("+12125550199").appName == "Messages")
        #expect(PickLink.ReplyTo.email("sam@example.com").appName == "Mail")
    }
}

# OpenTime

See when you are free at a glance, and send it as a link the other person picks a time from. Your calendar stays on your iPhone.

<a href="https://apps.apple.com/us/app/opentime/id6760204246"><img src="scripts/assets/app-store-badge.svg" alt="Download on the App Store" height="48"></a>

$0.99, once. No subscription, no account. iPhone, iPad and Apple Watch. [lulls.app](https://lulls.app)

<p>
  <img src="docs/img/02-link.webp" width="32%" alt="The Pick-a-Time Link sheet: an optional first name, a 30 minute meeting length and 57 free times">
  <img src=".github/readme/pick.gif" width="32%" alt="The other person taps three times, adds their name and sends them back">
  <img src=".github/readme/reply.jpg" width="32%" alt="Times Picked: Maya picked 3 times, each with Confirm this time and Add to Calendar">
</p>

**You choose** the days, the meeting length and, if you like, your first name. **They pick** up to five times in their own time zone, in an App Clip on iPhone or in any browser, with nothing to install, and send them back. **You confirm** one in OpenTime and it goes on your calendar.

No more typing a list of times into a message that goes stale the moment either calendar moves, and no booking page that asks them to make an account.

## Or ask your assistant

<a href="https://lulls.app/img/claude-mcp.mp4"><img src=".github/readme/claude-mcp.jpg" width="70%" alt="Claude reading Maya's reply: Maya picked three times, Tuesday Oct 27 10:30, Wednesday Oct 28 3:00 and Thursday Oct 29 9:30, all in New York time"></a>

[Watch the one-minute recording](https://lulls.app/img/claude-mcp.mp4): a real session in Claude, sped up. OpenTime goes in as a custom connector, Claude makes a link for Maya, Maya picks three times on the link page, and Claude reads her reply back.

If your assistant can see your calendar, like Claude with Google Calendar connected, it can find the gaps and send the link for you. **Make a link** from free time it already knows, ready to paste into a message or an email. **Read one back:** paste a link or a reply someone sent you and it lists the times in your time zone. **Answer one:** it finds the times that suit you both and makes the reply. **Confirm it:** it makes the link that puts the meeting on their calendar. The server stores nothing and never sees your calendar: the assistant hands it only the free times.

<img src="docs/img/logo-claude.png" width="18" height="18" alt=""> **Claude:** Settings, then Connectors, then add a custom connector with the URL `https://lulls.app/mcp`.

<img src="docs/img/logo-cursor.png" width="18" height="18" alt=""> **Cursor:** one click installs it.

<a href="cursor://anysphere.cursor-deeplink/mcp/install?name=OpenTime&config=eyJ1cmwiOiJodHRwczovL2x1bGxzLmFwcC9tY3AifQ%3D%3D"><img src="docs/img/add-to-cursor.svg" alt="Add OpenTime to Cursor" height="32"></a>

<img src="docs/img/logo-grokbot.png" width="18" height="18" alt=""> **Grok Bot:** ask it to use `https://lulls.app/mcp`; it offers to add it as a custom connector, then makes the link.

<p>
  <a href="https://lulls.app/img/cursor-mcp.mp4"><img src=".github/readme/cursor-mcp.jpg" width="48%" alt="Cursor's agent making Maya a pick-a-time link with OpenTime"></a>
  <a href="https://lulls.app/img/grok-mcp.mp4"><img src=".github/readme/grok-mcp.jpg" width="48%" alt="Grok Bot making Maya's confirmation link with OpenTime"></a>
</p>

Recordings of real sessions: [Cursor](https://lulls.app/img/cursor-mcp.mp4) and [Grok Bot](https://lulls.app/img/grok-mcp.mp4).

Any other assistant or agent that speaks MCP over HTTP can use the same URL. There is no sign-in and no key.

## Your week at a glance

<img src=".github/readme/glance.jpg" width="70%" alt="The week in OpenTime with free times as chips and meetings listed, the Home Screen widget, and OpenTime on Apple Watch">

Every free half hour between meetings, inside your working hours, as a row of times you can tap. Press and hold one to make an event there or copy it. The same answer sits on your Home Screen and on your wrist.

## Only the calendars that count

<img src=".github/readme/calendars.jpg" width="50%" alt="The Calendars sheet with Calendar and Birthdays on and US Holidays switched off">

Leave out holidays, the kids' sports or a partner's shared calendar. Declined invites and events marked Free never count against you.

## Ask in plain words

<img src=".github/readme/ask.jpg" width="70%" alt="The Ask field with suggestions: next Tuesday after 2pm, coffee next week, 30 min tomorrow morning">

"Next Tuesday after 2pm." "Coffee next week." "Any 2-hour block." Apple Intelligence works it out on the device, and the question never leaves your phone.

## Wherever you check the time

The Home Screen widget, a Live Activity and the Dynamic Island, Apple Watch, the iMessage app, the share sheet in any app, and Siri: "When am I free in OpenTime".

## Nothing leaves the phone

The app makes no network connections. There is no account, no analytics and no tracking. A pick-a-time link carries only the free times you chose, in the part of the URL a browser never sends to a server, and a reply carries only the times they picked.

## Build it yourself

Open `OpenTime.xcodeproj` in Xcode and run the `OpenTime` scheme (iOS 26.2 or later). The display font is licensed separately and not included, so the app uses the system font until you add your own copy. [DEVELOPMENT.md](DEVELOPMENT.md) covers the link format, the MCP server, the website and how the screenshots are made.

## License

The code is under the [MIT License](LICENSE). The Neue Haas Grotesk Display font is not included and not covered by it, and neither are the OpenTime name and app icon.

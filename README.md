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

## Your week at a glance

<img src=".github/readme/glance.jpg" width="70%" alt="The week in OpenTime with free times as chips and meetings listed, the Home Screen widget, and OpenTime on Apple Watch">

Every free half hour between meetings, inside your working hours, from only the calendars that count: leave out holidays or a partner's shared calendar. Declined invites and events marked Free never block you. Type a question in plain words, such as "tomorrow afternoon for 30 min", and Apple Intelligence works it out on the device.

The same answer is on the Home Screen widget, a Live Activity and the Dynamic Island, Apple Watch, the iMessage app, the share sheet, and Siri ("When am I free in OpenTime").

## Nothing leaves the phone

The app makes no network connections. There is no account, no analytics and no tracking. A pick-a-time link carries only the free times you chose, in the part of the URL a browser never sends to a server, and a reply carries only the times they picked.

## For AI assistants

`https://lulls.app/mcp` is a public, stateless MCP server. An assistant can turn free time it already knows into a pick-a-time link, or read a link or reply someone sent you. It stores nothing and never sees a calendar. In Claude: Settings > Connectors > Add custom connector.

## Development

Swift and SwiftUI with EventKit, WidgetKit, ActivityKit, App Intents, an App Clip (`OpenTimeClip`), Foundation Models and watchOS. The site, the browser pick and reply pages and the MCP server run on Cloudflare Pages. Requires iOS and iPadOS 26.2, watchOS 10, and calendar access.

### Fonts

The display face is Neue Haas Grotesk Display, a commercial typeface licensed separately, so the font files are not in the public repository. To build with it, add your own licensed `NHGDisplay-Regular.ttf`, `NHGDisplay-Medium.ttf` and `NHGDisplay-Bold.ttf` to `OpenTimeUI/Sources/OpenTimeUI/Resources/`. Without them the app builds and runs with the system font.

### Pick-a-time links and replies

A link (`https://lulls.app/pick#...`) carries free times in the URL fragment, encoded by `OpenTimeUI/Sources/OpenTimeUI/Share/PickLink.swift`. It opens the App Clip, the app when installed, or `docs/pick.html` in any browser.

A reply (`https://lulls.app/reply#...`, `PickReply` in the same file) carries only the chosen times, the meeting length, an optional name and the picker's time zone. It opens in the app (`PickReplyView`) or `docs/reply.html`. Universal links for `/pick*` and `/reply*` and the App Clip association are in `docs/.well-known/apple-app-site-association`.

The MCP server is a Pages Function (`functions/mcp.js`, logic in `mcp/`) with two tools, `create_pick_link` and `read_pick_link`. `mcp/pick.js` mirrors the Swift wire format; `node --test mcp/test/pick.test.js` and the Swift `PickLinkTests` check both directions.

### Simulator screenshots and recordings

Debug builds take launch arguments so screenshots and the clips above can be made without a real calendar or a real link tap:

- `-seedDemoCalendar` fills the default calendar with a believable week (seeded events are marked and replaced on every run)
- `-openURL <url>` routes a `lulls.app/pick#...` or `lulls.app/reply#...` link as if it had been opened
- `-pickSelect <n>` preselects `n` times on the pick screen
- `-pickLink <url>` opens a link in the App Clip

With no Simulator window, a UI test can drive the installed app through `XCUIApplication(bundleIdentifier:)` with these arguments while `xcrun simctl io <device> recordVideo` records the screen.

<details>
<summary>Deploying lulls.app</summary>

The site lives in `docs/` and is served at [lulls.app](https://lulls.app) by the Cloudflare Pages project `lulls` on account `aa7a67b77a9549dc7cb54bb8aac477d8`. GitHub Pages at [jtannahill.github.io/open-time](https://jtannahill.github.io/open-time) is a mirror only. Deploy from the repo root:

```sh
CLOUDFLARE_ACCOUNT_ID=aa7a67b77a9549dc7cb54bb8aac477d8 npx wrangler pages deploy docs --project-name=lulls --branch=main --commit-dirty=true
```

This also ships `functions/_middleware.js`, which 301-redirects `www.lulls.app` to the apex. The zone caches for up to 7 days, so purge the cache after a deploy if changes need to show immediately.

- `docs/og-image.png` (1200x630 share card) is generated by `scripts/make_og_image.py` (run from the repo root, e.g. `uv run --with pillow python scripts/make_og_image.py`).
- `docs/screenshot-availability.jpg` is an App Store screenshot shown in the hero.

Site design rules are in `docs/DESIGN.md`. **On every release**, keep the site facts (price, version, minimum OS) in sync with the App Store listing in `docs/index.html`, its JSON-LD block, `docs/llms.txt`, and `docs/llms-full.txt`.

</details>

### Public repository

OpenTime is developed in a private repository and published, without the font files, at [github.com/jtannahill/opentime](https://github.com/jtannahill/opentime). `scripts/sync-public.sh` copies a commit across and refuses to publish if a font file is present or gitleaks finds a secret; `scripts/pre-push` runs it on every push to `main` (install once per clone with `ln -sf ../../scripts/pre-push .git/hooks/pre-push`).

## License

The code is under the [MIT License](LICENSE). The Neue Haas Grotesk Display font is not included and not covered by it, and neither are the OpenTime name and app icon.

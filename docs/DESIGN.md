---
version: beta
name: OpenTime (lulls.app)
description: Dark-only marketing and legal site for the OpenTime iOS, iPadOS and watchOS app. The homepage is built around one idea, that your free time lives inside a link, and lets the visitor make one.
colors:
  bg: "#0a0b0d"
  field: "#121418"
  field-2: "#181b20"
  text: "#e8eaec"
  text-2: "#a6abb2"
  accent: "#4ade80"
  screen: "#ffffff"
---

## Idea

On this site, the pick-a-time link, with the free times living inside it, becomes the hero itself. The homepage opens with "Your free time, inside a link." beside a working link maker: a made-up week starting tomorrow whose times the visitor can tap out of the link, watching the link change, then open it as the recipient would. It uses the same wire format as the app (`OpenTimeUI/Share/PickLink.swift`).

## Colors

- `bg` is the page ground and the browser theme colour.
- `field` and `field-2` are tone steps for surfaces: the link maker, the "Send a link. They pick." band, and pressed or switched-off controls. Surfaces are separated by tone, never by a line or a shadow.
- `text` is for headings and all running text. `text-2` is only for secondary notes (hints, the version note, footer links).
- `accent` appears on the one primary action in each place (the bar's Get it button, Open this link, Copy on the MCP URL in the assistant section, Copy a reply on /pick) and on one field: the privacy band, where text sits in `bg`. Nowhere else.
- `screen` is the white behind app screenshots so their rounded phone corners read cleanly.

## Typography

System faces only (SF Pro Display for headings, SF Pro Text for body); no web fonts. Sizes are in rem so they follow the reader's text size. Display headline `clamp(2.9rem, 6.2vw, 5.25rem)`, section headings `clamp(2rem, 4.2vw, 3.5rem)`, both with -0.035em tracking and leading near 1. Body 1.125rem at 1.55 leading, measure capped near 62ch. Every heading fits in two lines at every width. No small uppercase labels, no monospace except the real MCP URL and the real Cursor and Grok config snippets, no numbering.

## Layout

One 1240px column with a fluid gutter. Sections are separated by large vertical space (88 to 176px), never by rules. From 1000px the hero splits into copy and the link maker; from 900px the week section sets the large app picture beside its text. Neighbouring sections use different compositions: split, band with a picture pair, split with an example conversation on a field (the assistant section, linked from the bar as Assistants), heading beside a two-column list, a full accent field with one statement, a question list. The footer closes with the name at full width.

## Imagery

Real app screens only: the week with busy events, the Calendars sheet, the link sheet, a looping clip of the pick, and a recorded Claude session for the assistant section (`/img/claude-mcp.mp4`, captions burned in like the pick clip). Both play only while visible, have a Pause button and stay still under Reduce Motion. Phone screenshots keep rounded corners; nothing else is rounded except pill buttons. The App Store badge is shown exactly as Apple supplies it, with no hover or press effect.

## Components

- Buttons are fully round pills, flat fill, 44px minimum. Press feedback is `scale(0.96-0.97)` on `:active`, dropped under Reduce Motion.
- Time chips: `text` fill when in the link, `field-2` with strikethrough when left out, `aria-pressed` carries the state.
- The looping clip plays only while visible, never under Reduce Motion (controls shown instead), and has a visible Pause button.

## Motion

Section parts rise 24px and fade in once as they enter, staggered 60 to 120ms, on a strong ease-out. Content is visible without script and fully static under Reduce Motion. Only transform and opacity animate.

## Pick-a-time page

`/pick` renders a link's free times from the URL fragment (nothing is fetched): times grouped by day as `surface` buttons, the chosen one in `accent`. Choosing raises a translucent bottom bar (solid under Reduce Transparency, no slide under Reduce Motion) that enters in 280ms and leaves in 180ms, with Copy a reply (primary) and Add to calendar (.ics). A bare `/pick` explains itself and offers an example. It is `noindex`, sends no referrer, and offers the App Clip through a Smart App Banner.

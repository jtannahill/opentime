// Pick-a-time links for the lulls.app MCP server.
//
// Mirrors OpenTimeUI/Sources/OpenTimeUI/Share/PickLink.swift exactly, so a
// link made here opens in the Open Time App Clip and app, and a link made in
// the app reads here. The free times live in the URL fragment; the server
// never stores or forwards them.

export const HOST = "lulls.app";
export const PATH = "/pick";
export const MAX_SLOTS = 80;
export const REPLY_PATH = "/reply";
export const MAX_PICKS = 5;

function base64url(bytes) {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function fromBase64url(text) {
  let b = text.replace(/-/g, "+").replace(/_/g, "/");
  while (b.length % 4) b += "=";
  const raw = atob(b);
  return Uint8Array.from(raw, (c) => c.charCodeAt(0));
}

function cleanName(name) {
  if (typeof name !== "string") return null;
  const t = name.trim();
  return t ? t.slice(0, 40) : null;
}

function validZone(zone) {
  if (typeof zone !== "string" || !zone) return null;
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: zone });
    return zone;
  } catch {
    return null;
  }
}

/// Builds a link from free stretches. Each stretch is { start, end } as ISO
/// 8601 strings with an offset or Z. Stretches shorter than the meeting are
/// left out, as the app does.
export function createLink({ freeTimes, meetingMinutes = 30, name = null, timeZone = "UTC" }) {
  const d = Math.round(Number(meetingMinutes));
  if (!(d >= 5 && d <= 480)) throw new Error("meeting_minutes must be between 5 and 480.");
  if (!Array.isArray(freeTimes) || freeTimes.length === 0) throw new Error("free_times needs at least one { start, end }.");
  const zone = validZone(timeZone) || "UTC";
  const slots = [];
  const skipped = [];
  for (const [i, ft] of freeTimes.entries()) {
    const start = Date.parse(ft?.start);
    const end = Date.parse(ft?.end);
    if (Number.isNaN(start) || Number.isNaN(end)) { skipped.push(`#${i + 1}: start and end must be ISO 8601 times`); continue; }
    if (!/(Z|[+-]\d\d:?\d\d)$/i.test(String(ft.start).trim())) { skipped.push(`#${i + 1}: give the time with an offset or Z so it is unambiguous`); continue; }
    // Whole minutes, as the wire format stores them.
    const startMin = Math.ceil(start / 60000);
    const minutes = Math.floor(end / 60000) - startMin;
    if (minutes < d) { skipped.push(`#${i + 1}: shorter than the ${d}-minute meeting`); continue; }
    slots.push([startMin, Math.min(minutes, 1440)]);
  }
  if (!slots.length) throw new Error("No free time is long enough for the meeting. " + skipped.join("; "));
  slots.sort((a, b) => a[0] - b[0]);
  const wire = { v: 1, z: zone, d, s: slots.slice(0, MAX_SLOTS) };
  const n = cleanName(name);
  if (n) wire.n = n;
  const json = new TextEncoder().encode(JSON.stringify(wire));
  return {
    url: `https://${HOST}${PATH}#${base64url(json)}`,
    slots: wire.s.length,
    dropped: Math.max(0, slots.length - MAX_SLOTS),
    skipped,
  };
}

/// Reads a link into its meeting length, sender, and the meeting start
/// times still ahead. Malformed entries are dropped rather than failing.
export function readLink(url, now = Date.now()) {
  let u;
  try { u = new URL(url); } catch { throw new Error("That is not a URL."); }
  if (u.hostname !== HOST && u.hostname !== `www.${HOST}`) throw new Error("Not a lulls.app pick-a-time link.");
  if (u.pathname !== PATH && u.pathname !== PATH + "/") throw new Error("Not a pick-a-time link (expected lulls.app/pick#...).");
  const fragment = u.hash.slice(1);
  if (!fragment) throw new Error("The link has no times in it; it may have been cut short.");
  let wire;
  try { wire = JSON.parse(new TextDecoder().decode(fromBase64url(fragment))); } catch { throw new Error("The link's times could not be read; it may have been cut short."); }
  if (wire?.v !== 1 || !(wire.d >= 5 && wire.d <= 480) || !Array.isArray(wire.s)) throw new Error("The link is not in a format this server understands.");
  const d = wire.d;
  const slots = wire.s.slice(0, MAX_SLOTS)
    .filter((p) => Array.isArray(p) && p.length === 2 && Number.isFinite(p[0]) && p[1] >= d && p[1] <= 1440)
    .map(([m, len]) => ({ start: m * 60000, minutes: len }));
  const step = Math.min(d, 30) * 60000;
  const choices = [];
  for (const s of slots) {
    for (let t = s.start; t + d * 60000 <= s.start + s.minutes * 60000; t += step) {
      if (t >= now) choices.push(t);
    }
  }
  choices.sort((a, b) => a - b);
  return {
    name: cleanName(wire.n),
    senderTimeZone: validZone(wire.z) || "UTC",
    meetingMinutes: d,
    freeTimes: slots.map((s) => ({ start: new Date(s.start).toISOString(), end: new Date(s.start + s.minutes * 60000).toISOString() })),
    choices: choices.map((t) => new Date(t).toISOString()),
  };
}

/// Reads a reply link: the up-to-five meeting times someone picked from a
/// pick-a-time link, earliest first. Mirrors PickReply in PickLink.swift.
export function readReply(url) {
  let u;
  try { u = new URL(url); } catch { throw new Error("That is not a URL."); }
  if (u.hostname !== HOST && u.hostname !== `www.${HOST}`) throw new Error("Not a lulls.app link.");
  if (u.pathname !== REPLY_PATH && u.pathname !== REPLY_PATH + "/") throw new Error("Not a reply (expected lulls.app/reply#...).");
  const fragment = u.hash.slice(1);
  if (!fragment) throw new Error("The reply has no times in it; it may have been cut short.");
  let wire;
  try { wire = JSON.parse(new TextDecoder().decode(fromBase64url(fragment))); } catch { throw new Error("The reply's times could not be read; it may have been cut short."); }
  if (wire?.v !== 1 || !(wire.d >= 5 && wire.d <= 480) || !Array.isArray(wire.p)) throw new Error("The reply is not in a format this server understands.");
  const picks = [...new Set(wire.p.filter(Number.isFinite))].sort((a, b) => a - b).slice(0, MAX_PICKS);
  if (!picks.length) throw new Error("The reply has no times in it; it may have been cut short.");
  return {
    name: cleanName(wire.n),
    forName: cleanName(wire.f),
    pickerTimeZone: validZone(wire.z) || "UTC",
    meetingMinutes: wire.d,
    picks: picks.map((m) => new Date(m * 60000).toISOString()),
  };
}

/// Groups meeting start times by day in a time zone, for a readable answer.
export function describeChoices(choices, meetingMinutes, timeZone) {
  const zone = validZone(timeZone) || "UTC";
  const day = new Intl.DateTimeFormat("en-US", { timeZone: zone, weekday: "long", month: "short", day: "numeric" });
  const time = new Intl.DateTimeFormat("en-US", { timeZone: zone, hour: "numeric", minute: "2-digit" });
  const groups = new Map();
  for (const iso of choices) {
    const t = Date.parse(iso);
    const key = day.format(t);
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(time.format(t));
  }
  return [...groups].map(([k, v]) => `${k}: ${v.join(", ")}`).join("\n");
}

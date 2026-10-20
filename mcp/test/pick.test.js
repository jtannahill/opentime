import { test } from "node:test";
import assert from "node:assert/strict";
import { createLink, readLink, readReply } from "../pick.js";
import { handleMessage } from "../server.js";

const NOW = Date.parse("2026-10-18T12:00:00Z");

test("a link round-trips and keeps times in the fragment", () => {
  const r = createLink({
    freeTimes: [
      { start: "2026-10-20T13:00:00-04:00", end: "2026-10-20T15:00:00-04:00" },
      { start: "2026-10-19T09:30:00-04:00", end: "2026-10-19T11:00:00-04:00" },
    ],
    meetingMinutes: 30, name: " Jamie ", timeZone: "America/New_York",
  });
  const u = new URL(r.url);
  assert.equal(u.host, "lulls.app");
  assert.equal(u.pathname, "/pick");
  assert.equal(u.search, "");
  const back = readLink(r.url, NOW);
  assert.equal(back.name, "Jamie");
  assert.equal(back.meetingMinutes, 30);
  assert.equal(back.senderTimeZone, "America/New_York");
  assert.equal(back.freeTimes[0].start, "2026-10-19T13:30:00.000Z", "sorted, Monday first");
  assert.equal(back.choices.length, 3 + 4); // 9:30,10:00,10:30 and 13:00..14:30
});

test("reads a link made by the iOS app's wire format", () => {
  // Same JSON the Swift PickLink encodes: {v,n,z,d,s:[[minutes, length]]}.
  const wire = { v: 1, n: "Jamie", z: "America/New_York", d: 30, s: [[29883450, 90]] };
  const frag = Buffer.from(JSON.stringify(wire)).toString("base64url");
  const r = readLink("https://lulls.app/pick#" + frag, NOW);
  assert.equal(r.freeTimes[0].start, new Date(29883450 * 60000).toISOString());
  assert.equal(r.choices.length, 3);
});

test("rejects other links and explains why", () => {
  assert.throws(() => readLink("https://example.com/pick#abc"), /Not a lulls.app/);
  assert.throws(() => readLink("https://lulls.app/pick"), /no times/);
  assert.throws(() => readLink("https://lulls.app/pick#%%%"), /could not be read/);
});

test("stretches shorter than the meeting, or without an offset, are left out", () => {
  const r = createLink({
    freeTimes: [
      { start: "2026-10-20T09:00:00Z", end: "2026-10-20T09:20:00Z" },
      { start: "2026-10-20T10:00:00", end: "2026-10-20T12:00:00" },
      { start: "2026-10-20T13:00:00Z", end: "2026-10-20T14:00:00Z" },
    ],
    meetingMinutes: 30,
  });
  assert.equal(r.slots, 1);
  assert.equal(r.skipped.length, 2);
  assert.throws(() => createLink({ freeTimes: [{ start: "2026-10-20T09:00:00Z", end: "2026-10-20T09:10:00Z" }] }), /No free time/);
});

test("MCP: initialize, list, call, and notifications", () => {
  const init = handleMessage({ jsonrpc: "2.0", id: 1, method: "initialize", params: { protocolVersion: "2025-06-18" } });
  assert.equal(init.result.protocolVersion, "2025-06-18");
  assert.ok(init.result.capabilities.tools);
  assert.equal(handleMessage({ jsonrpc: "2.0", method: "notifications/initialized" }), null);
  const list = handleMessage({ jsonrpc: "2.0", id: 2, method: "tools/list" });
  assert.deepEqual(list.result.tools.map((t) => t.name), ["create_pick_link", "read_pick_link", "create_confirmation_link"]);
  const made = handleMessage({ jsonrpc: "2.0", id: 3, method: "tools/call", params: { name: "create_pick_link", arguments: {
    free_times: [{ start: "2026-10-21T14:00:00Z", end: "2026-10-21T15:00:00Z" }], meeting_minutes: 30 } } }, NOW);
  assert.equal(made.result.isError, false);
  const url = made.result.structuredContent.url;
  const read = handleMessage({ jsonrpc: "2.0", id: 4, method: "tools/call", params: { name: "read_pick_link", arguments: { url, time_zone: "Europe/London" } } }, NOW);
  assert.match(read.result.content[0].text, /Wednesday, Oct 21: 3:00 PM, 3:30 PM/);
  const bad = handleMessage({ jsonrpc: "2.0", id: 5, method: "tools/call", params: { name: "read_pick_link", arguments: { url: "nope" } } });
  assert.equal(bad.result.isError, true);
  assert.equal(handleMessage({ jsonrpc: "2.0", id: 6, method: "nope" }).error.code, -32601);
});

test("reads a reply made by the web page and the app", () => {
  // Same JSON PickReply encodes: {v,n,f,z,d,p:[minutes]}.
  const wire = { v: 1, n: "Ana", f: "Jamie", z: "Europe/London", d: 30, p: [29875080, 29875020, 29875020, 1, 2, 3, 4] };
  const url = "https://lulls.app/reply#" + Buffer.from(JSON.stringify(wire)).toString("base64url");
  const r = readReply(url);
  assert.equal(r.name, "Ana");
  assert.equal(r.forName, "Jamie");
  assert.equal(r.picks.length, 5, "at most five, duplicates dropped");
  assert.equal(r.picks[4], "2026-10-20T13:00:00.000Z", "earliest five kept, sorted");
  const out = handleMessage({ jsonrpc: "2.0", id: 9, method: "tools/call", params: { name: "read_pick_link", arguments: { url, time_zone: "UTC" } } });
  assert.equal(out.result.isError, false);
  assert.equal(out.result.structuredContent.kind, "reply");
  assert.match(out.result.content[0].text, /Ana picked 5 30-minute times for Jamie/);
  assert.throws(() => readReply("https://lulls.app/reply"), /no times/);
  assert.throws(() => readReply("https://lulls.app/pick#abc"), /Not a reply/);
});

test("a confirmation link round-trips and reads through the tool", async () => {
  const { createConfirmation, readConfirmation } = await import("../pick.js");
  const { callTool } = await import("../server.js");
  const c = createConfirmation({ start: "2026-10-27T10:30:00-04:00", meetingMinutes: 30, name: "Jamie", forName: "Maya", timeZone: "America/New_York" });
  const u = new URL(c.url);
  assert.equal(u.pathname, "/confirmed");
  assert.equal(u.search, "");
  const back = readConfirmation(c.url);
  assert.equal(back.start, "2026-10-27T14:30:00.000Z");
  assert.equal(back.name, "Jamie");
  assert.equal(back.forName, "Maya");
  const made = callTool("create_confirmation_link", { start: "2026-10-27T10:30:00-04:00", time_zone: "America/New_York" });
  assert.equal(made.isError, false);
  assert.match(made.content[0].text, /lulls\.app\/confirmed#/);
  const read = callTool("read_pick_link", { url: c.url });
  assert.equal(read.structuredContent.kind, "confirmation");
  assert.throws(() => createConfirmation({ start: "2026-10-27T10:30:00" }), /offset/);
});

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
  assert.deepEqual(list.result.tools.map((t) => t.name), ["create_pick_link", "read_pick_link", "create_confirmation_link", "find_common_times", "create_reply_link"]);
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

test("a full exchange through the tools: link, overlap, reply, read, confirm", async () => {
  const { callTool } = await import("../server.js");
  const link = callTool("create_pick_link", {
    free_times: [
      { start: "2026-10-27T10:00:00-04:00", end: "2026-10-27T12:00:00-04:00" },
      { start: "2026-10-28T14:00:00-04:00", end: "2026-10-28T16:30:00-04:00" },
    ],
    meeting_minutes: 30, name: "Jamie", time_zone: "America/New_York",
  }, NOW).structuredContent.url;
  // Maya (Central) is free 9:00-10:00 her time on the 27th and 2:00-3:00 on the 28th.
  const common = callTool("find_common_times", {
    url: link,
    my_free_times: [
      { start: "2026-10-27T09:00:00-05:00", end: "2026-10-27T10:00:00-05:00" },
      { start: "2026-10-28T14:00:00-05:00", end: "2026-10-28T15:00:00-05:00" },
    ],
    time_zone: "America/Chicago",
  }, NOW);
  assert.equal(common.isError, false);
  // 27th: 10:00, 10:30 ET fit inside 9-10 CT (= 10-11 ET); 28th: 15:00, 15:30 ET fit inside 2-3 CT (= 3-4 ET).
  assert.deepEqual(common.structuredContent.common, [
    "2026-10-27T14:00:00.000Z", "2026-10-27T14:30:00.000Z", "2026-10-28T19:00:00.000Z", "2026-10-28T19:30:00.000Z",
  ]);
  const reply = callTool("create_reply_link", {
    url: link, picks: ["2026-10-27T09:30:00-05:00", "2026-10-28T14:00:00-05:00"], name: "Maya", time_zone: "America/Chicago",
  }, NOW);
  assert.equal(reply.isError, false);
  const read = callTool("read_pick_link", { url: reply.structuredContent.url }, NOW);
  assert.equal(read.structuredContent.name, "Maya");
  assert.equal(read.structuredContent.for_name, "Jamie");
  assert.deepEqual(read.structuredContent.picks, ["2026-10-27T14:30:00.000Z", "2026-10-28T19:00:00.000Z"]);
  const bad = callTool("create_reply_link", { url: link, picks: ["2026-10-27T13:00:00-04:00"] }, NOW);
  assert.equal(bad.isError, true);
  assert.match(bad.content[0].text, /not one of the link's times/);
  const fromStretches = callTool("find_common_times", {
    their_free_times: [{ start: "2026-10-27T10:00:00-04:00", end: "2026-10-27T11:00:00-04:00" }],
    meeting_minutes: 60,
    my_free_times: [{ start: "2026-10-27T09:00:00-05:00", end: "2026-10-27T11:00:00-05:00" }],
  }, NOW);
  assert.deepEqual(fromStretches.structuredContent.common, ["2026-10-27T14:00:00.000Z"]);
});

test("a reply-to number or address rides in the link and reads back", () => {
  const free = [{ start: "2026-10-20T13:00:00-04:00", end: "2026-10-20T15:00:00-04:00" }];
  const phone = createLink({ freeTimes: free, replyTo: "(212) 555-0199" });
  assert.equal(readLink(phone.url, NOW).replyTo, "2125550199", "tidied to digits, as the app does");
  const mail = createLink({ freeTimes: free, replyTo: " Sam@example.com " });
  assert.equal(readLink(mail.url, NOW).replyTo, "Sam@example.com");
  const none = createLink({ freeTimes: free });
  assert.equal(readLink(none.url, NOW).replyTo, null);
  assert.ok(!Buffer.from(new URL(none.url).hash.slice(1), "base64url").toString().includes('"r"'), "no field when there is none");
  assert.throws(() => createLink({ freeTimes: free, replyTo: "sam at example" }), /reply_to/);
  // Junk in a hand-made link is dropped, not fatal.
  const wire = { v: 1, z: "UTC", d: 30, s: [[29883450, 90]], r: "nope" };
  assert.equal(readLink("https://lulls.app/pick#" + Buffer.from(JSON.stringify(wire)).toString("base64url"), NOW).replyTo, null);
  // The tool takes it as reply_to and says what it does.
  const r = handleMessage({ jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: "create_pick_link", arguments: { free_times: free, reply_to: "+1 212 555 0199" } } }, NOW);
  assert.match(r.result.content[0].text, /Messages/);
  assert.equal(readLink(r.result.structuredContent.url, NOW).replyTo, "+12125550199");
});

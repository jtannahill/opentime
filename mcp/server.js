// A stateless MCP server (Streamable HTTP, JSON responses) for pick-a-time
// links. No sessions, no storage, no calendar access: every answer is
// computed from the request alone.

import { createLink, readLink, readReply, createConfirmation, readConfirmation, createReply, findCommonTimes, describeChoices, REPLY_PATH, CONFIRM_PATH } from "./pick.js";

export const PROTOCOL_VERSIONS = ["2025-06-18", "2025-03-26", "2024-11-05"];

const SERVER_INFO = { name: "open-time-pick", title: "Open Time pick-a-time links", version: "1.4.0" };

const INSTRUCTIONS =
  "Open Time pick-a-time links let someone choose up to five meeting times from a set of free times and send them back as a lulls.app/reply link. " +
  "Use create_pick_link with free times you already know (from the user's calendar tools or what they told you) " +
  "to get a lulls.app link they can send; the recipient picks a time in their own time zone on iPhone (no install) or in any browser. " +
  "Use read_pick_link when someone shares a lulls.app/pick link, to list its times or check them against a calendar, " +
  "or a lulls.app/reply link, to see which times they picked. " +
  "After reading a reply, ask the user which time they want if there is more than one. Then, if you have calendar tools, offer to create the event and invite the other person; " +
  "either way, offer create_confirmation_link so the user can send them a link that adds the meeting to their calendar in one tap. " +
  "When someone sends the user a lulls.app/pick link, use find_common_times with the user's free time (from their calendar tools or what they told you) " +
  "to see which of its times suit both sides, let the user choose, then use create_reply_link to answer with up to five of them. " +
  "The times travel inside the link; this server stores nothing and cannot see anyone's calendar.";

export const TOOLS = [
  {
    name: "create_pick_link",
    title: "Create a pick-a-time link",
    description:
      "Turn free time into a lulls.app link that someone opens to pick a meeting time. Give free stretches as ISO 8601 times with an offset or Z. " +
      "Each stretch must be at least the meeting length; the recipient can start a meeting at any half hour (or meeting length, if shorter) inside it.",
    inputSchema: {
      type: "object",
      properties: {
        free_times: {
          type: "array",
          minItems: 1,
          maxItems: 80,
          description: "Free stretches, e.g. [{\"start\":\"2026-10-20T09:00:00-04:00\",\"end\":\"2026-10-20T11:30:00-04:00\"}].",
          items: {
            type: "object",
            properties: {
              start: { type: "string", description: "ISO 8601 start with offset or Z." },
              end: { type: "string", description: "ISO 8601 end with offset or Z." },
            },
            required: ["start", "end"],
          },
        },
        meeting_minutes: { type: "integer", minimum: 5, maximum: 480, default: 30, description: "How long the meeting is." },
        name: { type: "string", maxLength: 40, description: "Optional first name shown as \"<name> shared these free times.\"" },
        time_zone: { type: "string", description: "IANA time zone of the person sharing, e.g. America/New_York. Shown to the recipient as a hint." },
        reply_to: { type: "string", maxLength: 80, description: "Optional phone number or email of the person sharing. The recipient's Send button then opens Messages or Mail already addressed to it. It is visible to anyone who has the link, so include it only if the user asks." },
      },
      required: ["free_times"],
    },
    annotations: { readOnlyHint: true, openWorldHint: false, idempotentHint: true },
  },
  {
    name: "read_pick_link",
    title: "Read a pick-a-time link",
    description:
      "List the meeting times offered in a lulls.app/pick link, the up to five times someone picked in a lulls.app/reply link, or the agreed time in a lulls.app/confirmed link, " +
      "as ISO times and grouped by day in a chosen time zone. Offered times already past are left out.",
    inputSchema: {
      type: "object",
      properties: {
        url: { type: "string", description: "The full link, including everything after #." },
        time_zone: { type: "string", description: "IANA time zone to show times in. Defaults to the sender's." },
      },
      required: ["url"],
    },
    annotations: { readOnlyHint: true, openWorldHint: false, idempotentHint: true },
  },
  {
    name: "create_confirmation_link",
    title: "Create a confirmation link",
    description:
      "Once a time is agreed, make a lulls.app/confirmed link for the other person. It shows the meeting in their own time zone " +
      "with buttons to add it to Apple Calendar, Google Calendar or Outlook. Use it after reading a reply, with the time the user chose.",
    inputSchema: {
      type: "object",
      properties: {
        start: { type: "string", description: "Meeting start, ISO 8601 with an offset or Z." },
        meeting_minutes: { type: "integer", minimum: 5, maximum: 480, default: 30, description: "How long the meeting is." },
        name: { type: "string", maxLength: 40, description: "Optional first name of the person confirming (the user)." },
        for_name: { type: "string", maxLength: 40, description: "Optional first name of the person it is for." },
        time_zone: { type: "string", description: "IANA time zone of the person confirming, shown as a hint." },
      },
      required: ["start"],
    },
    annotations: { readOnlyHint: true, openWorldHint: false, idempotentHint: true },
  },
  {
    name: "find_common_times",
    title: "Find times that suit both sides",
    description:
      "List the meeting times that fit both people: the times offered in a lulls.app/pick link (or the other person's free stretches) " +
      "that lie wholly inside the user's own free stretches. Give the user's free time as ISO 8601 stretches with an offset or Z.",
    inputSchema: {
      type: "object",
      properties: {
        url: { type: "string", description: "A lulls.app/pick link someone sent, including everything after #. Use this or their_free_times." },
        their_free_times: { type: "array", description: "The other person's free stretches, if there is no link: [{\"start\",\"end\"}] in ISO 8601.", items: { type: "object", properties: { start: { type: "string" }, end: { type: "string" } }, required: ["start", "end"] } },
        meeting_minutes: { type: "integer", minimum: 5, maximum: 480, description: "Meeting length when using their_free_times. A link carries its own." },
        my_free_times: { type: "array", minItems: 1, description: "The user's free stretches: [{\"start\",\"end\"}] in ISO 8601 with an offset or Z.", items: { type: "object", properties: { start: { type: "string" }, end: { type: "string" } }, required: ["start", "end"] } },
        time_zone: { type: "string", description: "IANA time zone to show the times in." },
      },
      required: ["my_free_times"],
    },
    annotations: { readOnlyHint: true, openWorldHint: false, idempotentHint: true },
  },
  {
    name: "create_reply_link",
    title: "Answer a pick-a-time link",
    description:
      "Answer a lulls.app/pick link someone sent the user: choose up to five of its meeting times and get the lulls.app/reply link to send back, " +
      "exactly as the link page would make it. Each pick must be one of the link's times (see read_pick_link or find_common_times).",
    inputSchema: {
      type: "object",
      properties: {
        url: { type: "string", description: "The lulls.app/pick link, including everything after #." },
        picks: { type: "array", minItems: 1, maxItems: 5, items: { type: "string" }, description: "Up to five meeting start times from the link, ISO 8601 with an offset or Z." },
        name: { type: "string", maxLength: 40, description: "Optional first name of the user, shown to the sender." },
        time_zone: { type: "string", description: "IANA time zone of the user, shown to the sender as a hint." },
      },
      required: ["url", "picks"],
    },
    annotations: { readOnlyHint: true, openWorldHint: false, idempotentHint: true },
  },
];

function isConfirmation(url) {
  try { return new URL(url).pathname.startsWith(CONFIRM_PATH); } catch { return false; }
}

function isReply(url) {
  try { return new URL(url).pathname.startsWith(REPLY_PATH); } catch { return false; }
}

function text(t, structured, isError = false) {
  const out = { content: [{ type: "text", text: t }], isError };
  if (structured) out.structuredContent = structured;
  return out;
}

export function callTool(name, args = {}, now = Date.now()) {
  try {
    if (name === "create_pick_link") {
      const r = createLink({
        freeTimes: args.free_times,
        meetingMinutes: args.meeting_minutes ?? 30,
        name: args.name ?? null,
        timeZone: args.time_zone ?? "UTC",
        replyTo: args.reply_to ?? null,
      });
      const notes = [];
      if (r.replyTo) notes.push(`Their Send button opens ${r.replyTo.includes("@") ? "Mail" : "Messages"} addressed to ${r.replyTo}.`);
      if (r.skipped.length) notes.push("Left out: " + r.skipped.join("; ") + ".");
      if (r.dropped) notes.push(`Only the first 80 stretches fit; ${r.dropped} left out.`);
      return text(
        `Pick-a-time link (${r.slots} free stretch${r.slots === 1 ? "" : "es"}):\n${r.url}\n\n` +
          "Send it as is; everything after # is needed. The recipient picks up to five times in their own time zone and can send them back as a lulls.app/reply link." +
          (notes.length ? "\n\n" + notes.join(" ") : ""),
        { url: r.url, free_stretches: r.slots, skipped: r.skipped, reply_to: r.replyTo },
      );
    }
    if (name === "find_common_times") {
      const r = findCommonTimes({
        url: args.url ?? null,
        theirFreeTimes: args.their_free_times ?? null,
        meetingMinutes: args.meeting_minutes ?? null,
        myFreeTimes: args.my_free_times,
      }, now);
      const zone = args.time_zone || "UTC";
      const body = r.common.length
        ? describeChoices(r.common, r.meetingMinutes, zone)
        : "None of the times on offer fit the free time given. Ask for a fresh link or other days.";
      return text(
        `${r.common.length} of ${r.offered} ${r.meetingMinutes}-minute time${r.offered === 1 ? "" : "s"} suit both sides (shown in ${zone}):\n${body}`,
        { meeting_minutes: r.meetingMinutes, offered: r.offered, common: r.common, name: r.name },
      );
    }
    if (name === "create_reply_link") {
      const r = createReply({ url: args.url, picks: args.picks, name: args.name ?? null, timeZone: args.time_zone ?? "UTC" }, now);
      return text(
        `Reply link with ${r.picks.length} time${r.picks.length === 1 ? "" : "s"}${r.forName ? ` for ${r.forName}` : ""}:\n${r.url}\n\n` +
          "Send it back as is; everything after # is needed. It opens in OpenTime or any browser, with a button to confirm each time.",
        { url: r.url, picks: r.picks, meeting_minutes: r.meetingMinutes },
      );
    }
    if (name === "create_confirmation_link") {
      const r = createConfirmation({
        start: args.start,
        meetingMinutes: args.meeting_minutes ?? 30,
        name: args.name ?? null,
        forName: args.for_name ?? null,
        timeZone: args.time_zone ?? "UTC",
      });
      return text(
        `Confirmation link for ${describeChoices([r.start], r.meetingMinutes, args.time_zone || "UTC")} (${r.meetingMinutes} minutes):\n${r.url}\n\n` +
          "Send it to the other person; it opens with buttons to add the meeting to Apple Calendar, Google Calendar or Outlook, in their own time zone.",
        { url: r.url, start: r.start, meeting_minutes: r.meetingMinutes },
      );
    }
    if (name === "read_pick_link") {
      if (typeof args.url !== "string") throw new Error("url is required.");
      if (isConfirmation(args.url)) {
        const r = readConfirmation(args.url);
        const zone = args.time_zone || r.timeZone;
        return text(
          `Confirmed${r.name ? ` by ${r.name}` : ""}${r.forName ? ` with ${r.forName}` : ""}: ${r.meetingMinutes} minutes on ` +
            describeChoices([r.start], r.meetingMinutes, zone) + ` (${zone}).`,
          { kind: "confirmation", name: r.name, for_name: r.forName, meeting_minutes: r.meetingMinutes, time_zone: r.timeZone, start: r.start },
        );
      }
      if (isReply(args.url)) {
        const r = readReply(args.url);
        const zone = args.time_zone || r.pickerTimeZone;
        const who = r.name || "They";
        return text(
          `${who} picked ${r.picks.length} ${r.meetingMinutes}-minute time${r.picks.length === 1 ? "" : "s"}` +
            `${r.forName ? ` for ${r.forName}` : ""} (shown in ${zone}; picker in ${r.pickerTimeZone}):\n` +
            describeChoices(r.picks, r.meetingMinutes, zone),
          { kind: "reply", name: r.name, for_name: r.forName, meeting_minutes: r.meetingMinutes, picker_time_zone: r.pickerTimeZone, picks: r.picks },
        );
      }
      const r = readLink(args.url, now);
      const zone = args.time_zone || r.senderTimeZone;
      const who = r.name ? `${r.name} shared` : "Shared";
      const body = r.choices.length
        ? describeChoices(r.choices, r.meetingMinutes, zone)
        : "None of the times are still ahead; ask for a fresh link.";
      return text(
        `${who} ${r.meetingMinutes}-minute meeting times (shown in ${zone}; sender in ${r.senderTimeZone}):\n${body}`,
        { name: r.name, reply_to: r.replyTo, meeting_minutes: r.meetingMinutes, sender_time_zone: r.senderTimeZone, choices: r.choices, free_times: r.freeTimes },
      );
    }
    return text(`Unknown tool: ${name}`, null, true);
  } catch (e) {
    return text(String(e.message || e), null, true);
  }
}

/// Handles one JSON-RPC message. Returns a response object, or null for a
/// notification (which gets 202 Accepted and no body).
export function handleMessage(msg, now = Date.now()) {
  const id = msg?.id;
  const isNotification = id === undefined || id === null;
  const ok = (result) => ({ jsonrpc: "2.0", id, result });
  const fail = (code, message) => ({ jsonrpc: "2.0", id: id ?? null, error: { code, message } });
  if (!msg || msg.jsonrpc !== "2.0" || typeof msg.method !== "string") return fail(-32600, "Invalid request");
  switch (msg.method) {
    case "initialize": {
      const asked = msg.params?.protocolVersion;
      return ok({
        protocolVersion: PROTOCOL_VERSIONS.includes(asked) ? asked : PROTOCOL_VERSIONS[0],
        capabilities: { tools: { listChanged: false } },
        serverInfo: SERVER_INFO,
        instructions: INSTRUCTIONS,
      });
    }
    case "ping":
      return ok({});
    case "tools/list":
      return ok({ tools: TOOLS });
    case "tools/call":
      return ok(callTool(msg.params?.name, msg.params?.arguments ?? {}, now));
    default:
      if (isNotification) return null;
      return fail(-32601, `Method not found: ${msg.method}`);
  }
}

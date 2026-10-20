// lulls.app/mcp: a public, stateless MCP server for pick-a-time links.
// Streamable HTTP with plain JSON responses; no sessions and no storage.
import { handleMessage } from "../mcp/server.js";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Accept, Mcp-Protocol-Version, Mcp-Session-Id",
};

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store", ...CORS },
  });
}

export async function onRequestPost({ request }) {
  let payload;
  try {
    payload = await request.json();
  } catch {
    return json({ jsonrpc: "2.0", id: null, error: { code: -32700, message: "Parse error" } }, 400);
  }
  const now = Date.now();
  if (Array.isArray(payload)) {
    const out = payload.map((m) => handleMessage(m, now)).filter(Boolean);
    return out.length ? json(out) : new Response(null, { status: 202, headers: CORS });
  }
  const out = handleMessage(payload, now);
  return out ? json(out) : new Response(null, { status: 202, headers: CORS });
}

// No server-initiated stream: this server only answers requests.
export function onRequestGet() {
  return json({
    name: "Open Time pick-a-time links",
    mcp: "POST JSON-RPC to this URL (Streamable HTTP). Tools: create_pick_link, read_pick_link.",
    about: "https://lulls.app/",
  }, 405);
}

export function onRequestOptions() {
  return new Response(null, { status: 204, headers: CORS });
}

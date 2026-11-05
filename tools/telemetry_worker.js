// Pressure telemetry endpoint: a Cloudflare Worker (free tier) that stores run records in KV.
//
// What it does
//   POST /          body: one run or session record as JSON (under 256 KB). Stored in KV under
//                   its run_id (a partial upload is later overwritten by the finished run).
//                   Answers 204. CORS is open so the web build on GitHub Pages can post.
//   GET  /dump      with header "X-Dump-Key: <DUMP_KEY>": every record as JSON lines
//                   (application/x-ndjson). At most 900 records per call; when more remain the
//                   response carries "X-Next-Cursor", pass it back as /dump?cursor=<value>.
//
// Deploy (once)
//   npm install -g wrangler
//   wrangler login
//   mkdir pressure-telemetry && cd pressure-telemetry && copy this file in as telemetry_worker.js
//   wrangler kv namespace create RUNS          (prints an id)
//   create wrangler.toml next to it:
//       name = "pressure-telemetry"
//       main = "telemetry_worker.js"
//       compatibility_date = "2024-11-01"
//       [[kv_namespaces]]
//       binding = "RUNS"
//       id = "<the id printed above>"
//   wrangler secret put DUMP_KEY               (type a long random string; keep it private)
//   wrangler deploy                            (prints https://pressure-telemetry.<you>.workers.dev)
//   In scripts/telemetry.gd set ENDPOINT to that URL (ENDPOINT_SIMPLE stays false), bump VERSION,
//   export the web build.
//
// Fetch the data
//   curl -s -H "X-Dump-Key: <DUMP_KEY>" https://pressure-telemetry.<you>.workers.dev/dump > dump.jsonl
//   python tools/analyze_telemetry.py dump.jsonl
//
// Free tier limits worth knowing: 1,000 KV writes a day (each run writes once per floor plus
// once at the end, so roughly 150 runs a day), 1,000 list operations a day, 100,000 reads.

const MAX_BYTES = 256 * 1024;
const PAGE = 900;
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, X-Build, X-Dump-Key",
  "Access-Control-Max-Age": "86400",
};

function reply(status, body = null, headers = {}) {
  return new Response(body, { status, headers: { ...CORS, ...headers } });
}

async function store(request, env) {
  const declared = Number(request.headers.get("Content-Length") || "0");
  if (declared > MAX_BYTES) return reply(413, "too large");
  const text = await request.text();
  if (new TextEncoder().encode(text).length > MAX_BYTES) return reply(413, "too large");
  let record;
  try {
    record = JSON.parse(text);
  } catch (e) {
    return reply(400, "not json");
  }
  if (record === null || typeof record !== "object" || Array.isArray(record)) return reply(400, "not an object");
  const id = String(record.run_id || "");
  if (!/^[A-Za-z0-9-]{4,40}$/.test(id) || !Array.isArray(record.events)) return reply(400, "bad record");
  record.received = new Date().toISOString();
  record.build_header = request.headers.get("X-Build") || "";
  await env.RUNS.put(id, JSON.stringify(record));
  return reply(204);
}

async function dump(request, env, url) {
  const key = request.headers.get("X-Dump-Key") || "";
  if (!env.DUMP_KEY || key !== env.DUMP_KEY) return reply(403, "forbidden");
  const listed = await env.RUNS.list({ limit: PAGE, cursor: url.searchParams.get("cursor") || undefined });
  const values = await Promise.all(listed.keys.map((k) => env.RUNS.get(k.name)));
  const lines = values.filter((v) => v !== null).join("\n");
  const headers = { "Content-Type": "application/x-ndjson" };
  if (!listed.list_complete && listed.cursor) headers["X-Next-Cursor"] = listed.cursor;
  return reply(200, lines + (lines ? "\n" : ""), headers);
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === "OPTIONS") return reply(204);
    if (request.method === "POST") return store(request, env);
    if (request.method === "GET" && url.pathname === "/dump") return dump(request, env, url);
    return reply(404, "not found");
  },
};

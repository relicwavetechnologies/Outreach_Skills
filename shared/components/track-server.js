/*
 * html-skills / track-server.js
 *
 * Vercel serverless function template for receiving events from
 * shared/components/track.js. Writes each event as an append-only JSONL
 * line into Vercel KV. Local sync (shared/lib/track.sh) reads from KV
 * and appends into ~/.cache/html-skills/memory/outcomes/feedback.jsonl.
 *
 * Deploy:
 *   1. Place this file at  api/track.js  in a small Vercel project
 *      (the html-skills installer can scaffold this for you on first run).
 *   2. In the Vercel dashboard, enable KV on the project.
 *      Vercel will inject KV_REST_API_URL + KV_REST_API_TOKEN as env vars.
 *   3. Set a shared key:
 *        vercel env add HTML_SKILLS_TRACK_KEY production
 *      (Any short random string. Mostly replay-protection; the bar is "not
 *      a public-facing free-write endpoint", not crypto.)
 *   4. `vercel --prod` — gives you the endpoint URL the client uses.
 *
 * Privacy properties:
 *   - No cookies are set.
 *   - The only identifier stored is a per-tab `session` string from
 *     sessionStorage (cleared when the tab closes).
 *   - IPs are NOT logged here (Vercel may keep its own access logs).
 *   - The user OWNS this endpoint and the KV namespace. No third party.
 */

// This file targets the Vercel Node runtime + @vercel/kv. The runtime
// resolves the import at deploy time; no node_modules needed locally.
import { kv } from '@vercel/kv';

export const config = { runtime: 'nodejs' };

export default async function handler(req, res) {
  // Tight CORS so beacons from any deploy of this user's pages can post.
  res.setHeader('Access-Control-Allow-Origin',  '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST')    return res.status(405).json({ error: 'POST only' });

  // Parse body. Some runtimes pre-parse; some don't. Handle both.
  let body = req.body;
  if (typeof body === 'string') {
    try { body = JSON.parse(body); } catch { return res.status(400).json({ error: 'invalid json' }); }
  }
  if (!body || typeof body !== 'object') return res.status(400).json({ error: 'invalid body' });

  // Optional shared-key check.
  const expected = process.env.HTML_SKILLS_TRACK_KEY;
  if (expected && body.key !== expected) {
    // Silently 204 rather than 401 so probers don't learn the key exists.
    return res.status(204).end();
  }

  // Event-name allowlist. Reject anything else so we don't accumulate junk.
  const ALLOWED_EVENTS = new Set([
    'page_view',
    'scroll_25', 'scroll_50', 'scroll_75', 'scroll_100',
    'dwell_30s', 'dwell_60s', 'dwell_180s',
    'cta_click'
  ]);
  const event = String(body.event || '').slice(0, 40);
  if (!ALLOWED_EVENTS.has(event)) {
    return res.status(400).json({ error: 'unknown event' });
  }

  // run_id format: a generated run ID won't be longer than ~60 chars.
  // Reject anything wildly off so KV keys don't grow unbounded.
  const runId = String(body.run_id || '').slice(0, 80);
  if (!runId || !/^[A-Za-z0-9._:-]+$/.test(runId)) {
    return res.status(400).json({ error: 'invalid run_id' });
  }

  // Replay window: drop events whose client-supplied `at` timestamp is more
  // than 7 days old or more than 1 hour in the future. Clock skew tolerance.
  let clientAt;
  try { clientAt = body.at ? new Date(body.at).getTime() : Date.now(); }
  catch { clientAt = Date.now(); }
  const now = Date.now();
  if (isNaN(clientAt)
      || clientAt < now - 7 * 24 * 3600 * 1000
      || clientAt > now + 3600 * 1000) {
    return res.status(400).json({ error: 'timestamp out of window' });
  }

  // Build the record. Defensive length caps on every string field.
  // Strip query strings from page/referrer — they sometimes contain emails
  // or tokens passed via tracking pixels elsewhere.
  const stripQuery = (s) => {
    if (!s) return s;
    const q = s.indexOf('?');
    return q >= 0 ? s.slice(0, q) : s;
  };
  const record = {
    event,
    run_id:   runId,
    session:  String(body.session || '').slice(0, 24),
    page:     stripQuery(String(body.page || '')).slice(0, 200),
    referrer: body.referrer ? stripQuery(String(body.referrer)).slice(0, 200) : null,
    label:    body.label    ? String(body.label).slice(0, 120)                : undefined,
    at:       new Date(clientAt).toISOString(),
    received: new Date(now).toISOString()
  };
  for (const k of Object.keys(record)) if (record[k] === undefined) delete record[k];

  // Per-session rate cap: max 60 events / minute. Best-effort — uses Vercel
  // KV incr with a 60s TTL. If the increment exceeds the cap, silently drop
  // (still 204 so the client doesn't retry storms).
  const RATE_LIMIT_PER_MINUTE = 60;
  if (record.session) {
    try {
      const minuteBucket = Math.floor(now / 60000);
      const rateKey = `hs:rate:${record.session}:${minuteBucket}`;
      const count = await kv.incr(rateKey);
      if (count === 1) await kv.expire(rateKey, 90);
      if (count > RATE_LIMIT_PER_MINUTE) {
        return res.status(204).end();
      }
    } catch { /* rate-limiting is best-effort; never block writes on failure */ }
  }

  // Append to a per-run list AND a global recent-events list.
  // Use lpush so newest are first; trim to a reasonable size.
  try {
    await Promise.all([
      kv.lpush(`hs:run:${runId}`, JSON.stringify(record)),
      kv.lpush('hs:recent',       JSON.stringify(record)),
      kv.ltrim('hs:recent', 0, 9999)   // global cap: last ~10k events
    ]);
    // Per-run cap (keep last 1k events per page to avoid runaway lists).
    await kv.ltrim(`hs:run:${runId}`, 0, 999);
  } catch (e) {
    return res.status(500).json({ error: 'kv-write-failed' });
  }

  return res.status(204).end();
}

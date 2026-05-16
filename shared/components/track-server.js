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

  // Required fields.
  const event  = String(body.event  || '').slice(0, 40);
  const runId  = String(body.run_id || '').slice(0, 200);
  if (!event || !runId) return res.status(400).json({ error: 'missing event or run_id' });

  // Build the record. Server adds server-side timestamp + a tiny rate identifier.
  const record = {
    event,
    run_id:   runId,
    session:  String(body.session || '').slice(0, 24),
    page:     String(body.page    || '').slice(0, 400),
    referrer: body.referrer ? String(body.referrer).slice(0, 400) : null,
    label:    body.label   ? String(body.label).slice(0, 120)     : undefined,
    at:       body.at      ? String(body.at).slice(0, 40)         : new Date().toISOString(),
    received: new Date().toISOString()
  };
  for (const k of Object.keys(record)) if (record[k] === undefined) delete record[k];

  // Append to a per-run list AND a global recent-events list.
  // Use lpush so newest are first; trim to a reasonable size.
  try {
    await Promise.all([
      kv.lpush(`hs:run:${runId}`, JSON.stringify(record)),
      kv.lpush('hs:recent',       JSON.stringify(record)),
      kv.ltrim('hs:recent', 0, 9999) // keep last ~10k events globally
    ]);
  } catch (e) {
    return res.status(500).json({ error: 'kv-write-failed' });
  }

  return res.status(204).end();
}

/*
 * html-skills / track.js
 * Privacy-respecting visit tracker for HTML-skills deployed pages.
 *
 * Skills inject this as a <script> at the end of <body>, replacing the
 * placeholder tokens with real values. No cookies. No fingerprinting.
 * No third-party calls — events POST to a user-owned endpoint (typically
 * the Vercel KV serverless function shipped at shared/components/track-server.js).
 *
 * Required tokens to replace before serving:
 *   __TRACK_ENDPOINT__   — absolute URL to POST events to (e.g. https://your-app.vercel.app/api/track)
 *   __TRACK_RUN_ID__     — the run_id this page belongs to (from memory::log_run)
 *   __TRACK_SHARED_KEY__ — short shared key set on the serverless function (replay protection only;
 *                         NOT cryptographically secure — pages are public)
 *
 * If __TRACK_ENDPOINT__ is left unreplaced (literal token still in the file),
 * the script silently no-ops.
 *
 * Events emitted (one POST each, JSON body):
 *   page_view      — fired once, on DOMContentLoaded
 *   scroll_25/50/75/100 — fired at the first time each milestone is reached
 *   dwell_30s/60s/180s  — fired at dwell time milestones (only if page is visible)
 *   cta_click           — fired when any element with [data-track-cta] is clicked
 *
 * Session ID is a random 10-char base36 string generated per page-load and stored
 * in sessionStorage. Cleared when the tab closes. No persistent identifier.
 *
 * Size: ~2 KB minified. No external dependencies.
 */
(function () {
  'use strict';

  var ENDPOINT = '__TRACK_ENDPOINT__';
  var RUN_ID   = '__TRACK_RUN_ID__';
  var KEY      = '__TRACK_SHARED_KEY__';

  // No-op if not configured (placeholder still present, or empty)
  if (!ENDPOINT || ENDPOINT.indexOf('__TRACK_') === 0) return;
  if (!RUN_ID   || RUN_ID.indexOf('__TRACK_')   === 0) return;

  // Respect Do Not Track.
  if (navigator.doNotTrack === '1' || window.doNotTrack === '1' || navigator.msDoNotTrack === '1') return;

  // Per-page session id — anonymous, ephemeral, NOT persistent.
  var sid;
  try {
    sid = sessionStorage.getItem('__hs_sid');
    if (!sid) {
      sid = Math.random().toString(36).slice(2, 12);
      sessionStorage.setItem('__hs_sid', sid);
    }
  } catch (e) {
    sid = Math.random().toString(36).slice(2, 12);
  }

  // Deduplicate events within this session.
  var sent = Object.create(null);

  function send(event, extras) {
    if (sent[event]) return;
    sent[event] = 1;

    var body = {
      event: event,
      run_id: RUN_ID,
      session: sid,
      at: new Date().toISOString(),
      page: location.pathname + location.search,
      referrer: document.referrer || null,
      key: KEY || null
    };
    if (extras) for (var k in extras) body[k] = extras[k];

    var payload = JSON.stringify(body);
    // sendBeacon is fire-and-forget — survives page unload, the right primitive here.
    if (navigator.sendBeacon) {
      var blob = new Blob([payload], { type: 'application/json' });
      navigator.sendBeacon(ENDPOINT, blob);
    } else {
      try {
        var xhr = new XMLHttpRequest();
        xhr.open('POST', ENDPOINT, true);
        xhr.setRequestHeader('Content-Type', 'application/json');
        xhr.send(payload);
      } catch (e) { /* swallow */ }
    }
  }

  // ── page_view ─────────────────────────────────────────────────────────
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function () { send('page_view'); });
  } else {
    send('page_view');
  }

  // ── scroll milestones ────────────────────────────────────────────────
  var lastScrollFired = 0;
  function onScroll() {
    var doc = document.documentElement;
    var pct = Math.round(((window.scrollY + window.innerHeight) / doc.scrollHeight) * 100);
    if (pct >= 100 && lastScrollFired < 100) { lastScrollFired = 100; send('scroll_100'); }
    else if (pct >= 75 && lastScrollFired < 75)  { lastScrollFired = 75;  send('scroll_75'); }
    else if (pct >= 50 && lastScrollFired < 50)  { lastScrollFired = 50;  send('scroll_50'); }
    else if (pct >= 25 && lastScrollFired < 25)  { lastScrollFired = 25;  send('scroll_25'); }
  }
  window.addEventListener('scroll', onScroll, { passive: true });

  // ── dwell milestones (only count while tab is visible) ───────────────
  var dwell = 0;
  var lastTick = Date.now();
  var dwellFired = {};
  function tick() {
    var now = Date.now();
    if (!document.hidden) dwell += (now - lastTick);
    lastTick = now;
    var sec = Math.floor(dwell / 1000);
    if (sec >= 30  && !dwellFired[30])  { dwellFired[30]  = 1; send('dwell_30s');  }
    if (sec >= 60  && !dwellFired[60])  { dwellFired[60]  = 1; send('dwell_60s');  }
    if (sec >= 180 && !dwellFired[180]) { dwellFired[180] = 1; send('dwell_180s'); }
  }
  var dwellTimer = setInterval(tick, 1000);
  document.addEventListener('visibilitychange', function () { lastTick = Date.now(); });

  // ── CTA click ────────────────────────────────────────────────────────
  document.addEventListener('click', function (e) {
    var t = e.target;
    while (t && t !== document.body) {
      if (t.matches && t.matches('[data-track-cta], a[data-cta], button[data-cta]')) {
        var label = t.getAttribute('data-track-cta') || t.getAttribute('data-cta') || (t.textContent || '').trim().slice(0, 60);
        send('cta_click', { label: label });
        return;
      }
      t = t.parentNode;
    }
  });

  // Stop the dwell timer when leaving — saves cycles.
  window.addEventListener('beforeunload', function () {
    clearInterval(dwellTimer);
  });
})();

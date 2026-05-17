#!/usr/bin/env python3
"""
voice_consolidate.py — called by shared/lib/voice.sh::consolidate.

Reads ~/.cache/html-skills/memory/runs/*.json, distills the user's writing
voice from the optional text fields (dm_text, hero_text, trojan_text,
draft_text, shipped_text), prints the resulting voice.json JSON on stdout.

Usage:  voice_consolidate.py <cache-root> <half-life-days>

Time-decay weighting: recent runs count more. weight = exp(-ln 2 * age / hl)
"""
import json, os, sys, glob, datetime as dt, re, math
from collections import Counter

if len(sys.argv) != 3:
    sys.stderr.write("usage: voice_consolidate.py <cache-root> <half-life-days>\n")
    sys.exit(2)

root = sys.argv[1]
half_life = int(sys.argv[2])
runs_dir = os.path.join(root, "memory", "runs")
now = dt.datetime.now(dt.timezone.utc)

# ── Load all runs.
runs = []
for path in glob.glob(os.path.join(runs_dir, "*.json")):
    try:
        with open(path, encoding="utf-8") as f:
            r = json.load(f)
    except Exception:
        continue
    if isinstance(r, dict):
        runs.append(r)

def age_days(r):
    started = r.get("started_at") or r.get("finished_at")
    if not started:
        return None
    try:
        d = dt.datetime.fromisoformat(started.replace("Z", "+00:00"))
        return max(0, (now - d).days)
    except Exception:
        return None

def weight(r):
    # Runs without timestamps weight 0.5 (neutral but discounted).
    days = age_days(r)
    if days is None:
        return 0.5
    return math.exp(-math.log(2) * days / half_life)

# ── Collect text samples paired with their weights.
dms, heros, trojans = [], [], []
drafts, shipped = [], []

FIELD_BUCKETS = [
    ("dm_text", dms),
    ("hero_text", heros),
    ("trojan_text", trojans),
    ("draft_text", drafts),
    ("shipped_text", shipped),
]

for r in runs:
    w = weight(r)
    for field, bucket in FIELD_BUCKETS:
        v = r.get(field)
        if isinstance(v, str) and v.strip():
            bucket.append((v.strip(), w))

# ── Helpers — sentence + word extraction.
SENTENCE_SPLIT = re.compile(r"(?<=[.!?])\s+(?=[A-Z0-9])")
WORD_REGEX     = re.compile(r"[A-Za-z][A-Za-z’'-]*")

def sentence_word_counts(text):
    chunks = SENTENCE_SPLIT.split(text)
    counts = []
    for c in chunks:
        words = WORD_REGEX.findall(c)
        if words:
            counts.append(len(words))
    return counts

def words_of(text):
    return len(WORD_REGEX.findall(text))

def weighted_mean(pairs):
    s = sum(v * w for v, w in pairs)
    t = sum(w for _, w in pairs)
    return (s / t) if t > 0 else None

def weighted_median(pairs):
    if not pairs:
        return None
    pairs = sorted(pairs)
    total = sum(w for _, w in pairs)
    half = total / 2
    acc = 0
    for v, w in pairs:
        acc += w
        if acc >= half:
            return v
    return pairs[-1][0]

# ── Sentence-length stats from DMs.
sent_pairs = []
for text, w in dms:
    for c in sentence_word_counts(text):
        sent_pairs.append((c, w))

avg_sent = weighted_mean(sent_pairs)
med_sent = weighted_median(sent_pairs)
avg_hero_words   = weighted_mean([(words_of(t), w) for t, w in heros])
avg_trojan_words = weighted_mean([(words_of(t), w) for t, w in trojans])
avg_dm_words     = weighted_mean([(words_of(t), w) for t, w in dms])

# ── Punctuation signatures per DM (averages).
def count_emdash(t):  return t.count("—") + t.count("--")
def count_ellipsis(t): return t.count("…") + len(re.findall(r"\.\.\.", t))
def count_q(t):       return t.count("?")
def has_lowercase_start(t):
    t = t.strip()
    return 1 if (t and t[0].islower()) else 0

em_per_dm  = weighted_mean([(count_emdash(t),   w) for t, w in dms])
ell_per_dm = weighted_mean([(count_ellipsis(t), w) for t, w in dms])
q_per_dm   = weighted_mean([(count_q(t),        w) for t, w in dms])
low_pct    = weighted_mean([(has_lowercase_start(t), w) for t, w in dms])

# ── Openers — first 4 words of each DM, lowercased.
OPENER_WORD = re.compile(r"[A-Za-z][A-Za-z’'-]*")
def opener_of(t):
    words = OPENER_WORD.findall(t.lower())
    return " ".join(words[:4]) if words else ""

opener_weights = Counter()
total_dm_weight = 0
for t, w in dms:
    o = opener_of(t)
    if o:
        opener_weights[o] += w
        total_dm_weight += w

preferred_openers = []
if total_dm_weight > 0:
    for op, w_sum in opener_weights.most_common():
        if w_sum / total_dm_weight >= 0.20:
            preferred_openers.append(op)
    preferred_openers = preferred_openers[:5]

# ── Anti-openers carried through from explicit voice_corrections.
rejected_openers = []
for r in runs:
    for k in (r.get("voice_corrections") or []):
        if isinstance(k, dict) and k.get("kind") == "rejected_opener":
            txt = k.get("text")
            if txt and txt not in rejected_openers:
                rejected_openers.append(txt)

# ── Vocabulary — words appearing > 2x baseline share.
STOPWORDS = set("""
a an and are as at be but by for from has have he her his how i in is it its
me my of on or our she so that the their them they this to us was we were
what when which who will with you your im ill ive youre youd its thats
""".split())

VOCAB_TOKEN = re.compile(r"[a-z][a-z’'-]+")
vocab_w = Counter()
total_word_weight = 0
for t, w in dms:
    for tok in VOCAB_TOKEN.findall(t.lower()):
        if tok in STOPWORDS or len(tok) <= 2:
            continue
        vocab_w[tok] += w
        total_word_weight += w

words_use = []
if total_word_weight > 0 and vocab_w:
    baseline = 1.0 / max(20, len(vocab_w))
    for word, w_sum in vocab_w.most_common(40):
        share = w_sum / total_word_weight
        if share >= 2 * baseline:
            words_use.append(word)
    words_use = words_use[:10]

words_avoid = []
for r in runs:
    for k in (r.get("voice_corrections") or []):
        if isinstance(k, dict) and k.get("kind") == "avoid_word":
            txt = k.get("text")
            if txt and txt not in words_avoid:
                words_avoid.append(txt)

# ── Punctuation signature human string.
punct_bits = []
if em_per_dm  is not None and em_per_dm  > 0.7:  punct_bits.append("em-dashes")
if ell_per_dm is not None and ell_per_dm > 0.3:  punct_bits.append("ellipses")
if q_per_dm   is not None and q_per_dm   > 0.5:  punct_bits.append("questions")
if low_pct    is not None and low_pct    > 0.4:  punct_bits.append("lowercase sentence-starts")
punct_signature = ", ".join(punct_bits) if punct_bits else None

def r2(x):
    return None if x is None else round(x, 2)

result = {
    "version": 1,
    "last_consolidated": now.strftime("%Y-%m-%dT%H:%M:%SZ"),
    "runs_analyzed": len(runs),
    "dm_samples": len(dms),
    "hero_samples": len(heros),
    "trojan_samples": len(trojans),
    "half_life_days": half_life,
    "tone_signals": {
        "avg_sentence_words_dm":    r2(avg_sent),
        "median_sentence_words_dm": med_sent,
        "avg_dm_words":             r2(avg_dm_words),
        "avg_hero_words":           r2(avg_hero_words),
        "avg_trojan_words":         r2(avg_trojan_words),
        "em_dashes_per_dm":         r2(em_per_dm),
        "ellipses_per_dm":          r2(ell_per_dm),
        "questions_per_dm":         r2(q_per_dm),
        "lowercase_start_fraction": r2(low_pct),
    },
    "openers": {
        "preferred": preferred_openers,
        "rejected":  rejected_openers,
    },
    "vocabulary": {
        "use":   words_use,
        "avoid": words_avoid,
    },
    "punctuation_signature": punct_signature,
}

print(json.dumps(result, indent=2, ensure_ascii=False))

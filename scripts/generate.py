#!/usr/bin/env python3
"""
Nightly question generator for the Daily Review app.
Runs via launchd at 00:10. Implements SM-2 spaced repetition:
  - Reads ~/.dailyreview/cards.json as the persistent card library
  - Selects cards due for TARGET_DATE (nextReviewDate <= TARGET_DATE)
  - Calls claude -p only to generate new cards for unfilled slots
  - Writes ~/.dailyreview/session.json for tomorrow

Args: [date] [--fresh]
  date:    target dateString YYYY-MM-DD (default: tomorrow)
  --fresh: generate a full new set regardless of library (used by in-app refresh button)
"""

import datetime
import glob
import json
import os
import shutil
import subprocess
import sys
import uuid

# ── Paths and config ──────────────────────────────────────────────────────────

HOME         = os.path.expanduser("~")
DR_DIR       = os.path.join(HOME, ".dailyreview")
SESSION_FILE = os.path.join(DR_DIR, "session.json")
LIBRARY_FILE = os.path.join(DR_DIR, "cards.json")
TOPICS_FILE  = os.path.join(DR_DIR, "topics.json")
LOG_FILE     = os.path.join(DR_DIR, "generate.log")

# Ensure the working directory exists before any file access
os.makedirs(DR_DIR, exist_ok=True)

# Load personal config from .env (KEY=VALUE lines; comments and blanks ignored)
env_path = os.path.join(DR_DIR, ".env")
if os.path.exists(env_path):
    with open(env_path) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, _, val = line.partition("=")
                # Strip surrounding quotes that users sometimes add
                val = val.strip().strip("\"'")
                os.environ.setdefault(key.strip(), val)

WIKI_DIR = os.environ.get("WIKI_PATH", os.path.join(HOME, "Documents", "wiki", "topics"))

# Resolve claude binary: env var → known install path → PATH
def _find_claude():
    if "CLAUDE_BIN" in os.environ and os.access(os.environ["CLAUDE_BIN"], os.X_OK):
        return os.environ["CLAUDE_BIN"]
    candidate = os.path.join(HOME, ".local", "bin", "claude")
    if os.access(candidate, os.X_OK):
        return candidate
    found = shutil.which("claude")
    return found or "claude"

CLAUDE_BIN = _find_claude()

# ── CLI args ──────────────────────────────────────────────────────────────────

args = sys.argv[1:]
FRESH = "--fresh" in args
date_args = [a for a in args if a != "--fresh"]
if date_args:
    TARGET_DATE = date_args[0]
else:
    TARGET_DATE = (datetime.date.today() + datetime.timedelta(days=1)).strftime("%Y-%m-%d")

# ── Helpers ───────────────────────────────────────────────────────────────────

def log(msg):
    try:
        with open(LOG_FILE, "a") as f:
            f.write(str(msg) + "\n")
    except Exception:
        pass  # If we can't log, carry on — losing a log line is better than crashing

def load_json(path, default):
    try:
        with open(path) as f:
            return json.load(f)
    except FileNotFoundError:
        return default
    except Exception as e:
        log(f"WARNING: could not parse {path}: {e} — using empty default")
        return default

def save_json(path, data):
    try:
        with open(path, "w") as f:
            json.dump(data, f, indent=2)
    except Exception as e:
        log(f"ERROR: could not write {path}: {e}")

def read_wiki():
    content = ""
    for path in sorted(glob.glob(os.path.join(WIKI_DIR, "*.md"))):
        name = os.path.basename(path).replace(".md", "")
        try:
            with open(path) as f:
                content += f"\n\n=== {name} ===\n{f.read()}"
        except Exception:
            pass
    if not content:
        log(f"WARNING: no wiki .md files found in {WIKI_DIR} — new questions will lack wiki context")
    return content

def active_topics():
    topics = load_json(TOPICS_FILE, [])
    return [t["text"] for t in topics if isinstance(t, dict) and not t.get("isPaused", False)]

def make_new_card(text, answer, card_type, topic, target_date):
    return {
        "id":              str(uuid.uuid4()),
        "text":            text,
        "answer":          answer,
        "type":            card_type,
        "topic":           topic,
        "isRevealed":      False,
        "isAddedToWiki":   False,
        "srsRating":       None,
        "eli5Answer":      None,
        "eli5IsPreferred": False,
        "interval":        0,
        "easeFactor":      2.5,
        "nextReviewDate":  target_date,
    }

def session_card(card):
    """Return a copy of a library card reset for a fresh review session."""
    c = dict(card)
    c["srsRating"]  = None
    c["isRevealed"] = False
    return c

# ── Claude call ───────────────────────────────────────────────────────────────

def call_claude(wiki_n, nonwiki_n, wiki_content, topics, existing_texts, target_date):
    """Generate new cards via claude -p. Returns a list of card dicts."""
    if wiki_n == 0 and nonwiki_n == 0:
        return []

    existing_block = "\n".join(f"- {t}" for t in existing_texts[:200]) or "(none)"
    fence = "```"  # plain string — safe in a .py file, unlike a bash heredoc

    if topics:
        topics_instruction = (
            "AVAILABLE TOPICS FOR NEW-KNOWLEDGE QUESTIONS:\n"
            + "\n".join(topics)
            + "\n\nFor each nonWiki question, independently pick one topic at random. "
            "Set the 'topic' field to the chosen topic."
        )
    else:
        topics_instruction = (
            "No topics configured. New-knowledge questions should introduce "
            "concepts that extend the wiki content."
        )

    prompt = f"""Generate exactly {wiki_n} wiki questions and {nonwiki_n} nonWiki questions for a spaced repetition card library. Output ONLY a JSON array — no explanation, no markdown fences.

WIKI CONTENT (knowledge base):
{wiki_content}

{topics_instruction}

EXISTING QUESTIONS — do not duplicate any of these:
{existing_block}

WRITING RULES:
- Questions: use acronyms WITHOUT spelling them out — recall is part of the learning.
- Answers: explain every acronym in brackets on first use.
- Prefer questions that test understanding ("why / how / what is the effect of") over pure recall.

OUTPUT — a JSON array of exactly {wiki_n + nonwiki_n} objects:
[
  {{
    "text": "<question>",
    "answer": "<concise 1-3 sentence answer>",
    "type": "wiki" or "nonWiki",
    "topic": "<chosen topic for nonWiki; empty string for wiki>"
  }}
]

Output only the JSON array. Nothing before it, nothing after it."""

    log(f"Calling claude for {wiki_n} wiki + {nonwiki_n} nonWiki new cards...")
    try:
        result = subprocess.run([CLAUDE_BIN, "-p", prompt], capture_output=True, text=True)
    except FileNotFoundError:
        log(f"ERROR: claude binary not found at '{CLAUDE_BIN}' — install Claude Code CLI or set CLAUDE_BIN in ~/.dailyreview/.env")
        return []
    except Exception as e:
        log(f"ERROR: failed to launch claude: {e}")
        return []

    log(f"claude exit: {result.returncode}")
    if result.returncode != 0 or not result.stdout.strip():
        log(f"ERROR: claude produced no output. stderr: {result.stderr[:500]}")
        return []

    raw = "\n".join(
        line for line in result.stdout.strip().splitlines()
        if not line.strip().startswith(fence)
    )
    try:
        items = json.loads(raw)
    except Exception as e:
        log(f"JSON parse error: {e}\nRaw output: {raw[:500]}")
        return []

    if not isinstance(items, list):
        log(f"ERROR: claude returned {type(items).__name__} instead of a list — skipping")
        return []

    cards = []
    for item in items:
        if not isinstance(item, dict):
            log(f"WARNING: skipping non-dict item in claude response: {item!r}")
            continue
        text   = item.get("text", "").strip()
        answer = item.get("answer", "").strip()
        if not text or not answer:
            log(f"WARNING: skipping card with empty text or answer: {item!r}")
            continue
        cards.append(make_new_card(
            text=text,
            answer=answer,
            card_type=item.get("type", "wiki"),
            topic=item.get("topic", ""),
            target_date=target_date,
        ))
    return cards

# ── Main ──────────────────────────────────────────────────────────────────────

log(f"--- {datetime.datetime.now()} --- target={TARGET_DATE} fresh={FRESH}")

library = {c["id"]: c for c in load_json(LIBRARY_FILE, []) if isinstance(c, dict) and "id" in c}
session = load_json(SESSION_FILE, {})
if not isinstance(session, dict):
    log("WARNING: session.json is not a JSON object — treating as empty")
    session = {}

wiki_count    = session.get("wikiQuestionCount", 5)
nonwiki_count = session.get("nonWikiQuestionCount", 2)

tomorrow_wiki    = []
tomorrow_nonwiki = []

if not FRESH:
    # Merge today's session into library (captures SM-2 fields written by the app)
    for q in session.get("wikiQuestions", []) + session.get("nonWikiQuestions", []):
        if isinstance(q, dict) and "id" in q:
            library[q["id"]] = q
        else:
            log(f"WARNING: skipping malformed question during merge: {q!r}")
    save_json(LIBRARY_FILE, list(library.values()))
    log(f"Library: {len(library)} cards total after merge")

    # Select cards due for TARGET_DATE, oldest overdue first
    due_wiki, due_nonwiki = [], []
    for card in library.values():
        if card.get("interval", 0) == 36500:          # retired (boring)
            continue
        due_date = card.get("nextReviewDate") or TARGET_DATE
        if due_date <= TARGET_DATE:
            (due_wiki if card.get("type") == "wiki" else due_nonwiki).append(card)

    due_wiki.sort(    key=lambda c: c.get("nextReviewDate") or "0000-00-00")
    due_nonwiki.sort( key=lambda c: c.get("nextReviewDate") or "0000-00-00")

    tomorrow_wiki    = due_wiki[:wiki_count]
    tomorrow_nonwiki = due_nonwiki[:nonwiki_count]

    new_wiki_n    = max(0, wiki_count    - len(tomorrow_wiki))
    new_nonwiki_n = max(0, nonwiki_count - len(tomorrow_nonwiki))
    log(f"Due: {len(due_wiki)} wiki, {len(due_nonwiki)} nonWiki | "
        f"New needed: {new_wiki_n} wiki, {new_nonwiki_n} nonWiki")
else:
    new_wiki_n    = wiki_count
    new_nonwiki_n = nonwiki_count
    log("--fresh: generating full new set")

# Generate new cards for any unfilled slots
new_cards = call_claude(
    new_wiki_n, new_nonwiki_n,
    read_wiki(), active_topics(),
    [c["text"] for c in library.values() if "text" in c],
    TARGET_DATE,
)
for card in new_cards:
    library[card["id"]] = card
    (tomorrow_wiki if card["type"] == "wiki" else tomorrow_nonwiki).append(card)

save_json(LIBRARY_FILE, list(library.values()))

session_out = {
    "dateString":           TARGET_DATE,
    "wikiQuestions":        [session_card(c) for c in tomorrow_wiki],
    "nonWikiQuestions":     [session_card(c) for c in tomorrow_nonwiki],
    "wikiQuestionCount":    wiki_count,
    "nonWikiQuestionCount": nonwiki_count,
}
save_json(SESSION_FILE, session_out)
log(f"Session written: {len(tomorrow_wiki)}w + {len(tomorrow_nonwiki)}nw for {TARGET_DATE}")
log(f"Done at {datetime.datetime.now()}")

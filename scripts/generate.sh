#!/bin/bash
# Nightly question generator for the Daily Review app.
# Runs via launchd at 00:10. Implements SM-2 spaced repetition:
#   - Reads ~/.dailyreview/cards.json as the persistent card library
#   - Selects cards due for TARGET_DATE (nextReviewDate <= TARGET_DATE)
#   - Calls claude -p only to generate new cards for unfilled slots
#   - Writes ~/.dailyreview/session.json for tomorrow
#
# Args: [date] [--fresh]
#   date:    target dateString (default: tomorrow)
#   --fresh: generate a full new set regardless of library (used by in-app ↺ button)

SESSION_FILE="$HOME/.dailyreview/session.json"
LIBRARY_FILE="$HOME/.dailyreview/cards.json"
TOPICS_FILE="$HOME/.dailyreview/topics.json"
LOG="$HOME/.dailyreview/generate.log"

# Load personal config (.env overrides WIKI_DIR etc.)
if [ -f "$HOME/.dailyreview/.env" ]; then
    set -a; source "$HOME/.dailyreview/.env"; set +a
fi
WIKI_DIR="${WIKI_PATH:-$HOME/Documents/wiki/topics}"

TARGET_DATE=""
FRESH=false
for arg in "$@"; do
    case "$arg" in
        --fresh) FRESH=true ;;
        *)       TARGET_DATE="$arg" ;;
    esac
done
[ -z "$TARGET_DATE" ] && TARGET_DATE=$(date -v+1d +%Y-%m-%d)

CLAUDE_BIN="${CLAUDE_BIN:-$HOME/.local/bin/claude}"
[ -x "$CLAUDE_BIN" ] || CLAUDE_BIN=$(command -v claude 2>/dev/null || echo "claude")

echo "--- $(date) --- target=$TARGET_DATE fresh=$FRESH" >> "$LOG"

python3 << PYEOF
import json, os, subprocess, sys, math, random, glob, uuid, datetime

SESSION_FILE  = "$SESSION_FILE"
LIBRARY_FILE  = "$LIBRARY_FILE"
TOPICS_FILE   = "$TOPICS_FILE"
WIKI_DIR      = "$WIKI_DIR"
LOG_FILE      = "$LOG"
TARGET_DATE   = "$TARGET_DATE"
FRESH         = ("$FRESH" == "true")
CLAUDE_BIN    = "$CLAUDE_BIN"

def log(msg):
    with open(LOG_FILE, 'a') as f:
        f.write(str(msg) + '\n')

def load_json(path, default):
    try:
        with open(path) as f:
            return json.load(f)
    except:
        return default

def save_json(path, data):
    with open(path, 'w') as f:
        json.dump(data, f, indent=2)

def read_wiki():
    content = ""
    for path in sorted(glob.glob(os.path.join(WIKI_DIR, "*.md"))):
        name = os.path.basename(path).replace('.md', '')
        try:
            with open(path) as f:
                content += f"\n\n=== {name} ===\n{f.read()}"
        except:
            pass
    return content

def active_topics():
    topics = load_json(TOPICS_FILE, [])
    return [t['text'] for t in topics if not t.get('isPaused', False)]

def make_new_card(text, answer, card_type, topic, target_date):
    return {
        "id":             str(uuid.uuid4()),
        "text":           text,
        "answer":         answer,
        "type":           card_type,
        "topic":          topic,
        "isRevealed":     False,
        "isAddedToWiki":  False,
        "srsRating":      None,
        "eli5Answer":     None,
        "eli5IsPreferred": False,
        "interval":       0,
        "easeFactor":     2.5,
        "nextReviewDate": target_date,
    }

def session_card(card):
    """Return a copy of a library card ready for a fresh review session."""
    c = dict(card)
    c["srsRating"]  = None
    c["isRevealed"] = False
    return c

def call_claude(wiki_n, nonwiki_n, wiki_content, topics, existing_texts, target_date):
    """Ask claude to generate new cards. Returns list of card dicts."""
    if wiki_n == 0 and nonwiki_n == 0:
        return []

    existing_block = "\n".join(f"- {t}" for t in existing_texts[:200]) or "(none)"

    if topics:
        topics_instruction = (
            "AVAILABLE TOPICS FOR NEW-KNOWLEDGE QUESTIONS:\n" +
            "\n".join(topics) + "\n\n"
            "For each nonWiki question, independently pick one topic at random. "
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
    result = subprocess.run([CLAUDE_BIN, "-p", prompt], capture_output=True, text=True)
    log(f"claude exit: {result.returncode}")
    if result.returncode != 0 or not result.stdout.strip():
        log(f"ERROR: {result.stderr[:500]}")
        return []

    raw = "\n".join(l for l in result.stdout.strip().splitlines() if not l.strip().startswith("```"))
    try:
        items = json.loads(raw)
    except Exception as e:
        log(f"JSON parse error: {e}\nRaw: {raw[:500]}")
        return []

    return [
        make_new_card(
            text=item.get("text", ""),
            answer=item.get("answer", ""),
            card_type=item.get("type", "wiki"),
            topic=item.get("topic", ""),
            target_date=target_date,
        )
        for item in items
    ]


# ── Main ──────────────────────────────────────────────────────────────────────

library = {c['id']: c for c in load_json(LIBRARY_FILE, [])}
session = load_json(SESSION_FILE, {})

wiki_count    = session.get('wikiQuestionCount', 5)
nonwiki_count = session.get('nonWikiQuestionCount', 2)

tomorrow_wiki    = []
tomorrow_nonwiki = []

if not FRESH:
    # Merge today's session into library (copies SM-2 fields computed by the app)
    for q in session.get('wikiQuestions', []) + session.get('nonWikiQuestions', []):
        library[q['id']] = q
    save_json(LIBRARY_FILE, list(library.values()))
    log(f"Library: {len(library)} cards total after merge")

    # Select cards due for TARGET_DATE (oldest overdue first)
    due_wiki, due_nonwiki = [], []
    for card in library.values():
        if card.get('interval', 0) == 36500:      # retired (boring)
            continue
        due_date = card.get('nextReviewDate') or TARGET_DATE
        if due_date <= TARGET_DATE:
            (due_wiki if card.get('type') == 'wiki' else due_nonwiki).append(card)

    due_wiki.sort(   key=lambda c: c.get('nextReviewDate') or '0000-00-00')
    due_nonwiki.sort(key=lambda c: c.get('nextReviewDate') or '0000-00-00')

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

# Generate new cards only for unfilled slots
new_cards = call_claude(
    new_wiki_n, new_nonwiki_n,
    read_wiki(), active_topics(),
    [c['text'] for c in library.values()],
    TARGET_DATE,
)
for card in new_cards:
    library[card['id']] = card
    (tomorrow_wiki if card['type'] == 'wiki' else tomorrow_nonwiki).append(card)

# Persist library with newly added cards
save_json(LIBRARY_FILE, list(library.values()))

# Write session: reset srsRating/isRevealed; keep SRS scheduling fields for display
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
PYEOF

STATUS=$?
[ $STATUS -ne 0 ] && echo "ERROR: generator failed (exit $STATUS)" >> "$LOG"

#!/bin/bash
# Nightly question generator for the Daily Review app.
# Runs via launchd at 23:00. Uses claude -p with Claude Pro — no API key needed.
# Claude outputs JSON to stdout; bash writes it to the session file.
# No Claude tool permissions needed.
#
# SETUP: Set WIKI_DIR below to the folder containing your wiki .md files.
# Then copy this script to ~/.dailyreview/generate.sh and make it executable:
#   chmod +x ~/.dailyreview/generate.sh

SESSION_FILE="$HOME/.dailyreview/session.json"
WIKI_DIR="$HOME/Documents/wiki/topics"   # <-- change this to your wiki folder
LOG="$HOME/.dailyreview/generate.log"

# Args: [date] [--fresh]
# date:    target dateString for generated session (default: tomorrow)
# --fresh: ignore existing session — generate a full new set (used by the in-app ↺ button)
TARGET_DATE=""
FRESH=false
for arg in "$@"; do
    case "$arg" in
        --fresh) FRESH=true ;;
        *)       TARGET_DATE="$arg" ;;
    esac
done
[ -z "$TARGET_DATE" ] && TARGET_DATE=$(date -v+1d +%Y-%m-%d)

echo "--- $(date) --- target=$TARGET_DATE fresh=$FRESH" >> "$LOG"

# Read current session (ignored in --fresh mode)
if [ "$FRESH" = "true" ]; then
    SESSION_CONTENT="{}"
elif [ -f "$SESSION_FILE" ]; then
    SESSION_CONTENT=$(cat "$SESSION_FILE")
else
    SESSION_CONTENT="{}"
fi

# Read all wiki .md files into one block
WIKI_CONTENT=""
for f in "$WIKI_DIR"/*.md; do
    [ -f "$f" ] || continue
    NAME=$(basename "$f" .md)
    WIKI_CONTENT="$WIKI_CONTENT

=== $NAME ===
$(cat "$f")"
done

PROMPT="Generate tomorrow's daily review questions. Output ONLY valid JSON — no explanation, no markdown fences, nothing else.

TODAY'S SESSION:
$SESSION_CONTENT

WIKI CONTENT (personal knowledge base):
$WIKI_CONTENT

RULES:
1. Keep every question where srsRating is null or absent EXACTLY as-is.
2. Keep every question where srsRating is "miss" or "hazy" — the user needs to retry it. Reset it: set srsRating to null and isRevealed to false. All other fields stay unchanged (same id, text, answer, type, isAddedToWiki).
3. For every question where srsRating is "solid" or "boring", generate a replacement:
   - wiki questions: test a concept from the wiki that is NOT covered by any kept question. If the replaced question was rated "boring", choose a concept from a noticeably different subject area.
   - nonWiki questions: introduce knowledge that EXTENDS the wiki — choose adjacent or deeper concepts not yet present in any wiki file. If topicForTomorrow is set and non-empty, generate questions specifically about that topic instead.
4. Total questions must equal wikiQuestionCount + nonWikiQuestionCount from the session.
   If the session is empty or missing those fields, default to 5 wiki + 2 nonWiki.
5. If there are fewer solid-rated questions than the total quota, generate fresh questions to fill the remaining slots.

OUTPUT — a single JSON object with exactly these fields:
{
  \"dateString\": \"$TARGET_DATE\",
  \"wikiQuestions\": [ ...wiki-type questions... ],
  \"nonWikiQuestions\": [ ...nonWiki-type questions... ],
  \"topicForTomorrow\": \"<copy topicForTomorrow from today's session, or 'general knowledge' if absent>\",
  \"currentNonWikiTopic\": \"<same value as topicForTomorrow above>\",
  \"wikiQuestionCount\": <integer from today's session or 5>,
  \"nonWikiQuestionCount\": <integer from today's session or 2>
}

WRITING RULES:
- Questions: use acronyms WITHOUT explanation — recalling what they stand for is part of the learning.
- Answers: explain every acronym in brackets on first use. E.g. RLHF (Reinforcement Learning from Human Feedback). Do not assume any acronym is universally known.

Each NEW question object (srsRating always null for new questions):
{
  \"id\": \"<fresh lowercase UUID v4>\",
  \"text\": \"<question>\",
  \"answer\": \"<concise 1-3 sentence answer>\",
  \"type\": \"wiki\" or \"nonWiki\",
  \"isRevealed\": false,
  \"isAddedToWiki\": false,
  \"srsRating\": null
}

Output only the JSON. Nothing before it, nothing after it."

echo "Calling claude -p..." >> "$LOG"
OUTPUT=$(claude -p "$PROMPT" 2>> "$LOG")
STATUS=$?
echo "claude exit status: $STATUS" >> "$LOG"

if [ $STATUS -ne 0 ] || [ -z "$OUTPUT" ]; then
    echo "ERROR: claude produced no output or failed." >> "$LOG"
    exit 1
fi

# Strip any accidental markdown fences before writing
CLEAN=$(echo "$OUTPUT" | sed '/^```/d')

echo "$CLEAN" > "$SESSION_FILE"
echo "Written to $SESSION_FILE" >> "$LOG"
echo "Done at $(date)" >> "$LOG"

# Daily Review

A macOS menu bar app for daily spaced repetition learning, driven by a personal knowledge wiki and AI-generated questions.

![Daily Review panel showing questions with answers revealed and SRS rating buttons](screenshots/panel-questions.png)

*Questions in various states: answered with GOT IT, answer revealed with AGAIN/HARD/GOT IT buttons, and unrevealed cards showing REVEAL.*

![Panel with topic input box and a question added to wiki](screenshots/panel-topic-input.png)

*After all wiki questions are rated, the topic input box appears. GOT IT on a NEW question shows "Added to wiki" confirmation.*

## What it does

A **?** icon sits in the menu bar — red until all questions are answered, white when done. Each day presents a set of flashcard-style questions drawn from your wiki and optionally a topic you choose. Questions are rated AGAIN / HARD / GOT IT after the answer is revealed. Rating a non-wiki question GOT IT automatically adds its knowledge to the wiki, growing the source material for future questions.

## How it works

### Daily flow

1. **Morning**: Open the panel — today's questions are ready (generated the previous night)
2. **Review**: Tap any question card to reveal the answer, then rate it
3. **Set tomorrow's topic**: After the last wiki question is rated, an input box appears — type a topic for tomorrow's extra questions
4. **Tonight**: A launchd job runs at 23:00, calls `claude -p` to generate replacement questions for everything you rated, writes them to `~/.dailyreview/session.json` with tomorrow's date
5. **Next morning**: App reads the file, shows fresh questions

### Question types

| Badge | Source | On GOT IT |
|---|---|---|
| `WIKI` | Drawn from your wiki files | Replaced with a new wiki question |
| `NEW` | Extends the wiki / covers the topic you set | Auto-added to the wiki |

### Spaced repetition

- **AGAIN**: You forgot — question carries over to tomorrow unchanged
- **HARD**: Partial recall — question carries over to tomorrow
- **GOT IT**: You knew it — question is replaced with a fresh one tonight

Unanswered questions (not rated by end of day) carry over with no change.

---

## Architecture

### App (`Sources/DailyReview/`)

Swift 6.2 / SwiftUI `MenuBarExtra` app. No network calls at runtime.

| File | Role |
|---|---|
| `DailyReviewApp.swift` | App entry point, icon generation (Core Text glyph path) |
| `AppStore.swift` | State management, session loading, `rateQuestion`, `addToWiki`, `runGenerateScript` |
| `Models/Question.swift` | `Question`, `DaySession`, `SRSRating` models |
| `Services/WikiService.swift` | Appends Q&A to wiki files on GOT IT |
| `Views/MenuBarView.swift` | Panel layout, toolbar, question list |
| `Views/QuestionView.swift` | Card UI — reveal, AGAIN/HARD/GOT IT buttons, wiki-add |
| `Views/TopicInputView.swift` | Tomorrow's topic input (appears after last wiki question is rated) |
| `Views/SettingsView.swift` | Question counts, wiki folder path |

### Session file (`~/.dailyreview/session.json`)

Shared between the app and the nightly script. Written by both.

```json
{
  "dateString": "2026-05-31",
  "wikiQuestions": [...],
  "nonWikiQuestions": [...],
  "topicForTomorrow": "transformer attention mechanisms",
  "currentNonWikiTopic": "large language models",
  "wikiQuestionCount": 5,
  "nonWikiQuestionCount": 2
}
```

Each question:
```json
{
  "id": "...",
  "text": "What is SASE?",
  "answer": "SASE (Secure Access Service Edge) converges...",
  "type": "wiki",
  "isRevealed": false,
  "isAddedToWiki": false,
  "srsRating": null
}
```

`srsRating` is `null` until rated; one of `"miss"`, `"hazy"`, `"solid"` after.

### Nightly script (`~/.dailyreview/generate.sh`)

Runs via launchd at 23:00. Calls `claude -p` (Claude Code CLI, uses existing Claude Pro session — no separate API key). Claude outputs JSON to stdout; bash writes it to `session.json`.

**Arguments:**
- No args: nightly mode — writes tomorrow's date, carries over unrated questions
- `<date>`: override the target date
- `--fresh`: ignore current session, generate a completely new set (used by the in-app ↺ button)

**Question generation rules:**
- `srsRating: null` — kept unchanged (not yet attempted)
- `srsRating: "miss"` or `"hazy"` — carried over with rating reset to null (retry tomorrow)
- `srsRating: "solid"` — replaced with a fresh question
- Wiki replacements test different concepts not covered by carryovers
- Non-wiki replacements extend the wiki or cover `topicForTomorrow`

### launchd job (`~/Library/LaunchAgents/com.example.dailyreview.plist`)

Fires at 23:00 local time every night. Logs to `~/.dailyreview/generate.log` and `launchd.log`.

---

## Design decisions

### Why launchd + `claude -p` instead of a remote scheduled agent

Claude Code's `/schedule` skill creates remote cloud agents. Remote agents have no access to local files — they can't read `~/.dailyreview/session.json` or the Obsidian wiki. `claude -p` runs a local non-interactive Claude Code session that has full filesystem access and uses the existing Claude Pro subscription. No separate API key is needed.

### Why session data lives in a file, not UserDefaults

The nightly `generate.sh` script (a bash process, not the app) needs to read and write the session. UserDefaults is per-app and inaccessible to external processes. A plain JSON file at `~/.dailyreview/session.json` is readable by both.

### Why the icon is drawn as a glyph path, not a font render

The menu bar needs two explicit colour variants (red and white). Using `.isTemplate = true` lets macOS auto-colour a single image but doesn't support two distinct colours. Instead, `makeQuestionIcon(color:)` extracts the `?` glyph outline from Helvetica Bold via Core Text (`CTFontCreatePathForGlyph`), then fills it with the target colour using Core Graphics. This is a proper vector image, not a text render.

### Why GOT IT auto-adds to the wiki but HARD does not

GOT IT means the user has internalised the knowledge — it belongs in their long-term notes. HARD means partial recall — adding it to the wiki prematurely could pollute it with half-understood material. HARD shows a manual "Add to wiki" button so the user can choose.

### Why AGAIN carries over rather than being discarded

Discarding a missed question loses it entirely. Carrying it over means it keeps appearing until the user actually learns it, which is the point of spaced repetition.

### Wiki path

Default: `~/Documents/wiki/topics/`. Configurable in Settings (stored in UserDefaults). When a non-wiki question is added to the wiki, `WikiService` finds the best-matching `.md` file by normalising hyphens to spaces and checking for substring overlap (minimum 4 chars to prevent false matches). If no match, a new file is created.

---

## Setup

1. **Build**: `swift build` from the project root (requires macOS 26 / Xcode with Swift 6.2)
2. **Run**: `swift run &`
3. **Load the launchd job** (once):
   ```
   launchctl load ~/Library/LaunchAgents/com.example.dailyreview.plist
   ```
4. **Generate first questions** — click ↺ in the panel toolbar (takes ~30s)

No `.env` file or API key needed. The app uses the Claude Code CLI session (`~/.local/bin/claude`).

**Settings** (gear icon): adjust wiki/non-wiki question counts, change wiki folder path.

---

## Testing iterative changes

Click **↺** in the toolbar — passes `--fresh` to the script, ignores all current ratings, generates a completely new set of questions dated today. Use this during development to test changes without waiting for the nightly run.

---

## Logs

```
~/.dailyreview/generate.log   # script output (claude call, status, timing)
~/.dailyreview/launchd.log    # launchd stdout/stderr capture
```

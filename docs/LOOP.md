# How the "Set a goal" loop works, and how to run it for Ludeck

This is a note for humans (and for a future session of me) about the
mechanism behind the dashboard's "Set a goal" dialog, so it doesn't have to
be re-derived from a chat transcript.

## What it actually is

It is a **self-nudge loop bound to this one chat session** -- not a separate
worker, not a multi-session orchestration. Every `interval_secs` seconds, the
dashboard re-injects the dialog's "Goal description" text into this same
conversation as the next user-turn equivalent. Same session, same tool
access, same conversation history (until that history gets compacted). It
keeps firing until either:

- a stop file (a specific path the dialog fills in as `{{STOP_FILE}}`, shown
  in the dialog text) is created on disk, or
- the "Max cycles" count is reached (0 means unlimited -- do not set this to
  0 for unattended app-building work), or
- the "Stop loop" button is pressed in the dashboard.

There is **no built-in critique, verification, or "done" detection** --
those have to be written into the goal text itself and enforced by the
agent reading it each cycle. That's what `GOAL.md` Section 4 (design
standard) and Section 1 ("what done means") are for.

## Why this is the right mechanism for Ludeck, and `goal-conductor` is not

There's a separate, more elaborate skill (`goal-conductor`) for a
multi-session work-ledger conductor: it spawns a worker session per
independent work item, verifies each with a scripted acceptance evaluator,
and patrols with `monitor_start`. That's the right tool for something like
"fix every flaky test across 12 independent PRs" -- many genuinely
independent, parallelizable items with machine-checkable completion.

Ludeck's remaining work is mostly **sequential and interdependent** (Phase C
blocks clean Phase E work; F6/F7 are mid-flight and must finish before F8) on
**one codebase** with **one person driving it**. Spinning up a conductor and
worker sessions for that would add coordination overhead with no
parallelism to show for it. The simple self-nudge loop, reading
`GOAL.md`/`PROGRESS.md` as its external memory, is the correct-sized tool.

## Recommended dialog settings for this project

**Goal description** (paste this into the dialog, replacing the placeholder
-- `{{STOP_FILE}}` is filled in automatically by the dashboard, leave that
token exactly as written):

```
Your goal is docs/GOAL.md in F:\Abin\Ludeck. Read it in full before acting.
Read docs/PROGRESS.md for what's already done and what loop N found last time.
Pick ONE item from PROGRESS.md's "Next" section. Implement it. Run flutter
analyze, flutter test, and scripts/check.ps1 -- all three must be clean before
you touch the emulator. Run the app on the emulator and read runtime errors
with the dart MCP tools. Screenshot every screen you touched. Run the
design-critique skill against each screenshot using the standard in
docs/GOAL.md Section 4. Fix what critique finds in the SAME loop if it's
small; if it's structural, log it as a new Next item instead of silently
expanding scope. Append one dated entry to docs/PROGRESS.md: what you did,
what critique found, what's still open. Commit with a plain message, never
push to main. If the same item fails twice in a row, stop touching code,
write the blocker at the top of PROGRESS.md under "BLOCKED", and create
{{STOP_FILE}}. To halt for any other reason, also create {{STOP_FILE}}.
```

**Seconds between nudges: 1800** (30 minutes). Not the dialog's 60-second
default -- one real cycle here means a Flutter build, an emulator run, a
screenshot, and a critique pass. A 60-second nudge would interrupt that
mid-cycle almost every time.

**Max cycles: 12**, not 0. Bounded to roughly a 6-hour unattended run (12
cycles x up to 30 min each, though most cycles will finish faster). Review
`PROGRESS.md` after it stops or hits the cap; raise the cap and restart if
the direction looks right and there's more to do.

## What to check when you come back

1. Read `docs/PROGRESS.md`'s cycle log, newest entries first.
2. Check the `BLOCKED` section at the top -- if non-empty, the loop stopped
   itself on a real problem, not the cycle cap.
3. Check `Needs human judgment` -- these are subjective design calls the
   loop deliberately did not decide. Answer them, then remove the entries
   you've resolved (or leave them and add your decision as a note, your
   call).
4. Run `git log --oneline -20` to see what actually landed as commits --
   `PROGRESS.md` is the loop's own account, but the commit history is what
   actually happened to the code.
5. If everything in `GOAL.md` Section 2 is checked off in `PROGRESS.md`'s
   checklist AND analyze/test/check.ps1 are clean AND every screen has
   passed critique, the loop should have stopped itself. If it's still
   running past that point, stop it manually -- that's a bug in how it read
   its own exit condition, worth fixing before the next run.

## Known constraints this loop must work within (see docs/CONSTRAINTS.md)

- No emulator issue anymore -- WHPX works, `Pixel_8` boots. But cold Gradle
  builds are slow (multi-minute) and the emulator's `/data` partition runs
  close to full; build `--target-platform android-x64` rather than the
  default fat APK if space errors recur.
- `skill_search` / `learn_add` are refused on this install
  (`policy_unreadable`, an unparsed agent spec) -- the loop cannot save
  lessons to persistent memory. `PROGRESS.md` is the substitute; make sure
  the loop actually writes to it rather than silently doing nothing when a
  memory tool fails.
- No code generation on this Flutter/Dart toolchain version -- hand-written
  SQL and hand-written models only, no Drift/freezed/json_serializable.

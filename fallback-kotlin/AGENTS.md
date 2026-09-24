# AGENTS.md

Read `BUILD.md` in this directory **before writing any code**. It is binding.

The three things most often got wrong here, so check them first:

1. **Status values.** Use the exact enums in BUILD.md section 4. Do not invent
   `want_to_play`, `backlog`, `completed`, `beaten` or `dropped`.
2. **IGDB.** 4 requests per second, 8 concurrent, no CORS. Every call goes through
   the Supabase Edge Function proxy, from exactly one call site. `time_to_beat`
   values are in **seconds**.
3. **Tokens.** No colour literal outside `ui/theme/Tokens.kt`. If you need a value
   that is not in the token file, change the token file and say why.

Before claiming done, run `scripts/check.ps1`. It fails on the six violations
listed in BUILD.md section 9.

Target is **Google Play, Android only**. There is no iOS build on this machine.

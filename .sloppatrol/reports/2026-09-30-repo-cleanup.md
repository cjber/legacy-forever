# Runtime organisation @ 7cc2a9ee8ec151ee17ecac918b358fd7a4aa3631

Scope: byte-identical relocation of 14 runtime Lua/XML files, their manifest entries and active developer consumers. The manifest execution order is unchanged; public API, saved data and gameplay code are preserved.

Tests, screenshot source readers and developer documentation follow the new paths. Generated Data paths and historical audit/release entries remain unchanged. Type coverage rejects unlisted runtime modules in the new folders, with a regression exercising each folder. Independent review found no runtime path regressions.

Verification: full Lua specs, LuaLS/Ketho and checker regressions, formatting/lint, changelog and sift gates, workflow checks and secret scanning. Temporary storage uses the workspace because /tmp has exhausted its quota. No gate thresholds, assertions, diagnostic exclusions or performance budgets were relaxed. No live gameplay verification is claimed.

This focused cleanup does not settle every historical whole-repository candidate. No speculative runtime deletion or new abstraction was applied.

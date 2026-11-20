### Fixed

- The Legacy section in the objective tracker attaches again at login. After the latest ForeverCore update, Legacy's files ran after the game's loading signals they were waiting for, so the tracker's deferred attach pass and its "couldn't add a section" check never ran. They now wait only for the signals still to come (cjber/forever-core#980).

### For addon authors

- `ZoneSummary` and `Targets` answer the standard reason `"none"` for a map with no Legacy data, where they answered `"unsupported"`, and a wrong argument answers through `ForeverCore.APIKit.Invalid()` (still `nil, "invalid"`).

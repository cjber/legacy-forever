-- Run from the repository root: luajit tests/error_journal_spec.lua
-- The shared error journal (Core/SafeCall.lua) and debug log (Core/Log.lua) live in LegacyForeverDB, attached by
-- Core/Saved.lua once the saved variables are in, so the report lists earlier sessions' errors and the lines that led
-- to them after a /reload.
local checks = 0
local function check(condition, label)
	checks = checks + 1
	assert(condition, label)
end

CreateFrame = function()
	return { RegisterEvent = function() end, SetScript = function() end }
end
SlashCmdList = {}
-- The client defines the error handler, strtrim and date Core/SafeCall.lua and Core/Log.lua read.
geterrorhandler = function()
	return error
end
seterrorhandler = function() end
strtrim = function(text)
	return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end
date = function()
	return "2026-11-08 12:00:00"
end
GetTime = function()
	return 1.5
end

local ns = {}
assert(loadfile("Locales/enUS.lua"))("LegacyForever", ns)
assert(loadfile("Core/SafeCall.lua"))("LegacyForever", ns)
assert(loadfile("Core/Log.lua"))("LegacyForever", ns)
assert(loadfile("Core/Core.lua"))("LegacyForever", ns)

-- A first install, with no saved table at all: Saved makes the journal and the log in LegacyForeverDB and attaches
-- them.
LegacyForeverDB = nil
assert(loadfile("Core/Saved.lua"))("LegacyForever", ns)
check(type(LegacyForeverDB.errors) == "table", "the saved table has no error journal")
check(type(LegacyForeverDB.log) == "table", "the saved table has no debug log")

-- An error caught by ns.SafeCall is recorded in the saved journal, which is where the next session reads it.
local ok = ns.SafeCall("error journal spec", function()
	error("error journal spec failure")
end)
check(ok == false, "the failure was not caught")
local entry
for _, candidate in ipairs(LegacyForeverDB.errors) do
	if candidate.message:find("error journal spec failure", 1, true) then
		entry = candidate
	end
end
check(entry ~= nil, "the caught error did not reach the saved journal")
check(entry and entry.kind == "error" and entry.count == 1, "the journal entry is not one error")
check(entry and type(entry.firstSeen) == "number" and type(entry.lastSeen) == "number", "no times kept")

-- The log rides in the same saved table, so the lines that led to a bug survive a /reload too.
ns.Log("info", "error journal spec", "a line before the reload")
local logged
for _, line in ipairs(LegacyForeverDB.log.lines or {}) do
	if line:find("a line before the reload", 1, true) then
		logged = line
	end
end
check(logged ~= nil, "the log line did not reach the saved ring")
check(logged and logged:find("info error journal spec:", 1, true), "the saved line has no level and topic")

-- A table a previous session saved is the journal and the log this one keeps, and its entries reach the report as
-- earlier sessions' errors.
local saved = {
	errors = {
		{
			signature = "earlier\n",
			kind = "error",
			message = "error from an earlier session",
			stack = "",
			count = 2,
			firstSeen = 1,
			lastSeen = 2,
		},
	},
	log = {
		lines = { "2026-11-07 09:00:00 +12.0s info earlier: line from an earlier session" },
		pinned = false,
	},
}
LegacyForeverDB = saved
local reloaded = {}
assert(loadfile("Locales/enUS.lua"))("LegacyForever", reloaded)
assert(loadfile("Core/SafeCall.lua"))("LegacyForever", reloaded)
assert(loadfile("Core/Log.lua"))("LegacyForever", reloaded)
assert(loadfile("Core/Core.lua"))("LegacyForever", reloaded)
assert(loadfile("Core/Saved.lua"))("LegacyForever", reloaded)
check(LegacyForeverDB.errors == saved.errors, "the journal is not the saved errors table")
check(LegacyForeverDB.log == saved.log, "the log is not the saved log table")
local earlier
for _, candidate in ipairs(reloaded.CaughtErrors()) do
	if candidate.message == "error from an earlier session" then
		earlier = candidate
	end
end
check(earlier ~= nil and earlier.fromSession == false, "an earlier session's error is missing from the report")
check(earlier and earlier.count == 2, "the earlier session's count was lost")
local kept
for _, line in ipairs(reloaded.LogLines(10)) do
	if line:find("line from an earlier session", 1, true) then
		kept = line
	end
end
check(kept ~= nil, "an earlier session's log line is missing after the reload")

print(("error_journal_spec: %d checks passed"):format(checks))

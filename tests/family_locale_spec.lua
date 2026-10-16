-- Run from the repository root: luajit tests/family_locale_spec.lua
-- Legacy's Forever addons page reads in Legacy's own translations even when another Forever addon's copy of the
-- shared UI/ForeverFamily.lua is the one in use (cjber/shortest-path-forever#201), and Legacy's French covers every
-- phrase that file shows.
local checks = 0
local function check(condition, label)
	checks = checks + 1
	assert(condition, label)
end

function GetLocale()
	return "frFR"
end

-- Another Forever addon with English only loads first, as Shortest Path Forever does (Legacy's OptionalDeps), and
-- its copy of the shared file becomes the one in use.
local other = {
	L = setmetatable({}, {
		__index = function(_, key)
			return key
		end,
	}),
}
assert(loadfile("UI/ForeverFamily.lua"))("ShortestPathForever", other)
local legacy = {}
assert(loadfile("Locales/enUS.lua"))("LegacyForever", legacy)
assert(loadfile("Locales/frFR.lua"))("LegacyForever", legacy)
assert(loadfile("UI/ForeverFamily.lua"))("LegacyForever", legacy)
local Family = legacy.Family
check(Family == other.Family and Family == ForeverFamily, "the first copy loaded stays in use")

local row
for _, addon in ipairs(Family.ADDONS) do
	if addon.folder == "LegacyForever" then
		row = addon
	end
end
local french = rawget(legacy.L, row.phrase)
check(type(french) == "string" and french ~= row.phrase, "Legacy's French has its own line")
check(Family.Line(row, legacy.L) == french, "with Legacy's L the line is in French")
check(Family.Line(row) == row.phrase, "without it, the copy in use answers in English")

-- Every phrase the shared file sends through L has a French entry, so none falls back to English on the page or
-- in the link window. A phrase reworded in a later sync without a new translation fails here.
local file = assert(io.open("UI/ForeverFamily.lua", "rb"))
local source = file:read("*a")
file:close()
local phrases = 0
for phrase in source:gmatch('L%["(.-)"%]') do
	phrases = phrases + 1
	check(type(rawget(legacy.L, phrase)) == "string", "frFR translates: " .. phrase)
end
check(phrases >= 15, "the shared file's phrases are found")

print(("family_locale_spec: %d checks passed"):format(checks))

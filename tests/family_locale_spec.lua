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
local Family = ForeverFamily
check(other.Family == Family.For(other.L), "the first copy loaded stays in use, bound to its own L")
check(legacy.Family == Family.For(legacy.L), "Legacy's view is bound to Legacy's own L")
check(legacy.Family ~= other.Family, "and not to the other addon's")

-- The page and the link window are built with the L the view was bound to.
local seen = {}
local CreatePanel, ShowLink = Family.CreatePanel, Family.ShowLink
Family.CreatePanel = function(_, _, _, locale)
	seen.panel = locale
end
Family.ShowLink = function(_, _, _, _, locale)
	seen.link = locale
end
legacy.Family.CreatePanel(nil, {}, "LegacyForever")
legacy.Family.ShowLink(nil, nil, "ShortestPathForever")
check(seen.panel == legacy.L and seen.link == legacy.L, "Legacy's page and window read in Legacy's L")
other.Family.CreatePanel(nil, {}, "ShortestPathForever")
check(seen.panel == other.L, "the other addon's page keeps its own L")
Family.CreatePanel, Family.ShowLink = CreatePanel, ShowLink

local row
for _, addon in ipairs(Family.ADDONS) do
	if addon.folder == "LegacyForever" then
		row = addon
	end
end
local french = rawget(legacy.L, row.line)
check(type(french) == "string" and french ~= row.line, "Legacy's French has its own line")

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

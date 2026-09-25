-- Run from the repository root: luajit tests/settings_spec.lua
-- Settings read through ns.DEFAULTS: a missing key is its default, a saved value always wins.
local checks = 0
local function check(condition, label)
	checks = checks + 1
	assert(condition, label)
end

SlashCmdList = {}
local ns = {}
assert(loadfile("Core.lua"))("LegacyForever", ns)
local defaults = ns.DEFAULTS.zoneCompletion

-- A fresh install: no saved variables at all.
LegacyForeverDB = nil
check(ns.Setting("showAreas") == true, "areas are shaded out of the box")
check(ns.Setting("whatsNew") == true and ns.Setting("companions") == true, "update line and hints on out of the box")
check(ns.ZoneSetting("map") == true and ns.ZoneSetting("tracker") == false, "on the map, not in the tracker")
check(not ns.ZoneSetting("mapCollapsed") and not ns.ZoneSetting("trackerCollapsed"), "expanded out of the box")
for _, category in ipairs({ "areas", "dungeons", "raids", "legacy" }) do
	check(ns.ZoneSetting("count_" .. category) == true, category .. " count out of the box")
end
for _, category in ipairs({ "taxis", "reputations", "quests" }) do
	check(ns.ZoneSetting("count_" .. category) == false, category .. " wait to be ticked")
end
check(ns.ZoneSetting("unknown") == false, "an undeclared key reads as off")
check(LegacyForeverDB.showAreas == nil, "reading a default saves nothing")
for key in pairs(defaults) do
	check(LegacyForeverDB.zoneCompletion[key] == nil, key .. " is not written by a read")
end

-- A save file from before DEFAULTS: every saved true or false keeps its meaning.
LegacyForeverDB = {
	showAreas = false,
	zoneCompletion = { map = false, tracker = true, mapCollapsed = true, count_areas = false, count_quests = true },
}
check(ns.Setting("showAreas") == false, "a saved off stays off")
check(ns.ZoneSetting("map") == false and ns.ZoneSetting("tracker") == true, "saved surfaces win")
check(ns.ZoneSetting("mapCollapsed") == true and ns.ZoneSetting("trackerCollapsed") == false, "saved collapse wins")
check(ns.ZoneSetting("count_areas") == false and ns.ZoneSetting("count_quests") == true, "saved categories win")
check(ns.ZoneSetting("count_raids") == true, "a key the old file lacks is its default")

-- Saved true for a default-on switch is still on.
LegacyForeverDB = { showAreas = true }
check(ns.Setting("showAreas") == true, "a saved on stays on")

print(("settings_spec: %d checks passed"):format(checks))

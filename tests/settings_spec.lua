-- Run from the repository root: luajit tests/settings_spec.lua
-- Settings read through ns.DEFAULTS: a missing key is its default, a saved value always wins.
local checks = 0
local function check(condition, label)
	checks = checks + 1
	assert(condition, label)
end

SlashCmdList = {}
local ns = {}
assert(loadfile("Locales/enUS.lua"))("LegacyForever", ns)
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

-- A bare /lf opens the map's Legacy menu, where the options live, as the compartment entry does.
function strtrim(text)
	return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end
local calls, printed = {}, {}
WorldMapFrame = {
	IsShown = function()
		return calls.map ~= nil
	end,
}
function ToggleWorldMap()
	calls.map = (calls.map or 0) + 1
end
function ns.OpenMapMenu()
	calls.menu = (calls.menu or 0) + 1
end
function ns.Print(text)
	printed[#printed + 1] = text
end
SlashCmdList.LEGACYFOREVER("")
check(calls.map == 1 and calls.menu == 1 and #printed == 0, "a bare /lf opens the map and its menu")
LegacyForever_OnAddonCompartmentClick()
check(calls.map == 1 and calls.menu == 2, "the compartment entry opens the menu on the open map")
SlashCmdList.LEGACYFOREVER("help")
check(#printed == 3 and calls.menu == 2, "/lf help prints the commands")

-- The Settings page: the same options as subcategories with an index page, every row through
-- RegisterInitializer (CreateCheckbox and layout:AddInitializer would taint the settings search), and the
-- map menu's own toggles sharing the values.
local registered, subcategories, opened = {}, {}, {}
local function Category(name)
	return {
		name = name,
		GetID = function()
			return name
		end,
	}
end
Settings = {
	VarType = { Boolean = "boolean" },
	RegisterVerticalLayoutCategory = function(name)
		check(name == "Legacy Forever", "the category is named after the addon")
		return Category(name)
	end,
	RegisterVerticalLayoutSubcategory = function(parent, name)
		subcategories[#subcategories + 1] = { parent = parent, category = Category(name) }
		return subcategories[#subcategories].category
	end,
	RegisterAddOnSetting = function(_, variable, key, _, varType, name, default)
		return {
			variable = variable,
			key = key,
			varType = varType,
			name = name,
			default = default,
			SetValueChangedCallback = function(self, callback)
				self.changed = callback
			end,
			SetValue = function(self, value)
				self.value = value
				if self.changed then
					self.changed()
				end
			end,
		}
	end,
	CreateCheckbox = function()
		error("addon code inserted a row; use Settings.RegisterInitializer")
	end,
	CreateCheckboxInitializer = function(setting, options, tooltip)
		check(setting.varType == "boolean" and options == nil, "boolean rows only")
		local initializer = { setting = setting, tooltip = tooltip, modify = {} }
		function initializer.AddModifyPredicate(self, predicate)
			self.modify[#self.modify + 1] = predicate
		end
		return initializer
	end,
	RegisterInitializer = function(category, initializer)
		registered[#registered + 1] = { category = category, initializer = initializer }
	end,
	RegisterAddOnCategory = function(category)
		check(category.name == "Legacy Forever", "the category is registered")
	end,
	OpenToCategory = function(id)
		opened[#opened + 1] = id
	end,
}
function CreateSettingsButtonInitializer(name, text, click, _tooltip, addSearchTags)
	check(text == "Open" and addSearchTags == false, "index buttons stay out of search")
	return { button = true, name = name, click = click }
end
ns.Model = { COMPLETION_CATEGORIES = { "areas", "taxis", "dungeons", "raids", "legacy", "reputations", "quests" } }
local surfaceChanges, countChanges, questsUsable = 0, 0, true
ns.Completion = {
	Label = function(key)
		return key
	end,
	SurfacesChanged = function()
		surfaceChanges = surfaceChanges + 1
	end,
	CountsChanged = function()
		countChanges = countChanges + 1
	end,
	QuestsUsable = function()
		return questsUsable
	end,
	QuestsStatusText = function()
		return "a quest source"
	end,
}
local refreshed = 0
ns.RefreshMap = function()
	refreshed = refreshed + 1
end
assert(loadfile("Settings.lua"))("LegacyForever", ns)

-- Every section is a subpage; the index holds one button per subpage, in order.
check(#subcategories == 4, "four subcategory groups")
local names = { "World map", "Objective tracker", "What counts", "Hints and updates" }
for index, name in ipairs(names) do
	check(subcategories[index].category.name == name, name .. " is a subcategory")
end
local kinds, expectedKinds =
	{}, {
		"button@Legacy Forever",
		"checkbox@World map",
		"checkbox@World map",
		"button@Legacy Forever",
		"checkbox@Objective tracker",
		"button@Legacy Forever",
	}
for _ = 1, 7 do
	expectedKinds[#expectedKinds + 1] = "checkbox@What counts"
end
expectedKinds[#expectedKinds + 1] = "button@Legacy Forever"
expectedKinds[#expectedKinds + 1] = "checkbox@Hints and updates"
expectedKinds[#expectedKinds + 1] = "checkbox@Hints and updates"
for index, entry in ipairs(registered) do
	kinds[index] = (entry.initializer.button and "button" or "checkbox") .. "@" .. entry.category.name
end
check(table.concat(kinds, " ") == table.concat(expectedKinds, " "), table.concat(kinds, " "))

-- Every setting keeps its key and default, and has a variable of its own.
local byKey = {}
for _, entry in ipairs(registered) do
	local setting = entry.initializer.setting
	if setting then
		byKey[setting.key] = setting
	end
end
local expected = {
	showAreas = true,
	map = true,
	tracker = false,
	count_areas = true,
	count_taxis = false,
	count_dungeons = true,
	count_raids = true,
	count_legacy = true,
	count_reputations = false,
	count_quests = false,
	whatsNew = true,
	companions = true,
}
local seen = 0
for key, default in pairs(expected) do
	seen = seen + 1
	check(byKey[key], key .. " is on the page")
	check(byKey[key].default == default, key .. " keeps its default")
	check(byKey[key].variable == "LegacyForever_" .. key, key .. " has its own setting variable")
end
check(seen == 12, "all twelve settings are on the page")

-- The index buttons open their subpages, and never land in search.
local buttons = {}
for _, entry in ipairs(registered) do
	if entry.initializer.button then
		buttons[entry.initializer.name] = entry.initializer
	end
end
for _, name in ipairs(names) do
	buttons[name].click()
end
check(
	table.concat(opened, " ") == "World map Objective tracker What counts Hints and updates",
	"each button opens its subpage"
)

-- Quests grey out without Questie, as the map menu's box does, and the name and tooltip are translated.
local quests = byKey.count_quests
check(quests.name == "quests", "a category row is named by its label")
check(#registered[7].initializer.modify == 0, "only quests can grey out")
local questsRow
for _, entry in ipairs(registered) do
	if entry.initializer.setting == quests then
		questsRow = entry.initializer
	end
end
check(questsRow.modify[1](), "quests are usable while Questie is ready")
questsUsable = false
check(not questsRow.modify[1](), "quests grey out without Questie")
check(questsRow.tooltip() == "a quest source", "the quest row explains its status")

-- A row change redraws what the switch affects; a toggle elsewhere drives the row through the setting.
byKey.showAreas.changed()
check(refreshed == 1, "showing areas refreshes the map")
byKey.map.changed()
byKey.tracker.changed()
check(surfaceChanges == 2, "a surface row redraws the map and tracker")
byKey.count_areas.changed()
check(countChanges == 1, "a counted row re-checks rewards and redraws")
ns.SetOption("map", false)
check(surfaceChanges == 3, "the Legacy map menu's toggle drives the settings row")
ns.SetOption("missing", true)
check(surfaceChanges == 3, "an unregistered switch is left alone")

print(("settings_spec: %d checks passed"):format(checks))

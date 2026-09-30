---@type string, LegacyForeverNamespace
local _, ns = ...
local L = ns.L

-- Options -> AddOns -> Legacy Forever: a short index page, then a stock subpage per group so no page grows
-- tall. Every row goes in through Settings.RegisterInitializer, which inserts it from Blizzard's secure
-- delegate: Settings.CreateCheckbox inserts from our code instead, and the settings search reads every layout,
-- so that tainted it, and a restricted button in its results (Social's Discord Sign In) was then blocked and
-- blamed on this addon.
-- The Legacy map menu keeps its own toggles; they set the same switches through this page, so the two never
-- disagree.

-- The registered rows, so a toggle elsewhere (the Legacy map menu, the tracker's own menu) can set one
-- through the Settings setting and keep the page in step while it is open.
local settings = {}

---@param key string
---@param value boolean
function ns.SetOption(key, value)
	if settings[key] then
		settings[key]:SetValue(value)
	end
end

---@return table<string, boolean>
local function Database()
	LegacyForeverDB = LegacyForeverDB or {}
	return LegacyForeverDB
end

-- One switch: the same key, default and tooltip the Legacy map menu uses. `usable` greys the row out;
-- `changed` redraws whatever the switch affects. The row inserts from Blizzard's delegate.
---@param category SettingsCategoryMixin
---@param table_ table<string, boolean>
---@param key string
---@param name string
---@param default boolean
---@param tooltip? string|fun(): string?
---@param usable? fun(): boolean
---@param changed? fun()
local function AddCheckbox(category, table_, key, name, default, tooltip, usable, changed)
	local setting = Settings.RegisterAddOnSetting(
		category,
		"LegacyForever_" .. key,
		key,
		table_,
		Settings.VarType.Boolean,
		name,
		default
	)
	settings[key] = setting
	if changed then
		setting:SetValueChangedCallback(changed)
	end
	local initializer = Settings.CreateCheckboxInitializer(setting, nil, tooltip)
	if usable then
		initializer:AddModifyPredicate(usable)
	end
	Settings.RegisterInitializer(category, initializer)
end

-- A subpage and its button on the index, which opens it. The index stays out of search: the search finds
-- the settings themselves.
---@param category SettingsCategoryMixin
---@param name string
---@return SettingsCategoryMixin
local function Section(category, name)
	local subcategory = Settings.RegisterVerticalLayoutSubcategory(category, name)
	Settings.RegisterInitializer(
		category,
		CreateSettingsButtonInitializer(name, L["Open"], function()
			Settings.OpenToCategory(subcategory:GetID())
		end, nil, false)
	)
	return subcategory
end

local category = Settings.RegisterVerticalLayoutCategory(ns.TITLE)

local map = Section(category, L["World map"])
AddCheckbox(map, Database(), "showAreas", L["Show undiscovered areas"], ns.DEFAULTS.showAreas, nil, nil, function()
	-- The map may not have loaded yet; it refreshes itself when it does.
	if ns.RefreshMap then
		ns.RefreshMap()
	end
end)
AddCheckbox(
	map,
	ns.SavedTable("zoneCompletion"),
	"map",
	L["On the world map"],
	ns.DEFAULTS.zoneCompletion.map,
	L["The zone you're viewing in the map's corner, and a badge on each zone of a continent map."],
	nil,
	ns.Completion.SurfacesChanged
)

local tracker = Section(category, L["Objective tracker"])
local host = ns.TrackerHost
if host and host.GetSettings and host.SetAttached and host.OnAttachmentChanged then
	local variable = "LegacyForever_trackerAttached"
	local attachment = Settings.RegisterProxySetting(
		tracker,
		variable,
		Settings.VarType.Boolean,
		L["Attach to quest tracker"],
		true,
		function()
			return host.GetSettings().attached
		end,
		function(value)
			host.SetAttached(value)
		end
	)
	Settings.RegisterInitializer(
		tracker,
		Settings.CreateCheckboxInitializer(
			attachment,
			nil,
			L["Turn this off to drag the shared Forever tracker anywhere on screen."]
		)
	)
	host.OnAttachmentChanged(function()
		Settings.NotifyUpdate(variable)
	end)
end

AddCheckbox(
	tracker,
	ns.SavedTable("zoneCompletion"),
	"tracker",
	L["In the objective tracker"],
	ns.DEFAULTS.zoneCompletion.tracker,
	nil,
	nil,
	ns.Completion.SurfacesChanged
)

local counts = Section(category, L["What counts"])
for _, key in ipairs(ns.Model.COMPLETION_CATEGORIES) do
	local tooltip
	local usable
	if key == "quests" then
		tooltip = ns.Completion.QuestsStatusText
		usable = ns.Completion.QuestsUsable
	end
	AddCheckbox(
		counts,
		ns.SavedTable("zoneCompletion"),
		"count_" .. key,
		ns.Completion.Label(key),
		ns.DEFAULTS.zoneCompletion["count_" .. key],
		tooltip,
		usable,
		ns.Completion.CountsChanged
	)
end

local hints = Section(category, L["Hints and updates"])
AddCheckbox(hints, Database(), "whatsNew", L["Tell me what's new after an update"], ns.DEFAULTS.whatsNew)
AddCheckbox(
	hints,
	Database(),
	"companions",
	L["Suggest companion addons"],
	ns.DEFAULTS.companions,
	L["A grey line in a pin's tooltip when Shortest Path Forever would plot the route."]
)

Settings.RegisterAddOnCategory(category)

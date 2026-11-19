---@type string, LegacyForeverNamespace
local _, ns = ...
local L = ns.L

if ns.broken then
	return
end

-- Options -> AddOns -> Legacy Forever: a short index page, then a stock subpage per group so no page grows
-- tall. Every row goes in through Settings.RegisterInitializer, which inserts it from Blizzard's secure
-- delegate: Settings.CreateCheckbox inserts from our code instead, and the settings search reads every layout,
-- so that tainted it, and a restricted button in its results (Social's Discord Sign In) was then blocked and
-- blamed on this addon.
-- The Legacy map menu keeps its own toggles. Both ends go through ns.Saved, so the two never disagree.

local PREFIX = "LegacyForever_"

-- One switch: the same key, default and tooltip the Legacy map menu uses. The row is a proxy: it holds no
-- value of its own and reads and saves through ns.Saved, which redraws whatever the switch affects. `usable`
-- disables the control, which greys the row and leaves its tick box in place: an option this client cannot use
-- still reads, with its tooltip saying why. The row inserts from Blizzard's delegate.
---@param category SettingsCategoryMixin
---@param key string
---@param name string
---@param tooltip? string|fun(): string?
---@param usable? fun(): boolean
local function AddCheckbox(category, key, name, tooltip, usable)
	local setting = Settings.RegisterProxySetting(
		category,
		PREFIX .. key,
		Settings.VarType.Boolean,
		name,
		ns.Saved.Default(key),
		function()
			return ns.Saved.Get(key)
		end,
		function(value)
			ns.Saved.Set(key, value)
		end
	)
	local initializer = Settings.CreateCheckboxInitializer(setting, nil, tooltip)
	if usable then
		initializer:AddModifyPredicate(usable)
	end
	Settings.RegisterInitializer(category, initializer)
end

-- A switch saved from anywhere (the Legacy map menu, this page): its row reads the value again, so the page
-- stays in step while it is open. A switch with no row (a collapse state) has no setting to notify.
ns.Saved.OnChange(function(key)
	Settings.NotifyUpdate(PREFIX .. key)
end)

-- A subpage's button on the index, which opens it. The index stays out of search: the search finds the
-- settings themselves. The page opens through the shared secure opener: Settings.OpenToCategory is Blizzard's own
-- Lua around a restricted client call, which the client refuses from addon code (cjber/forever-core#333).
---@param category SettingsCategoryMixin
---@param subcategory SettingsCategoryMixin
---@param name string
---@return SettingsCategoryMixin
local function IndexButton(category, subcategory, name)
	Settings.RegisterInitializer(
		category,
		CreateSettingsButtonInitializer(name, L["Open"], function()
			ForeverCore.OpenSettingsPanel(subcategory:GetID())
		end, nil, false)
	)
	return subcategory
end

-- A subpage of rows and its button on the index.
---@param category SettingsCategoryMixin
---@param name string
---@return SettingsCategoryMixin
local function Section(category, name)
	return IndexButton(category, Settings.RegisterVerticalLayoutSubcategory(category, name), name)
end

local category = Settings.RegisterVerticalLayoutCategory(ns.TITLE)

local map = Section(category, L["World map"])
AddCheckbox(map, "showAreas", L["Show undiscovered areas"])
AddCheckbox(
	map,
	"showOutlines",
	L["Show where to discover areas"],
	L["Shades each undiscovered area's real ground, with a pin at its edge. Areas without terrain data keep the shading."]
)
AddCheckbox(
	map,
	"showEntrances",
	L["Show dungeon and raid entrances"],
	L["Turn this off if another addon already marks them. The Legacy map menu still lists them."]
)
AddCheckbox(
	map,
	"map",
	L["On the world map"],
	L["The zone you're viewing in the map's corner, and a badge on each zone of a continent map."]
)

local tracker = Section(category, L["Objective tracker"])
AddCheckbox(tracker, "showTracker", L["Tracked Legacy challenges"])
local host = ForeverCore.TrackerHost
if host and host.GetSettings and host.SetAttached and host.OnAttachmentChanged then
	-- The shared column's attach choice, the same row and words in every Forever addon (forever-core#910).
	local sections = ForeverCore.SettingsSections
	if sections and sections.RegisterTrackerAttach then
		sections.RegisterTrackerAttach(tracker, PREFIX .. "trackerAttached")
	end
	-- Lock keeps the detached column where it is: the grip ignores drag while it is on. It only writes the saved
	-- switch, so it is safe to toggle in combat.
	if host.SetLocked then
		local lock = Settings.RegisterProxySetting(
			tracker,
			PREFIX .. "trackerLocked",
			Settings.VarType.Boolean,
			L["Lock the tracker"],
			false,
			function()
				return host.GetSettings().locked == true
			end,
			function(value)
				host.SetLocked(value == true)
			end
		)
		Settings.RegisterInitializer(
			tracker,
			Settings.CreateCheckboxInitializer(
				lock,
				nil,
				L["Keeps the shared Forever tracker where you put it. The grip at its top no longer drags it."]
			)
		)
	end
end

-- Named in full: this page has no "Zone completion" title above the row, as the map menu has, and the Legacy
-- section of tracked challenges is not this switch's to hide.
AddCheckbox(
	tracker,
	"tracker",
	L["Zone completion in the tracker"],
	L["The zone you're in and what is left to do there. Challenges you track keep their own Legacy section."]
)

local counts = Section(category, L["What counts"])
for _, key in ipairs(ns.Model.COMPLETION_CATEGORIES) do
	local tooltip
	local usable
	if key == "quests" then
		tooltip = ns.Completion.QuestsStatusText
		usable = ns.Completion.QuestsUsable
	end
	AddCheckbox(counts, "count_" .. key, ns.Completion.Label(key), tooltip, usable)
	if key == "quests" then
		-- Named short: the page draws a row's label up to 85 px left of its centre and cuts what is longer, so a
		-- full sentence runs into the tick box. The explanation stays in the tooltip.
		AddCheckbox(
			counts,
			"accountQuests",
			L["Count account quests"],
			ns.Completion.AccountQuestsStatusText,
			ns.Live.AccountQuestsUsable
		)
	end
end

local updates = Section(category, L["Updates"])
AddCheckbox(updates, "whatsNew", L["What's new after an update"])

Settings.RegisterAddOnCategory(category)

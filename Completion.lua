---@type string, LegacyForeverNamespace
local addonName, ns = ...

-- Zone completion, Guild Wars 2 style: how much of a zone's areas, flight paths, dungeons, raids,
-- Legacy objectives, local reputations and quests are done, as a section in the objective tracker
-- (the zone you're in) and in the world map's corner (the zone you're viewing). Each is optional and
-- collapsible.
---@class LegacyCompletion
local Completion = {}
ns.Completion = Completion

---@type table<LegacyCategoryKey, { atlas?: string, file?: string, aspect?: number }>
local ICONS = {
	areas = { atlas = "islands-queue-prop-compass" },
	taxis = { atlas = "flightmaster" },
	dungeons = { atlas = "dungeon" },
	raids = { atlas = "raid" },
	legacy = { atlas = "UI-Legacy-Points-icon-c60", aspect = 50 / 73 },
	-- No atlas reads as reputation, so the classic handshake icon, trimmed of its border.
	reputations = { file = "Interface\\Icons\\Achievement_Reputation_01" },
	quests = { atlas = "QuestNormal" },
}
local LABELS = {
	areas = "Areas explored",
	taxis = "Flight paths",
	dungeons = "Dungeons",
	raids = "Raids",
	legacy = "Legacy objectives",
	reputations = "Reputations (Friendly)",
	quests = "Quests",
}
-- Names listed per category in a tooltip before "and N more".
local MAX_LEFT = 6
-- Remaining names listed under the tracker's counts before "...", matching the challenge section.
local MAX_TRACKER_LEFT = 5

---@return LegacySettings
local function Settings()
	return ns.SavedTable("zoneCompletion")
end

---@type (fun())[]
local listeners = {}

-- The map is on out of the box so the feature is visible; the tracker takes screen space, so it waits to be asked.
local DEFAULT_SHOWN = { tracker = false, map = true }

---@param surface LegacySurface
---@return boolean
local function IsShown(surface)
	local shown = Settings()[surface]
	if shown == nil then
		return DEFAULT_SHOWN[surface]
	end
	return shown
end

-- Out of the box only Legacy objectives count: areas (each an "Explore <zone>" step toward
-- Explorer), Spelunker dungeons, Conqueror raids and the zone's other Legacy steps. No Legacy
-- challenge asks for flight paths, these reputations or quests, so they wait under "What counts" to
-- be ticked. The saved setting is nil until the player ticks or unticks it, so a choice made
-- before these defaults keeps its saved true or false.
local COUNTED_BY_DEFAULT = {
	areas = true,
	taxis = false,
	dungeons = true,
	raids = true,
	legacy = true,
	reputations = false,
	quests = false,
}

---@param category LegacyCategoryKey
---@return boolean
local function IsCounted(category)
	local counted = Settings()["count_" .. category]
	if counted == nil then
		return COUNTED_BY_DEFAULT[category]
	end
	return counted
end

local function Refresh()
	for _, callback in ipairs(listeners) do
		callback()
	end
end

---@type (fun())[]
local toggleListeners = {}

-- For what other files draw under these switches: the continent map's zone badges follow "map".
---@param callback fun()
function Completion.OnToggle(callback)
	toggleListeners[#toggleListeners + 1] = callback
end

---@return boolean
function Completion.ShownOnMap()
	return IsShown("map")
end

---@param surface LegacySurface
local function Toggle(surface)
	Settings()[surface] = not IsShown(surface)
	Refresh()
	for _, callback in ipairs(toggleListeners) do
		callback()
	end
end

Completion.IsCounted = IsCounted

-- For readers outside the map and tracker (API.lua): called whenever the counts or what counts may have changed.
---@param callback fun()
function Completion.OnRefresh(callback)
	listeners[#listeners + 1] = callback
end

-- A zone's completion, even when nothing counts; nil for a map without completion data.
-- `deferred` reads the zone's quests without building QuestieDB's index (see Quests.Zone).
---@param uiMapID number?
---@param deferred? boolean
---@return LegacyZoneResult?
function Completion.Result(uiMapID, deferred)
	local zone = uiMapID and ns.Data.completion[uiMapID]
	if not uiMapID or not zone then
		return nil
	end
	local snapshot = ns.Live.ZoneSnapshot(uiMapID)
	if deferred then
		snapshot = {
			explored = snapshot.explored,
			taxis = snapshot.taxis,
			faction = snapshot.faction,
			refsDone = snapshot.refsDone,
			reaction = snapshot.reaction,
			completed = snapshot.completed,
			quests = function()
				return ns.Quests.Zone(uiMapID, true)
			end,
		}
	end
	return ns.Model.ZoneCompletion(zone, snapshot, IsCounted)
end

---@param uiMapID number?
---@return LegacyZoneResult?
function Completion.Of(uiMapID)
	local result = Completion.Result(uiMapID)
	return result and result.total > 0 and result or nil
end

---@param key LegacyCategoryKey
---@param size number
---@return string
function Completion.Icon(key, size)
	local icon = ICONS[key]
	if icon.file then
		return ("|T%s:%d:%d:0:0:64:64:5:59:5:59|t"):format(icon.file, size, size)
	end
	return CreateAtlasMarkup(icon.atlas, math.floor(size * (icon.aspect or 1) + 0.5), size)
end

-- What the player does to resolve a category's pending items.
local PENDING_HINTS = {
	taxis = "Open a flight master on this continent to check these.",
	quests = "Waiting for Questie and your quest log.",
}

---@param result LegacyZoneResult
---@return string
local function PercentText(result)
	return ("%d%%"):format(result.percent)
end

-- "3/5", or "?" while every item is pending; `colored` greens a finished category.
---@param category LegacyCategory
---@param colored? boolean
---@return string
local function CategoryText(category, colored)
	if category.total == 0 then
		return GRAY_FONT_COLOR:WrapTextInColorCode("?")
	end
	local text = ("%d/%d"):format(category.done, category.total)
	if category.pending > 0 then
		text = text .. " +?"
	end
	if not colored then
		return text
	end
	local color = category.complete and GREEN_FONT_COLOR or HIGHLIGHT_FONT_COLOR
	return color:WrapTextInColorCode(text)
end

-- "[compass] 9/14   [gryphon] 1/1   [door] 0/1", a finished category in green.
---@param result LegacyZoneResult
---@param iconSize number
---@return string
local function CountsText(result, iconSize)
	local parts = {}
	for _, key in ipairs(ns.Model.COMPLETION_CATEGORIES) do
		local category = result[key]
		if category then
			parts[#parts + 1] = ("%s %s"):format(Completion.Icon(key, iconSize), CategoryText(category, true))
		end
	end
	return table.concat(parts, "   ")
end

---@param tooltip GameTooltip
---@param name string
---@param result LegacyZoneResult
local function AddTooltip(tooltip, name, result)
	GameTooltip_SetTitle(tooltip, ("%s  %s"):format(name, PercentText(result)))
	for _, key in ipairs(ns.Model.COMPLETION_CATEGORIES) do
		local category = result[key]
		if category then
			tooltip:AddDoubleLine(
				("%s %s"):format(Completion.Icon(key, 14), LABELS[key]),
				CategoryText(category),
				NORMAL_FONT_COLOR.r,
				NORMAL_FONT_COLOR.g,
				NORMAL_FONT_COLOR.b,
				HIGHLIGHT_FONT_COLOR.r,
				HIGHLIGHT_FONT_COLOR.g,
				HIGHLIGHT_FONT_COLOR.b
			)
			for index, left in ipairs(category.left) do
				if index > MAX_LEFT then
					GameTooltip_AddDisabledLine(tooltip, ("    and %d more"):format(#category.left - MAX_LEFT))
					break
				end
				GameTooltip_AddColoredLine(tooltip, "    " .. left, WHITE_FONT_COLOR)
			end
			if category.pending > 0 then
				local line = ("    %d not known yet."):format(category.pending)
				GameTooltip_AddDisabledLine(tooltip, PENDING_HINTS[key] and line .. " " .. PENDING_HINTS[key] or line)
			end
		end
	end
	if result.dungeons or result.raids or result.legacy then
		GameTooltip_AddDisabledLine(
			tooltip,
			"Dungeons, raids and Legacy objectives count your progress on any character."
		)
	end
end

-- A thin fill for the percent, in the tracker's gold; green once the zone is done.
local BAR_HEIGHT = 2

---@param parent Frame
---@return StatusBar
local function CreateProgressBar(parent)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetHeight(BAR_HEIGHT)
	bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
	bar:SetMinMaxValues(0, 100)
	local background = bar:CreateTexture(nil, "BACKGROUND")
	background:SetAllPoints()
	background:SetColorTexture(0, 0, 0, 0.45)
	return bar
end

---@param bar StatusBar
---@param result LegacyZoneResult
local function SetProgress(bar, result)
	bar:SetValue(result.percent)
	bar:SetStatusBarColor((result.complete and GREEN_FONT_COLOR or NORMAL_FONT_COLOR):GetRGB())
end

--[[ Objective tracker: the zone you're in ]]

---@class LegacyCompletionTracker : LegacyTrackerModule
local TrackerMixin = {}

function TrackerMixin:LayoutContents()
	local uiMapID = IsShown("tracker") and ns.Live.CurrentZone() or nil
	local result = Completion.Of(uiMapID)
	if not uiMapID or not result then
		return
	end
	self:SetHeader(C_Map.GetMapInfo(uiMapID).name)
	self.Header.Percent:SetText(PercentText(result))
	SetProgress(self.Header.Progress, result)
	local block = self:GetBlock(uiMapID)
	block:SetHeader(CountsText(result, 14))
	local shown = 0
	for _, key in ipairs(ns.Model.COMPLETION_CATEGORIES) do
		local category = result[key]
		for _, left in ipairs(category and category.left or {}) do
			if shown == MAX_TRACKER_LEFT then
				block:AddObjective("Extra", "...", nil, nil, OBJECTIVE_DASH_STYLE_HIDE)
				self:LayoutBlock(block)
				return
			end
			shown = shown + 1
			block:AddObjective(shown, ("%s %s"):format(Completion.Icon(key, 12), left))
		end
	end
	self:LayoutBlock(block)
end

---@param block LegacyTrackerBlock
function TrackerMixin:OnBlockHeaderEnter(block)
	local result = Completion.Of(block.id)
	if result then
		GameTooltip:SetOwner(block, "ANCHOR_LEFT")
		AddTooltip(GameTooltip, C_Map.GetMapInfo(block.id).name, result)
		GameTooltip_AddInstructionLine(GameTooltip, "Click to open the map. Right-click for options.")
		GameTooltip:Show()
	end
end

function TrackerMixin:OnBlockHeaderLeave()
	GameTooltip:Hide()
end

-- Right-click opens a menu, as on the Legacy section.
---@param block LegacyTrackerBlock
---@param mouseButton string
function TrackerMixin:OnBlockHeaderClick(block, mouseButton)
	if mouseButton ~= "RightButton" then
		OpenWorldMap(block.id)
		return
	end
	MenuUtil.CreateContextMenu(self:GetContextMenuParent(), function(_, root)
		root:SetTag("MENU_LEGACY_HERE_ZONE_TRACKER", block)
		root:CreateTitle(C_Map.GetMapInfo(block.id).name)
		root:CreateButton("Open the map", function()
			OpenWorldMap(block.id)
		end)
		root:CreateButton("Hide from the tracker", function()
			Toggle("tracker")
		end)
	end)
end

local trackerModule = ns.Tracker.AddModule("LegacyForeverZoneTracker", TrackerMixin, -1)
if trackerModule then
	local header = trackerModule.Header
	header.Percent = header:CreateFontString(nil, "ARTWORK", "ObjectiveTrackerHeaderFont")
	header.Percent:SetPoint("RIGHT", header.MinimizeButton, "LEFT", -4, 0)
	-- Along the header art's own underline, under the zone name and percent.
	header.Progress = CreateProgressBar(header)
	header.Progress:SetPoint("BOTTOMLEFT", 7, 1)
	header.Progress:SetPoint("BOTTOMRIGHT", header.Percent, "BOTTOMRIGHT", 0, 1)
	-- Deferred so the collapse state is restored even on a client that ignores LoadSavedVariablesFirst.
	EventUtil.ContinueOnAddOnLoaded(addonName, function()
		trackerModule:SetCollapsed(Settings().trackerCollapsed == true)
		hooksecurefunc(trackerModule, "SetCollapsed", function(_, collapsed)
			Settings().trackerCollapsed = collapsed
		end)
	end)
	listeners[#listeners + 1] = function()
		trackerModule:MarkDirty()
	end
end

--[[ World map: the zone you're viewing, in the corner; on a continent, in each zone badge's tooltip ]]

---@class LegacyForeverZoneOverlayMixin : Button
---@field GetParent fun(self: LegacyForeverZoneOverlayMixin): WorldMapFrame
---@field Title FontString
---@field Counts FontString
---@field Progress StatusBar
---@field result? LegacyZoneResult
---@field name string
LegacyForeverZoneOverlayMixin = {}

-- Room for the text, the bar and a fade on the right, so it never looks boxed.
local OVERLAY_MIN_WIDTH = 140

function LegacyForeverZoneOverlayMixin:OnLoad()
	self.Progress = CreateProgressBar(self)
	self.Progress:SetPoint("TOPLEFT", self.Title, "BOTTOMLEFT", 0, -4)
	self.Progress:SetPoint("RIGHT")
end

-- Called by the world map whenever it changes map.
function LegacyForeverZoneOverlayMixin:Refresh()
	---@type WorldMapFrame
	local map = self:GetParent()
	local uiMapID = map:GetMapID()
	self.result = IsShown("map") and Completion.Of(uiMapID) or nil
	if not self.result then
		self:Hide()
		return
	end
	local collapsed = Settings().mapCollapsed == true
	self.name = C_Map.GetMapInfo(uiMapID).name
	self.Title:SetText(("%s  %s"):format(self.name, PercentText(self.result)))
	SetProgress(self.Progress, self.result)
	self.Counts:SetText(CountsText(self.result, 16))
	self.Counts:SetShown(not collapsed)
	local height = self.Title:GetStringHeight() + 4 + BAR_HEIGHT
	if not collapsed then
		height = height + 6 + self.Counts:GetStringHeight()
	end
	local width = math.max(self.Title:GetStringWidth(), OVERLAY_MIN_WIDTH)
	if not collapsed then
		width = math.max(width, self.Counts:GetStringWidth())
	end
	self:SetSize(width, height)
	self:Show()
end

function LegacyForeverZoneOverlayMixin:OnClick()
	Settings().mapCollapsed = not Settings().mapCollapsed
	self:Refresh()
	self:OnEnter()
end

function LegacyForeverZoneOverlayMixin:OnEnter()
	GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
	AddTooltip(GameTooltip, self.name, self.result)
	GameTooltip_AddInstructionLine(GameTooltip, Settings().mapCollapsed and "Click to expand." or "Click to collapse.")
	GameTooltip:Show()
end

function LegacyForeverZoneOverlayMixin:OnLeave()
	GameTooltip:Hide()
end

-- Closing the map hides the overlay without an OnLeave.
function LegacyForeverZoneOverlayMixin:OnHide()
	if GameTooltip:GetOwner() == self then
		GameTooltip:Hide()
	end
end

-- The map refreshes providers on show and on every map change, but its overlay frames
-- only on a map change, so a provider keeps the corner current.
---@param overlay LegacyForeverZoneOverlayMixin
---@return MapCanvasDataProviderMixin
local function CreateProvider(overlay)
	local provider = CreateFromMixins(MapCanvasDataProviderMixin)

	function provider:RefreshAllData()
		overlay:Refresh()
	end

	return provider
end

local function AttachMap()
	local map = WorldMapFrame
	-- Right of the floor dropdown and Camelot's tracking pin button, which share the corner.
	---@type LegacyForeverZoneOverlayMixin
	local overlay = map:AddOverlayFrame(
		"LegacyForeverZoneOverlayTemplate",
		"BUTTON",
		"TOPLEFT",
		map:GetCanvasContainer(),
		"TOPLEFT",
		44,
		-18
	)
	local provider = CreateProvider(overlay)
	map:AddDataProvider(provider)
	listeners[#listeners + 1] = function()
		if map:IsShown() then
			provider:RefreshAllData()
		end
	end
end

EventUtil.ContinueOnAddOnLoaded("Blizzard_WorldMap", AttachMap)
ns.Live.OnChange(Refresh)

--[[ A zone reaching 100%: a toast and a sound, GW2 style ]]

-- The reward follows "What counts", as the percentage does, so 100% on screen is what earns it.
-- Unticking a category isn't progress, so a zone that completes is noted without a toast.
---@param uiMapID number
---@return boolean
local function IsZoneComplete(uiMapID)
	local result = ns.Model.ZoneCompletion(ns.Data.completion[uiMapID], ns.Live.ZoneSnapshot(uiMapID), IsCounted)
	return ns.Model.CompletionCounts(result) and result.complete
end

-- "Kalimdor: 3 of 20 zones complete (15%)", counting what the player counts.
---@param continentID number
---@return string?
local function ContinentText(continentID)
	local results = {}
	for uiMapID, zone in pairs(ns.Data.completion) do
		if ns.Live.ContinentOf(uiMapID) == continentID then
			results[#results + 1] = ns.Model.ZoneCompletion(zone, ns.Live.ZoneSnapshot(uiMapID), IsCounted)
		end
	end
	local continent = ns.Model.ContinentCompletion(results)
	local info = C_Map.GetMapInfo(continentID)
	if not continent or not info then
		return nil
	end
	return ("%s: %d of %d zones complete (%d%%)"):format(
		info.name,
		continent.complete,
		continent.zones,
		continent.percent
	)
end

---@param frame LegacyToast
---@param button string
---@param down boolean
local function OnToastClick(frame, button, down)
	if not AlertFrame_OnClick(frame, button, down) then
		OpenWorldMap(frame.uiMapID)
	end
end

-- Blizzard's own achievement-progress toast, so it queues and stacks with the game's alerts.
---@param frame LegacyToast
---@param uiMapID number
local function SetUpToast(frame, uiMapID)
	frame.uiMapID = uiMapID
	frame.Unlocked:SetText("Zone complete")
	frame.Name:SetText(C_Map.GetMapInfo(uiMapID).name)
	frame.Icon.Texture:SetAtlas(ICONS.areas.atlas)
	frame:SetScript("OnClick", OnToastClick)
	PlaySound(SOUNDKIT.UI_SCENARIO_STAGE_END)
	local continent = ns.Live.ContinentOf(uiMapID)
	local line = continent and ContinentText(continent)
	if line then
		ns.Print(("%s complete. %s"):format(C_Map.GetMapInfo(uiMapID).name, line))
	end
end

local toasts = AlertFrame:AddQueuedAlertFrameSubSystem("CriteriaAlertFrameTemplate", SetUpToast, 2, 6)

-- Zones already complete when you log in are not news. The first check (on entering the
-- world, however long the loading screen took) and those in the few seconds after it, while
-- the game is still sending achievement progress, only note completions.
local QUIET_SECONDS = 10
local quietUntil
local rewarded = {}

---@param silent? boolean
local function CheckRewards(silent)
	quietUntil = quietUntil or GetTime() + QUIET_SECONDS
	local quiet = silent or GetTime() < quietUntil
	for uiMapID in pairs(ns.Data.completion) do
		if not rewarded[uiMapID] and IsZoneComplete(uiMapID) then
			rewarded[uiMapID] = true
			-- Someone who has switched zone completion off entirely doesn't want its toasts.
			if not quiet and (IsShown("map") or IsShown("tracker")) then
				toasts:AddAlert(uiMapID)
			end
		end
	end
end

ns.Live.OnChange(CheckRewards)

--[[ Settings, in the Legacy map menu ]]

---@param category LegacyCategoryKey
local function ToggleCounted(category)
	Settings()["count_" .. category] = not IsCounted(category)
	CheckRewards(true)
	Refresh()
end

-- A zone's completion under a continent badge's tooltip: percent, then one row of counts.
---@param tooltip GameTooltip
---@param uiMapID number
function Completion.AddSummary(tooltip, uiMapID)
	local result = IsShown("map") and Completion.Of(uiMapID) or nil
	if not result then
		return
	end
	GameTooltip_AddBlankLineToTooltip(tooltip)
	tooltip:AddDoubleLine(
		"Zone completion",
		PercentText(result),
		NORMAL_FONT_COLOR.r,
		NORMAL_FONT_COLOR.g,
		NORMAL_FONT_COLOR.b,
		HIGHLIGHT_FONT_COLOR.r,
		HIGHLIGHT_FONT_COLOR.g,
		HIGHLIGHT_FONT_COLOR.b
	)
	GameTooltip_AddHighlightLine(tooltip, CountsText(result, 14))
	local continent = ns.Live.ContinentOf(uiMapID)
	local line = continent and ContinentText(continent)
	if line then
		GameTooltip_AddNormalLine(tooltip, line)
	end
end

-- Quests are read from QuestieDB, which comes with Questie, so they can only be counted with it installed.
---@return boolean
local function QuestsUsable()
	local status = ns.Quests.Status()
	return status == "ready" or status == "loading"
end

local QUESTS_STATUS = {
	ready = "Every quest this character can take in the zone, from Questie. Repeatable, holiday and "
		.. "profession quests are left out.",
	loading = "Waiting for Questie to finish loading.",
	missing = "Needs Questie, which lists each zone's quests.",
	unsupported = "This version of Questie isn't supported.",
}

---@param tooltip GameTooltip
local function QuestsTooltip(tooltip)
	GameTooltip_SetTitle(tooltip, LABELS.quests)
	GameTooltip_AddNormalLine(tooltip, QUESTS_STATUS[ns.Quests.Status()])
end

---@param root SharedMenuDescriptionProxy
function Completion.AddMenu(root)
	root:CreateTitle("Zone completion")
	root:CreateCheckbox("In the objective tracker", IsShown, Toggle, "tracker")
	local map = root:CreateCheckbox("On the world map", IsShown, Toggle, "map")
	map:SetTooltip(function(tooltip)
		GameTooltip_SetTitle(tooltip, "On the world map")
		GameTooltip_AddNormalLine(
			tooltip,
			"The zone you're viewing in the map's corner, and a badge on each zone of a continent map."
		)
	end)
	local counts = root:CreateButton("What counts")
	for _, key in ipairs(ns.Model.COMPLETION_CATEGORIES) do
		local box = counts:CreateCheckbox(
			("%s %s"):format(Completion.Icon(key, 14), LABELS[key]),
			IsCounted,
			ToggleCounted,
			key
		)
		if key == "quests" then
			box:SetEnabled(QuestsUsable)
			box:SetTooltip(QuestsTooltip)
		end
	end
end

-- For /lf audit: the current zone's counts against what the game reports.
function Completion.Audit()
	local uiMapID = ns.Live.CurrentZone()
	if not uiMapID then
		ns.Print("zone completion: no data for the zone you're in.")
		return
	end
	local zone = ns.Data.completion[uiMapID]
	local snapshot = ns.Live.ZoneSnapshot(uiMapID)
	local result = ns.Model.ZoneCompletion(zone, snapshot)
	local parts = {}
	for _, key in ipairs(ns.Model.COMPLETION_CATEGORIES) do
		local category = result[key]
		parts[#parts + 1] = category and ("%s %d/%d"):format(key, category.done, category.total) or (key .. " -")
	end
	ns.Print(("quests from QuestieDB: %s"):format(ns.Quests.Failure() or ns.Quests.Status()))
	ns.Print(
		("zone completion for %s (map %d): %s"):format(
			C_Map.GetMapInfo(uiMapID).name,
			uiMapID,
			table.concat(parts, ", ")
		)
	)

	local known = {}
	for _, area in ipairs(zone.areas) do
		known[area.key] = true
	end
	for key in pairs(snapshot.explored) do
		if not known[key] then
			ns.Print("  explored area not in the data: " .. key)
		end
	end
	if next(snapshot.explored) == nil then
		ns.Print("  the game reports nothing explored in this zone")
	end

	for _, taxi in ipairs(zone.taxis) do
		if taxi.faction == "Neutral" or taxi.faction == snapshot.faction then
			local learned = snapshot.taxis[taxi.node]
			local state = learned == nil and "unknown until you open a flight master on this continent"
				or learned and "known"
				or "not known"
			ns.Print(("  flight path %d (%s): %s"):format(taxi.node, taxi.name, state))
		end
	end
end

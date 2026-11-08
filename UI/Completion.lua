---@type string, LegacyForeverNamespace
local addonName, ns = ...
local L = ns.L

-- Zone completion, Guild Wars 2 style: how much of a zone's areas, flight paths, dungeons, raids,
-- Legacy objectives, local reputations and quests are done, as a section in the objective tracker
-- (the zone you're in), in a corner of the world map (the zone you're viewing) and in each zone badge's
-- tooltip on a continent map. The counting, what counts and when a completion is news are
-- Core/ZoneCompletion.lua's; this file draws them.
---@class LegacyCompletion
local Completion = {}
ns.Completion = Completion

-- One family of world map icons where the client has one: the quest log's dungeon glyph, the flight
-- master's node, the map's quest giver and raid entrance. Areas, reputations and Legacy objectives have no
-- pin of their own, so they keep the art that reads as those things.
---@type table<LegacyCategoryKey, { atlas?: string, file?: string }>
local ICONS = {
	areas = { atlas = "islands-queue-prop-compass" },
	taxis = { atlas = "taxinode_neutral" },
	dungeons = { atlas = "questlog-questtypeicon-dungeon" },
	-- The map's own raid entrance pin (MapLegendPinDefinitions.Raid).
	raids = { atlas = "Raid" },
	legacy = { atlas = ns.POINTS_ICON },
	-- No atlas reads as reputation, so the classic handshake icon, trimmed of its border.
	reputations = { file = "Interface\\Icons\\Achievement_Reputation_01" },
	quests = { atlas = "QuestNormal" },
}
local LABELS = {
	areas = L["Areas explored"],
	taxis = L["Flight paths"],
	dungeons = DUNGEONS,
	raids = RAIDS,
	legacy = L["Legacy objectives"],
	reputations = L["Reputations (Friendly)"],
	quests = QUESTS_LABEL,
}
-- Adventure Guide Forever's folder, for the zone tooltip's suggestion.
local ADVENTURE_GUIDE = "AdventureGuideForever"
-- Names listed per category in a tooltip before "and N more".
local MAX_LEFT = 6
-- Remaining names listed under the tracker's counts before "...", matching the challenge section.
local MAX_TRACKER_LEFT = 5

local Zones = ns.ZoneCompletion
local IsShown, IsCounted = Zones.IsShown, Zones.IsCounted

---@param surface LegacySurface
local function Toggle(surface)
	ns.Saved.Set(surface, not IsShown(surface))
end

---@param key LegacyCategoryKey
---@param size number
---@return string
function Completion.Icon(key, size)
	local icon = ICONS[key]
	if icon.file then
		-- art-ok: a 64x64 file icon cropped to its square middle, in a square
		return ("|T%s:%d:%d:0:0:64:64:5:59:5:59|t"):format(icon.file, size, size)
	end
	return ns.Art.Markup(icon.atlas --[[@as string]], size)
end

---@param category LegacyCategoryKey
---@return string
function Completion.Label(category)
	return LABELS[category]
end

-- What the player does to resolve a category's pending items.
local PENDING_HINTS = {
	taxis = L["Open a flight master on this continent to check these."],
	quests = L["Waiting for Questie and your quest log."],
}

---@param result LegacyZoneResult
---@return string
local function PercentText(result)
	if not result.percent then
		return GRAY_FONT_COLOR:WrapTextInColorCode("?")
	end
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

-- "[compass] 9/14   [gryphon] 1/1   [portal] 0/1", a finished category in green.
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
					GameTooltip_AddDisabledLine(tooltip, "    " .. L["and %d more"]:format(#category.left - MAX_LEFT))
					break
				end
				GameTooltip_AddColoredLine(tooltip, "    " .. left, WHITE_FONT_COLOR)
			end
			if category.pending > 0 then
				local line = "    " .. L["%d not known yet."]:format(category.pending)
				GameTooltip_AddDisabledLine(tooltip, PENDING_HINTS[key] and line .. " " .. PENDING_HINTS[key] or line)
			end
		end
	end
	if result.dungeons or result.raids or result.legacy then
		GameTooltip_AddDisabledLine(
			tooltip,
			L["Dungeons, raids and Legacy objectives count your progress on any character."]
		)
	end
	-- Zone completion counts what is left in a zone; Adventure Guide Forever plans its quests. A quiet line on a
	-- zone not yet done, while it is not installed, behind the shared "Suggest my other Forever addons" switch.
	if not result.complete and ns.Family.Hint(ns.FamilyDB(), "LegacyForever.zoneAdventureGuide", ADVENTURE_GUIDE) then
		GameTooltip_AddDisabledLine(tooltip, L["Adventure Guide Forever routes the quests left in this zone."])
	end
end

-- The objective tracker's own progress bar (Blizzard_ObjectiveTrackerShared.xml's
-- ObjectiveTrackerProgressBarTemplate): the 15-unit fill in its blue, the 9 by 22 UI-Character-Skills-BarBorder
-- caps hanging 3 units outside each end at their native size, and the percent centred on the fill. The template is
-- virtual and usable on its own, so the section inherits it and only points its bar across the section.
local BAR_HEIGHT = 15
-- The fill's top under the header band, its 3.5-unit cap overhang, and the gap before the counts row.
local BAR_TOP, BAR_CAP, BAR_GAP = 7, 3.5, 6
-- The caps sit 3 units outside the fill, which keeps them inside the section's width.
local BAR_INSET = 3

---@param parent Frame
---@return LegacyZoneProgressBar
local function CreateProgressBar(parent)
	local progress = CreateFrame("Frame", nil, parent, "ObjectiveTrackerProgressBarTemplate")
	---@cast progress LegacyZoneProgressBar
	progress:SetHeight(BAR_HEIGHT)
	local bar = progress.Bar
	bar:ClearAllPoints()
	bar:SetPoint("TOPLEFT", progress, "TOPLEFT", BAR_INSET, 0)
	bar:SetPoint("BOTTOMRIGHT", progress, "BOTTOMRIGHT", -BAR_INSET, 0)
	progress:Show()
	return progress
end

---@param progress LegacyZoneProgressBar
---@param result LegacyZoneResult
local function SetProgress(progress, result)
	if result.percent then
		progress:SetPercent(result.percent)
	else
		progress.Bar:SetValue(0)
		progress.Bar.Label:SetText(GRAY_FONT_COLOR:WrapTextInColorCode("?"))
	end
end

--[[ Objective tracker: the zone you're in ]]

---@class LegacyCompletionTracker : LegacyTrackerModule
local TrackerMixin = {}

function TrackerMixin:LayoutContents()
	local uiMapID = IsShown("tracker") and ns.Live.CurrentZone() or nil
	local result = Zones.Of(uiMapID)
	if not uiMapID or not result then
		return
	end
	self:SetHeader(C_Map.GetMapInfo(uiMapID).name)
	SetProgress(self.Header.Progress, result)
	local block = self:GetBlock(uiMapID)
	block:SetHeader(CountsText(result, 16))
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
	local result = Zones.Of(block.id)
	if result then
		GameTooltip:SetOwner(block, "ANCHOR_LEFT")
		AddTooltip(GameTooltip, C_Map.GetMapInfo(block.id).name, result)
		GameTooltip_AddInstructionLine(GameTooltip, L["Click to open the map. Right-click for options."])
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
		C_Map.OpenWorldMap(block.id)
		return
	end
	MenuUtil.CreateContextMenu(self:GetContextMenuParent(), function(_, root)
		root:SetTag("MENU_LEGACY_HERE_ZONE_TRACKER", block)
		root:CreateTitle(C_Map.GetMapInfo(block.id).name)
		root:CreateButton(L["Open the map"], function()
			C_Map.OpenWorldMap(block.id)
		end)
		root:CreateButton(L["Hide from the tracker"], function()
			Toggle("tracker")
		end)
	end)
end

-- -5 is the next free family tracker slot and puts the zone above every other Forever section. The shared
-- column lays sections out in uiOrder and gives each the room the ones above it left, and a native module is hidden
-- whole when its one block does not fit: at -1 this section came after Adventure Guide Forever's story and journey
-- sections and never drew when they filled the column below the quests. It still sorts above the tracked
-- challenges' blocks, which are 0.
local trackerModule = ns.Tracker.AddModule("LegacyForeverZoneTracker", TrackerMixin, -5)
if trackerModule then
	local header = trackerModule.Header
	-- The bar's own row under the header band, then the counts row; the module's layout places the first block
	-- below both. The percent sits in the bar's own Label, as the game's tracker draws it.
	trackerModule.fromHeaderOffsetY = -(BAR_TOP + BAR_HEIGHT + BAR_CAP + BAR_GAP)
	header.Progress = CreateProgressBar(header)
	header.Progress:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -BAR_TOP)
	header.Progress:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -BAR_TOP)
	-- Deferred so the collapse state is restored even on a client that ignores LoadSavedVariablesFirst.
	EventUtil.ContinueOnAddOnLoaded(addonName, function()
		trackerModule:SetCollapsed(ns.Saved.Get("trackerCollapsed"))
		local function SaveCollapse(_, collapsed)
			ns.Saved.Set("trackerCollapsed", collapsed)
		end
		hooksecurefunc(trackerModule, "SetCollapsed", SaveCollapse) -- taint-ok: addon-owned tracker
	end)
	Zones.OnChange(function()
		trackerModule:MarkDirty()
	end)
end

--[[ World map: the zone you're viewing, in the corner that covers least of it; on a continent, in each zone
     badge's tooltip ]]

-- A thin fill for the percent, black behind it, green once the zone is done.
local OVERLAY_BAR_HEIGHT = 2
-- Room for the text and the bar, so it never looks boxed.
local OVERLAY_MIN_WIDTH = 140

---@param parent Frame
---@return StatusBar
local function CreateCornerBar(parent)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetHeight(OVERLAY_BAR_HEIGHT)
	bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
	bar:SetMinMaxValues(0, 100)
	local background = bar:CreateTexture(nil, "BACKGROUND")
	background:SetAllPoints()
	background:SetColorTexture(0, 0, 0, 0.45)
	return bar
end

---@param bar StatusBar
---@param result LegacyZoneResult
local function SetCornerProgress(bar, result)
	bar:SetValue(result.percent or 0)
	bar:SetStatusBarColor((result.complete and GREEN_FONT_COLOR or NORMAL_FONT_COLOR):GetRGB())
end

-- The Legacy pins a zone's map places: every placed objective, including a cleared entrance drawn faded.
---@param uiMapID number
---@return LegacyCornerPin[]
local function Pins(uiMapID)
	local pins = {}
	local groups = ns.Model.ZoneObjectives(ns.Data, uiMapID, ns.Live.Visible(), ns.Live.Criteria, true)
	for _, group in ipairs(groups) do
		for _, objective in ipairs(group.objectives) do
			local entry = objective.entry
			if entry.kind ~= "explore" and entry.x and entry.y then
				pins[#pins + 1] = { x = entry.x, y = entry.y }
			end
		end
	end
	return pins
end

-- The corner this zone's box sits in, from the map's own geometry (Core/ZoneCompletion.lua judges it).
---@param uiMapID number
---@param map WorldMapFrame
---@param width number
---@param height number
---@return { point: string, x: number, y: number }
local function Corner(uiMapID, map, width, height)
	local canvas = map:GetCanvas()
	local container = map:GetCanvasContainer()
	---@type LegacyCornerGeometry
	local geometry = {
		containerWidth = container:GetWidth(),
		containerHeight = container:GetHeight(),
		mapWidth = canvas:GetWidth(),
		mapHeight = canvas:GetHeight(),
	}
	return Zones.Corner(uiMapID, width, height, geometry, function()
		return Pins(uiMapID)
	end)
end

---@class LegacyForeverZoneOverlayMixin : Button
---@field GetParent fun(self: LegacyForeverZoneOverlayMixin): WorldMapFrame
---@field Title FontString
---@field Counts FontString
---@field Progress StatusBar
---@field result? LegacyZoneResult
---@field name string
LegacyForeverZoneOverlayMixin = {}

function LegacyForeverZoneOverlayMixin:OnLoad()
	self.Progress = CreateCornerBar(self)
	self.Progress:SetPoint("TOPLEFT", self.Title, "BOTTOMLEFT", 0, -4)
	self.Progress:SetPoint("RIGHT")
end

-- Called as the world map opens or changes map.
function LegacyForeverZoneOverlayMixin:Refresh()
	---@type WorldMapFrame
	local map = self:GetParent()
	local uiMapID = map:GetMapID()
	self.result = IsShown("map") and Zones.Of(uiMapID) or nil
	if not self.result then
		self:Hide()
		return
	end
	local collapsed = ns.Saved.Get("mapCollapsed")
	self.name = C_Map.GetMapInfo(uiMapID).name
	self.Title:SetText(("%s  %s"):format(self.name, PercentText(self.result)))
	SetCornerProgress(self.Progress, self.result)
	self.Counts:SetText(CountsText(self.result, 16))
	self.Counts:SetShown(not collapsed)
	local height = self.Title:GetStringHeight() + 4 + OVERLAY_BAR_HEIGHT
	if not collapsed then
		height = height + 6 + self.Counts:GetStringHeight()
	end
	local width = math.max(self.Title:GetStringWidth(), OVERLAY_MIN_WIDTH)
	if not collapsed then
		width = math.max(width, self.Counts:GetStringWidth())
	end
	self:SetSize(width, height)
	local corner = Corner(uiMapID, map, width, height)
	self:ClearAllPoints()
	self:SetPoint(corner.point, map:GetCanvasContainer(), corner.point, corner.x, corner.y)
	self:Show()
end

function LegacyForeverZoneOverlayMixin:OnClick()
	ns.Saved.Set("mapCollapsed", not ns.Saved.Get("mapCollapsed"))
	self:Refresh()
	self:OnEnter()
end

function LegacyForeverZoneOverlayMixin:OnEnter()
	GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
	AddTooltip(GameTooltip, self.name, self.result)
	GameTooltip_AddInstructionLine(
		GameTooltip,
		ns.Saved.Get("mapCollapsed") and L["Click to expand."] or L["Click to collapse."]
	)
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

-- A frame of our own over the map, kept current as the map opens and turns (UI/MapCanvas.lua): never the map's
-- overlay frames or providers.
local function AttachMap()
	local map = WorldMapFrame
	local MapCanvas = ns.MapCanvas
	local overlay = MapCanvas.FrameUnder("Button", map, "LegacyForeverZoneOverlayTemplate")
	---@cast overlay LegacyForeverZoneOverlayMixin
	overlay:SetFrameStrata("HIGH")
	MapCanvas.Watch(map, function(_, what)
		if what == "show" or what == "map" then
			overlay:Refresh()
		end
	end)
	Zones.OnChange(function()
		if map:IsShown() then
			overlay:Refresh()
		end
	end)
end

EventUtil.ContinueOnAddOnLoaded("Blizzard_WorldMap", AttachMap)

--[[ A zone reaching 100%: a toast and a sound, GW2 style ]]

-- "Kalimdor: 3 of 20 zones complete (15%)", counting what the player counts.
---@param continentID number
---@return string?
local function ContinentText(continentID)
	local continent = Zones.Continent(continentID)
	local info = C_Map.GetMapInfo(continentID)
	if not continent or not info then
		return nil
	end
	return L["%s: %d of %d zones complete (%d%%)"]:format(
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
		C_Map.OpenWorldMap(frame.uiMapID)
	end
end

-- Blizzard's own achievement-progress toast, so it queues and stacks with the game's alerts.
---@param frame LegacyToast
---@param uiMapID number
local function SetUpToast(frame, uiMapID)
	frame.uiMapID = uiMapID
	frame.Unlocked:SetText(L["Zone complete"])
	frame.Name:SetText(C_Map.GetMapInfo(uiMapID).name)
	-- art-ok: the stock toast sizes its icon square, and the compass is 300 by 297, within 2% of square
	frame.Icon.Texture:SetAtlas(ICONS.areas.atlas)
	frame:SetScript("OnClick", OnToastClick)
	PlaySound(SOUNDKIT.UI_SCENARIO_STAGE_END)
	local continent = ns.Live.ContinentOf(uiMapID)
	local line = continent and ContinentText(continent)
	if line then
		ns.Print(L["%s complete. %s"]:format(C_Map.GetMapInfo(uiMapID).name, line))
	end
end

local toasts = AlertFrame:AddQueuedAlertFrameSubSystem("CriteriaAlertFrameTemplate", SetUpToast, 2, 6)

-- Only a completion that is news asks for the toast (ZoneCompletion.OnComplete).
Zones.OnComplete(function(uiMapID)
	toasts:AddAlert(uiMapID)
end)

--[[ Settings, in the Legacy map menu and on the Settings page ]]

---@param category LegacyCategoryKey
local function ToggleCounted(category)
	ns.Saved.Set("count_" .. category, not IsCounted(category))
end

--[[ World map: on a continent, in each zone badge's tooltip ]]

-- A zone's completion under a continent badge's tooltip: percent, then one row of counts.
---@param tooltip GameTooltip
---@param uiMapID number
function Completion.AddSummary(tooltip, uiMapID)
	local result = IsShown("map") and Zones.Of(uiMapID) or nil
	if not result then
		return
	end
	GameTooltip_AddBlankLineToTooltip(tooltip)
	tooltip:AddDoubleLine(
		L["Zone completion"],
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
function Completion.QuestsUsable()
	local status = ns.Quests.Status()
	return status == "ready" or status == "loading"
end

local QUESTS_STATUS = {
	ready = L["Every quest this character can take in the zone, from Questie."]
		.. " "
		.. L["Repeatable, holiday and profession quests are left out."],
	loading = L["Waiting for Questie to finish loading."],
	missing = L["Needs Questie, which lists each zone's quests."],
	unsupported = L["This version of Questie isn't supported."],
}

---@return string
function Completion.QuestsStatusText()
	return QUESTS_STATUS[ns.Quests.Status()]
end

---@param tooltip GameTooltip
local function QuestsTooltip(tooltip)
	GameTooltip_SetTitle(tooltip, LABELS.quests)
	GameTooltip_AddNormalLine(tooltip, QUESTS_STATUS[ns.Quests.Status()])
end

---@param root SharedMenuDescriptionProxy
function Completion.AddMenu(root)
	root:CreateTitle(L["Zone completion"])
	root:CreateCheckbox(L["In the objective tracker"], IsShown, Toggle, "tracker")
	local map = root:CreateCheckbox(L["On the world map"], IsShown, Toggle, "map")
	map:SetTooltip(function(tooltip)
		GameTooltip_SetTitle(tooltip, L["On the world map"])
		GameTooltip_AddNormalLine(
			tooltip,
			L["The zone you're viewing in the map's corner, and a badge on each zone of a continent map."]
		)
	end)
	local counts = root:CreateButton(L["What counts"])
	for _, key in ipairs(ns.Model.COMPLETION_CATEGORIES) do -- menu-scroll-ok: COMPLETION_CATEGORIES is seven fixed kinds
		local box = counts:CreateCheckbox(
			("%s %s"):format(Completion.Icon(key, 14), LABELS[key]),
			IsCounted,
			ToggleCounted,
			key
		)
		if key == "quests" then
			box:SetEnabled(Completion.QuestsUsable)
			box:SetTooltip(QuestsTooltip)
		end
	end
end

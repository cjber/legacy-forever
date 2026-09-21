local addonName, ns = ...

-- Zone completion, Guild Wars 2 style: how much of a zone's areas, flight paths, dungeons,
-- Legacy objectives and local reputations are done, as a section in the objective tracker (the zone you're in) and in
-- the world map's corner (the zone you're viewing). Each is optional and collapsible.
local Completion = {}
ns.Completion = Completion

local ICONS = {
	areas = { atlas = "islands-queue-prop-compass" },
	taxis = { atlas = "flightmaster" },
	dungeons = { atlas = "dungeon" },
	legacy = { atlas = "UI-Legacy-Points-icon-c60", aspect = 50 / 73 },
	-- No atlas reads as reputation, so the classic handshake icon, trimmed of its border.
	reputations = { file = "Interface\\Icons\\Achievement_Reputation_01" },
}
local LABELS = {
	areas = "Areas explored",
	taxis = "Flight paths",
	dungeons = "Dungeons",
	legacy = "Legacy objectives",
	reputations = "Reputations (Friendly)",
}
-- Names listed per category in a tooltip before "and N more".
local MAX_LEFT = 6
local PERCENT_PIN_TEMPLATE = "LegacyHereZonePercentPinTemplate"

local function Settings()
	return ns.SavedTable("zoneCompletion")
end

local listeners = {}

-- The map is on out of the box so the feature is visible; the tracker takes screen space, so it waits to be asked.
local DEFAULT_SHOWN = { tracker = false, map = true }

local function IsShown(surface)
	local shown = Settings()[surface]
	if shown == nil then
		return DEFAULT_SHOWN[surface]
	end
	return shown
end

-- Every category counts until the player unticks it under "What counts".
local function IsCounted(category)
	return Settings()["count_" .. category] ~= false
end

local function Refresh()
	for _, callback in ipairs(listeners) do
		callback()
	end
end

function Completion.Of(uiMapID)
	local zone = uiMapID and ns.Data.completion[uiMapID]
	if not zone then
		return nil
	end
	local result = ns.Model.ZoneCompletion(zone, ns.Live.ZoneSnapshot(uiMapID), IsCounted)
	return result.total > 0 and result or nil
end

local function Icon(key, size)
	local icon = ICONS[key]
	if icon.file then
		return ("|T%s:%d:%d:0:0:64:64:5:59:5:59|t"):format(icon.file, size, size)
	end
	return CreateAtlasMarkup(icon.atlas, math.floor(size * (icon.aspect or 1) + 0.5), size)
end

-- What the player does to resolve a category's pending items.
local PENDING_HINTS = {
	taxis = "Open a flight master on this continent to check these.",
}

local function PercentText(result)
	return ("%d%%"):format(result.percent)
end

-- "3/5", or "?" while every item is pending; `colored` greens a finished category.
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
local function CountsText(result, iconSize)
	local parts = {}
	for _, key in ipairs(ns.Model.COMPLETION_CATEGORIES) do
		local category = result[key]
		if category then
			parts[#parts + 1] = ("%s %s"):format(Icon(key, iconSize), CategoryText(category, true))
		end
	end
	return table.concat(parts, "   ")
end

local function AddTooltip(tooltip, name, result)
	GameTooltip_SetTitle(tooltip, ("%s  %s"):format(name, PercentText(result)))
	for _, key in ipairs(ns.Model.COMPLETION_CATEGORIES) do
		local category = result[key]
		if category then
			tooltip:AddDoubleLine(
				("%s %s"):format(Icon(key, 14), LABELS[key]),
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
	if result.dungeons or result.legacy then
		GameTooltip_AddDisabledLine(tooltip, "Dungeons and Legacy objectives count your progress on any character.")
	end
end

-- A thin fill for the percent, in the tracker's gold; green once the zone is done.
local BAR_HEIGHT = 2

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

local function SetProgress(bar, result)
	bar:SetValue(result.percent)
	bar:SetStatusBarColor((result.complete and GREEN_FONT_COLOR or NORMAL_FONT_COLOR):GetRGB())
end

--[[ Objective tracker: the zone you're in ]]

local TrackerMixin = {}

function TrackerMixin:LayoutContents()
	local uiMapID = IsShown("tracker") and ns.Live.CurrentZone()
	local result = Completion.Of(uiMapID)
	if not result then
		return
	end
	self:SetHeader(C_Map.GetMapInfo(uiMapID).name)
	self.Header.Percent:SetText(PercentText(result))
	SetProgress(self.Header.Progress, result)
	local block = self:GetBlock(uiMapID)
	block:SetHeader(CountsText(result, 14))
	self:LayoutBlock(block)
end

function TrackerMixin:OnBlockHeaderEnter(block)
	local result = Completion.Of(block.id)
	if result then
		GameTooltip:SetOwner(block, "ANCHOR_LEFT")
		AddTooltip(GameTooltip, C_Map.GetMapInfo(block.id).name, result)
		GameTooltip_AddInstructionLine(GameTooltip, "Click to open the map.")
		GameTooltip:Show()
	end
end

function TrackerMixin:OnBlockHeaderLeave()
	GameTooltip:Hide()
end

function TrackerMixin:OnBlockHeaderClick(block)
	OpenWorldMap(block.id)
end

local trackerModule = ns.Tracker.AddModule("LegacyHereZoneTracker", TrackerMixin, -1)
if trackerModule then
	local header = trackerModule.Header
	header.Percent = header:CreateFontString(nil, "ARTWORK", "ObjectiveTrackerHeaderFont")
	header.Percent:SetPoint("RIGHT", header.MinimizeButton, "LEFT", -4, 0)
	-- Along the header art's own underline, under the zone name and percent.
	header.Progress = CreateProgressBar(header)
	header.Progress:SetPoint("BOTTOMLEFT", 7, 1)
	header.Progress:SetPoint("BOTTOMRIGHT", header.Percent, "BOTTOMRIGHT", 0, 1)
	-- Saved variables arrive only once every file has run.
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

--[[ World map: the zone you're viewing, in the corner; a percent per zone on a continent ]]

LegacyHereZoneOverlayMixin = {}

-- Called by the world map whenever it changes map.
-- Room for the text, the bar and a fade on the right, so it never looks boxed.
local OVERLAY_MIN_WIDTH = 140

function LegacyHereZoneOverlayMixin:OnLoad()
	self.Progress = CreateProgressBar(self)
	self.Progress:SetPoint("TOPLEFT", self.Title, "BOTTOMLEFT", 0, -4)
	self.Progress:SetPoint("RIGHT")
end

-- Called by the world map whenever it changes map.
function LegacyHereZoneOverlayMixin:Refresh()
	local map = self:GetParent()
	local uiMapID = map:GetMapID()
	self.result = IsShown("map") and Completion.Of(uiMapID)
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
	self:SetSize(math.max(self.Title:GetStringWidth(), self.Counts:GetStringWidth(), OVERLAY_MIN_WIDTH), height)
	self:Show()
end

function LegacyHereZoneOverlayMixin:OnClick()
	Settings().mapCollapsed = not Settings().mapCollapsed
	self:Refresh()
	self:OnEnter()
end

function LegacyHereZoneOverlayMixin:OnEnter()
	GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
	AddTooltip(GameTooltip, self.name, self.result)
	GameTooltip_AddInstructionLine(GameTooltip, Settings().mapCollapsed and "Click to expand." or "Click to collapse.")
	GameTooltip:Show()
end

function LegacyHereZoneOverlayMixin:OnLeave()
	GameTooltip:Hide()
end

LegacyHereZonePercentPinMixin = CreateFromMixins(MapCanvasPinMixin)

function LegacyHereZonePercentPinMixin:OnLoad()
	self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
	self:SetScalingLimits(1, 1.0, 1.2)
end

function LegacyHereZonePercentPinMixin:OnAcquired(x, y, result)
	self.Text:SetText(PercentText(result))
	self.Text:SetTextColor((result.complete and GREEN_FONT_COLOR or NORMAL_FONT_COLOR):GetRGB())
	self:SetPosition(x, y)
	self:ApplyCurrentScale()
end

-- One provider drives both map surfaces: the map refreshes providers on show and on
-- every map change, but its overlay frames only on a map change.
local function CreateProvider(overlay)
	local provider = CreateFromMixins(MapCanvasDataProviderMixin)

	function provider:RemoveAllData()
		self:GetMap():RemoveAllPinsByTemplate(PERCENT_PIN_TEMPLATE)
	end

	function provider:RefreshAllData()
		self:RemoveAllData()
		overlay:Refresh()
		local map = self:GetMap()
		local continentID = map:GetMapID()
		local info = continentID and C_Map.GetMapInfo(continentID)
		if not (IsShown("map") and info and info.mapType == Enum.UIMapType.Continent) then
			return
		end
		for uiMapID in pairs(ns.Data.completion) do
			local zoneInfo = C_Map.GetMapInfo(uiMapID)
			local result = zoneInfo and zoneInfo.parentMapID == continentID and Completion.Of(uiMapID)
			local left, right, top, bottom = C_Map.GetMapRectOnMap(uiMapID, continentID)
			if result and left then
				map:AcquirePin(PERCENT_PIN_TEMPLATE, (left + right) / 2, (top + bottom) / 2, result)
			end
		end
	end

	return provider
end

local function AttachMap()
	local map = WorldMapFrame
	-- Right of the floor dropdown and Camelot's tracking pin button, which share the corner.
	local overlay = map:AddOverlayFrame(
		"LegacyHereZoneOverlayTemplate",
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

--[[ Settings, in the Legacy map menu ]]

local function Toggle(surface)
	Settings()[surface] = not IsShown(surface)
	Refresh()
end

local function ToggleCounted(category)
	Settings()["count_" .. category] = not IsCounted(category)
	Refresh()
end

function Completion.AddMenu(root)
	root:CreateTitle("Zone completion")
	root:CreateCheckbox("In the objective tracker", IsShown, Toggle, "tracker")
	root:CreateCheckbox("On the world map", IsShown, Toggle, "map")
	local counts = root:CreateButton("What counts")
	for _, key in ipairs(ns.Model.COMPLETION_CATEGORIES) do
		counts:CreateCheckbox(("%s %s"):format(Icon(key, 14), LABELS[key]), IsCounted, ToggleCounted, key)
	end
end

-- For /lh audit: the current zone's counts against what the game reports.
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
	ns.Print(
		("zone completion for %s (map %d): %s"):format(
			C_Map.GetMapInfo(uiMapID).name,
			uiMapID,
			table.concat(parts, ", ")
		)
	)

	local known = {}
	for _, area in ipairs(zone.areas or {}) do
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

	for _, taxi in ipairs(zone.taxis or {}) do
		if taxi.faction == "Neutral" or taxi.faction == snapshot.faction then
			local learned = snapshot.taxis[taxi.node]
			local state = learned == nil and "unknown until you open a flight master on this continent"
				or learned and "known"
				or "not known"
			ns.Print(("  flight path %d (%s): %s"):format(taxi.node, taxi.name, state))
		end
	end
end

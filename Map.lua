local _, ns = ...

local PIN_TEMPLATE = "LegacyHerePinTemplate"
local POINTS_ICON = "UI-Legacy-Points-icon-c60"

local KIND_LABEL = {
	explore = "Undiscovered area",
	instance = "Dungeon or raid",
	kill = "Defeat",
	quest = "Quest",
	reputation = "Reputation",
}

local function ZoneGroups(uiMapID)
	if not uiMapID then
		return {}
	end
	return ns.Model.ZoneObjectives(ns.Data, uiMapID, ns.Live.Visible(), ns.Live.Criteria)
end

local function PointsText(challenge)
	local points = ns.Live.Points(challenge)
	if points then
		return ("%s %d Legacy |4point:points;"):format(CreateAtlasMarkup(POINTS_ICON, 10, 14), points)
	end
end

local function AddPointsLine(tooltip, challenge)
	local text = PointsText(challenge)
	if text then
		GameTooltip_AddNormalLine(tooltip, text)
	end
end

-- Points belong to the whole challenge, so a feeding achievement (an "Explore <zone>")
-- names what it counts toward rather than implying each step is worth them.
local function AddRewardLine(tooltip, group)
	if group.achievement == group.challenge then
		AddPointsLine(tooltip, group.challenge)
		return
	end
	local points = PointsText(group.challenge)
	local name = ns.Live.Name(group.challenge)
	GameTooltip_AddNormalLine(
		tooltip,
		points and ("Part of %s (%s)"):format(name, points) or ("Part of %s"):format(name)
	)
end

local function IsExploreGroup(group)
	return group.objectives[1].entry.kind == "explore"
end

-- "9 of 12 areas left" for an exploration achievement, from live progress.
local function AreasLeftText(group)
	local total, left = 0, 0
	for _, progress in pairs(ns.Live.Criteria(group.achievement) or {}) do
		total = total + 1
		if not progress.completed then
			left = left + 1
		end
	end
	return ("%s: %d of %d areas left"):format(ns.Live.Name(group.achievement), left, total)
end

local function AddGroupTooltip(tooltip, group)
	if IsExploreGroup(group) then
		GameTooltip_SetTitle(tooltip, ns.Live.Name(group.achievement))
		GameTooltip_AddNormalLine(tooltip, AreasLeftText(group))
		for _, objective in ipairs(group.objectives) do
			GameTooltip_AddColoredLine(tooltip, objective.text, WHITE_FONT_COLOR)
		end
	else
		GameTooltip_SetTitle(tooltip, ns.Live.Name(group.challenge))
		for _, objective in ipairs(group.objectives) do
			local label = KIND_LABEL[objective.entry.kind]
			GameTooltip_AddColoredLine(tooltip, ("%s: %s"):format(label, objective.text), WHITE_FONT_COLOR)
		end
	end
	AddRewardLine(tooltip, group)
end

local function AddPinTooltip(tooltip, group, objective)
	if objective.entry.kind == "explore" then
		GameTooltip_SetTitle(tooltip, objective.text)
		GameTooltip_AddNormalLine(tooltip, KIND_LABEL.explore)
		GameTooltip_AddHighlightLine(tooltip, AreasLeftText(group))
	else
		GameTooltip_SetTitle(tooltip, ns.Live.Name(group.challenge))
		local label = KIND_LABEL[objective.entry.kind]
		GameTooltip_AddColoredLine(tooltip, ("%s: %s"):format(label, objective.text), WHITE_FONT_COLOR)
	end
	AddRewardLine(tooltip, group)
end

-- Session default is on; kept across sessions only where SavedVariables load.
local function ShowAreas()
	return not (LegacyHereDB and LegacyHereDB.hideAreas)
end

local function ToggleAreas()
	LegacyHereDB = LegacyHereDB or {}
	LegacyHereDB.hideAreas = ShowAreas()
	ns.RefreshMap()
end

--[[ Button: sits in the map's top-right button column and lists this map's objectives ]]

-- Click opens the Legacy panel; shift-click adds to or removes from our own tracker.
local function OnChallengeClick(challenge)
	if IsShiftKeyDown() then
		ns.Tracker.Toggle(challenge)
	else
		ns.Live.ShowInLegacyPanel(challenge)
	end
end

local CLICK_HINT = "Click to open in the Legacy panel. Shift-click to track."

local function ChallengeText(name, count, challenge)
	local check = ns.Tracker.IsTracked(challenge) and "|TInterface\\RaidFrame\\ReadyCheck-Ready:12|t " or ""
	return ("%s%s |cffffffff(%d)|r"):format(check, name, count)
end

local function AddGroup(root, group)
	local name = ns.Live.Name(group.achievement)
	local button =
		root:CreateButton(ChallengeText(name, #group.objectives, group.challenge), OnChallengeClick, group.challenge)
	button:SetTooltip(function(tooltip)
		AddGroupTooltip(tooltip, group)
		GameTooltip_AddInstructionLine(tooltip, CLICK_HINT)
	end)
end

local function AddUnlocated(root)
	local unlocated = ns.Model.Unlocated(ns.Data, ns.Live.Visible(), ns.Live.Criteria)
	if #unlocated == 0 then
		return
	end
	local submenu = root:CreateButton(("No fixed location |cffffffff(%d)|r"):format(#unlocated))
	for _, item in ipairs(unlocated) do
		local text = ChallengeText(ns.Live.Name(item.challenge), item.open, item.challenge)
		local button = submenu:CreateButton(text, OnChallengeClick, item.challenge)
		button:SetTooltip(function(tooltip)
			GameTooltip_SetTitle(tooltip, ns.Live.Name(item.challenge))
			GameTooltip_AddNormalLine(tooltip, "Levels, skills, ranks and anything without a fixed place.")
			AddPointsLine(tooltip, item.challenge)
			GameTooltip_AddInstructionLine(tooltip, CLICK_HINT)
		end)
	end
end

local function BuildMenu(root, uiMapID)
	root:SetTag("MENU_LEGACY_HERE")
	local mapInfo = uiMapID and C_Map.GetMapInfo(uiMapID)
	root:CreateTitle(mapInfo and mapInfo.name or ns.TITLE)
	local groups = ZoneGroups(uiMapID)
	if #groups == 0 then
		root:CreateTitle("|cff808080Nothing left to do here|r")
	end
	for _, group in ipairs(groups) do
		AddGroup(root, group)
	end
	root:CreateDivider()
	root:CreateCheckbox("Show undiscovered areas", ShowAreas, ToggleAreas)
	AddUnlocated(root)
	root:CreateButton("Open the Legacy panel", ToggleLegacySystemUI)
end

LegacyHereMapButtonMixin = {}

function LegacyHereMapButtonMixin:OnLoad()
	self:SetupMenu(function(_, root)
		BuildMenu(root, self:GetParent():GetMapID())
	end)
end

-- Below whichever of Blizzard's top-right buttons are actually showing there: rulesets
-- disable them (C_GameRules) and layout addons move them, so this is checked per refresh.
local TOP_RIGHT_BUTTONS = { "WorldMapTrackingOptionsButton", "WorldMapTrackingPinButton" }
local BUTTON_SPACING = -32

local function TopRightOffset(map)
	local offsetY = -2
	for _, key in ipairs(TOP_RIGHT_BUTTONS) do
		local button = map[key]
		if button and button:IsShown() and button:GetPoint(1) == "TOPRIGHT" then
			offsetY = offsetY + BUTTON_SPACING
		end
	end
	return offsetY
end

function LegacyHereMapButtonMixin:Refresh()
	local map = self:GetParent()
	self:ClearAllPoints()
	self:SetPoint("TOPRIGHT", map:GetCanvasContainer(), "TOPRIGHT", -4, TopRightOffset(map))
	local count = ns.Model.CountObjectives(ZoneGroups(self:GetParent():GetMapID()))
	self.Count:SetText(count > 0 and count or "")
	self.Icon:SetDesaturated(count == 0)
	self.count = count
end

function LegacyHereMapButtonMixin:OnShow()
	self:Refresh()
end

function LegacyHereMapButtonMixin:OnEnter()
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip_SetTitle(GameTooltip, ns.TITLE)
	if self.count and self.count > 0 then
		GameTooltip_AddNormalLine(GameTooltip, ("%d unfinished Legacy objectives on this map."):format(self.count))
	else
		GameTooltip_AddNormalLine(GameTooltip, "No unfinished Legacy objectives with a place on this map.")
	end
	GameTooltip:Show()
end

function LegacyHereMapButtonMixin:OnLeave()
	GameTooltip:Hide()
end

--[[ Pins: one per unfinished objective the data can place on this map.
     Built once Blizzard_WorldMap (and so MapCanvas) is loaded; the XML template
     resolves its mixin by name when the first pin is created. ]]

local function CreatePinProvider()
	LegacyHerePinMixin = CreateFromMixins(MapCanvasPinMixin)

	function LegacyHerePinMixin:OnLoad()
		self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
	end

	-- Areas are many and minor, so they sit smaller and quieter than dungeons,
	-- bosses and quests. Pins are pooled, so every acquire sets both looks.
	function LegacyHerePinMixin:OnAcquired(group, objective)
		self.group = group
		self.objective = objective
		if objective.entry.kind == "explore" then
			self:SetScalingLimits(1, 0.65, 0.9)
			self:SetAlpha(0.8)
		else
			self:SetScalingLimits(1, 1.0, 1.2)
			self:SetAlpha(1)
		end
		self:SetPosition(objective.entry.x, objective.entry.y)
		self:ApplyCurrentScale()
	end

	function LegacyHerePinMixin:OnMouseEnter()
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		AddPinTooltip(GameTooltip, self.group, self.objective)
		GameTooltip:Show()
	end

	function LegacyHerePinMixin:OnMouseLeave()
		GameTooltip:Hide()
	end

	local provider = CreateFromMixins(MapCanvasDataProviderMixin)

	function provider:RemoveAllData()
		self:GetMap():RemoveAllPinsByTemplate(PIN_TEMPLATE)
	end

	function provider:RefreshAllData()
		self:RemoveAllData()
		for _, group in ipairs(ZoneGroups(self:GetMap():GetMapID())) do
			for _, objective in ipairs(group.objectives) do
				if objective.entry.x and (objective.entry.kind ~= "explore" or ShowAreas()) then
					self:GetMap():AcquirePin(PIN_TEMPLATE, group, objective)
				end
			end
		end
	end

	return provider
end

--[[ Wiring ]]

local function Attach()
	local map = WorldMapFrame
	local provider = CreatePinProvider()
	map:AddDataProvider(provider)

	-- Refresh anchors it; see TopRightOffset.
	local button = map:AddOverlayFrame("LegacyHereMapButtonTemplate", "DROPDOWNBUTTON")

	function ns.RefreshMap()
		if map:IsShown() then
			provider:RefreshAllData()
			button:Refresh()
		end
	end
	ns.Live.OnChange(ns.RefreshMap)
	button:Refresh()
end

EventUtil.ContinueOnAddOnLoaded("Blizzard_WorldMap", Attach)

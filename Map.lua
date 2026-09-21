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

local function AddPointsLine(tooltip, challenge)
	local points = ns.Live.Points(challenge)
	if points then
		local icon = CreateAtlasMarkup(POINTS_ICON, 10, 14)
		GameTooltip_AddNormalLine(tooltip, ("%s %d Legacy |4point:points;"):format(icon, points))
	end
end

-- The challenge, the exploration achievement feeding it (if any), then what's left here.
local function AddGroupTooltip(tooltip, group, objectives)
	GameTooltip_SetTitle(tooltip, ns.Live.Name(group.challenge))
	if group.achievement ~= group.challenge then
		GameTooltip_AddHighlightLine(tooltip, ns.Live.Name(group.achievement))
	end
	for _, objective in ipairs(objectives) do
		local label = KIND_LABEL[objective.entry.kind]
		GameTooltip_AddColoredLine(tooltip, ("%s: %s"):format(label, objective.text), WHITE_FONT_COLOR)
	end
	AddPointsLine(tooltip, group.challenge)
end

--[[ Button: sits in the map's top-right button column and lists this map's objectives ]]

local function OnObjectiveClick(achievementID)
	if IsShiftKeyDown() then
		ns.Live.ShowInLegacyPanel(achievementID)
	else
		ns.Live.ToggleTracked(achievementID)
	end
end

local function AddGroup(root, group)
	local name = ns.Live.Name(group.achievement)
	local text = ("%s |cffffffff(%d)|r"):format(name, #group.objectives)
	local button = root:CreateCheckbox(text, ns.Live.IsTracked, OnObjectiveClick, group.achievement)
	button:SetTooltip(function(tooltip)
		AddGroupTooltip(tooltip, group, group.objectives)
		GameTooltip_AddInstructionLine(tooltip, "Click to track. Shift-click to open in the Legacy panel.")
	end)
end

local function AddUnlocated(root)
	local unlocated = ns.Model.Unlocated(ns.Data, ns.Live.Visible(), ns.Live.Criteria)
	if #unlocated == 0 then
		return
	end
	local submenu = root:CreateButton(("No fixed location |cffffffff(%d)|r"):format(#unlocated))
	for _, item in ipairs(unlocated) do
		local text = ("%s |cffffffff(%d)|r"):format(ns.Live.Name(item.challenge), item.open)
		local button = submenu:CreateCheckbox(text, ns.Live.IsTracked, OnObjectiveClick, item.challenge)
		button:SetTooltip(function(tooltip)
			GameTooltip_SetTitle(tooltip, ns.Live.Name(item.challenge))
			GameTooltip_AddNormalLine(tooltip, "Levels, skills, ranks and anything without a fixed place.")
			AddPointsLine(tooltip, item.challenge)
			GameTooltip_AddInstructionLine(tooltip, "Click to track. Shift-click to open in the Legacy panel.")
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
	AddUnlocated(root)
	root:CreateButton("Open the Legacy panel", ToggleLegacySystemUI)
end

LegacyHereMapButtonMixin = {}

function LegacyHereMapButtonMixin:OnLoad()
	self:SetupMenu(function(_, root)
		BuildMenu(root, self:GetParent():GetMapID())
	end)
end

function LegacyHereMapButtonMixin:Refresh()
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
		self:SetScalingLimits(1, 1.0, 1.2)
	end

	function LegacyHerePinMixin:OnAcquired(group, objective)
		self.group = group
		self.objective = objective
		self:SetPosition(objective.entry.x, objective.entry.y)
	end

	function LegacyHerePinMixin:OnMouseEnter()
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		AddGroupTooltip(GameTooltip, self.group, { self.objective })
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
				if objective.entry.x then
					self:GetMap():AcquirePin(PIN_TEMPLATE, group, objective)
				end
			end
		end
	end

	return provider
end

--[[ Wiring ]]

local BUTTON_SPACING = -32

local function Attach()
	local map = WorldMapFrame
	local provider = CreatePinProvider()
	map:AddDataProvider(provider)

	-- Below whichever of Blizzard's own top-right buttons this ruleset enables.
	local offsetY = -2
	for _, key in ipairs({ "WorldMapTrackingOptionsButton", "WorldMapTrackingPinButton" }) do
		if map[key] then
			offsetY = offsetY + BUTTON_SPACING
		end
	end
	local button = map:AddOverlayFrame(
		"LegacyHereMapButtonTemplate",
		"DROPDOWNBUTTON",
		"TOPRIGHT",
		map:GetCanvasContainer(),
		"TOPRIGHT",
		-4,
		offsetY
	)

	hooksecurefunc(map, "OnMapChanged", function()
		button:Refresh()
	end)
	ns.Live.OnChange(function()
		if map:IsShown() then
			provider:RefreshAllData()
			button:Refresh()
		end
	end)
	button:Refresh()
end

EventUtil.ContinueOnAddOnLoaded("Blizzard_WorldMap", Attach)

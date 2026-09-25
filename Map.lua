---@type string, LegacyForeverNamespace
local _, ns = ...

local PIN_TEMPLATE = "LegacyForeverPinTemplate"
local AREA_TEMPLATE = "LegacyForeverAreaPinTemplate"
-- Unseen ground reads darker, the fog-of-war convention (a warm tint vanished on the
-- parchment); darker still under the mouse.
local AREA_ALPHA, AREA_HOVER_ALPHA = 0.25, 0.4
local POINTS_ICON = "UI-Legacy-Points-icon-c60"
-- The original game's raids by instance map ID; every other instance entrance is a dungeon.
local RAIDS = { [249] = true, [309] = true, [409] = true, [469] = true, [509] = true, [531] = true, [533] = true }

local KIND_LABEL = {
	explore = "Undiscovered area",
	instance = "Dungeon or raid",
	kill = "Defeat",
	quest = "Quest",
	reputation = "Reputation",
}

---@param uiMapID number?
---@return LegacyGroup[]
local function ZoneGroups(uiMapID)
	if not uiMapID then
		return {}
	end
	return ns.Model.ZoneObjectives(ns.Data, uiMapID, ns.Live.Visible(), ns.Live.Criteria)
end

---@param challenge number
---@return string?
local function PointsText(challenge)
	local points = ns.Live.Points(challenge)
	if points then
		return ("%s %d Legacy |4point:points;"):format(CreateAtlasMarkup(POINTS_ICON, 10, 14), points)
	end
end

---@param tooltip GameTooltip
---@param challenge number
local function AddPointsLine(tooltip, challenge)
	local text = PointsText(challenge)
	if text then
		GameTooltip_AddNormalLine(tooltip, text)
	end
end

---@param group LegacyGroup
---@return boolean
local function IsExploreGroup(group)
	return group.objectives[1].entry.kind == "explore"
end

-- Points belong to the whole challenge, so a feeding achievement (an "Explore <zone>")
-- names what it counts toward rather than implying each step is worth them.
---@param tooltip GameTooltip
---@param group LegacyGroup
local function AddRewardLine(tooltip, group)
	if group.achievement == group.challenge then
		AddPointsLine(tooltip, group.challenge)
		return
	end
	local points = PointsText(group.challenge)
	local name = ns.Live.Name(group.challenge)
	-- Explorer pays once for exploring all of Azeroth (Explore Azeroth), so one area is a
	-- small share of a single point; say so rather than let it read as a point per area.
	local scope = IsExploreGroup(group) and "for exploring every zone" or "for the whole challenge"
	GameTooltip_AddNormalLine(
		tooltip,
		points and ("Part of %s: %s %s"):format(name, points, scope) or ("Part of %s"):format(name)
	)
end

-- "9 of 12 areas left" for an exploration achievement, from live progress.
---@param group LegacyGroup
---@return string
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

---@param tooltip GameTooltip
---@param group LegacyGroup
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

---@param tooltip GameTooltip
---@param group LegacyGroup
---@param objective LegacyObjective
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

---@param tooltip GameTooltip
---@param zone LegacyContinentZone
local function AddZoneTooltip(tooltip, zone)
	GameTooltip_SetTitle(tooltip, zone.name)
	GameTooltip_AddHighlightLine(
		tooltip,
		("%d Legacy %s left"):format(zone.count, zone.count == 1 and "objective" or "objectives")
	)
	for _, group in ipairs(zone.groups) do
		GameTooltip_AddNormalLine(tooltip, ("%s: %d left"):format(ns.Live.Name(group.challenge), #group.objectives))
	end
	ns.Completion.AddSummary(tooltip, zone.uiMapID)
	GameTooltip_AddInstructionLine(tooltip, "Click the zone to see where.")
end

-- On a continent, one badge per zone with unfinished objectives, instead of every pin; its tooltip gives the count.
-- Exploration is left to the zone map's shading, so badges count place-bound objectives only.
-- They follow zone completion's "On the world map" switch, so turning it off leaves continents bare.
---@param continentID number
---@return LegacyContinentZone[]
local function ContinentZones(continentID)
	local zones = {}
	for uiMapID in pairs(ns.Data.zones) do
		local info = C_Map.GetMapInfo(uiMapID)
		if info and info.parentMapID == continentID then
			local groups = {}
			for _, group in ipairs(ZoneGroups(uiMapID)) do
				if not IsExploreGroup(group) then
					groups[#groups + 1] = group
				end
			end
			local count = ns.Model.CountObjectives(groups)
			local left, right, top, bottom = C_Map.GetMapRectOnMap(uiMapID, continentID)
			if count > 0 and left then
				zones[#zones + 1] = {
					uiMapID = uiMapID,
					name = info.name,
					groups = groups,
					count = count,
					x = (left + right) / 2,
					y = (top + bottom) / 2,
				}
			end
		end
	end
	return zones
end

local function ShowAreas()
	return ns.Setting("showAreas")
end

local function ToggleAreas()
	LegacyForeverDB = LegacyForeverDB or {}
	LegacyForeverDB.showAreas = not ShowAreas()
	ns.RefreshMap()
end

---@param key 'whatsNew'|'companions'
---@return boolean
local function IsSet(key)
	return ns.Setting(key)
end

---@param key 'whatsNew'|'companions'
local function ToggleSetting(key)
	LegacyForeverDB = LegacyForeverDB or {}
	LegacyForeverDB[key] = not ns.Setting(key)
end

--[[ Button: sits in the map's top-right button column and lists this map's objectives ]]

-- Each entry is a checkbox for our own tracker (Forever refuses Blizzard's): a zone's
-- entry tracks only this zone's share of its challenge (Model.ZoneKey), "No fixed location"
-- the whole challenge. The tracker's challenge names open the Legacy panel.
local TRACK_HINT = "Click to track, with live progress."

---@param name string
---@param count number
---@return string
local function ChallengeText(name, count)
	return ("%s |cffffffff(%d)|r"):format(name, count)
end

-- Each entry wears the icon it has on the map: the Legacy pin, or for exploration the
-- compass of the undiscovered-area shading (as under "What counts").
---@param root SharedMenuDescriptionProxy
---@param group LegacyGroup
local function AddGroup(root, group)
	local icon = IsExploreGroup(group) and ns.Completion.Icon("areas", 14) or CreateAtlasMarkup(POINTS_ICON, 10, 14)
	local name = ("%s %s"):format(icon, ns.Live.Name(group.achievement))
	local button = root:CreateCheckbox(
		ChallengeText(name, #group.objectives),
		ns.Tracker.IsTracked,
		ns.Tracker.Toggle,
		ns.Model.ZoneKey(group)
	)
	button:SetTooltip(function(tooltip)
		AddGroupTooltip(tooltip, group)
		GameTooltip_AddInstructionLine(tooltip, TRACK_HINT)
	end)
end

---@param menu SharedMenuDescriptionProxy
---@param item LegacyUnlocated
local function AddUnlocatedItem(menu, item)
	local text = ChallengeText(ns.Live.Name(item.challenge), item.open)
	local button = menu:CreateCheckbox(text, ns.Tracker.IsTracked, ns.Tracker.Toggle, item.challenge)
	button:SetTooltip(function(tooltip)
		GameTooltip_SetTitle(tooltip, ns.Live.Name(item.challenge))
		GameTooltip_AddNormalLine(tooltip, "Levels, skills, ranks and anything without a fixed place.")
		AddPointsLine(tooltip, item.challenge)
		GameTooltip_AddInstructionLine(tooltip, TRACK_HINT)
	end)
end

-- Ordered groups keyed by name, so submenus keep the order items first appear in.
---@param list LegacyMenuGroup[]
---@param byName table<string, LegacyMenuGroup>
---@param name string
---@return LegacyMenuGroup
local function Group(list, byName, name)
	local group = byName[name]
	if not group then
		group = { name = name, items = {}, subs = {}, subsByName = {} }
		byName[name] = group
		list[#list + 1] = group
	end
	return group
end

-- Grouped like the Legacy panel: the game's category, under its parent when it has
-- one (Classes > Priest, PvP > Ranks), so no submenu runs off the screen.
---@param root SharedMenuDescriptionProxy
local function AddUnlocated(root)
	local unlocated = ns.Model.Unlocated(ns.Data, ns.Live.Visible(), ns.Live.Criteria)
	if #unlocated == 0 then
		return
	end
	local tops, topsByName = {}, {}
	for _, item in ipairs(unlocated) do
		local name, parentID = GetCategoryInfo(GetAchievementCategory(item.challenge))
		local parentName = parentID and parentID > 0 and GetCategoryInfo(parentID)
		if parentName then
			local top = Group(tops, topsByName, parentName)
			local sub = Group(top.subs, top.subsByName, name)
			sub.items[#sub.items + 1] = item
		else
			local top = Group(tops, topsByName, name or OTHER)
			top.items[#top.items + 1] = item
		end
	end
	local submenu = root:CreateButton(("No fixed location |cffffffff(%d)|r"):format(#unlocated))
	for _, top in ipairs(tops) do
		local topMenu = submenu:CreateButton(top.name)
		for _, sub in ipairs(top.subs) do
			local subMenu = topMenu:CreateButton(sub.name)
			for _, item in ipairs(sub.items) do
				AddUnlocatedItem(subMenu, item)
			end
		end
		for _, item in ipairs(top.items) do
			AddUnlocatedItem(topMenu, item)
		end
	end
end

---@param root SharedMenuDescriptionProxy
---@param uiMapID number?
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
	root:CreateDivider()
	ns.Completion.AddMenu(root)
	root:CreateDivider()
	root:CreateButton("Open the Legacy panel", ToggleLegacySystemUI)
	root:CreateDivider()
	root:CreateCheckbox("Tell me what's new after an update", IsSet, ToggleSetting, "whatsNew")
	local companions = root:CreateCheckbox("Suggest companion addons", IsSet, ToggleSetting, "companions")
	companions:SetTooltip(function(tooltip)
		GameTooltip_SetTitle(tooltip, "Suggest companion addons")
		GameTooltip_AddNormalLine(
			tooltip,
			"A grey line in a pin's tooltip when Shortest Path Forever would plot the route."
		)
	end)
end

---@class LegacyForeverMapButtonMixin : DropdownButton
---@field GetParent fun(self: LegacyForeverMapButtonMixin): WorldMapFrame
---@field Count FontString
---@field Icon Texture
---@field count number
LegacyForeverMapButtonMixin = {}

function LegacyForeverMapButtonMixin:OnLoad()
	self:SetupMenu(function(_, root)
		BuildMenu(root, self:GetParent():GetMapID())
	end)
end

-- Below whichever of Blizzard's top-right buttons are actually showing there: rulesets
-- disable them (C_GameRules) and layout addons move them, so this is checked per refresh.
local TOP_RIGHT_BUTTONS = { "WorldMapTrackingOptionsButton", "WorldMapTrackingPinButton" }
local BUTTON_SPACING = -32

---@param map WorldMapFrame
---@return number
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

function LegacyForeverMapButtonMixin:Refresh()
	---@type WorldMapFrame
	local map = self:GetParent()
	self:ClearAllPoints()
	self:SetPoint("TOPRIGHT", map:GetCanvasContainer(), "TOPRIGHT", -4, TopRightOffset(map))
	local count = ns.Model.CountObjectives(ZoneGroups(self:GetParent():GetMapID()))
	self.Count:SetFontObject(
		count >= 100 and GameFontNormalTiny or count >= 10 and GameFontNormalSmall or GameFontNormal
	)
	self.Count:SetText(count > 0 and tostring(count) or "")
	self.Icon:SetDesaturated(count == 0)
	self.count = count
end

function LegacyForeverMapButtonMixin:OnShow()
	self:Refresh()
end

function LegacyForeverMapButtonMixin:OnEnter()
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip_SetTitle(GameTooltip, ns.TITLE)
	if self.count and self.count > 0 then
		GameTooltip_AddNormalLine(GameTooltip, ("%d unfinished Legacy objectives on this map."):format(self.count))
	else
		GameTooltip_AddNormalLine(GameTooltip, "No unfinished Legacy objectives with a place on this map.")
	end
	GameTooltip:Show()
end

function LegacyForeverMapButtonMixin:OnLeave()
	GameTooltip:Hide()
end

-- Closing the map hides the button without an OnLeave.
function LegacyForeverMapButtonMixin:OnHide()
	if GameTooltip:GetOwner() == self then
		GameTooltip:Hide()
	end
end

--[[ Pins: one per unfinished objective the data can place on this map.
     Built once Blizzard_WorldMap (and so MapCanvas) is loaded; the XML template
     resolves its mixin by name when the first pin is created. ]]

local function DefinePinMixin()
	---@class LegacyForeverPinMixin : Frame, MapCanvasPinMixin
	---@field Icon Texture
	---@field Portal Texture
	---@field Highlight Texture
	---@field group? LegacyGroup
	---@field objective? LegacyObjective
	---@field zone? LegacyContinentZone
	LegacyForeverPinMixin = CreateFromMixins(MapCanvasPinMixin)

	-- Setup lives here rather than in OnLoad, as Blizzard's own map pins do:
	-- this client doesn't reliably run OnLoad for addon pins.
	---@param group LegacyGroup?
	---@param objective LegacyObjective?
	---@param zone LegacyContinentZone?
	function LegacyForeverPinMixin:OnAcquired(group, objective, zone)
		self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
		self.group = group
		self.objective = objective
		self.zone = zone
		self:SetScalingLimits(1, 1.0, 1.2)
		-- Closing the map hides the pin without an OnMouseLeave.
		self:SetScript("OnHide", self.OnMouseLeave)
		-- Pins are pooled, so this is set on every acquire. A zone badge lets the click open the zone below it.
		self:SetMouseClickEnabled(self:Destination() ~= nil)
		self:Layout(objective and objective.entry.instance)
		if zone then
			self:SetPosition(zone.x, zone.y)
		elseif objective then
			self:SetPosition(objective.entry.x, objective.entry.y)
		end
		self:ApplyCurrentScale()
	end

	-- At an entrance: the retail portal the map already uses there, with a small shield on its corner, so the
	-- entrance still reads as one and the Legacy step as a badge on it. Anywhere else: the shield alone.
	---@param instance number?
	function LegacyForeverPinMixin:Layout(instance)
		self.Icon:ClearAllPoints()
		self.Highlight:ClearAllPoints()
		self.Portal:SetShown(instance ~= nil)
		if instance then
			local atlas = RAIDS[instance] and "Raid" or "Dungeon"
			self:SetSize(32, 32)
			self.Portal:SetAtlas(atlas)
			self.Icon:SetSize(12, 17)
			self.Icon:SetPoint("BOTTOMRIGHT", 2, -2)
			self.Highlight:SetAtlas(atlas)
			self.Highlight:SetAllPoints(self.Portal)
		else
			self:SetSize(20, 20)
			self.Icon:SetSize(14, 20)
			self.Icon:SetPoint("CENTER")
			self.Highlight:SetAtlas(POINTS_ICON)
			self.Highlight:SetAllPoints(self.Icon)
		end
	end

	-- Where a click takes the player: only an objective with coordinates in the data, on the zone map they are for.
	---@return number? uiMapID
	---@return number? x
	---@return number? y
	function LegacyForeverPinMixin:Destination()
		local entry = self.objective and self.objective.entry
		if self.group and entry and entry.x and entry.y then
			return self.group.uiMapID, entry.x, entry.y
		end
	end

	function LegacyForeverPinMixin:OnMouseEnter()
		self.Highlight:Show()
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if self.zone then
			AddZoneTooltip(GameTooltip, self.zone)
		elseif self.group and self.objective then
			AddPinTooltip(GameTooltip, self.group, self.objective)
			if self:Destination() then
				GameTooltip_AddInstructionLine(GameTooltip, ns.NavigateHint())
				local companion = ns.CompanionHint()
				if companion then
					GameTooltip_AddDisabledLine(GameTooltip, companion)
				end
			end
		end
		GameTooltip:Show()
	end

	---@param button string
	function LegacyForeverPinMixin:OnMouseClickAction(button)
		local uiMapID, x, y = self:Destination()
		if button == "LeftButton" and uiMapID and x and y and self.objective then
			ns.Navigate(uiMapID, x, y, self.objective.text)
		end
	end

	function LegacyForeverPinMixin:OnMouseLeave()
		self.Highlight:Hide()
		if GameTooltip:GetOwner() == self then
			GameTooltip:Hide()
		end
	end
end

local function DefineAreaPinMixin()
	-- One pin per zone map holding every undiscovered area, drawn from the same map
	-- tiles Blizzard reveals on discovery (see MapExplorationPinMixin:RefreshOverlays).
	---@class LegacyForeverAreaPinMixin : Frame, MapCanvasPinMixin
	---@field textures? LegacyTexturePool
	---@field zone? LegacyZone
	---@field hovered? LegacyArea
	---@field drawn table<string, Texture[]>
	---@field legacy table<string, LegacyAreaObjective>
	LegacyForeverAreaPinMixin = CreateFromMixins(MapCanvasPinMixin)

	-- Pools are made on first acquire, as MapExplorationPinMixin does; see LegacyForeverPinMixin:OnAcquired.
	-- Hover is polled rather than caught by a mouse-enabled frame, which would swallow the
	-- map's own clicks (right-click to zoom out, drag to pan). While the cursor is on bare map
	-- (no pin or button above it), the area under it is picked (Model.AreaAt) among all the
	-- zone's areas, explored or not, so an explored label never lights up the unexplored
	-- neighbour whose rectangle overlaps it.
	function LegacyForeverAreaPinMixin:CreatePools()
		self:SetIgnoreGlobalPinScale(true)
		self:UseFrameLevelType("PIN_FRAME_LEVEL_MAP_EXPLORATION")
		self:EnableMouse(false)
		self.textures = CreateTexturePool(self, "OVERLAY")
		self:SetScript("OnUpdate", function()
			if self:GetMap():IsCanvasMouseFocus() then
				self:HoverAt(self:CursorPosition())
			elseif self.hovered then
				self:Highlight(nil)
			end
		end)
		-- The polling stops while the map is closed, so the hovered area's shade and tooltip go now.
		self:SetScript("OnHide", function()
			self:Highlight(nil)
		end)
	end

	function LegacyForeverAreaPinMixin:ReleaseAreas()
		if self.textures then
			self:Highlight(nil)
			self.textures:ReleaseAll()
		end
		self.zone, self.drawn = nil, {}
	end

	function LegacyForeverAreaPinMixin:OnReleased()
		MapCanvasPinMixin.OnReleased(self)
		self:ReleaseAreas()
	end

	---@param tileID number
	---@param x number
	---@param y number
	---@param width number
	---@param height number
	---@param u number
	---@param v number
	---@return Texture
	function LegacyForeverAreaPinMixin:DrawTile(tileID, x, y, width, height, u, v)
		local texture = self.textures:Acquire()
		self:GetMap():AddMaskableTexture(texture)
		texture:SetTexture(tileID, nil, nil, "TRILINEAR")
		texture:SetSize(width, height)
		texture:SetTexCoord(0, u, 0, v)
		texture:ClearAllPoints()
		texture:SetPoint("TOPLEFT", x, -y)
		texture:SetVertexColor(0, 0, 0, AREA_ALPHA)
		texture:Show()
		return texture
	end

	---@param zone LegacyZone
	---@param areas LegacyArea[]
	---@param legacy table<string, LegacyAreaObjective>
	function LegacyForeverAreaPinMixin:OnAcquired(zone, areas, legacy)
		if not self.textures then
			self:CreatePools()
		end
		-- Cleared here too: a pooled pin that missed OnReleased would otherwise stack another shade.
		self:ReleaseAreas()
		self:SetSize(self:GetMap():GetCanvas():GetSize())
		self:SetPosition(0.5, 0.5)
		self.zone, self.legacy = zone, legacy
		for _, area in ipairs(areas) do
			local offsetX, offsetY, width, height = ns.Model.OverlayRect(area.key)
			local textures = {}
			for _, tile in ipairs(ns.Model.OverlayTiles(width, height, zone.tileWidth, zone.tileHeight)) do
				textures[#textures + 1] = self:DrawTile(
					area.tiles[tile.index],
					offsetX + tile.x,
					offsetY + tile.y,
					tile.width,
					tile.height,
					tile.u,
					tile.v
				)
			end
			self.drawn[area.key] = textures
		end
	end
end

-- Hover is polled by the OnUpdate CreatePools installs; see the note there.
local function DefineAreaPinHover()
	-- The cursor in canvas pixels, the space overlay offsets are in.
	---@return number x
	---@return number y
	function LegacyForeverAreaPinMixin:CursorPosition()
		local scale = self:GetEffectiveScale()
		local x, y = GetCursorPosition()
		return x / scale - self:GetLeft(), self:GetTop() - y / scale
	end

	---@param x number
	---@param y number
	function LegacyForeverAreaPinMixin:HoverAt(x, y)
		local index = self.zone and ns.Model.AreaAt(self.zone.areas, x, y)
		local area = index and self.zone.areas[index]
		local shaded = area and self.drawn[area.key] and area or nil
		if shaded ~= self.hovered then
			self:Highlight(shaded)
		end
	end

	---@param area LegacyArea?
	function LegacyForeverAreaPinMixin:Highlight(area)
		if self.hovered then
			for _, texture in ipairs(self.drawn[self.hovered.key]) do
				texture:SetVertexColor(0, 0, 0, AREA_ALPHA)
			end
			-- Only our own tooltip: a pin the cursor just moved onto has already shown its own.
			if GameTooltip:GetOwner() == self then
				GameTooltip:Hide()
			end
		end
		self.hovered = area
		if not area then
			return
		end
		for _, texture in ipairs(self.drawn[area.key]) do
			texture:SetVertexColor(0, 0, 0, AREA_HOVER_ALPHA)
		end
		GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT")
		local objective = self.legacy[area.key]
		if objective then
			AddPinTooltip(GameTooltip, objective.group, objective.objective)
		else
			GameTooltip_SetTitle(GameTooltip, area.name)
			GameTooltip_AddNormalLine(GameTooltip, KIND_LABEL.explore)
		end
		GameTooltip:Show()
	end
end

-- The zone's undiscovered areas that have map tiles; nil for a map without shading data.
---@param mapID number
---@return LegacyZone?
---@return LegacyArea[]?
local function UndiscoveredAreas(mapID)
	local zone = ns.Data.completion[mapID]
	if not (zone and zone.tileWidth and zone.tileHeight) then
		return nil
	end
	local explored = ns.Live.ZoneSnapshot(mapID).explored
	local areas = {}
	for _, area in ipairs(zone.areas) do
		if area.tiles and not explored[area.key] then
			areas[#areas + 1] = area
		end
	end
	return zone, areas
end

---@return MapCanvasDataProviderMixin
local function CreatePinProvider()
	DefinePinMixin()
	DefineAreaPinMixin()
	DefineAreaPinHover()
	local provider = CreateFromMixins(MapCanvasDataProviderMixin)

	function provider:RemoveAllData()
		self:GetMap():RemoveAllPinsByTemplate(PIN_TEMPLATE)
		self:GetMap():RemoveAllPinsByTemplate(AREA_TEMPLATE)
	end

	function provider:RefreshAllData()
		self:RemoveAllData()
		local mapID = self:GetMap():GetMapID()
		local info = mapID and C_Map.GetMapInfo(mapID)
		if info and info.mapType == Enum.UIMapType.Continent then
			if ns.Completion.ShownOnMap() then
				for _, zone in ipairs(ContinentZones(mapID)) do
					self:GetMap():AcquirePin(PIN_TEMPLATE, nil, nil, zone)
				end
			end
			return
		end
		-- Exploration is never pinned: undiscovered areas are shaded, carrying their Legacy
		-- step in the hover, and only place-bound objectives (bosses, dungeons, quests) get pins.
		local zone, areas = nil, nil
		if ShowAreas() then
			zone, areas = UndiscoveredAreas(mapID)
		end
		local shaded, legacy = {}, {}
		for _, area in ipairs(areas or {}) do
			shaded[area.key] = true
		end
		for _, group in ipairs(ZoneGroups(mapID)) do
			for _, objective in ipairs(group.objectives) do
				local entry = objective.entry
				if entry.kind == "explore" and shaded[entry.key] then
					legacy[entry.key] = { group = group, objective = objective }
				elseif entry.x and entry.kind ~= "explore" then
					self:GetMap():AcquirePin(PIN_TEMPLATE, group, objective)
				end
			end
		end
		if areas and #areas > 0 then
			self:GetMap():AcquirePin(AREA_TEMPLATE, zone, areas, legacy)
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
	---@type LegacyForeverMapButtonMixin
	local button = map:AddOverlayFrame("LegacyForeverMapButtonTemplate", "DROPDOWNBUTTON")

	function ns.RefreshMap()
		if map:IsShown() then
			provider:RefreshAllData()
			button:Refresh()
		end
	end
	ns.Live.OnChange(ns.RefreshMap)
	ns.Completion.OnToggle(ns.RefreshMap)
	button:Refresh()
end

EventUtil.ContinueOnAddOnLoaded("Blizzard_WorldMap", Attach)

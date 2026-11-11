---@type string, LegacyForeverNamespace
local _, ns = ...
local L = ns.L

if ns.broken then
	return
end

local PIN_TEMPLATE = "LegacyForeverPinTemplate"
-- Unseen ground reads darker, the fog-of-war convention (a warm tint vanished on the
-- parchment); darker still under the mouse.
local AREA_ALPHA, AREA_HOVER_ALPHA = 0.25, 0.4
-- A cleared dungeon or raid entrance reads as done the way an explored area reads as explored: faded.
local DONE_ALPHA = 0.4
-- Lists in the map menu scroll past 20 rows of 20 px: Blizzard's submenus never clamp to the screen (WFA-36).
local MENU_EXTENT = 20 * 20
local POINTS_ICON = ns.POINTS_ICON
-- The terrain glow: a soft wide stroke under a brighter core, in the Legacy gold, along each area's real
-- ground. The strip is a feather texture, the same for every area.
local GLOW = "Interface\\AddOns\\LegacyForever\\media\\Glow"
local GOLD_R, GOLD_G, GOLD_B = 1, 0.8, 0.35
local GLOW_WIDE, GLOW_WIDE_ALPHA = 11, 0.2
local GLOW_CORE, GLOW_CORE_ALPHA = 2.5, 0.75
local GLOW_HOVER = 1.7
-- Moving the player moves the outline pins at most once a second, never once a frame.
local PLAYER_REFRESH = 1

local KIND_LABEL = {
	explore = L["Undiscovered area"],
	instance = L["Dungeon or raid"],
	kill = L["Defeat"],
	quest = L["Quest"],
	reputation = REPUTATION,
}

---@param challenge number
---@return string?
local function PointsText(challenge)
	local points = ns.Live.Points(challenge)
	if points then
		return L["%s %d Legacy |4point:points;"]:format(ns.Art.Markup(POINTS_ICON, 14), points)
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
	local line
	if not points then
		line = L["Part of %s"]:format(name)
	elseif ns.MapContents.IsExploration(group) then
		line = L["Part of %s: %s for exploring every zone"]:format(name, points)
	else
		line = L["Part of %s: %s for the whole challenge"]:format(name, points)
	end
	GameTooltip_AddNormalLine(tooltip, line)
end

-- "9 of 12 areas left" for an exploration achievement, from live progress.
---@param group LegacyGroup
---@return string
local function AreasLeftText(group)
	local done, total = ns.Model.Tally(ns.Live.Criteria(group.achievement) or {})
	return L["%s: %d of %d areas left"]:format(ns.Live.Name(group.achievement), total - done, total)
end

-- An outlined area's tooltip: the same name and zone progress line as a shaded one, plus how far the
-- nearest part of its ground is when the player is on this map. Only the area's pin can be clicked, so the
-- click line (and the companion suggestion under it) appears when `clickable`: bare map never takes the
-- mouse by design, and a hover there must not promise a click that does nothing.
---@param tooltip GameTooltip
---@param area LegacyOutlineArea
---@param yards? number
---@param clickable boolean
local function AddOutlineTooltip(tooltip, area, yards, clickable)
	GameTooltip_SetTitle(tooltip, area.name)
	GameTooltip_AddNormalLine(tooltip, L["Undiscovered area"])
	if area.objective then
		GameTooltip_AddHighlightLine(tooltip, AreasLeftText(area.objective.group))
	end
	if yards then
		GameTooltip_AddNormalLine(tooltip, L["%d yards away"]:format(yards))
	end
	if clickable then
		GameTooltip_AddInstructionLine(tooltip, ns.NavigateHint())
		local companion = ns.CompanionHint()
		if companion then
			GameTooltip_AddDisabledLine(tooltip, companion)
		end
	end
end

---@param tooltip GameTooltip
---@param group LegacyGroup
local function AddGroupTooltip(tooltip, group)
	if ns.MapContents.IsExploration(group) then
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
		if objective.entry.kind == "instance" and objective.entry.instance then
			local minimum, maximum, hint = ns.DungeonLevelRange(objective.entry.instance)
			if minimum and maximum then
				local color = GetQuestDifficultyColor(minimum)
				local range = ("%d-%d"):format(minimum, maximum)
				local text = RGBTableToColorCode(color) .. range .. FONT_COLOR_CODE_CLOSE
				GameTooltip_AddNormalLine(tooltip, L["Recommended levels: %s (AtlasLoot)"]:format(text))
			elseif hint then
				GameTooltip_AddDisabledLine(tooltip, hint)
			end
		end
		if objective.done then
			GameTooltip_AddColoredLine(tooltip, L["Already complete"], GREEN_FONT_COLOR)
		end
	end
	AddRewardLine(tooltip, group)
end

---@param tooltip GameTooltip
---@param zone LegacyContinentZone
local function AddZoneTooltip(tooltip, zone)
	GameTooltip_SetTitle(tooltip, zone.name)
	GameTooltip_AddHighlightLine(
		tooltip,
		(zone.count == 1 and L["%d Legacy objective left"] or L["%d Legacy objectives left"]):format(zone.count)
	)
	for _, group in ipairs(zone.groups) do
		GameTooltip_AddNormalLine(tooltip, L["%s: %d left"]:format(ns.Live.Name(group.challenge), #group.objectives))
	end
	ns.Completion.AddSummary(tooltip, zone.uiMapID)
	GameTooltip_AddInstructionLine(tooltip, L["Click the zone to see where."])
end

---@param key LegacySwitchKey
local function ToggleSetting(key)
	ns.Saved.Set(key, not ns.Saved.Get(key))
end

--[[ Button: sits in the map's top-right button column and lists this map's objectives ]]

-- Each entry is a checkbox for our own tracker (Forever refuses Blizzard's): a zone's
-- entry tracks only this zone's share of its challenge (Model.ZoneKey), "No fixed location"
-- the whole challenge. The tracker's challenge names open the Legacy panel.
local TRACK_HINT = L["Click to track, with live progress."]
-- The same line as the switch's row on the Settings page.
local ENTRANCES_TOOLTIP = L["Turn this off if another addon already marks them. The Legacy map menu still lists them."]

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
	local icon = ns.Completion.Icon(ns.MapContents.IsExploration(group) and "areas" or "legacy", 14)
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
		GameTooltip_AddNormalLine(tooltip, L["Levels, skills, ranks and anything without a fixed place."])
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
	local submenu = root:CreateButton(ChallengeText(L["No fixed location"], #unlocated))
	submenu:SetScrollMode(MENU_EXTENT)
	for _, top in ipairs(tops) do
		local topMenu = submenu:CreateButton(top.name)
		topMenu:SetScrollMode(MENU_EXTENT)
		for _, sub in ipairs(top.subs) do
			local subMenu = topMenu:CreateButton(sub.name)
			subMenu:SetScrollMode(MENU_EXTENT)
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
	root:SetScrollMode(MENU_EXTENT)
	local mapInfo = uiMapID and C_Map.GetMapInfo(uiMapID)
	root:CreateTitle(mapInfo and mapInfo.name or ns.TITLE)
	local groups = ns.MapContents.Objectives(uiMapID)
	if #groups == 0 then
		root:CreateTitle("|cff808080" .. L["Nothing left to do here"] .. "|r")
	end
	for _, group in ipairs(groups) do
		AddGroup(root, group)
	end
	root:CreateDivider()
	root:CreateCheckbox(L["Show undiscovered areas"], ns.Saved.Get, ToggleSetting, "showAreas")
	local outlines = root:CreateCheckbox(L["Show where to discover areas"], ns.Saved.Get, ToggleSetting, "showOutlines")
	outlines:SetTooltip(function(tooltip)
		GameTooltip_SetTitle(tooltip, L["Show where to discover areas"])
		GameTooltip_AddNormalLine(
			tooltip,
			L["Glows each undiscovered area's real ground, with a pin at its edge. Areas without terrain data keep the shading."]
		)
	end)
	local entrances =
		root:CreateCheckbox(L["Show dungeon and raid entrances"], ns.Saved.Get, ToggleSetting, "showEntrances")
	entrances:SetTooltip(function(tooltip)
		GameTooltip_SetTitle(tooltip, L["Show dungeon and raid entrances"])
		GameTooltip_AddNormalLine(tooltip, ENTRANCES_TOOLTIP)
	end)
	AddUnlocated(root)
	root:CreateDivider()
	ns.Completion.AddMenu(root)
	root:CreateDivider()
	ns.Live.LockPanelEntry(root:CreateButton(L["Open the Legacy panel"], ToggleLegacySystemUI))
	root:CreateDivider()
	root:CreateCheckbox(L["What's new after an update"], ns.Saved.Get, ToggleSetting, "whatsNew")
	local family =
		root:CreateCheckbox(L["Suggest my other Forever addons"], ns.Saved.Get, ToggleSetting, "suggestFamily")
	family:SetTooltip(function(tooltip)
		GameTooltip_SetTitle(tooltip, L["Suggest my other Forever addons"])
		GameTooltip_AddNormalLine(
			tooltip,
			L["Show a quiet line where one of my other Forever addons would help. Only for addons you don't have."]
		)
	end)
end

---@class LegacyForeverMapButtonMixin : DropdownButton
---@field GetParent fun(self: LegacyForeverMapButtonMixin): WorldMapFrame
---@field Count FontString
---@field Icon Texture
---@field count number
LegacyForeverMapButtonMixin = {}

-- MapCanvas.FrameUnder makes the button with no parent, and SetupMenu builds the menu at once while it shows: the map
-- is not there yet. Opening the menu always builds it again (DropdownButtonMixin:OpenMenu), by then under the map.
function LegacyForeverMapButtonMixin:OnLoad()
	self:SetupMenu(function(_, root)
		local map = self:GetParent()
		if map then
			BuildMenu(root, map:GetMapID())
		end
	end)
	-- Under the gamepad interface a menu opened from our own code takes the gamepad focus under our taint (see
	-- ns.GamepadUI). Every switch in this menu is also on the addon's Settings page (UI/Settings.lua), so a gamepad
	-- player loses nothing by a press showing a line instead.
	local open = self.OpenMenu
	self.OpenMenu = function(button)
		if ns.GamepadUI() then
			UIErrorsFrame:AddMessage(L["This menu needs mouse and keyboard."], 1, 1, 0)
			return
		end
		return open(button)
	end
end

-- Below whichever other top-right buttons are actually showing there: rulesets disable Blizzard's
-- (C_GameRules), layout addons move them, and this client keeps them unnamed, so the map's own list
-- of overlay frames is checked per refresh.
local BUTTON_SPACING = -32

---@param map WorldMapFrame
---@param own Frame
---@return number
local function TopRightOffset(map, own)
	local offsetY = -2
	-- The map's own list holds Blizzard's tracking options and pin buttons as well as ours.
	---@diagnostic disable-next-line: undefined-field
	for _, button in ipairs(map.overlayFrames or {}) do
		if button ~= own and button:IsShown() and button:GetPoint(1) == "TOPRIGHT" then
			offsetY = offsetY + BUTTON_SPACING
		end
	end
	-- Current Krowi buttons stack from TOPLEFT on Forever. Older copies may still use this corner.
	local index = 1
	local other = _G["Krowi_WorldMapButtons" .. index]
	while other do
		if other:IsShown() and other:GetPoint(1) == "TOPRIGHT" then
			return offsetY + BUTTON_SPACING
		end
		index = index + 1
		other = _G["Krowi_WorldMapButtons" .. index]
	end
	return offsetY
end

function LegacyForeverMapButtonMixin:Refresh()
	---@type WorldMapFrame
	local map = self:GetParent()
	self:ClearAllPoints()
	self:SetPoint("TOPRIGHT", map:GetCanvasContainer(), "TOPRIGHT", -4, TopRightOffset(map, self))
	local _, count = ns.MapContents.Objectives(map:GetMapID())
	self.Count:SetFontObject(
		count >= 100 and GameFontNormalTiny or count >= 10 and GameFontNormalSmall or GameFontNormal
	)
	self.Count:SetText(count > 0 and tostring(count) or "")
	self.Icon:SetDesaturated(count == 0)
	self.count = count
end

-- Made shown with no parent, the button shows as it is made, before MapCanvas.FrameUnder sets it on the map; Attach
-- refreshes it once it is there.
function LegacyForeverMapButtonMixin:OnShow()
	if self:GetParent() then
		self:Refresh()
	end
end

function LegacyForeverMapButtonMixin:OnEnter()
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip_SetTitle(GameTooltip, ns.TITLE)
	if self.count and self.count > 0 then
		local line = self.count == 1 and L["%d unfinished Legacy objective on this map."]
			or L["%d unfinished Legacy objectives on this map."]
		GameTooltip_AddNormalLine(GameTooltip, line:format(self.count))
	else
		GameTooltip_AddNormalLine(GameTooltip, L["No unfinished Legacy objectives with a place on this map."])
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

--[[ Pins: one per unfinished objective the data can place on this map, on frames of our own (ForeverCore's canvas) ]]

---@class LegacyObjectivePin : ForeverCanvasPin
---@field Icon Texture
---@field Portal Texture
---@field Highlight Texture
---@field group? LegacyGroup
---@field objective? LegacyObjective
---@field zone? LegacyContinentZone
---@field outline? LegacyOutlinePin the outlined area's place, when this pin stands on one
---@field done boolean a cleared dungeon or raid entrance, drawn faded
local ObjectivePin = CreateFromMixins(ns.core.MapCanvas.PinMixin)

function ObjectivePin:OnLoad()
	self.takesMouse = true
	self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
	self:SetScalingLimits(1, 1.0, 1.2)
end

---@param group LegacyGroup?
---@param objective LegacyObjective?
---@param zone LegacyContinentZone?
---@param outline? LegacyOutlinePin
function ObjectivePin:OnAcquired(group, objective, zone, outline)
	self.group = group
	self.objective = objective
	self.zone = zone
	self.outline = outline
	self.done = objective ~= nil and objective.done == true
	-- A zone badge lets the click open the zone below it; an outlined area's click sets a waypoint.
	self.clicks = self:Destination() ~= nil or outline ~= nil
	self:Layout(objective and objective.entry)
	if outline then
		self:SetPosition(outline.x, outline.y)
	elseif zone then
		self:SetPosition(zone.x, zone.y)
	elseif objective then
		self:SetPosition(objective.entry.x, objective.entry.y)
	end
	self:SetAlpha(self.done and DONE_ALPHA or 1)
end

-- At an entrance: the retail portal the map already uses there, with a small shield on its corner, so the
-- entrance still reads as one and the Legacy step as a badge on it. Anywhere else: the shield alone.
---@param entry LegacyEntry?
function ObjectivePin:Layout(entry)
	local instance = entry and entry.instance
	self.Icon:ClearAllPoints()
	self.Highlight:ClearAllPoints()
	self.Portal:SetShown(instance ~= nil)
	if entry and instance then
		local atlas = entry.raid and "Raid" or "Dungeon"
		self:SetSize(32, 32)
		self.Portal:SetAtlas(atlas) -- art-ok: both portals are square atlases, over the 32x32 pin
		ns.Art.Fit(self.Icon, POINTS_ICON, 12, 17)
		self.Icon:SetPoint("BOTTOMRIGHT", 2, -2)
		self.Highlight:SetAtlas(atlas) -- art-ok: the portal again, over the square Portal texture
		self.Highlight:SetAllPoints(self.Portal)
	else
		self:SetSize(20, 20)
		ns.Art.Fit(self.Icon, POINTS_ICON, 14, 20)
		self.Icon:SetPoint("CENTER")
		self.Highlight:SetAtlas(POINTS_ICON) -- art-ok: the shield again, over the Icon that Art.Fit sized
		self.Highlight:SetAllPoints(self.Icon)
	end
end

-- Where a click takes the player: only an objective with coordinates in the data, on the zone map they are for.
---@return number? uiMapID
---@return number? x
---@return number? y
function ObjectivePin:Destination()
	local entry = self.objective and self.objective.entry
	if self.group and entry and entry.x and entry.y then
		return self.group.uiMapID, entry.x, entry.y
	end
end

function ObjectivePin:OnMouseEnter()
	self.Highlight:Show()
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	if self.outline then
		AddOutlineTooltip(GameTooltip, self.outline.area, self.outline.yards, true)
	elseif self.zone then
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
function ObjectivePin:OnMouseClickAction(button)
	if button ~= "LeftButton" then
		return
	end
	if self.outline then
		ns.NavigateOutline(self.outline.uiMapID, self.outline.area, self.outline.x, self.outline.y)
		return
	end
	local uiMapID, x, y = self:Destination()
	if uiMapID and x and y and self.objective then
		ns.Navigate(uiMapID, x, y, self.objective.text)
	end
end

function ObjectivePin:OnMouseLeave()
	self.Highlight:Hide()
	if GameTooltip:GetOwner() == self then
		GameTooltip:Hide()
	end
end

-- One frame per zone map holding every undiscovered area, drawn from the same map tiles Blizzard reveals on
-- discovery (see MapExplorationPinMixin:RefreshOverlays), or, with "Show where to discover areas" on, as a gold
-- glow along each area's real ground (MapContents.OutlineAt). It never takes the mouse, which would swallow the
-- map's own clicks (right-click to zoom out, drag to pan): while the cursor is on bare map, the area under it is
-- polled (MapContents.OutlineAt, then MapContents.AreaAt for the areas that keep their shading).
---@class LegacyAreaPin : ForeverCanvasPin
---@field textures LegacyTexturePool
---@field shade? LegacyShade
---@field outline? LegacyOutline
---@field hovered? LegacyShadedArea|LegacyOutlineArea
---@field cursorX? number
---@field cursorY? number
---@field drawn table<string, Texture[]>
---@field glow table<string, LegacyGlowLine[]>
---@field lines LegacyGlowLine[]
---@field used number
---@field width number
---@field height number
---@field shadeAlpha number
---@field playerX? number
---@field playerY? number
---@field clock number
local AreaPin = CreateFromMixins(ns.core.MapCanvas.PinMixin)

-- Set by Attach: moves the outline pins to the player's new place while the map shows.
---@type (fun()|nil)
local RefreshOutlinePins

function AreaPin:OnLoad()
	self:SetIgnoreGlobalPinScale(true)
	-- No level type: the canvas's own level plus one, above the map art and below every pin, ours, Blizzard's or
	-- another addon's. Blizzard's exploration level is about 2,000, which drew the shading and its glow over other
	-- addons' markers on the canvas (Leatrix Maps puts its points of interest at level 100).
	self.textures = CreateTexturePool(self, "OVERLAY")
	self.drawn, self.glow, self.lines = {}, {}, {}
	self.used = 0
	self.clock = 0
	-- The area scan runs only when the cursor moves over the canvas; the position is in canvas pixels, so a zoom or
	-- pan under a still cursor counts as a move. The player's place is read once a second, not every frame.
	self:SetScript("OnUpdate", function(_, elapsed)
		self.clock = self.clock + elapsed
		if self.outline and self.clock >= PLAYER_REFRESH then
			self.clock = 0
			if RefreshOutlinePins then
				RefreshOutlinePins()
			end
		end
		if self:GetMap():IsCanvasMouseFocus() then
			local x, y = self:CursorPosition()
			if x ~= self.cursorX or y ~= self.cursorY then
				self.cursorX, self.cursorY = x, y
				self:HoverAt(x, y)
			end
		else
			self.cursorX, self.cursorY = nil, nil
			if self.hovered then
				self:Highlight(nil)
			end
		end
	end)
	-- The polling stops while the map is closed, so the hovered area's shade and tooltip go now.
	self:SetScript("OnHide", function()
		self:Highlight(nil)
	end)
end

function AreaPin:OnReleased()
	self:Highlight(nil)
	self.textures:ReleaseAll()
	for _, line in ipairs(self.lines) do
		line:Hide()
	end
	self.shade, self.outline = nil, nil
	self.drawn, self.glow = {}, {}
	self.used = 0
	self.cursorX, self.cursorY = nil, nil
end

local masks = setmetatable({}, { __mode = "k" })

---@param tile LegacyShadeTile
---@return Texture
function AreaPin:DrawTile(tile)
	local texture = self.textures:Acquire()
	if masks[texture] then
		texture:RemoveMaskTexture(masks[texture])
		masks[texture] = nil
	end
	local mask = self:GetMap():GetMaskTexture()
	if mask and self:GetMap():GetUseMaskTexture() then
		texture:AddMaskTexture(mask)
		masks[texture] = mask
	end
	-- art-ok: a map tile at the size and crop the generated data gives it, and the pool only ever draws files
	texture:SetTexture(tile.file, nil, nil, "TRILINEAR")
	texture:SetSize(tile.width, tile.height)
	texture:SetTexCoord(0, tile.u, 0, tile.v)
	texture:ClearAllPoints()
	texture:SetPoint("TOPLEFT", tile.x, -tile.y)
	texture:SetVertexColor(0, 0, 0, self.shadeAlpha)
	texture:Show()
	return texture
end

-- One line of the glow from the pool; a shorter ring hides the lines it does not need.
---@param u1 number
---@param v1 number
---@param u2 number
---@param v2 number
---@param thickness number
---@param alpha number
---@return Line
function AreaPin:DrawEdge(u1, v1, u2, v2, thickness, alpha)
	local index = self.used + 1
	local line = self.lines[index]
	if not line then
		local created = self:CreateLine(nil, "OVERLAY")
		---@cast created LegacyGlowLine
		self.lines[index] = created
		line = created
	end
	self.used = index
	ns.Art.GlowLine(line, GLOW, thickness, GOLD_R, GOLD_G, GOLD_B, alpha)
	line.baseAlpha = alpha
	line:SetStartPoint("TOPLEFT", self, u1 * self.width, -v1 * self.height)
	line:SetEndPoint("TOPLEFT", self, u2 * self.width, -v2 * self.height)
	line:Show()
	return line
end

-- Every ring of every area, as a wide soft stroke under a brighter core.
---@param outline LegacyOutline
function AreaPin:Paint(outline)
	self.outline = outline
	self.used = 0
	for _, area in ipairs(outline.areas) do
		local lines = {}
		for _, ring in ipairs(area.rings) do
			local count = #ring / 2
			for index = 1, count do
				local following = index % count + 1
				local u1, v1, u2, v2 =
					ring[index * 2 - 1], ring[index * 2], ring[following * 2 - 1], ring[following * 2]
				if not (u1 == u2 and v1 == v2) then
					lines[#lines + 1] = self:DrawEdge(u1, v1, u2, v2, GLOW_WIDE, GLOW_WIDE_ALPHA)
					lines[#lines + 1] = self:DrawEdge(u1, v1, u2, v2, GLOW_CORE, GLOW_CORE_ALPHA)
				end
			end
		end
		self.glow[area.key] = lines
	end
	for index = self.used + 1, #self.lines do
		self.lines[index]:Hide()
	end
end

---@param shade? LegacyShade
---@param alpha number
---@param outline? LegacyOutline
function AreaPin:OnAcquired(shade, alpha, outline)
	local width, height = self:GetMap():GetCanvas():GetSize()
	self:SetSize(width, height)
	self:SetPosition(0.5, 0.5)
	self.width, self.height = width, height
	self.shade, self.shadeAlpha = shade, alpha
	if shade then
		for _, shaded in ipairs(shade.areas) do
			local textures = {}
			for _, tile in ipairs(shaded.tiles) do
				textures[#textures + 1] = self:DrawTile(tile)
			end
			self.drawn[shaded.area.key] = textures
		end
	end
	if outline then
		self:Paint(outline)
	else
		self.outline = nil
		for _, line in ipairs(self.lines) do
			line:Hide()
		end
	end
end

-- The cursor in canvas pixels, the space overlay offsets are in.
---@return number x
---@return number y
function AreaPin:CursorPosition()
	local scale = self:GetEffectiveScale()
	local x, y = GetCursorPosition()
	return x / scale - self:GetLeft(), self:GetTop() - y / scale
end

---@param x number
---@param y number
function AreaPin:HoverAt(x, y)
	local target
	if self.outline then
		target = ns.MapContents.OutlineAt(self.outline, x / self.width, y / self.height)
	end
	if not target then
		target = self.shade and ns.MapContents.AreaAt(self.shade, x, y) or nil
	end
	if target ~= self.hovered then
		self:Highlight(target)
	end
end

-- The hovered area's own drawing brightens: a shaded area's tiles, or an outlined area's glow.
---@param area LegacyShadedArea|LegacyOutlineArea?
function AreaPin:Highlight(area)
	local previous = self.hovered
	if previous then
		local before = previous.outline and previous --[[@as LegacyOutlineArea]]
		if before then
			for _, line in ipairs(self.glow[before.key] or {}) do
				line:SetAlpha(line.baseAlpha)
			end
		else
			local shaded = previous --[[@as LegacyShadedArea]]
			for _, texture in ipairs(self.drawn[shaded.area.key]) do
				texture:SetVertexColor(0, 0, 0, self.shadeAlpha)
			end
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
	GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT")
	local outlined = area.outline and area --[[@as LegacyOutlineArea]]
	if outlined then
		for _, line in ipairs(self.glow[outlined.key] or {}) do
			line:SetAlpha(line.baseAlpha * GLOW_HOVER)
		end
		local yards
		if self.outline then
			local _, _, distance = ns.MapContents.OutlinePoint(self.outline.zone, outlined, self.playerX, self.playerY)
			yards = distance
		end
		AddOutlineTooltip(GameTooltip, outlined, yards, false)
	else
		local shaded = area --[[@as LegacyShadedArea]]
		for _, texture in ipairs(self.drawn[shaded.area.key]) do
			texture:SetVertexColor(0, 0, 0, AREA_HOVER_ALPHA)
		end
		local objective = shaded.objective
		if objective then
			AddPinTooltip(GameTooltip, objective.group, objective.objective)
		else
			GameTooltip_SetTitle(GameTooltip, shaded.area.name)
			GameTooltip_AddNormalLine(GameTooltip, KIND_LABEL.explore)
		end
	end
	GameTooltip:Show()
end

-- Leatrix Maps reveals the map's own tiles whether or not they were explored, so a black veil over ground it has
-- already shown is the opposite of what the player asked for. Keep exploration hovers without resting shading.
---@return boolean
local function RevealedByLeatrix()
	return type(LeaMapsDB) == "table" and LeaMapsDB.RevealMap == "On"
end

--[[ Wiring ]]

-- The player's place on this map, or nil when the player is on another one. The client's point is a
-- vector with GetXY, absent where the map does not cover the player.
---@param uiMapID number?
---@return number? u
---@return number? v
local function PlayerPosition(uiMapID)
	if not uiMapID then
		return nil
	end
	local position = C_Map.GetPlayerMapPosition(uiMapID, "player")
	if not position then
		return nil
	end
	local x, y = position:GetXY()
	if not x or not y then
		return nil
	end
	return x, y
end

local function Attach()
	local map = WorldMapFrame
	local MapCanvas = ns.core.MapCanvas
	local pins = MapCanvas.Pool(map, ObjectivePin, { template = PIN_TEMPLATE, marker = "legacy" })
	local areas = MapCanvas.Pool(map, AreaPin)
	local refreshPending = false
	-- The outlined areas' pins, and the drawing they stand on, as the last Draw left them.
	---@type LegacyObjectivePin[]
	local outlinePins = {}
	---@type LegacyOutline?
	local outlineDrawn
	---@type LegacyAreaPin?
	local areaPin
	-- The player's place the pins were last placed at, so a still player costs no second pass.
	local placed, placedU, placedV

	-- The outline pins follow the player: the point nearest the player on each area's ground, or the
	-- area's first point while the player is elsewhere.
	local function PlaceOutlinePins()
		local zone = outlineDrawn and outlineDrawn.zone
		if not (zone and map:IsShown()) then
			return
		end
		local u, v = PlayerPosition(map:GetMapID())
		if placed and u == placedU and v == placedV then
			return
		end
		placed, placedU, placedV = true, u, v
		for _, pin in ipairs(outlinePins) do
			local place = pin.outline
			if place then
				local x, y, yards = ns.MapContents.OutlinePoint(zone, place.area, u, v)
				place.x, place.y, place.yards = x, y, yards
				pin:SetPosition(x, y)
			end
		end
		if areaPin then
			areaPin.playerX, areaPin.playerY = u, v
		end
	end
	RefreshOutlinePins = PlaceOutlinePins

	-- Our pins are our own frames, but a pass-through change is refused in combat, so a redraw in combat hides them
	-- and waits for its end.
	local function Draw()
		if InCombatLockdown() then
			refreshPending = true
			MapCanvas.SetShown(map, false)
			return
		end
		refreshPending = false
		pins:ReleaseAll()
		areas:ReleaseAll()
		outlinePins = {}
		placed = false
		local uiMapID = map:GetMapID()
		local drawn = ns.MapContents.Drawn(uiMapID)
		outlineDrawn = drawn.outline
		for _, zone in ipairs(drawn.badges) do
			pins:Acquire(nil, nil, zone)
		end
		for _, pin in ipairs(drawn.pins) do
			pins:Acquire(pin.group, pin.objective)
		end
		local u, v
		if drawn.outline then
			u, v = PlayerPosition(uiMapID)
			for _, area in ipairs(drawn.outline.areas) do
				local x, y, yards = ns.MapContents.OutlinePoint(drawn.outline.zone, area, u, v)
				local objective = area.objective
				local pin = pins:Acquire(
					objective and objective.group,
					objective and objective.objective,
					nil,
					{ uiMapID = uiMapID, area = area, x = x, y = y, yards = yards }
				)
				---@cast pin LegacyObjectivePin
				outlinePins[#outlinePins + 1] = pin
			end
		end
		if drawn.shade or drawn.outline then
			local pin = areas:Acquire(drawn.shade, RevealedByLeatrix() and 0 or AREA_ALPHA, drawn.outline)
			---@cast pin LegacyAreaPin
			areaPin = pin
			pin.playerX, pin.playerY = u, v
		else
			areaPin = nil
		end
		MapCanvas.SetShown(map, true)
	end

	-- A button of our own in the map's top-right column; Refresh anchors it (see TopRightOffset).
	local button = MapCanvas.FrameUnder("DropdownButton", map, "LegacyForeverMapButtonTemplate")
	---@cast button LegacyForeverMapButtonMixin
	button:SetFrameStrata("HIGH")

	MapCanvas.Watch(map, function(_, what)
		if what == "show" or what == "map" or what == "size" then
			Draw()
			button:Refresh()
		end
	end)
	local events = CreateFrame("Frame")
	events:RegisterEvent("PLAYER_REGEN_ENABLED")
	events:RegisterEvent("CVAR_UPDATE")
	events:SetScript("OnEvent", function(_, event, cvar)
		if map:IsShown() and (refreshPending or event == "CVAR_UPDATE" and cvar == "showDungeonEntrancesOnMap") then
			Draw()
		end
	end)

	function ns.OpenMapMenu()
		if not button:IsMenuOpen() then
			button:OpenMenu()
		end
	end

	function ns.RefreshMap()
		if map:IsShown() then
			Draw()
			button:Refresh()
		end
	end
	-- Progress moves the pins and the "On the world map" switch the badges: zone completion's notice covers both.
	ns.ZoneCompletion.OnChange(ns.RefreshMap)
	ns.Saved.OnChange(function(key)
		if key == "showAreas" or key == "showOutlines" or key == "showEntrances" then
			ns.RefreshMap()
		end
	end)
	button:Refresh()
end

EventUtil.ContinueOnAddOnLoaded("Blizzard_WorldMap", Attach)

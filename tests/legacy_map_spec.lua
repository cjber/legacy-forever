-- Run from the repository root: luajit tests/legacy_map_spec.lua
-- UI/Map.lua on ForeverCore's shared map canvas on a world map that fails on any write (core's tests/strict_map.lua):
-- Legacy draws its pins, undiscovered areas and map button on frames of its own, adds no data provider, acquires no
-- pin and adds no overlay frame, and keeps every pin's behaviour: placing, scaling, tooltips, clicks, and waiting out
-- combat.
local checks = 0
local function check(condition, label)
	checks = checks + 1
	assert(condition, label)
end

local Kit = dofile("tests/legacy_map_kit.lua")
Kit.Install(_G)

local attach
EventUtil = {
	ContinueOnAddOnLoaded = function(addon, callback)
		assert(addon == "Blizzard_WorldMap")
		attach = callback
	end,
}
REPUTATION = "Reputation"
WHITE_FONT_COLOR = {}
Enum = {}

-- The tooltip: who owns it and what it says.
local tooltip = { lines = {} }
GameTooltip = {
	SetOwner = function(_, owner)
		tooltip.owner, tooltip.lines = owner, {}
	end,
	GetOwner = function()
		return tooltip.owner
	end,
	Show = function()
		tooltip.shown = true
	end,
	Hide = function()
		tooltip.shown, tooltip.owner = false, nil
	end,
}
local function Line(_, text)
	tooltip.lines[#tooltip.lines + 1] = text
end
GameTooltip_SetTitle, GameTooltip_AddNormalLine, GameTooltip_AddHighlightLine = Line, Line, Line
GameTooltip_AddInstructionLine, GameTooltip_AddDisabledLine = Line, Line
GameTooltip_AddColoredLine = Line

-- Where the player is on the map being drawn, as C_Map answers it for the outline pins.
local playerPosition = { 0.35, 0.25 }
C_Map = {
	GetPlayerMapPosition = function()
		if not playerPosition then
			return nil
		end
		return {
			GetXY = function()
				return playerPosition[1], playerPosition[2]
			end,
		}
	end,
}

-- What the map shows: on map 1429 an objective with a place and a shaded area; on continent 1415 a zone badge.
local drawCalls = 0
local group = { challenge = 10, achievement = 10, uiMapID = 1429, objectives = {} }
local objective = { text = "Slay Hogger", entry = { kind = "kill", x = 0.25, y = 0.5 } }
group.objectives[1] = objective
local badge = { name = "Elwynn Forest", uiMapID = 1429, x = 0.6, y = 0.7, count = 1, groups = { group } }
local area = { name = "Northshire", key = "0:0:1:1" }
local shade = {
	areas = { { area = area, tiles = { { file = 1, x = 0, y = 0, width = 256, height = 256, u = 1, v = 1 } } } },
}
-- The outlined area on 1429: one square of real ground, filled from its terrain, with a pin of its own.
local outlineArea = {
	key = "outline:0",
	name = "Northshire Ground",
	rings = { { 0.2, 0.2, 0.4, 0.2, 0.4, 0.4, 0.2, 0.4 } },
	outline = true,
}
local outline = {
	uiMapID = 1429,
	zone = { width = 1000, height = 700, areas = {} },
	areas = { outlineArea },
	byKey = { [outlineArea.key] = outlineArea },
}
local drawn = {
	[1429] = {
		badges = {},
		pins = { { group = group, objective = objective } },
		shade = shade,
		outline = outline,
	},
	[1430] = { badges = {}, pins = {} },
	[1415] = { badges = { badge }, pins = {} },
}
local navigated, outlined, hovering, switched = {}, {}, nil, nil
local settings = { showAreas = true, showEntrances = true, showOutlines = false }

local ns = {
	ShadingMasks = {
		[1429] = {
			["outline:0"] = { 160, 93, 512, 256, "Interface\\AddOns\\LegacyForever\\media\\legacy-masks\\Fixture" },
		},
	},
	L = setmetatable({}, {
		__index = function(_, key)
			return key
		end,
	}),
	POINTS_ICON = "UI-Legacy-Points-icon-c60",
	Art = {
		Fit = function() end,
	},
	GamepadUI = function()
		return false
	end,
	Live = {
		Name = function()
			return "Defender of Elwynn"
		end,
		Points = function()
			return nil
		end,
	},
	MapContents = {
		Drawn = function(uiMapID)
			drawCalls = drawCalls + 1
			local drawing = drawn[uiMapID] or { badges = {}, pins = {} }
			if drawing.outline and not settings.showOutlines then
				return { badges = drawing.badges, pins = drawing.pins, shade = drawing.shade }
			end
			return drawing
		end,
		Objectives = function()
			return {}, 1
		end,
		IsExploration = function()
			return false
		end,
		AreaAt = function()
			return hovering
		end,
		OutlineAt = function(data, u, v)
			for _, shape in ipairs(data.areas) do
				if u > 0.2 and u < 0.4 and v > 0.2 and v < 0.4 then
					return shape
				end
			end
		end,
		-- UI/MapContents.lua ear-clips each ring; this stub fans a convex ring, which is enough for a square.
		Triangles = function(rings)
			local triangles = {}
			for _, ring in ipairs(rings) do
				for index = 3, #ring / 2 do
					triangles[#triangles + 1] = {
						ring[1],
						ring[2],
						ring[(index - 1) * 2 - 1],
						ring[(index - 1) * 2],
						ring[index * 2 - 1],
						ring[index * 2],
					}
				end
			end
			return triangles
		end,
		OutlinePoint = function(zone, shape, u, v)
			local x, y = shape.rings[1][1], shape.rings[1][2]
			local yards
			if u then
				local best = math.huge
				for _, ring in ipairs(shape.rings) do
					for index = 1, #ring, 2 do
						local dx, dy = (ring[index] - u) * zone.width, (ring[index + 1] - v) * zone.height
						local distance = dx * dx + dy * dy
						if distance < best then
							best, x, y = distance, ring[index], ring[index + 1]
						end
					end
				end
				yards = math.sqrt(best)
			end
			return x, y, yards
		end,
	},
	Completion = { AddSummary = function() end },
	NavigateHint = function()
		return "Click to travel there."
	end,
	CompanionHint = function()
		return nil
	end,
	Navigate = function(uiMapID, x, y, title)
		navigated[#navigated + 1] = { uiMapID, x, y, title }
	end,
	NavigateOutline = function(uiMapID, shape, x, y)
		outlined[#outlined + 1] = { uiMapID, shape, x, y }
	end,
	ZoneCompletion = { OnChange = function() end },
	Saved = {
		Get = function(key)
			return settings[key] ~= false
		end,
		OnChange = function(callback)
			switched = callback
		end,
	},
}

ForeverCore = dofile("tests/forever_core.lua").install(_G, {
	"Core/SafeCall.lua",
	"Core/Log.lua",
	"UI/Report.lua",
	"UI/Credits.lua",
	"UI/MapCanvas.lua",
	"Expose.lua",
})
ns.core = ForeverCore.Register("LegacyForever", {})
assert(loadfile("UI/Shading.lua"))("LegacyForever", ns)
assert(loadfile("UI/Map.lua"))("LegacyForever", ns)
check(attach, "UI/Map.lua waits for the world map to load")
attach()

local function Pins()
	local shown = {}
	for _, frame in ipairs(Kit.Made("LegacyForeverPinTemplate")) do
		if frame.shown then
			shown[#shown + 1] = frame
		end
	end
	return shown
end
local function Areas()
	local shown = {}
	for _, frame in ipairs(Kit.frames) do
		if frame.shade and frame.shown then
			shown[#shown + 1] = frame
		end
	end
	return shown
end
local button = Kit.Made("LegacyForeverMapButtonTemplate")[1]
check(button and button:GetParent() == Kit.map, "the map button is a frame of ours on the map, not an overlay frame")
-- Krowi v1.4 minor 11 stacks Forever buttons at TOPLEFT, clear of our TOPRIGHT column.
local offset = button.point[5]
_G.Krowi_WorldMapButtons1 = {
	IsShown = function()
		return true
	end,
	GetPoint = function()
		return "TOPLEFT", Kit.container, "TOPLEFT", 3, 0
	end,
}
button:Refresh()
check(button.point[5] == offset, "top-left Krowi buttons do not reserve a top-right slot")
_G.Krowi_WorldMapButtons1.GetPoint = function()
	return "TOPRIGHT", Kit.container, "TOPRIGHT", -4, -2
end
button:Refresh()
check(button.point[5] == offset - 32, "a top-right Krowi button still reserves its slot")
_G.Krowi_WorldMapButtons1.IsShown = function()
	return false
end
button:Refresh()
check(button.point[5] == offset, "a hidden Krowi button reserves no slot")
_G.Krowi_WorldMapButtons1 = nil

-- Opening the map draws on the next frame of the view, under a host and layer of ours on the canvas.
Kit.Tick()
local pins = Pins()
check(#pins == 1 and #Areas() == 1, "opening a zone map draws its objective and its undiscovered areas")
-- The template binds OnEnter in XML; the harness calls the mixin method.
button:OnEnter()
check(
	tooltip.lines[#tooltip.lines] == "1 unfinished Legacy objective on this map.",
	"one objective reads in the singular"
)
button:OnLeave()
local pin = pins[1]
local host = pin:GetParent():GetParent()
check(host:GetParent() == Kit.canvas, "the pins sit on a layer of ours over the map's canvas")
check(pin.level == 30, "objective pins take the map's frame level for their kind")
check(pin.point[2] == Kit.canvas and pin.point[4] == 250 and pin.point[5] == -350, "the pin sits at its map fraction")
check(math.abs(pin.scale - 1) < 1e-9, "zoomed out, the pin is at its start scale")
check(
	pin.mouse and pin.mouseClicks and pin.passThrough == nil,
	"right-click zooms out, and the pin never calls the restricted SetPassThroughButtons"
)
local areaFrame = Areas()[1]
-- Another addon's marker on the canvas, the way Leatrix Maps places its points of interest: level 100.
local otherMarker = Kit.CreateFrame("Frame")
otherMarker:SetParent(Kit.canvas)
otherMarker:SetFrameLevel(100)
check(
	areaFrame.level == Kit.canvas:GetFrameLevel() + 1,
	"the undiscovered areas sit directly above the map art, at the canvas's level plus one"
)
check(areaFrame.level < otherMarker.level, "another addon's map marker draws above the undiscovered areas")
check(
	pin.levelType == "PIN_FRAME_LEVEL_AREA_POI" and areaFrame.levelType == nil,
	"objective pins keep their own frame level type, the areas take the canvas's"
)
check(areaFrame.mouse == false, "the shading never takes the mouse, so the map keeps its clicks and drags")
check(areaFrame.width == 1000 and areaFrame.height == 700, "the shading covers the canvas")

-- Zooming in grows the pin to its end scale, divided by the canvas's own scale so it stays the same on screen.
Kit.zoom, Kit.scale = 1, 2
Kit.Tick()
check(math.abs(pin.scale - 0.6) < 1e-9, "zoomed in, the pin keeps its end size on screen")
check(pin.point[4] == 250 / 0.6, "a rescaled pin stays on its spot")
Kit.zoom, Kit.scale = 0, 1
Kit.Tick()

-- Pointing at the pin shows its tooltip; a left press and release on it travels there.
pin:Run("OnEnter")
check(tooltip.owner == pin and pin.Highlight.shown, "pointing at a pin highlights it and shows its tooltip")
check(tooltip.lines[#tooltip.lines] == "Click to travel there.", "the tooltip says what a click does")
-- Entrances use the companion's recommended band, and retain useful guidance without it.
local entrance = { text = "Blackfathom Deeps", entry = { kind = "instance", instance = 48, x = 0.25, y = 0.5 } }
local range = true
GetQuestDifficultyColor = function(level)
	check(level == 24, "the entire range uses its lower level for difficulty")
	return { r = 1, g = 0.82, b = 0 }
end
RGBTableToColorCode = function(color)
	return ("|cff%02x%02x%02x"):format(color.r * 255, color.g * 255, color.b * 255)
end
FONT_COLOR_CODE_CLOSE = "|r"
ns.DungeonLevelRange = function(instance)
	check(instance == 48, "the tooltip queries its entrance's instance ID")
	if range then
		return 24, 32
	end
	return nil, nil, "Install AtlasLoot for recommended levels."
end
pin:Run("OnLeave")
pin.objective = entrance
pin:Run("OnEnter")
check(
	tooltip.lines[3] == "Recommended levels: |cffffd10024-32|r (AtlasLoot)",
	"the entrance shows the recommended range"
)
range = false
pin:Run("OnLeave")
pin:Run("OnEnter")
check(tooltip.lines[3] == "Install AtlasLoot for recommended levels.", "missing companion guidance reaches the tooltip")
pin:Run("OnLeave")
pin.objective = objective
pin:Run("OnEnter")
Kit.mouseOver = pin
Kit.Fire("GLOBAL_MOUSE_DOWN", "LeftButton")
Kit.Fire("GLOBAL_MOUSE_UP", "LeftButton")
check(#navigated == 1 and navigated[1][1] == 1429 and navigated[1][4] == "Slay Hogger", "a click travels there")
Kit.Fire("GLOBAL_MOUSE_DOWN", "RightButton")
Kit.Fire("GLOBAL_MOUSE_UP", "RightButton")
check(#navigated == 1, "a right-click is the map's, to zoom out")
Kit.mouseOver = nil
Kit.Fire("GLOBAL_MOUSE_DOWN", "LeftButton")
Kit.mouseOver = pin
Kit.Fire("GLOBAL_MOUSE_UP", "LeftButton")
check(#navigated == 1, "a press that began off the pin is no click on it")
Kit.mouseOver = nil
pin:Run("OnLeave")
check(tooltip.owner == nil and not pin.Highlight.shown, "leaving the pin hides its tooltip")

-- Hovering bare map over an undiscovered area darkens it and names it.
Kit.mouseFocus, hovering = true, shade.areas[1]
Kit.Tick()
check(tooltip.owner == areaFrame and tooltip.lines[1] == "Northshire", "an undiscovered area names itself")
Kit.mouseFocus = false
Kit.Tick()
check(tooltip.owner == nil, "the cursor leaving the canvas hides the area's tooltip")

-- Leatrix reveals the terrain, but Legacy still owns the exploration challenge hover.
_G.LeaMapsDB = { RevealMap = "On" }
ns.RefreshMap()
check(#Areas() == 1, "Leatrix reveal preserves exploration hovers")
local revealed = Areas()[1]
-- Leatrix tints unexplored ground with the exploration pin's textures (level 20 here): the shading draws above
-- that tint and still below every marker.
check(revealed.level == 21, "with Leatrix's reveal on, the shading sits one level above its tint")
check(revealed.level < pin.level, "with Leatrix's reveal on, our markers still draw above the shading")
local tile = revealed.drawn[area.key][1]
check(tile.color[4] == 0, "revealed ground has no resting black veil")
revealed:Highlight(shade.areas[1])
check(
	tooltip.owner == revealed and tile.color[4] == 0.4,
	"a revealed exploration area still highlights and names itself"
)
revealed:Highlight(nil)
check(tile.color[4] == 0 and tooltip.owner == nil, "leaving revealed ground restores transparent shading")
_G.LeaMapsDB.RevealMap = "Off"
ns.RefreshMap()
check(Areas()[1].drawn[area.key][1].color[4] == 0.25, "turning reveal off restores the pooled layer's normal veil")
check(
	Areas()[1].level == Kit.canvas:GetFrameLevel() + 1,
	"turning reveal off puts the shading back directly above the map art"
)
_G.LeaMapsDB = nil

-- The terrain shading: the same frame as the tile shading, one fill per triangle of the area's real ground and a
-- pin at the point nearest the player. No gold glow and no line at all.
settings.showOutlines = true
ns.RefreshMap()
local filled = Areas()[1]
check(filled.outline and filled.outline.areas[1] == outlineArea, "the terrain fill is drawn on the shading's own frame")
check(filled.lines == nil, "an outlined area draws no line")
local textures = filled.drawn[outlineArea.key]
check(#textures == 1, "one alpha field covers the area without overlapping feather quads")
local mask = textures[1]
check(mask.file == "Interface\\AddOns\\LegacyForever\\media\\legacy-masks\\Fixture", "the area uses its generated mask")
check(mask.color[4] == 0.25, "the mask uses normal shading opacity")
check(rawget(mask, "offsets") == nil, "reused textures clear old vertex offsets")
check(math.abs(mask.width - 512 * 1000 / 1002) < 1e-6, "mask width scales from canonical map pixels")
check(math.abs(mask.height - 256 * 700 / 668) < 1e-6, "mask height scales independently with the canvas")
check(math.abs(mask.point[2] - 160 * 1000 / 1002) < 1e-6, "mask left anchor scales with the canvas")
check(math.abs(mask.point[3] + 93 * 700 / 668) < 1e-6, "mask top anchor keeps screen-down orientation")
check(next(filled.feathers) == nil, "no independent edge gradients can stack at corners")
check(#Pins() == 2, "an outlined area adds a pin beside the objective's")
local outlinePin = Pins()[2]
check(
	outlinePin.outline and outlinePin.point[4] == 400 and outlinePin.point[5] == -140,
	"the outline pin sits at the vertex nearest the player"
)
outlinePin:Run("OnEnter")
check(tooltip.lines[1] == "Northshire Ground" and tooltip.lines[2] == "Undiscovered area", "the pin names its area")
check(tooltip.lines[3] == "61 yards away", "the pin gives the distance to the nearest ground")
check(tooltip.lines[#tooltip.lines] == "Click to travel there.", "the pin says what a click does")
outlinePin:Run("OnLeave")

-- Bare map over the outline: the same frame hovers it and brightens its terrain fill exactly as a tile-shaded area
-- brightens its tiles, and a click on the pin routes the journey.
Kit.mouseFocus = true
Kit.cursorX, Kit.cursorY = 300, -210
Kit.Tick()
check(tooltip.owner == filled and tooltip.lines[1] == "Northshire Ground", "the cursor over the outline names the area")
check(tooltip.lines[2] == "Undiscovered area" and tooltip.lines[3] == "61 yards away", "the hover gives its distance")
check(
	tooltip.lines[#tooltip.lines] ~= "Click to travel there.",
	"bare map shows no click hint, because the area hover takes no clicks"
)
check(mask.color[4] == 0.4, "the hovered area's terrain fill brightens like a tile-shaded area")
Kit.mouseFocus = false
Kit.Tick()
check(tooltip.owner == nil and mask.color[4] == 0.25, "leaving the outline restores the terrain fill")

Kit.mouseOver = outlinePin
outlinePin:Run("OnEnter")
Kit.Fire("GLOBAL_MOUSE_DOWN", "LeftButton")
Kit.Fire("GLOBAL_MOUSE_UP", "LeftButton")
check(
	#outlined == 1 and outlined[1][1] == 1429 and outlined[1][2] == outlineArea,
	"a click on an outline pin asks for its outline route"
)
Kit.mouseOver = nil
outlinePin:Run("OnLeave")

-- With Leatrix Maps' reveal on, its aerial tint stands in for the veil: the terrain fill and its feathers clear.
_G.LeaMapsDB = { RevealMap = "On" }
ns.RefreshMap()
local clearOutline = Areas()[1]
check(clearOutline.drawn[outlineArea.key][1].color[4] == 0, "revealed ground leaves the terrain fill clear")
_G.LeaMapsDB = nil
ns.RefreshMap()
filled = Areas()[1]
check(filled.drawn[outlineArea.key][1].color[4] == 0.25, "turning reveal off restores the mask alpha")

-- A missing descriptor never falls back to overlapping geometry or borrows another zone's area key.
local savedMasks = ns.ShadingMasks[1429]
ns.ShadingMasks[1429] = nil
ns.ShadingMasks[1430] = savedMasks
ns.RefreshMap()
check(Areas()[1].drawn[outlineArea.key] == nil, "mask lookup is scoped to the map")
ns.ShadingMasks[1429] = savedMasks
ns.ShadingMasks[1430] = nil
ns.RefreshMap()

-- With the terrain fill off, the tile shading is the drawing again: no triangles and no extra pin.
settings.showOutlines = false
ns.RefreshMap()
check(#Pins() == 1, "with the terrain fill off, an outlined area adds no pin")
check(#Areas() == 1 and Areas()[1].drawn[area.key] ~= nil, "with the terrain fill off, the shading keeps the area")
check(Areas()[1].drawn[outlineArea.key] == nil, "with the terrain fill off, no terrain triangle is drawn")

-- Changing the map releases the terrain triangles, and a map without terrain areas keeps no outline pin.
settings.showOutlines = true
Kit.mapID = 1430
Kit.Tick()
check(#Pins() == 0, "a map without terrain areas keeps no outline pin")
check(#Areas() == 0, "a map with neither shading nor terrain fill draws no area frame")
check(filled.drawn[outlineArea.key] == nil, "changing the map releases the terrain triangles")
check(filled.feathers[outlineArea.key] == nil, "changing the map releases the edge feathers")
Kit.mapID = 1429
settings.showOutlines = false
Kit.Tick()

-- Nothing of ours is made inside an open window, the canvas holds one frame of ours, and no pin has a click script
-- or a field the map reads off its mouse focus.
local onCanvas = 0
for _, frame in ipairs(Kit.frames) do
	if frame ~= Kit.canvas and frame ~= Kit.container then
		check(frame.madeUnder == nil, "every frame of ours is made with no parent")
	end
	onCanvas = onCanvas + (frame.parent == Kit.canvas and frame ~= otherMarker and 1 or 0)
	if frame.template == "LegacyForeverPinTemplate" or frame.shade then
		for _, script in ipairs({ "OnClick", "OnMouseDown", "OnMouseUp", "OnDoubleClick" }) do
			check(frame.scripts[script] == nil, "a pin has no " .. script .. " script")
		end
		check(frame.owningMap == nil and frame.pinTemplate == nil, "a pin carries no field the map reads")
	end
end
check(onCanvas == 1, "the canvas holds exactly one frame of ours, the view's host")

-- The map switches redraw at once; any other switch leaves the map alone.
local before = #Kit.frames
drawn[1429].pins = {}
switched("whatsNew", false)
check(#Pins() == 1, "a switch the map does not draw from leaves it alone")
switched("showEntrances", false)
check(#Pins() == 0 and #Areas() == 1, "turning entrances off redraws the pins")
drawn[1429].pins = { { group = group, objective = objective } }
switched("showAreas", true)
check(#Pins() == 1 and #Kit.frames == before, "a redraw reuses the pins it released")

local beforeFilter = drawCalls
Kit.Fire("CVAR_UPDATE", "unrelatedSetting")
check(drawCalls == beforeFilter, "unrelated native filters leave Legacy pins alone")
Kit.Fire("CVAR_UPDATE", "showDungeonEntrancesOnMap")
check(drawCalls == beforeFilter + 1, "the native entrance filter redraws an open map")

-- Other addons find the shown pins through ForeverCore's canvas markers.
local markers = ns.core.MapCanvas.Markers(Kit.map)
check(#markers == 1 and markers[1].x == 0.25 and markers[1].kind == "legacy", "the pins are listed for other addons")

-- On a continent: the zone badge passes every click through to the map, which opens the zone.
Kit.mapID = 1415
check(#ns.core.MapCanvas.Markers(Kit.map) == 0, "a map just turned to lists nothing until it is drawn")
Kit.Tick()
pins = Pins()
check(#pins == 1 and #Areas() == 0, "turning the map redraws: the continent shows its zone badge")
check(pins[1].mouseClicks == false, "a zone badge lets the map take its clicks")
Kit.mouseOver = pins[1]
pins[1]:Run("OnEnter")
Kit.Fire("GLOBAL_MOUSE_DOWN", "LeftButton")
Kit.Fire("GLOBAL_MOUSE_UP", "LeftButton")
check(#navigated == 1, "a zone badge never travels")
check(tooltip.lines[1] == "Elwynn Forest", "a zone badge's tooltip names the zone")
Kit.mouseOver = nil

-- Combat: a redraw then hides every pin of ours and waits; its end draws once and shows them again.
Kit.mapID = 1429
Kit.combat = true
Kit.Tick()
check(not pin:GetParent().shown, "a redraw in combat hides our pins and acquires none")
check(#ns.core.MapCanvas.Markers(Kit.map) == 0, "hidden pins are not listed for other addons")
ns.RefreshMap()
Kit.combat = false
Kit.Fire("PLAYER_REGEN_ENABLED")
check(pin:GetParent().shown and #Pins() == 1, "the end of combat draws the zone and shows our pins again")

-- Settings redraw an open map; closing it ends the view's clicks and hides any tooltip of ours.
pins = Pins()
pins[1]:Run("OnEnter")
Kit.Close()
check(tooltip.owner == nil, "closing the map hides a pin's tooltip")
Kit.visible = true
Kit.Tick()
check(#Pins() == 1, "opening the map again draws it again")

-- Under the gamepad interface, the pin nearest the map's cursor shows its tooltip, as the map's own pins do.
Enum.InputDeviceInterfaceType = { Gamepad = 2 }
C_InputInterfaceStyle = {
	GetCurrentStyle = function()
		return 2
	end,
}
Kit.Close()
Kit.visible = true
pins = Pins()
pins[1].centerX, pins[1].centerY = 100, 100
SoftCursor = {
	IsShown = function()
		return true
	end,
	GetRect = function()
		return 95, 95, 10, 10
	end,
	GetEffectiveScale = function()
		return 1
	end,
}
Kit.Tick()
check(tooltip.owner == Pins()[1], "the gamepad's map cursor points at the pin under it")
SoftCursor.GetRect = function()
	return 300, 300, 10, 10
end
Kit.Tick()
check(tooltip.owner == nil, "moving the map cursor away leaves the pin")
Kit.mouseOver = Pins()[1]
Pins()[1]:Run("OnEnter")
Kit.Tick()
check(tooltip.owner == Pins()[1], "the map cursor never takes away a pin the mouse is on")
Kit.mouseOver = nil
Pins()[1]:Run("OnLeave")

ns.OpenMapMenu()
check(button.opened, "/lf opens the map button's menu")

print(("legacy_map_spec: %d checks passed"):format(checks))

---@type string, LegacyForeverNamespace
local _, ns = ...

if ns.broken then
	return
end

-- What the world map shows for a map ID, as plain tables: the objectives its button counts and its
-- menu lists, and what the map draws. UI/Map.lua turns the answer into pins, textures and
-- tooltips; tests/map_contents_spec.lua drives this file with stubbed client globals.
---@class LegacyMapContents
local MapContents = {}
ns.MapContents = MapContents

---@class LegacyMapPin
---@field group LegacyGroup
---@field objective LegacyObjective
---@field done boolean? a cleared dungeon or raid entrance, drawn faded

-- One map tile of a shaded area, placed in canvas pixels from the canvas's top-left.
---@class LegacyShadeTile
---@field file? number
---@field x number
---@field y number
---@field width number
---@field height number
---@field u number
---@field v number

---@class LegacyShadedArea
---@field area LegacyArea
---@field tiles LegacyShadeTile[]
---@field objective? LegacyAreaObjective the Legacy step this area is, when it is one

---@class LegacyShade
---@field zone LegacyZone
---@field areas LegacyShadedArea[]
---@field byKey table<string, LegacyShadedArea>

---@class LegacyMapDrawing
---@field badges LegacyContinentZone[] a continent's zone badges
---@field pins LegacyMapPin[] a zone's place-bound objectives
---@field shade? LegacyShade a zone's undiscovered areas, when there are any to shade
---@field outline? LegacyOutline a zone's undiscovered areas filled from their terrain instead

-- Exploration is shaded on the zone map; everything else is pinned.
---@param group LegacyGroup
---@return boolean
function MapContents.IsExploration(group)
	return group.objectives[1].entry.kind == "explore"
end

-- The unfinished objectives the data places on this map, and how many: the map button's count and
-- its menu's entries.
---@param uiMapID number?
---@return LegacyGroup[] groups
---@return number count
function MapContents.Objectives(uiMapID)
	if not uiMapID then
		return {}, 0
	end
	local groups = ns.Model.ZoneObjectives(ns.Data, uiMapID, ns.Live.Visible(), ns.Live.Criteria)
	return groups, ns.Model.CountObjectives(groups)
end

-- On a continent, one badge per zone with unfinished objectives, instead of every pin; its tooltip gives the count.
-- Exploration is left to the zone map's shading, so badges count place-bound objectives only.
---@param continentID number
---@return LegacyContinentZone[]
local function Badges(continentID)
	local zones = {}
	for uiMapID in pairs(ns.Data.zones) do
		local info = C_Map.GetMapInfo(uiMapID)
		if info and ns.Live.ContinentOf(uiMapID) == continentID then
			local groups = ns.Model.ZoneObjectives(ns.Data, uiMapID, ns.Live.Visible(), ns.Live.Criteria, false, true)
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

-- offsetX, offsetY, width, height from an overlay key ("offsetX:offsetY:width:height").
---@param key string
---@return number offsetX
---@return number offsetY
---@return number width
---@return number height
local function OverlayRect(key)
	local offsetX, offsetY, width, height = key:match("^(%d+):(%d+):(%d+):(%d+)$")
	-- The generator validates overlay keys; fail here if another caller violates that contract.
	return assert(tonumber(offsetX)), assert(tonumber(offsetY)), assert(tonumber(width)), assert(tonumber(height))
end

-- A tile's drawn size and how much of its power-of-two file that covers; only the last
-- tile in a row or column is partial.
---@param total number
---@param tileSize number
---@param index number
---@param count number
---@return number pixels
---@return number fraction
local function TileSpan(total, tileSize, index, count)
	if index < count then
		return tileSize, 1
	end
	local pixels = total % tileSize
	if pixels == 0 then
		pixels = tileSize
	end
	local file = 16
	while file < pixels do
		file = file * 2
	end
	return pixels, pixels / file
end

-- An area's tiles laid out as Blizzard's MapExplorationPinMixin:RefreshOverlays does it: row-major
-- through the overlay's tile list, from the overlay's top-left.
---@param area LegacyArea
---@param tileWidth number
---@param tileHeight number
---@return LegacyShadeTile[]
local function AreaTiles(area, tileWidth, tileHeight)
	local offsetX, offsetY, width, height = OverlayRect(area.key)
	local wide, tall = math.ceil(width / tileWidth), math.ceil(height / tileHeight)
	local tiles = {}
	for row = 1, tall do
		local tileH, v = TileSpan(height, tileHeight, row, tall)
		for col = 1, wide do
			local tileW, u = TileSpan(width, tileWidth, col, wide)
			tiles[#tiles + 1] = {
				file = area.tiles[(row - 1) * wide + col],
				x = offsetX + tileWidth * (col - 1),
				y = offsetY + tileHeight * (row - 1),
				width = tileW,
				height = tileH,
				u = u,
				v = v,
			}
		end
	end
	return tiles
end

-- The zone's undiscovered areas that have map tiles; nil for a map without shading data, with the
-- shading switched off, or with nothing left to discover. An area the outline layer also draws keeps its
-- tile shading, so the dark fade stays under the terrain fill.
---@param uiMapID number
---@return LegacyShade?
local function Shade(uiMapID)
	local zone = ns.Saved.Get("showAreas") and ns.Data.completion[uiMapID]
	if not (zone and zone.tileWidth and zone.tileHeight) then
		return nil
	end
	local explored = ns.Live.ZoneSnapshot(uiMapID).explored
	---@type LegacyShade
	local shade = { zone = zone, areas = {}, byKey = {} }
	for _, area in ipairs(zone.areas) do
		if area.tiles and not explored[area.key] then
			local shaded = { area = area, tiles = AreaTiles(area, zone.tileWidth, zone.tileHeight) }
			shade.areas[#shade.areas + 1] = shaded
			shade.byKey[area.key] = shaded
		end
	end
	return #shade.areas > 0 and shade or nil
end

-- The zone's undiscovered areas that have terrain rings; nil when the layer is off or the zone has no
-- terrain data. Areas without data stay with the shading.
---@param uiMapID number
---@return LegacyOutline?
local function Outline(uiMapID)
	local zone = ns.Data.completion[uiMapID]
	local data = ns.Explore and ns.Explore.zones[uiMapID]
	if not (zone and data) then
		return nil
	end
	local explored = ns.Live.ZoneSnapshot(uiMapID).explored
	---@type LegacyOutline
	local outline = { zone = data, uiMapID = uiMapID, areas = {}, byKey = {} }
	for _, area in ipairs(zone.areas) do
		local rings = area.key and data.areas[area.key]
		if rings and not explored[area.key] then
			---@type LegacyOutlineArea
			local drawn = { key = area.key, name = area.name, rings = rings, outline = true }
			outline.areas[#outline.areas + 1] = drawn
			outline.byKey[area.key] = drawn
		end
	end
	return #outline.areas > 0 and outline or nil
end

-- Each area's triangles, kept on its ring table: the map redraws on every zoom and resize, so an area is
-- ear-clipped once, never once per frame.
local triangulations = setmetatable({}, { __mode = "k" })

-- Append a ring's triangles to `into`, ear clipping: a simple polygon, which a ring is, is cut by one ear
-- (a convex corner no other point lies inside) at a time until three points are left. Either winding works;
-- the ring's own signed area says which way its convex corners turn.
---@param ring number[] flat u, v pairs
---@param into LegacyTriangle[]
local function ClipRing(ring, into)
	local count = #ring / 2
	if count < 3 then
		return
	end
	---@type number[][]
	local points = {}
	for index = 1, count do
		points[index] = { ring[index * 2 - 1], ring[index * 2] }
	end
	local area = 0
	for index = 1, count do
		local following = index % count + 1
		area = area + points[index][1] * points[following][2] - points[following][1] * points[index][2]
	end
	local clockwise = area < 0
	-- Strictly inside, so a point on an ear's diagonal does not keep that ear from being cut.
	---@param a number[]
	---@param b number[]
	---@param c number[]
	---@param point number[]
	---@return boolean
	local function inside(a, b, c, point)
		local ab = (b[1] - a[1]) * (point[2] - a[2]) - (b[2] - a[2]) * (point[1] - a[1])
		local bc = (c[1] - b[1]) * (point[2] - b[2]) - (c[2] - b[2]) * (point[1] - b[1])
		local ca = (a[1] - c[1]) * (point[2] - c[2]) - (a[2] - c[2]) * (point[1] - c[1])
		if clockwise then
			return ab < 0 and bc < 0 and ca < 0
		end
		return ab > 0 and bc > 0 and ca > 0
	end
	local index = 1
	while #points > 3 do
		local total = #points
		local clipped, convex
		for offset = 0, total - 1 do
			local at = (index - 1 + offset) % total + 1
			local previous, following = (at - 2) % total + 1, at % total + 1
			local a, b, c = points[previous], points[at], points[following]
			local cross = (b[1] - a[1]) * (c[2] - b[2]) - (b[2] - a[2]) * (c[1] - b[1])
			if cross ~= 0 and (cross < 0) == clockwise then
				convex = convex or at
				local ear = true
				for other = 1, total do
					if other ~= at and other ~= previous and other ~= following and inside(a, b, c, points[other]) then
						ear = false
						break
					end
				end
				if ear then
					clipped = at
					break
				end
			end
		end
		-- A corner exactly on a diagonal, or a degenerate ring, can leave no ear: cut a convex corner
		-- anyway, so the loop always ends.
		clipped = clipped or convex or index
		total = #points
		local a, b, c = points[(clipped - 2) % total + 1], points[clipped], points[clipped % total + 1]
		into[#into + 1] = { a[1], a[2], b[1], b[2], c[1], c[2] }
		table.remove(points, clipped)
		index = clipped
	end
	if #points == 3 then
		into[#into + 1] = { points[1][1], points[1][2], points[2][1], points[2][2], points[3][1], points[3][2] }
	end
end

-- An area's terrain rings as triangles, each a flat u, v, u, v, u, v: the fill that replaces the map-art
-- tiles for an area with terrain data. Every ring is filled on its own.
---@param rings number[][]
---@return LegacyTriangle[]
function MapContents.Triangles(rings)
	local triangles = triangulations[rings]
	if not triangles then
		triangles = {}
		for _, ring in ipairs(rings) do
			ClipRing(ring, triangles)
		end
		triangulations[rings] = triangles
	end
	return triangles
end

-- The outlined area under a point, or nil. Rings lie along the real ground, so the test is exact: a point
-- inside an odd number of rings (a hole counts as one more ring) is inside the area.
---@param outline LegacyOutline
---@param u number
---@param v number
---@return LegacyOutlineArea?
function MapContents.OutlineAt(outline, u, v)
	for _, area in ipairs(outline.areas) do
		local inside = false
		for _, ring in ipairs(area.rings) do
			local count = #ring / 2
			for index = 1, count do
				local following = index % count + 1
				local ui, vi, uj, vj =
					ring[index * 2 - 1], ring[index * 2], ring[following * 2 - 1], ring[following * 2]
				if (vi > v) ~= (vj > v) and u < (uj - ui) * (v - vi) / (vj - vi) + ui then
					inside = not inside
				end
			end
		end
		if inside then
			return area
		end
	end
end

-- Where an area's pin sits and how far it is: the outline point nearest the player when the player is on
-- this map, else the first point of the first ring. The distance is in yards, from the zone's rectangle.
---@param zone LegacyExploreZone
---@param area LegacyOutlineArea
---@param u? number
---@param v? number
---@return number x
---@return number y
---@return number? yards
function MapContents.OutlinePoint(zone, area, u, v)
	local rings = area.rings
	local x, y = rings[1][1], rings[1][2]
	local yards
	if u and v then
		local shortest = math.huge
		for _, ring in ipairs(rings) do
			for index = 1, #ring, 2 do
				local dx, dy = (ring[index] - u) * zone.width, (ring[index + 1] - v) * zone.height
				local distance = dx * dx + dy * dy
				if distance < shortest then
					shortest, x, y = distance, ring[index], ring[index + 1]
				end
			end
		end
		yards = math.sqrt(shortest)
	end
	return x, y, yards
end

-- What the map draws (UI/Map.lua). A continent gets zone badges, which follow zone completion's "On the
-- world map" switch, so turning it off leaves continents bare. A zone gets a pin per place-bound
-- objective (bosses, dungeons, quests) and its undiscovered areas shaded; exploration is never
-- pinned, a shaded area carrying its Legacy step for the hover instead. With "Show where to discover
-- areas" on, an undiscovered area with terrain data is also filled from its terrain and keeps its
-- Legacy step for the pin and the hover; it keeps the tile shading too, so the dark fade stays under
-- the fill. The areas without data have only the shading. "Show dungeon and raid entrances" off leaves
-- out only the entrance pins: the button still counts them and its menu still lists them.
---@param uiMapID number?
---@return LegacyMapDrawing
function MapContents.Drawn(uiMapID)
	---@type LegacyMapDrawing
	local drawn = { badges = {}, pins = {} }
	local entrances = ns.Saved.Get("showEntrances") and GetCVarBool("showDungeonEntrancesOnMap")
	local info = uiMapID and C_Map.GetMapInfo(uiMapID)
	if uiMapID and info and info.mapType == Enum.UIMapType.Continent then
		if ns.ZoneCompletion.IsShown("map") then
			drawn.badges = Badges(uiMapID)
		end
		return drawn
	end
	local outline = uiMapID and ns.Saved.Get("showOutlines") and Outline(uiMapID) or nil
	local shade = uiMapID and Shade(uiMapID) or nil
	-- Cleared dungeon and raid entrances are drawn too, marked done, so a zone shows both what is left and what is
	-- finished. The button's count and the menu still list only the unfinished objectives (MapContents.Objectives).
	local groups = uiMapID and ns.Model.ZoneObjectives(ns.Data, uiMapID, ns.Live.Visible(), ns.Live.Criteria, true)
		or {}
	for _, group in ipairs(groups) do
		for _, objective in ipairs(group.objectives) do
			local entry = objective.entry
			local outlined = entry.kind == "explore" and outline and outline.byKey[entry.key]
			local shaded = entry.kind == "explore" and shade and shade.byKey[entry.key]
			if outlined then
				outlined.objective = { group = group, objective = objective }
			end
			if shaded then
				shaded.objective = { group = group, objective = objective }
			end
			if
				not (outlined or shaded)
				and entry.x
				and entry.kind ~= "explore"
				and (entrances or entry.kind ~= "instance")
			then
				drawn.pins[#drawn.pins + 1] = { group = group, objective = objective, done = objective.done }
			end
		end
	end
	drawn.shade = shade
	drawn.outline = outline
	return drawn
end

-- The shaded area under a point on the map canvas, or nil. The area is picked among all the zone's
-- areas, explored or not, so an explored label never lights up the unexplored neighbour whose
-- rectangle overlaps it. Overlay textures are rectangles around irregular shapes and overlap, so of
-- the areas whose texture holds the point, the one whose centre (its hit rectangle's, Blizzard's own
-- label target, else the texture's) is nearest wins.
---@param shade LegacyShade
---@param x number
---@param y number
---@return LegacyShadedArea?
function MapContents.AreaAt(shade, x, y)
	local best, bestDistance
	for _, area in ipairs(shade.zone.areas) do
		-- An area without a current-art overlay has no rectangle to hit.
		if area.key then
			local offsetX, offsetY, width, height = OverlayRect(area.key)
			if x >= offsetX and x <= offsetX + width and y >= offsetY and y <= offsetY + height then
				local left, top, right, bottom = offsetX, offsetY, offsetX + width, offsetY + height
				if area.hit then
					left, top, right, bottom = area.hit[1], area.hit[2], area.hit[3], area.hit[4]
				end
				local dx, dy = x - (left + right) / 2, y - (top + bottom) / 2
				local distance = dx * dx + dy * dy
				if not bestDistance or distance < bestDistance then
					best, bestDistance = area, distance
				end
			end
		end
	end
	return best and shade.byKey[best.key] or nil
end

---@type string, LegacyForeverNamespace
local _, ns = ...

-- Zone completion without a frame: a zone's or continent's result under what the player counts, when a
-- completion is news, where the world map's corner sits, and the one notice that any of it may have changed.
-- The tracker section, the map's corner and badges, the toast and the menu (UI/Completion.lua), the map and
-- LegacyForever.API all read and listen here.
---@class LegacyZoneCompletion
local ZoneCompletion = {}
ns.ZoneCompletion = ZoneCompletion

-- Whether zone completion is drawn on a surface: the world map (its continent badges) or the objective
-- tracker.
---@param surface LegacySurface
---@return boolean
function ZoneCompletion.IsShown(surface)
	return ns.Saved.Get(surface)
end

-- "What counts": whether a category is part of the percentage.
---@param category LegacyCategoryKey
---@return boolean
function ZoneCompletion.IsCounted(category)
	return ns.Saved.Get("count_" .. category)
end

-- Only the zone's quests differ from Live's cached snapshot: they are read deferred, so a draw never builds
-- QuestieDB's index (see Quests.Zone). One view per zone, made again when Live replaces the snapshot.
---@type table<number, LegacySnapshot>
local deferredViews = {}

-- Built apart from DeferredSnapshot so its kept path, taken for every zone on every draw, makes no closure.
---@param uiMapID number
---@param snapshot LegacySnapshot
---@return LegacySnapshot
local function NewView(uiMapID, snapshot)
	---@type LegacySnapshot
	local view = setmetatable({
		quests = function()
			return ns.Quests.Zone(uiMapID, true)
		end,
	}, { __index = snapshot })
	deferredViews[uiMapID] = view
	return view
end

---@param uiMapID number
---@return LegacySnapshot
local function DeferredSnapshot(uiMapID)
	local snapshot = ns.Live.ZoneSnapshot(uiMapID)
	local view = deferredViews[uiMapID]
	if not view or getmetatable(view).__index ~= snapshot then
		view = NewView(uiMapID, snapshot)
	end
	return view
end

-- A zone's completion, even when nothing counts; nil for a map without completion data.
-- Every reader (the map, the tracker, news, the API) draws or checks it, so its quests never build QuestieDB's
-- index: a cold index reads as pending until the build on the next frame announces a change.
---@param uiMapID number?
---@return LegacyZoneResult?
function ZoneCompletion.Result(uiMapID)
	local zone = uiMapID and ns.Data.completion[uiMapID]
	if not uiMapID or not zone then
		return nil
	end
	return ns.Model.ZoneCompletion(zone, DeferredSnapshot(uiMapID), ZoneCompletion.IsCounted)
end

-- What the map and tracker draw: the zone's completion, or nil when it has nothing to count. A zone whose only
-- counted items are pending (quests while the index builds) is still drawn, with no percent yet.
---@param uiMapID number?
---@return LegacyZoneResult?
function ZoneCompletion.Of(uiMapID)
	local result = ZoneCompletion.Result(uiMapID)
	return result and ns.Model.CompletionCounts(result) and result or nil
end

-- How many of a continent's zones are complete, counting what the player counts; nil when none counts anything.
-- Every zone on the continent is computed on each call.
---@param continentID number
---@return LegacyContinentResult?
function ZoneCompletion.Continent(continentID)
	local results = {}
	for uiMapID in pairs(ns.Data.completion) do
		if ns.Live.ContinentOf(uiMapID) == continentID then
			results[#results + 1] = ZoneCompletion.Result(uiMapID)
		end
	end
	return ns.Model.ContinentCompletion(results)
end

--[[ Where the world map's corner sits ]]

-- A box on the map, in the map's own texture units: its top-left and size.
---@class LegacyCornerBox
---@field x number
---@field y number
---@field width number
---@field height number

-- A placed Legacy objective: where its pin sits, as fractions of the map's width and height.
---@class LegacyCornerPin
---@field x number
---@field y number

-- A pin under the box costs the map's area of a 40 by 40 patch: the zone's own ground still outweighs one pin.
local PIN_PATCH = 1600

-- An area's "offsetX:offsetY:width:height" rectangle. The generator writes the shape; fail loudly on another.
---@param key string
---@return number x
---@return number y
---@return number width
---@return number height
local function Rect(key)
	local x, y, width, height = assert(key:match("^(%d+):(%d+):(%d+):(%d+)$"))
	return assert(tonumber(x)), assert(tonumber(y)), assert(tonumber(width)), assert(tonumber(height))
end

-- How much of a zone a box covers, in square texture units: the part overlapping the zone's own area rectangles,
-- the same ones UI/Map.lua shades, plus a patch for every Legacy pin inside it. Ties are the caller's to order.
---@param box LegacyCornerBox
---@param areas LegacyArea[]
---@param pins LegacyCornerPin[]
---@param mapWidth number the map's width in texture units
---@param mapHeight number
---@return number
function ZoneCompletion.Covered(box, areas, pins, mapWidth, mapHeight)
	local left, top = box.x, box.y
	local right, bottom = left + box.width, top + box.height
	local covered = 0
	for _, area in ipairs(areas) do
		local x, y, width, height = Rect(area.key)
		local overlapX = math.min(right, x + width) - math.max(left, x)
		local overlapY = math.min(bottom, y + height) - math.max(top, y)
		if overlapX > 0 and overlapY > 0 then
			covered = covered + overlapX * overlapY
		end
	end
	for _, pin in ipairs(pins) do
		local x, y = pin.x * mapWidth, pin.y * mapHeight
		if x >= left and x <= right and y >= top and y <= bottom then
			covered = covered + PIN_PATCH
		end
	end
	return covered
end

-- The candidates, in tie order, as the box's own point and its offset from the canvas container's matching
-- point: top left and bottom left clear the floor dropdown, top right the Legacy map button and bottom right the
-- quest-log toggle.
---@type { point: string, x: number, y: number }[]
local CORNERS = {
	{ point = "TOPLEFT", x = 44, y = -18 },
	{ point = "TOPRIGHT", x = -48, y = -18 },
	{ point = "BOTTOMLEFT", x = 44, y = 18 },
	{ point = "BOTTOMRIGHT", x = -88, y = 18 },
}

-- One corner per zone and box size: every draw of the same zone asks for the same answer.
---@class LegacyCornerPlacement
---@field width number
---@field height number
---@field containerWidth number
---@field containerHeight number
---@field mapWidth number
---@field mapHeight number
---@field corner number
---@type table<number, LegacyCornerPlacement>
local placements = {}

-- A candidate box's top-left in the canvas container's UI units, y down.
---@param corner { point: string, x: number, y: number }
---@param width number
---@param height number
---@param containerWidth number
---@param containerHeight number
---@return number left
---@return number top
local function CornerOrigin(corner, width, height, containerWidth, containerHeight)
	local left = corner.x >= 0 and corner.x or containerWidth + corner.x - width
	local top = corner.y <= 0 and -corner.y or containerHeight - corner.y - height
	return left, top
end

-- The map's canvas container and its own canvas, in UI and texture units.
---@class LegacyCornerGeometry
---@field containerWidth number
---@field containerHeight number
---@field mapWidth number
---@field mapHeight number

-- Which corner the zone's completion sits in: the one whose box covers least of the zone's own areas and pins,
-- with the earliest candidate on a tie. The map opens with the whole zone fitted and centred, so a texture unit
-- is `scale` UI units and a box is judged in the map's own texture units. `pins` is read only when the corner has
-- to be judged, since the zone's pins are the costly part and the answer is kept.
---@param uiMapID number
---@param width number
---@param height number
---@param geometry LegacyCornerGeometry
---@param pins fun(): LegacyCornerPin[]
---@return { point: string, x: number, y: number }
function ZoneCompletion.Corner(uiMapID, width, height, geometry, pins)
	local containerWidth, containerHeight = geometry.containerWidth, geometry.containerHeight
	local mapWidth, mapHeight = geometry.mapWidth, geometry.mapHeight
	local cached = placements[uiMapID]
	if
		cached
		and cached.width == width
		and cached.height == height
		and cached.containerWidth == containerWidth
		and cached.containerHeight == containerHeight
		and cached.mapWidth == mapWidth
		and cached.mapHeight == mapHeight
	then
		return CORNERS[cached.corner]
	end
	local best = 1
	if containerWidth > 0 and containerHeight > 0 and mapWidth > 0 and mapHeight > 0 then
		local scale = math.min(containerWidth / mapWidth, containerHeight / mapHeight)
		-- The map is centred in the container, letterboxed on whichever side is longer.
		local offsetX = (containerWidth - mapWidth * scale) / 2
		local offsetY = (containerHeight - mapHeight * scale) / 2
		local zone = ns.Data.completion[uiMapID]
		local areas = zone and zone.areas or {}
		local placed = pins()
		local bestScore
		for index, corner in ipairs(CORNERS) do
			local left, top = CornerOrigin(corner, width, height, containerWidth, containerHeight)
			---@type LegacyCornerBox
			local box = {
				x = (left - offsetX) / scale,
				y = (top - offsetY) / scale,
				width = width / scale,
				height = height / scale,
			}
			local score = ZoneCompletion.Covered(box, areas, placed, mapWidth, mapHeight)
			if not bestScore or score < bestScore then
				best, bestScore = index, score
			end
		end
	end
	placements[uiMapID] = {
		width = width,
		height = height,
		containerWidth = containerWidth,
		containerHeight = containerHeight,
		mapWidth = mapWidth,
		mapHeight = mapHeight,
		corner = best,
	}
	return CORNERS[best]
end

--[[ The one notice ]]

---@type (fun())[]
local listeners = {}

-- Called whenever a result or where it is drawn may have changed: progress, a quest source, the zone the
-- player is in, "What counts", or the map and tracker switches. Listeners run in the order registered.
---@param callback fun()
function ZoneCompletion.OnChange(callback)
	listeners[#listeners + 1] = callback
end

local function Changed()
	for _, callback in ipairs(listeners) do
		ns.SafeCall("zone completion listener", callback)
	end
end

--[[ A zone reaching 100% ]]

---@type (fun(uiMapID: number))[]
local completeListeners = {}

-- Called with a zone that has just reached 100% of what the player counts, once per zone per session, and
-- only when that is news (see CheckNews).
---@param callback fun(uiMapID: number)
function ZoneCompletion.OnComplete(callback)
	completeListeners[#completeListeners + 1] = callback
end

-- Zones already complete when you log in are not news. The first check (on entering the
-- world, however long the loading screen took) and those in the few seconds after it, while
-- the game is still sending achievement progress, only note completions.
local QUIET_SECONDS = 10
---@type number?
local quietUntil
---@type LegacySet
local rewarded = {}

-- The reward follows "What counts", as the percentage does, so 100% on screen is what earns it.
-- This runs for every zone on every progress change, the first just after entering the world. A cold index
-- reads as pending (see Result), so the zone is not complete and not noted; the build on the next frame
-- announces a change, and the zone is checked again with its quests.
---@param uiMapID number
---@return boolean
local function IsComplete(uiMapID)
	local result = ZoneCompletion.Result(uiMapID)
	---@cast result -nil
	return ns.Model.CompletionCounts(result) and result.complete
end

-- Set by a silent check that found the quests still loading: the check once they are read stays silent too.
local silentWhenRead = false

-- Unticking a category isn't progress, so a zone that completes that way (`silent`) is noted without news.
-- Ticking Quests on a cold index reads them as pending; the build's notice a frame later is still that tick.
---@param silent? boolean
local function CheckNews(silent)
	local loading = ZoneCompletion.IsCounted("quests") and (ns.Quests.Cold() or ns.Quests.Status() == "loading")
	if silent and loading then
		silentWhenRead = true
	elseif silentWhenRead and not loading then
		silent, silentWhenRead = true, false
	end
	quietUntil = quietUntil or GetTime() + QUIET_SECONDS
	local quiet = silent or GetTime() < quietUntil
	for uiMapID in pairs(ns.Data.completion) do
		if not rewarded[uiMapID] and IsComplete(uiMapID) then
			rewarded[uiMapID] = true
			-- Someone who has switched zone completion off entirely doesn't want its toasts.
			if not quiet and (ZoneCompletion.IsShown("map") or ZoneCompletion.IsShown("tracker")) then
				for _, callback in ipairs(completeListeners) do
					ns.SafeCall("zone complete listener", callback, uiMapID)
				end
			end
		end
	end
end

ns.Live.OnChange(function()
	Changed()
	CheckNews()
end)

-- A switch was saved, from the Legacy map menu, the Settings page or anywhere else. A counted category
-- re-checks completions silently before the notice. The collapse states redraw themselves where they are
-- clicked.
ns.Saved.OnChange(function(key)
	if key == "map" or key == "tracker" then
		Changed()
	elseif key:find("^count_") then
		CheckNews(true)
		Changed()
	end
end)

-- For /lf audit and /lf report: the current zone's counts against what the game reports, added to `lines`. A typed
-- command, so it reads the quests in full and may build QuestieDB's index.
---@param lines string[]
---@return string[] lines
function ZoneCompletion.AuditLines(lines)
	local function Add(line)
		lines[#lines + 1] = line
	end
	local uiMapID = ns.Live.CurrentZone()
	if not uiMapID then
		Add("zone completion: no data for the zone you're in.")
		return lines
	end
	local zone = ns.Data.completion[uiMapID]
	local snapshot = ns.Live.ZoneSnapshot(uiMapID)
	local result = ns.Model.ZoneCompletion(zone, snapshot)
	local parts = {}
	for _, key in ipairs(ns.Model.COMPLETION_CATEGORIES) do
		local category = result[key]
		parts[#parts + 1] = category and ("%s %d/%d"):format(key, category.done, category.total) or (key .. " -")
	end
	Add(("quests from QuestieDB: %s"):format(ns.Quests.Failure() or ns.Quests.Status()))
	Add(
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
			Add("  explored area not in the data: " .. key)
		end
	end
	if next(snapshot.explored) == nil then
		Add("  the game reports nothing explored in this zone")
	end

	for _, taxi in ipairs(ns.Model.ForFaction(zone.taxis, snapshot.faction, "faction")) do
		local learned = snapshot.taxis[taxi.node]
		local state = learned == nil and "unknown until you open a flight master on this continent"
			or learned and "known"
			or "not known"
		Add(("  flight path %d (%s): %s"):format(taxi.node, taxi.name, state))
	end
	return lines
end

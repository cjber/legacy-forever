local _, ns = ...

-- Pure logic over the generated data and a snapshot of live progress; no WoW API
-- calls, so tests/model_spec.lua can exercise it under plain LuaJIT.
--
-- `visible` is the set of unfinished reward-bearing challenges the game shows this
-- character (Forever ships two variant sets and the client lists only one).
-- `criteria(achievementID)` returns { [criteriaID] = { text, completed, type, asset,
-- quantity, required, index } }
-- or nil when the game has no data for that achievement.
local Model = {}
ns.Model = Model

-- Achievement type 8: "earn achievement X", where X is the criterion's asset.
local EARN_ACHIEVEMENT = 8

-- The visible challenge an objective counts toward, or nil if none is visible.
function Model.OwningChallenge(data, achievementID, visible)
	if visible[achievementID] then
		return achievementID
	end
	for _, reward in ipairs(data.feeds[achievementID] or {}) do
		if visible[reward] then
			return reward
		end
	end
	return nil
end

-- Unfinished objectives in one zone, grouped by the achievement that holds them
-- (a challenge, or the exploration achievement feeding it). Objectives whose live
-- progress is unknown are left out rather than shown as unfinished; Audit reports them.
function Model.ZoneObjectives(data, uiMapID, visible, criteria)
	local groups, byAchievement = {}, {}
	for _, entry in ipairs(data.zones[uiMapID] or {}) do
		local challenge = Model.OwningChallenge(data, entry.achievement, visible)
		local live = challenge and criteria(entry.achievement)
		local progress = live and live[entry.criteria]
		if progress and not progress.completed then
			local group = byAchievement[entry.achievement]
			if not group then
				group = { achievement = entry.achievement, challenge = challenge, objectives = {} }
				byAchievement[entry.achievement] = group
				groups[#groups + 1] = group
			end
			group.objectives[#group.objectives + 1] = { entry = entry, text = progress.text }
		end
	end
	return groups
end

function Model.CountObjectives(groups)
	local count = 0
	for _, group in ipairs(groups) do
		count = count + #group.objectives
	end
	return count
end

local function LocatedCriteria(data)
	local located = {}
	for _, entries in pairs(data.zones) do
		for _, entry in ipairs(entries) do
			located[entry.criteria] = true
		end
	end
	return located
end

-- Unfinished criteria no zone places, counting through "earn achievement X" into
-- X's own criteria when X is a feeding achievement (the generator rejects cycles).
local function OpenUnlocated(data, located, criteria, achievementID)
	local open = 0
	for criteriaID, progress in pairs(criteria(achievementID) or {}) do
		if not progress.completed and not located[criteriaID] then
			if progress.type == EARN_ACHIEVEMENT and data.feeds[progress.asset] then
				open = open + OpenUnlocated(data, located, criteria, progress.asset)
			else
				open = open + 1
			end
		end
	end
	return open
end

-- Visible challenges with unfinished criteria no zone accounts for: levels, skills,
-- ranks, and anything whose location the data can't establish.
function Model.Unlocated(data, visible, criteria)
	local located = LocatedCriteria(data)
	local result = {}
	for challenge in pairs(visible) do
		local open = OpenUnlocated(data, located, criteria, challenge)
		if open > 0 then
			result[#result + 1] = { challenge = challenge, open = open }
		end
	end
	table.sort(result, function(a, b)
		return a.challenge < b.challenge
	end)
	return result
end

-- A tracked challenge's unfinished steps in game order, each with its progress:
-- "3/10" for counted criteria, and done/total of X's criteria for "earn achievement X".
function Model.TrackerLines(challenge, criteria)
	local open = {}
	for _, progress in pairs(criteria(challenge) or {}) do
		if not progress.completed then
			open[#open + 1] = progress
		end
	end
	table.sort(open, function(a, b)
		return a.index < b.index
	end)
	local lines = {}
	for _, progress in ipairs(open) do
		local detail
		local sub = progress.type == EARN_ACHIEVEMENT and criteria(progress.asset)
		if sub then
			local done, total = 0, 0
			for _, step in pairs(sub) do
				total = total + 1
				done = done + (step.completed and 1 or 0)
			end
			detail = ("%d/%d"):format(done, total)
		elseif progress.required and progress.required > 1 then
			detail = ("%d/%d"):format(progress.quantity, progress.required)
		end
		lines[#lines + 1] = { text = progress.text, detail = detail }
	end
	return lines
end

-- One category of a zone's completion: { done, total, left = { names } }, or nil when
-- the zone has none or its progress is unknown. `state(item)` returns true (done),
-- false (not done) or nil (unknown, left out of the count).
local function CompletionCategory(items, state)
	if not items or #items == 0 then
		return nil
	end
	local category = { done = 0, total = 0, left = {} }
	for _, item in ipairs(items) do
		local done = state(item)
		if done ~= nil then
			category.total = category.total + 1
			if done then
				category.done = category.done + 1
			else
				category.left[#category.left + 1] = item.name
			end
		end
	end
	return category.total > 0 and category or nil
end

Model.COMPLETION_CATEGORIES = { "areas", "taxis", "dungeons" }

-- A zone's completion, GW2 style: every area, flight path and dungeon counts once.
-- `snapshot` = { explored = set of overlay keys or nil, taxis = { [node] = discovered } for
-- the nodes the game lists (any other node is unknown), faction = "Alliance" | "Horde",
-- wingDone = function(refs) -> true/false/nil }.
-- Areas and flight paths are per character; dungeon wings are account-wide Legacy steps.
-- `counted(key)`, when given, says which categories the player counts; the rest are left out entirely.
function Model.ZoneCompletion(zone, snapshot, counted)
	local ownTaxis = {}
	for _, taxi in ipairs(zone.taxis or {}) do
		if taxi.faction == "Neutral" or taxi.faction == snapshot.faction then
			ownTaxis[#ownTaxis + 1] = taxi
		end
	end
	local result = {
		areas = snapshot.explored and CompletionCategory(zone.areas, function(area)
			return snapshot.explored[area.key] == true
		end),
		taxis = CompletionCategory(ownTaxis, function(taxi)
			return snapshot.taxis[taxi.node]
		end),
		dungeons = CompletionCategory(zone.dungeons, function(wing)
			return snapshot.wingDone(wing.refs)
		end),
		done = 0,
		total = 0,
	}
	for _, key in ipairs(Model.COMPLETION_CATEGORIES) do
		if counted and not counted(key) then
			result[key] = nil
		end
		local category = result[key]
		if category then
			result.done = result.done + category.done
			result.total = result.total + category.total
		end
	end
	-- Floored, so 100% means nothing is left.
	result.percent = result.total > 0 and math.floor(100 * result.done / result.total) or nil
	return result
end

-- offsetX, offsetY, width, height from an overlay key ("offsetX:offsetY:width:height").
function Model.OverlayRect(key)
	local offsetX, offsetY, width, height = key:match("^(%d+):(%d+):(%d+):(%d+)$")
	return tonumber(offsetX), tonumber(offsetY), tonumber(width), tonumber(height)
end

-- The area under a point on the map canvas, or nil. Overlay textures are rectangles around
-- irregular shapes and overlap, so of the areas whose texture holds the point, the one whose
-- centre (its hit rectangle's, Blizzard's own label target, else the texture's) is nearest wins.
function Model.AreaAt(areas, x, y)
	local best, bestDistance
	for index, area in ipairs(areas) do
		local offsetX, offsetY, width, height = Model.OverlayRect(area.key)
		if x >= offsetX and x <= offsetX + width and y >= offsetY and y <= offsetY + height then
			local left, top, right, bottom = offsetX, offsetY, offsetX + width, offsetY + height
			if area.hit then
				left, top, right, bottom = area.hit[1], area.hit[2], area.hit[3], area.hit[4]
			end
			local dx, dy = x - (left + right) / 2, y - (top + bottom) / 2
			local distance = dx * dx + dy * dy
			if not bestDistance or distance < bestDistance then
				best, bestDistance = index, distance
			end
		end
	end
	return best
end

-- A tile's drawn size and how much of its power-of-two file that covers; only the last
-- tile in a row or column is partial.
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

-- How an overlay's tiles lay out, as Blizzard's MapExplorationPinMixin:RefreshOverlays
-- does it: row-major, `index` into the overlay's tile list, x/y from its top-left.
function Model.OverlayTiles(width, height, tileWidth, tileHeight)
	local wide, tall = math.ceil(width / tileWidth), math.ceil(height / tileHeight)
	local tiles = {}
	for row = 1, tall do
		local tileH, v = TileSpan(height, tileHeight, row, tall)
		for col = 1, wide do
			local tileW, u = TileSpan(width, tileWidth, col, wide)
			tiles[#tiles + 1] = {
				index = (row - 1) * wide + col,
				x = tileWidth * (col - 1),
				y = tileHeight * (row - 1),
				width = tileW,
				height = tileH,
				u = u,
				v = v,
			}
		end
	end
	return tiles
end

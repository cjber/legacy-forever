---@type string, LegacyForeverNamespace
local _, ns = ...

-- Pure logic over the generated data and a snapshot of live progress; no WoW API
-- calls, so tests/model_spec.lua can exercise it under plain LuaJIT.
--
-- `visible` is the set of unfinished reward-bearing challenges the game shows this
-- character (Forever ships two variant sets and the client lists only one).
-- `criteria(achievementID)` returns { [criteriaID] = { text, completed, type, asset,
-- quantity, required, index } }
-- or nil when the game has no data for that achievement.
---@class LegacyModel
local Model = {}
ns.Model = Model

-- Achievement type 8: "earn achievement X", where X is the criterion's asset.
local EARN_ACHIEVEMENT = 8

-- The visible challenge an objective counts toward, or nil if none is visible.
---@param data LegacyData
---@param achievementID number
---@param visible LegacySet
---@return number?
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
---@param data LegacyData
---@param uiMapID number
---@param visible LegacySet
---@param criteria LegacyCriteriaReader
---@return LegacyGroup[]
function Model.ZoneObjectives(data, uiMapID, visible, criteria)
	---@type LegacyGroup[], table<number, LegacyGroup>
	local groups, byAchievement = {}, {}
	for _, entry in ipairs(data.zones[uiMapID] or {}) do
		local challenge = Model.OwningChallenge(data, entry.achievement, visible)
		local live = challenge and criteria(entry.achievement)
		local progress = live and live[entry.criteria]
		if challenge and progress and not progress.completed then
			local group = byAchievement[entry.achievement]
			if not group then
				group = { achievement = entry.achievement, challenge = challenge, uiMapID = uiMapID, objectives = {} }
				byAchievement[entry.achievement] = group
				groups[#groups + 1] = group
			end
			group.objectives[#group.objectives + 1] = { entry = entry, text = progress.text }
		end
	end
	return groups
end

---@param groups LegacyGroup[]
---@return number
function Model.CountObjectives(groups)
	local count = 0
	for _, group in ipairs(groups) do
		count = count + #group.objectives
	end
	return count
end

---@param data LegacyData
---@return LegacySet
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
---@param data LegacyData
---@param located LegacySet
---@param criteria LegacyCriteriaReader
---@param achievementID number
---@return number
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
---@param data LegacyData
---@param visible LegacySet
---@param criteria LegacyCriteriaReader
---@return LegacyUnlocated[]
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

-- Done/total of an achievement's criteria.
---@param steps LegacyCriteria
---@return number done
---@return number total
local function Tally(steps)
	local done, total = 0, 0
	for _, step in pairs(steps) do
		total = total + 1
		done = done + (step.completed and 1 or 0)
	end
	return done, total
end

-- One unfinished step as a tracker line: "3/10" for counted criteria, done/total of X's
-- criteria for "earn achievement X". `seen` names the step, so a block never lists it twice.
---@param criteriaID number
---@param progress LegacyProgress
---@param criteria LegacyCriteriaReader
---@return LegacyTrackerLine
local function StepLine(criteriaID, progress, criteria)
	local detail, seen
	local sub = progress.type == EARN_ACHIEVEMENT and criteria(progress.asset)
	if sub then
		detail = ("%d/%d"):format(Tally(sub))
		seen = "a" .. progress.asset
	elseif progress.required and progress.required > 1 then
		detail = ("%d/%d"):format(progress.quantity, progress.required)
	end
	return { text = progress.text, detail = detail, seen = seen or ("c" .. criteriaID) }
end

-- A tracked challenge's unfinished steps in game order, each with its progress.
---@param challenge number
---@param criteria LegacyCriteriaReader
---@return LegacyTrackerLine[]
function Model.TrackerLines(challenge, criteria)
	local open = {}
	for criteriaID, progress in pairs(criteria(challenge) or {}) do
		if not progress.completed then
			open[#open + 1] = { id = criteriaID, progress = progress }
		end
	end
	table.sort(open, function(a, b)
		return a.progress.index < b.progress.index
	end)
	local lines = {}
	for _, step in ipairs(open) do
		lines[#lines + 1] = StepLine(step.id, step.progress, criteria)
	end
	return lines
end

-- What the map menu tracks for one zone's group: a number is a whole challenge (all 0.3.0
-- stored, and what "No fixed location" still tracks); a string is one zone's share of it.
-- A feeding achievement ("Explore Felwood") is tracked whole, as "<achievement>", wherever
-- it is ticked; objectives a challenge places itself (its dungeons) as "<challenge>:<uiMapID>".
---@param group LegacyGroup
---@return string
function Model.ZoneKey(group)
	if group.achievement ~= group.challenge then
		return tostring(group.achievement)
	end
	return ("%d:%d"):format(group.challenge, group.uiMapID)
end

---@param key string
---@return number? achievement
---@return number? uiMapID
local function ParseKey(key)
	local achievement, uiMapID = key:match("^(%d+):?(%d*)$")
	return tonumber(achievement), tonumber(uiMapID)
end

-- The visible challenge a tracked entry belongs to, or nil while the game lists none.
---@param data LegacyData
---@param key LegacyTrackingKey
---@param visible LegacySet
---@return number?
function Model.TrackedChallenge(data, key, visible)
	if type(key) == "number" then
		return visible[key] and key or nil
	end
	local achievement = ParseKey(key)
	if not achievement then
		return nil
	end
	return Model.OwningChallenge(data, achievement, visible)
end

-- A tracked zone share's unfinished lines: a feeding achievement as one done/total line
-- under its own name, a challenge's own objectives in that zone one line each.
---@param data LegacyData
---@param key string
---@param criteria LegacyCriteriaReader
---@param name fun(achievementID: number): string
---@return LegacyTrackerLine[]
local function ZoneLines(data, key, criteria, name)
	local achievement, uiMapID = ParseKey(key)
	if not achievement then
		return {}
	end
	local steps = criteria(achievement)
	if not steps then
		return {}
	end
	if not uiMapID then
		local done, total = Tally(steps)
		if done == total then
			return {}
		end
		return { { text = name(achievement), detail = ("%d/%d"):format(done, total), seen = "a" .. achievement } }
	end
	local lines = {}
	for _, entry in ipairs(data.zones[uiMapID] or {}) do
		local progress = entry.achievement == achievement and steps[entry.criteria]
		if progress and not progress.completed then
			lines[#lines + 1] = StepLine(entry.criteria, progress, criteria)
		end
	end
	return lines
end

-- The tracker's blocks, one per visible challenge in the order first tracked: the zone shares
-- ticked under it, then (when the whole challenge is tracked) its other unfinished steps.
-- A challenge tracked only through zones drops out once none of them has anything left.
---@param data LegacyData
---@param tracked LegacyTrackingKey[]
---@param visible LegacySet
---@param criteria LegacyCriteriaReader
---@param name fun(achievementID: number): string
---@return LegacyTrackedBlock[]
function Model.TrackedBlocks(data, tracked, visible, criteria, name)
	---@type LegacyTrackedBlock[], table<number, LegacyTrackedBlock>
	local blocks, byChallenge = {}, {}
	for _, key in ipairs(tracked) do
		local challenge = Model.TrackedChallenge(data, key, visible)
		if challenge then
			local block = byChallenge[challenge]
			if not block then
				block = { challenge = challenge, lines = {}, seen = {} }
				byChallenge[challenge] = block
				blocks[#blocks + 1] = block
			end
			if type(key) == "number" then
				block.whole = true
			else
				for _, line in ipairs(ZoneLines(data, key, criteria, name)) do
					if not block.seen[line.seen] then
						block.seen[line.seen] = true
						block.lines[#block.lines + 1] = line
					end
				end
			end
		end
	end
	local shown = {}
	for _, block in ipairs(blocks) do
		if block.whole then
			for _, line in ipairs(Model.TrackerLines(block.challenge, criteria)) do
				if not block.seen[line.seen] then
					block.lines[#block.lines + 1] = line
				end
			end
		end
		if block.whole or #block.lines > 0 then
			shown[#shown + 1] = block
		end
	end
	return shown
end

-- One category of a zone's completion: { done, total, left = { names } }, or nil when
-- the zone has none. `state(item)` returns true (done),
-- false (not done) or nil (unknown, left out of the count).
---@generic T: { name: string }
---@param items T[]?
---@param state fun(item: T): boolean?
---@return LegacyCategory?
local function CompletionCategory(items, state)
	if not items or #items == 0 then
		return nil
	end
	local category = { done = 0, total = 0, left = {}, pending = 0 }
	for _, item in ipairs(items) do
		local done = state(item)
		if done == nil then
			category.pending = category.pending + 1
		else
			category.total = category.total + 1
			if done then
				category.done = category.done + 1
			else
				category.left[#category.left + 1] = item.name
			end
		end
	end
	category.complete = category.done == category.total and category.pending == 0
	return category
end

---@type LegacyCategoryKey[]
Model.COMPLETION_CATEGORIES = { "areas", "taxis", "dungeons", "raids", "legacy", "reputations" }

-- A raid is done when every boss is, and a boss when any of its refs is; unknown while any boss is.
---@param raid LegacyRaid
---@param refsDone fun(refs: LegacyRefs): boolean?
---@return boolean?
local function RaidDone(raid, refsDone)
	local done = true
	for _, boss in ipairs(raid.bosses) do
		local bossDone = refsDone(boss.refs)
		if bossDone == nil then
			return nil
		end
		done = done and bossDone
	end
	return done
end

-- A zone's reputation counts once the player is Friendly (reaction 5) or better with it.
Model.REPUTATION_TARGET = 5

-- Entries for the player's side: those with no side under `sideKey`, Neutral ones, and the player's faction's.
---@generic T
---@param items T[]?
---@param faction string
---@param sideKey string
---@return T[]
local function ForFaction(items, faction, sideKey)
	local own = {}
	for _, item in ipairs(items or {}) do
		local side = item[sideKey]
		if side == nil or side == "Neutral" or side == faction then
			own[#own + 1] = item
		end
	end
	return own
end

-- A zone's completion, GW2 style: every area, flight path, dungeon, Legacy objective and
-- local reputation counts once.
-- Items whose state is unknown (nil) are `pending`: shown, but outside done/total and the percent.
-- `snapshot` = { explored = set of overlay keys, taxis = { [node] = known } once a
-- flight master on the zone's continent has been opened (until then every node is pending),
-- faction = "Alliance" | "Horde",
-- refsDone = function(refs) -> true/false/nil, reaction = function(factionID) -> number }.
-- Areas, flight paths and reputations are per character; dungeon wings, raids and Legacy
-- objectives are account-wide Legacy steps, done when any of their refs is (a raid: every boss).
-- `counted(key)`, when given, says which categories the player counts; the rest are left out entirely.
---@param zone LegacyZone
---@param snapshot LegacySnapshot
---@param counted? fun(key: LegacyCategoryKey): boolean
---@return LegacyZoneResult
function Model.ZoneCompletion(zone, snapshot, counted)
	---@type LegacyZoneResult
	local result = {
		areas = CompletionCategory(zone.areas, function(area)
			return snapshot.explored[area.key] == true
		end),
		taxis = CompletionCategory(ForFaction(zone.taxis, snapshot.faction, "faction"), function(taxi)
			return snapshot.taxis[taxi.node]
		end),
		dungeons = CompletionCategory(zone.dungeons, function(wing)
			return snapshot.refsDone(wing.refs)
		end),
		raids = CompletionCategory(zone.raids, function(raid)
			return RaidDone(raid, snapshot.refsDone)
		end),
		legacy = CompletionCategory(zone.legacy, function(objective)
			return snapshot.refsDone(objective.refs)
		end),
		reputations = CompletionCategory(ForFaction(zone.reputations, snapshot.faction, "side"), function(rep)
			return snapshot.reaction(rep.faction) >= Model.REPUTATION_TARGET
		end),
		done = 0,
		total = 0,
		pending = 0,
		complete = false,
	}
	for _, key in ipairs(Model.COMPLETION_CATEGORIES) do
		if counted and not counted(key) then
			result[key] = nil
		end
		local category = result[key]
		if category then
			result.done = result.done + category.done
			result.total = result.total + category.total
			result.pending = result.pending + category.pending
		end
	end
	result.complete = result.done == result.total and result.pending == 0
	-- Floored, and held under 100 while anything is pending, so 100% means nothing is left.
	result.percent = result.total > 0 and math.floor(100 * result.done / result.total) or nil
	if result.percent and not result.complete then
		result.percent = math.min(result.percent, 99)
	end
	return result
end

-- Whether a zone completion counts anything at all: a zone with every category switched off
-- (or none to count) is neither complete nor incomplete.
---@param result LegacyZoneResult
---@return boolean
function Model.CompletionCounts(result)
	return result.total > 0 or result.pending > 0
end

-- A continent's zone completion from its zones' results: { complete, zones, percent },
-- or nil when none of them counts anything.
---@param results LegacyZoneResult[]
---@return LegacyContinentResult?
function Model.ContinentCompletion(results)
	local continent = { complete = 0, zones = 0 }
	for _, result in ipairs(results) do
		if Model.CompletionCounts(result) then
			continent.zones = continent.zones + 1
			if result.complete then
				continent.complete = continent.complete + 1
			end
		end
	end
	if continent.zones == 0 then
		return nil
	end
	continent.percent = math.floor(100 * continent.complete / continent.zones)
	return continent
end

-- offsetX, offsetY, width, height from an overlay key ("offsetX:offsetY:width:height").
---@param key string
---@return number offsetX
---@return number offsetY
---@return number width
---@return number height
function Model.OverlayRect(key)
	local offsetX, offsetY, width, height = key:match("^(%d+):(%d+):(%d+):(%d+)$")
	-- The generator validates overlay keys; fail here if another caller violates that contract.
	return assert(tonumber(offsetX)), assert(tonumber(offsetY)), assert(tonumber(width)), assert(tonumber(height))
end

-- The area under a point on the map canvas, or nil. Overlay textures are rectangles around
-- irregular shapes and overlap, so of the areas whose texture holds the point, the one whose
-- centre (its hit rectangle's, Blizzard's own label target, else the texture's) is nearest wins.
---@param areas LegacyArea[]
---@param x number
---@param y number
---@return number?
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

-- How an overlay's tiles lay out, as Blizzard's MapExplorationPinMixin:RefreshOverlays
-- does it: row-major, `index` into the overlay's tile list, x/y from its top-left.
---@param width number
---@param height number
---@param tileWidth number
---@param tileHeight number
---@return LegacyTile[]
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

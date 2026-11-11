---@type string, LegacyForeverNamespace
local _, ns = ...

if ns.broken then
	return
end

-- LegacyForever.API: zone completion and the zone's unfinished Legacy objectives for other addons, read from
-- the same computations the map and tracker draw. Every call returns fresh tables. docs/api.md has the contract.
-- Areas, flight paths, reputations and quests are this character's; dungeon wings, raids and Legacy
-- objectives are account-wide Legacy steps. `minor` rises with each addition within version 1 (1: Leaderboard,
-- 2: Subscribe's changes table and the reads' not-ready answers, 3: IsTracked/SetTracked and the tracked channel,
-- a nil map's current zone, achievementName and points on targets); a caller checks a member before using it.
local API = {
	version = 1,
	minor = 3,
}

-- The shared shape every Forever addon's API follows: the hub that tells callers a frame after a change, and the
-- not-ready answer a read gives while there is nothing to answer (ForeverCore's docs/api-conventions.md).
local APIKit = assert(ForeverCore.APIKit)

---@type table<LegacyCategoryKey, "character"|"account">
local SCOPES = {
	areas = "character",
	taxis = "character",
	dungeons = "account",
	raids = "account",
	legacy = "account",
	reputations = "character",
	quests = "character",
}
local MAX_TARGETS = 5

-- NaN and infinities fail `% 1 == 0`.
---@param value any
---@return boolean
local function IsInteger(value)
	return type(value) == "number" and value % 1 == 0
end

-- The game reports the player's faction, and this character's progress with it, once the player exists. Every read
-- that needs it answers "loading" until then, and the hub reads no key while it is false.
---@return boolean
local function Ready()
	return UnitFactionGroup("player") ~= nil
end

-- A read with nothing to answer, in this API's own read errors: the kit answers `nil, reason` and docs/api.md lists
-- which reasons each read can return.
---@param reason "loading"
---@return nil, LFReadError
local function NotReady(reason)
	local _, answer = APIKit.NotReady(reason)
	return nil, answer --[[@as LFReadError]]
end

---@return "disabled"|"ready"|"loading"|"missing"|"unsupported"
local function QuestsStatus()
	if not ns.ZoneCompletion.IsCounted("quests") then
		return "disabled"
	end
	if ns.Quests.Cold() then
		return "loading"
	end
	return ns.Quests.Status()
end

---@param map? integer
---@return LFZoneSummary?
---@return LFReadError?
function API.ZoneSummary(map)
	if map == nil then
		-- No map asks for the zone the player is in, the one the addon's map corner and tracker read.
		map = ns.Live.CurrentZone()
		if map == nil then
			return nil, "none"
		end
	end
	if not IsInteger(map) then
		return nil, "invalid"
	end
	if not ns.Data.completion[map] then
		return nil, "unsupported"
	end
	-- Flight paths and reputations are filtered by side, which the game reports once the player exists.
	if not Ready() then
		return NotReady("loading")
	end
	local result = assert(ns.ZoneCompletion.Result(map))
	---@type LFCategorySummary[]
	local categories = {}
	for _, key in ipairs(ns.Model.COMPLETION_CATEGORIES) do
		local category = result[key]
		if category then
			categories[#categories + 1] = {
				key = key,
				scope = SCOPES[key],
				done = category.done,
				total = category.total,
				pending = category.pending,
				complete = category.complete,
			}
		end
	end
	local info = C_Map.GetMapInfo(map)
	return {
		map = map,
		name = info and info.name or "",
		done = result.done,
		total = result.total,
		pending = result.pending,
		-- A zone with nothing counted is neither complete nor incomplete.
		complete = result.complete and ns.Model.CompletionCounts(result),
		categories = categories,
		questsStatus = QuestsStatus(),
	}
end

-- A target's key: its criterion, which appears at most once in a zone's data.
---@param entry LegacyEntry
---@return string
local function Key(entry)
	return ("%d:%d"):format(entry.achievement, entry.criteria)
end

-- The zone's unfinished objectives of visible challenges, in the data's order.
---@param map integer
---@return LegacyObjective[]
local function Objectives(map)
	local objectives = {}
	for _, group in ipairs(ns.Model.ZoneObjectives(ns.Data, map, ns.Live.Visible(), ns.Live.Criteria)) do
		for _, objective in ipairs(group.objectives) do
			objectives[#objectives + 1] = objective
		end
	end
	return objectives
end

---@param map integer
---@return boolean
local function KnownMap(map)
	return ns.Data.zones[map] ~= nil or ns.Data.completion[map] ~= nil
end

---@param map? integer
---@param limit? number
---@return LFTarget[]?
---@return LFReadError?
function API.Targets(map, limit)
	if map == nil then
		-- As the addon's own tracker reads it: the zone the player is in.
		map = ns.Live.CurrentZone()
		if map == nil then
			return nil, "none"
		end
	end
	if not IsInteger(map) or (limit ~= nil and (type(limit) ~= "number" or limit ~= limit)) then
		return nil, "invalid"
	end
	if not KnownMap(map) then
		return nil, "unsupported"
	end
	-- Before the player exists the game lists no challenge for this character, so an empty answer would be a guess.
	if not Ready() then
		return NotReady("loading")
	end
	limit = math.max(1, math.min(MAX_TARGETS, math.floor(limit or MAX_TARGETS)))
	---@type LFTarget[]
	local targets = {}
	-- A zone's rows usually share an achievement, so its name and points are asked once per call rather than once
	-- per row. Nothing outlives the call, so the values cannot go stale and no timer is added.
	---@type table<number, { name: string, points: number? }>
	local achievements = {}
	for _, objective in ipairs(Objectives(map)) do
		if #targets == limit then
			break
		end
		local entry = objective.entry
		local known = achievements[entry.achievement]
		if not known then
			known = { name = ns.Live.Name(entry.achievement), points = ns.Live.Points(entry.achievement) }
			achievements[entry.achievement] = known
		end
		---@type LFTarget
		local target = {
			key = Key(entry),
			text = objective.text,
			kind = entry.kind,
			achievementID = entry.achievement,
			achievementName = known.name,
			criteriaID = entry.criteria,
		}
		if known.points ~= nil then
			target.points = known.points
		end
		local progress = (ns.Live.Criteria(entry.achievement) or {})[entry.criteria]
		if progress and progress.required and progress.required > 1 then
			target.quantity = progress.quantity
			target.required = progress.required
		end
		if entry.x and entry.y then
			target.place = { map = map, x = entry.x, y = entry.y }
		end
		targets[#targets + 1] = target
	end
	return targets
end

--[[ Tracked: whether the tracker shows a target's challenge ]]

-- The tracker's own key for each criterion: the group holding it, which is a challenge's share of one zone
-- ("<challenge>:<uiMapID>") or the feeding achievement tracked whole ("<achievement>"). A criterion appears in at
-- most one zone's data, so an API key names one group.
---@type table<string, integer>?
local placement

---@return table<string, integer>
local function Placement()
	if not placement then
		placement = {}
		for uiMapID, entries in pairs(ns.Data.zones) do
			for _, entry in ipairs(entries) do
				placement[Key(entry)] = uiMapID
			end
		end
	end
	return placement
end

-- An API target key as the tracker's LegacyTrackingKey, or nil when no zone places it or the game lists no
-- challenge for it. The two keys differ (a target is one criterion, the tracker holds a zone share or a feeding
-- achievement), so the conversion stays here, at the API's edge, rather than in either side's own key.
---@param key string
---@return LegacyTrackingKey?
local function TrackingKey(key)
	local achievement = key:match("^(%d+):%d+$")
	if not achievement then
		return nil
	end
	local uiMapID = Placement()[key]
	if not uiMapID then
		return nil
	end
	local achievementID = assert(tonumber(achievement))
	local challenge = ns.Model.OwningChallenge(ns.Data, achievementID, ns.Live.Visible())
	if not challenge then
		return nil
	end
	return ns.Model.ZoneKey({
		achievement = achievementID,
		challenge = challenge,
		uiMapID = uiMapID,
		objectives = {},
	})
end

---@param key string
---@return boolean?
---@return LFReadError?
function API.IsTracked(key)
	if type(key) ~= "string" or not key:find("^%d+:%d+$") then
		return nil, "invalid"
	end
	if not Ready() then
		return NotReady("loading")
	end
	local trackingKey = TrackingKey(key)
	if trackingKey == nil then
		return nil, "invalid"
	end
	return ns.Tracker.IsTracked(trackingKey)
end

-- Tracking writes the tracker's own list, so it answers whether that list changed, or that the player is still
-- loading; IsTracked is the read that tells a caller why nothing changed.
---@param key string
---@param tracked boolean
---@return boolean?
---@return LFReadError?
function API.SetTracked(key, tracked)
	if type(key) ~= "string" or type(tracked) ~= "boolean" then
		return false
	end
	if not Ready() then
		return NotReady("loading")
	end
	local trackingKey = TrackingKey(key)
	if trackingKey == nil then
		return false
	end
	return ns.Tracker.SetTracked(trackingKey, tracked)
end

---@param value number?
---@return boolean
local function Normalised(value)
	return type(value) == "number" and value >= 0 and value <= 1
end

---@param map integer
---@param key string
---@return boolean
---@return LFNavError?
function API.Navigate(map, key)
	if not IsInteger(map) or type(key) ~= "string" or not KnownMap(map) or not key:find("^%d+:%d+$") then
		return false, "invalid"
	end
	-- Read again rather than trusted: the objective may have been finished since the key was handed out.
	for _, objective in ipairs(Objectives(map)) do
		local entry = objective.entry
		if Key(entry) == key then
			if not (Normalised(entry.x) and Normalised(entry.y)) then
				return false, "unlocated"
			end
			local guided, reason = ns.Guide(map, entry.x, entry.y, objective.text)
			return guided, reason
		end
	end
	return false, "stale"
end

-- A flight path is counted only after the player opens a flight master's map, the one source that reliably tells
-- this client which nodes the character knows. Zone exploration overlays are not used as a proxy on Forever.
---@return LFActivityRecord[]
function API.Stats()
	local guid = UnitGUID("player")
	local record = guid and ns.SavedTable("flightPaths")[guid]
	local rows = {}
	for nodeID, value in pairs(record and record.known or {}) do
		if value == true then
			rows[#rows + 1] = {
				addon = "LegacyForever",
				metric = "flight_path_known",
				subject = tostring(nodeID),
				value = 1,
				eventUnix = record and record.observedAt or nil,
			}
		end
	end
	table.sort(rows, function(a, b)
		return a.subject < b.subject
	end)
	return rows
end
ns.ActivityStats = API.Stats

-- Cumulative flight paths observed, as Forever Leaderboards ranks them for this addon's tab. A read-through, so the
-- caller gets the board's own fresh rows.
---@param limit? integer
---@return LFFlightLeaderboard?
---@return LFReadError?
function API.Leaderboard(limit)
	return ns.Stats.Leaderboard(limit)
end

--[[ Subscribe: the frame after the zone, its summary or its targets changes ]]

-- The API answers for the zone the player is in, so that is what each change name stands for. docs/api.md lists
-- every name, and a caller showing another map reads it again when `zone` changes.

-- The published summary as one comparable key: its counts, whether it is complete and its quest state.
---@param uiMapID integer?
---@return string|false
local function SummaryKey(uiMapID)
	local summary = uiMapID ~= nil and API.ZoneSummary(uiMapID) or nil
	if not summary then
		return false
	end
	local parts = {
		("%d:%d:%d:%s:%s"):format(
			summary.done,
			summary.total,
			summary.pending,
			tostring(summary.complete),
			summary.questsStatus
		),
	}
	for _, category in ipairs(summary.categories) do
		parts[#parts + 1] = ("%s:%d:%d:%d:%s"):format(
			category.key,
			category.done,
			category.total,
			category.pending,
			tostring(category.complete)
		)
	end
	return table.concat(parts, "|")
end

-- The published targets as one comparable key: each target's identity, text, achievement name and points, and
-- counted progress.
---@param uiMapID integer?
---@return string|false
local function TargetsKey(uiMapID)
	local targets = uiMapID ~= nil and API.Targets(uiMapID, MAX_TARGETS) or nil
	if not targets then
		return false
	end
	local parts = {}
	for _, target in ipairs(targets) do
		local part = ("%s:%s:%s:%s"):format(target.key, target.text, target.achievementName, tostring(target.points))
		if target.quantity ~= nil then
			part = part .. (":%d/%d"):format(target.quantity, target.required or 0)
		end
		parts[#parts + 1] = part
	end
	return table.concat(parts, "|")
end

-- One dispatch on the next frame per burst of changes, a fresh table naming only the names that changed, and each
-- callback under this addon's SafeCall (ForeverCore.APIKit.Hub). Progress, a quest source, "What counts" and the
-- zone the player is in all reach Legacy through ZoneCompletion's one notice.
-- Raised on every notice from ZoneCompletion, so a change in any zone (an account-wide wing done elsewhere, "What
-- counts" switched) still reaches callers, as Subscribe always did; the other names say what changed in the zone the
-- player is in. `tracked` is the tracker's list revision, raised where the list itself changes, so the player's own
-- map menu tick reaches callers as surely as SetTracked does.
local notices = 0
local hub = APIKit.Hub("LegacyForever", {
	progress = function()
		return notices
	end,
	zone = function()
		return ns.Live.CurrentZone() or false
	end,
	summary = function()
		return SummaryKey(ns.Live.CurrentZone())
	end,
	targets = function()
		return TargetsKey(ns.Live.CurrentZone())
	end,
	tracked = function()
		return ns.Tracker.Revision()
	end,
}, Ready)
API.Subscribe = hub.Subscribe
ns.ZoneCompletion.OnChange(function()
	notices = notices + 1
	hub.Queue()
end)
ns.Tracker.OnChange(hub.Queue)

LegacyForever = { API = API }
-- Handed to the suite's one list, so a reader finds this API without naming it (ForeverCore.APIKit.Addons). A core
-- from before the kit's minor 2 has no Publish, and the API reads exactly as before without it.
if (ForeverCore.APIKit.minor or 1) >= 2 then
	ForeverCore.APIKit.Publish("LegacyForever", API)
end

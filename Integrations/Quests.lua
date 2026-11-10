---@type string, LegacyForeverNamespace
local _, ns = ...

if ns.broken then
	return
end

-- A zone's quests come from QuestieDB, the database addon that ships with Questie
-- (github.com/Questie/QuestieDB), read through its public contract: its quest fields with the
-- Forever corrections applied, and its zone tables. Legacy Forever ships no quest data. When
-- Questie itself is loaded too, its blacklist also leaves out quests the game never offers
-- (removed quests, duplicates, holidays). Any other version turns the Quests category off
-- rather than breaking anything.
---@class LegacyQuests
local Quests = {}
ns.Quests = Quests

-- The QuestieDB contract this was written for (QuestieDB 1.0.3, the first with Forever data).
local CONTRACT = 2

-- Questie's blacklist value for a quest it only keeps off the map; the quest is still offered.
local HIDE_ON_MAP = "HIDE_ON_MAP"

-- Questie can load and then never report ready, when its own startup stops on an error for one character.
-- Waiting longer than this leaves the category on its loading line for the whole session, so past this the
-- database is read as it stands, without Questie's blacklist; a ready callback arriving later reads it again.
local READY_WAIT = 60

-- Milliseconds of the index one frame gets: QuestieDB reads about fifteen fields for every quest, then
-- walks the prerequisites, and in one frame that was a visible stall on the first draw and again when
-- Questie became ready.
local SLICE_MS = 2

-- Forever's Skyborne races use playable-race bits 32 and 33, not race ID minus one, and a
-- faction-wide mask from the Classic data (77 or 178) takes them in with their faction.
local SKYBORNE = { [95] = 2 ^ 32, [96] = 2 ^ 33 }
local FACTION_MASK = { Alliance = 77, Horde = 178 }

-- Built once QuestieDB (and Questie, when loaded) is ready: false when the data didn't read as expected.
---@type table<number, LegacyQuestItem[]>|false|nil
local index
---@type string?
local failure
-- The index build in progress, a slice a frame; nil when there is none.
---@type thread?
local builder
-- Milliseconds into the slice being built.
local sliceStart = 0
-- Whether Questie has kept the category waiting past READY_WAIT.
local waited = false

-- QuestieDB, when its contract and shape are the ones this was written for.
---@return LibQuestieDB?
local function Library()
	local lib = LibQuestieDB
	if type(lib) ~= "table" or type(lib.RequireContract) ~= "function" then
		return nil
	end
	local ok, compatible = pcall(lib.RequireContract, CONTRACT)
	local quest, support = lib.Quest, lib.Support
	local expected = ok
		and compatible
		and type(quest) == "table"
		and type(quest.Get) == "function"
		and type(quest.GetAllIds) == "function"
		and type(support) == "table"
		and type(support.Get) == "function"
	return expected and lib or nil
end

-- Questie's quest policy, when Questie is loaded and reads as expected: which quests it hides.
---@return fun(questID: number): boolean
local function Policy()
	if type(QuestieLoader) ~= "table" or type(QuestieLoader.ImportModule) ~= "function" then
		return function()
			return false
		end
	end
	local corrections = QuestieLoader:ImportModule("QuestieCorrections")
	local events = QuestieLoader:ImportModule("QuestieEvent")
	local hidden = type(corrections) == "table" and corrections.hiddenQuests
	local isEvent = type(events) == "table" and events.IsEventQuest
	return function(questID)
		local value = type(hidden) == "table" and hidden[questID]
		return (value ~= nil and value ~= false and value ~= HIDE_ON_MAP)
			or (type(isEvent) == "function" and isEvent(questID) == true)
	end
end

-- "ready", "loading" (Questie is still starting), "missing" (no QuestieDB) or "unsupported".
---@return 'ready'|'loading'|'missing'|'unsupported'
function Quests.Status()
	if type(LibQuestieDB) ~= "table" then
		return "missing"
	end
	if index == false or not Library() then
		return "unsupported"
	end
	-- Questie fills its blacklist as it starts; QuestieDB alone is ready once loaded. Questie can also stop
	-- starting without ever reporting ready, so past READY_WAIT the database is read as it stands.
	local api = type(Questie) == "table" and Questie.API
	if type(api) == "table" and api.isReady == false and not waited then
		return "loading"
	end
	return "ready"
end

---@return string?
function Quests.Failure()
	return failure
end

-- One of QuestieDB's zone tables: some ship as a `return {...}` chunk, decoded on first use.
---@param value any
---@return table
local function Decode(value)
	if type(value) == "string" then
		value = assert(loadstring(value))()
	end
	assert(type(value) == "table", "QuestieDB zone data isn't a table")
	return value
end

-- Base zone table with its overrides on top.
---@param zones table
---@param name string
---@return table<number, number>
local function Merged(zones, name)
	local merged = {}
	for key, value in pairs(Decode(zones[name])) do
		merged[key] = value
	end
	for key, value in pairs(Decode(zones[name .. "Override"] or {})) do
		merged[key] = value
	end
	return merged
end

---@param mask number
---@param flag number
---@return boolean
local function HasBit(mask, flag)
	return mask == 0 or mask % (2 * flag) >= flag
end

---@param lib LibQuestieDB
---@return LegacyQuestSource
local function Source(lib)
	local zones = assert(lib.Support.Get("ZoneDB"), "QuestieDB has no zone data").private
	local uiMaps = Merged(zones, "areaIdToUiMapId")
	local parents = Merged(zones, "subZoneToParentZone")
	local dungeons = {}
	for areaID, dungeon in pairs(Decode(zones.dungeons)) do
		dungeons[areaID] = true
		for _, alternative in ipairs(type(dungeon[2]) == "table" and dungeon[2] or {}) do
			dungeons[alternative] = true
		end
	end
	local raceID, classID = (select(3, UnitRace("player"))), (select(3, UnitClass("player")))
	local raceFlag = SKYBORNE[raceID] or (2 ^ (raceID - 1))
	local factionMask = FACTION_MASK[UnitFactionGroup("player")]
	return {
		ids = lib.Quest.GetAllIds(),
		get = lib.Quest.Get,
		hidden = Policy(),
		-- A subzone counts in its zone; an instance, or a zone inside one, in none.
		zone = function(areaID)
			local parent = parents[areaID]
			if dungeons[areaID] or (parent and dungeons[parent]) then
				return nil
			end
			local uiMapID = uiMaps[parent or areaID]
			return uiMapID ~= 0 and uiMapID or nil
		end,
		race = function(mask)
			if SKYBORNE[raceID] and (mask == FACTION_MASK.Alliance or mask == FACTION_MASK.Horde) then
				return mask == factionMask
			end
			return HasBit(mask, raceFlag)
		end,
		class = function(mask)
			return HasBit(mask, 2 ^ (classID - 1))
		end,
	}
end

-- Resumes the build once; true once it has finished or failed, with `index` set.
---@param co thread
---@return boolean done
local function Resume(co)
	local ok, result = coroutine.resume(co)
	if not ok then
		index, failure = false, tostring(result)
		return true
	end
	if coroutine.status(co) ~= "dead" then
		return false
	end
	local built = result --[[@as table<number, LegacyQuestItem[]>]]
	index, failure = built, nil
	return true
end

---@return LegacyQuestSource
local function SourceNow()
	return Source(assert(Library()))
end

-- Starts building the index, a slice a frame: the frame it lands on announces the change, as Questie
-- finishing its start does.
local function Start()
	local ok, source = pcall(SourceNow)
	if not ok then
		index, failure = false, tostring(source)
		ns.Live.Invalidate()
		return
	end
	local co = coroutine.create(function()
		return ns.Model.QuestIndex(source, ns.Data.completion, function()
			if debugprofilestop() - sliceStart >= SLICE_MS then
				coroutine.yield()
			end
		end)
	end)
	builder = co
	local function Step()
		-- A synchronous reader finished this build in its own call.
		if builder ~= co then
			return
		end
		sliceStart = debugprofilestop()
		if Resume(co) then
			builder = nil
			ns.Live.Invalidate()
		else
			C_Timer.After(0, Step)
		end
	end
	Step()
end

-- Builds the index in this call: a typed command (/lf audit) asks for the answer now. A build already
-- sliced across frames is finished here rather than started again.
local function Build()
	if builder then
		local co = builder
		while not Resume(co) do
		end
		builder = nil
		-- Whoever read the index as pending while it was sliced is waiting for this.
		ns.Live.Invalidate()
		return
	end
	local ok, source = pcall(SourceNow)
	if not ok then
		index, failure = false, tostring(source)
		return
	end
	local co = coroutine.create(function()
		return ns.Model.QuestIndex(source, ns.Data.completion)
	end)
	while not Resume(co) do
	end
end

-- Whether QuestieDB is ready but its index not yet built: the first read walks the whole database.
---@return boolean
function Quests.Cold()
	return index == nil and Quests.Status() == "ready"
end

local scheduled = false

-- The zone's quests for this character; false while Questie is still loading, nil without a usable QuestieDB
-- (missing, an unsupported version, or a failed build).
-- `deferred` never builds the index during the call: a cold index reads as loading, is built a slice a
-- frame from the next one, and the change is announced like Questie finishing its start.
---@param uiMapID number
---@param deferred? boolean
---@return LegacyQuestItem[]|false|nil
function Quests.Zone(uiMapID, deferred)
	local status = Quests.Status()
	if status == "loading" then
		return false
	end
	if Quests.Cold() then
		if not deferred then
			Build()
		else
			if not scheduled and not builder then
				scheduled = true
				C_Timer.After(0, function()
					scheduled = false
					if Quests.Cold() then
						Start()
					else
						-- Another reader built it first: whoever read "loading" is waiting for this.
						ns.Live.Invalidate()
					end
				end)
			end
			return false
		end
	end
	return index and (index[uiMapID] or {}) or nil
end

-- Questie's blacklist settles once it has started; the index is built after that. Questie is in
-- the TOC's OptionalDeps so it loads first and its API exists here.
local api = type(Questie) == "table" and Questie.API
if type(api) == "table" and type(api.RegisterOnReady) == "function" then
	pcall(api.RegisterOnReady, function()
		if index == false then
			return
		end
		-- A build in flight read QuestieDB before its blacklist: drop it, so the rebuild has the blacklist.
		index, builder = nil, nil
		ns.Live.Invalidate()
	end)
end
if type(api) == "table" and api.isReady == false then
	C_Timer.After(READY_WAIT, function()
		local now = type(Questie) == "table" and Questie.API
		if waited or type(now) ~= "table" or now.isReady ~= false then
			return
		end
		waited = true
		ns.Live.Invalidate()
	end)
end

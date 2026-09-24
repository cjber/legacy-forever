---@type string, LegacyForeverNamespace
local _, ns = ...

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

-- Forever's Skyborne races use playable-race bits 32 and 33, not race ID minus one, and a
-- faction-wide mask from the Classic data (77 or 178) takes them in with their faction.
local SKYBORNE = { [95] = 2 ^ 32, [96] = 2 ^ 33 }
local FACTION_MASK = { Alliance = 77, Horde = 178 }

-- Built once QuestieDB (and Questie, when loaded) is ready: false when the data didn't read as expected.
---@type table<number, LegacyQuestItem[]>|false|nil
local index
---@type string?
local failure

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
	-- Questie fills its blacklist as it starts; QuestieDB alone is ready once loaded.
	local api = type(Questie) == "table" and Questie.API
	if type(api) == "table" and api.isReady == false then
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

-- The zone's quests for this character; false while Questie is still loading, nil without QuestieDB.
---@param uiMapID number
---@return LegacyQuestItem[]|false|nil
function Quests.Zone(uiMapID)
	local status = Quests.Status()
	if status == "loading" then
		return false
	end
	if index == nil and status == "ready" then
		local ok, result = pcall(function()
			return ns.Model.QuestIndex(Source(assert(Library())), ns.Data.completion)
		end)
		index = ok and result or false
		failure = not ok and tostring(result) or nil
	end
	return index and (index[uiMapID] or {}) or nil
end

-- Questie's blacklist settles once it has started; the index is built after that.
local api = type(Questie) == "table" and Questie.API
if type(api) == "table" and type(api.RegisterOnReady) == "function" then
	pcall(api.RegisterOnReady, function()
		if index == false then
			return
		end
		index = nil
		ns.Live.Invalidate()
	end)
end

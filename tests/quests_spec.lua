-- Run from the repository root: luajit tests/quests_spec.lua
-- The Quests category against a fake QuestieDB (and, optionally, Questie): which quests count, how
-- they feed a zone's and a continent's completion, and how the adapter copes with QuestieDB
-- missing, another version, Questie still loading, or data that doesn't read.
local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

-- Area 12 is uiMapID 1429 and 14 is 1411; subzone 87 sits in 12; 1581 is an instance with an
-- alternative area 10029; 555 has no map. Race and class masks are 2^(ID - 1).
local HUMAN, ORC, PALADIN, WARRIOR = 1, 2, 2, 1
local quests = {
	[1] = { name = "Wolves", zoneOrSort = 12, startedBy = { { 5 } } },
	[2] = { name = "Subzone", zoneOrSort = 87, startedBy = { nil, { 7 } } },
	[3] = { name = "Orcs only", zoneOrSort = 12, startedBy = { { 5 } }, requiredRaces = ORC },
	[4] = { name = "Paladin", zoneOrSort = 12, startedBy = { { 5 } }, requiredClasses = PALADIN },
	[5] = { name = "Warrior", zoneOrSort = 12, startedBy = { { 5 } }, requiredClasses = WARRIOR },
	[6] = { name = "Either A", zoneOrSort = 12, startedBy = { { 5 } }, exclusiveTo = { 7 } },
	[7] = { name = "Either B", zoneOrSort = 12, startedBy = { { 5 } }, exclusiveTo = { 6 } },
	[8] = { name = "Removed", zoneOrSort = 12, startedBy = { { 5 } } },
	[9] = { name = "Repeat", zoneOrSort = 12, startedBy = { { 5 } }, specialFlags = 1 },
	[10] = { name = "Daily", zoneOrSort = 12, startedBy = { { 5 } }, questFlags = 4096 + 8 },
	[11] = { name = "Tailoring", zoneOrSort = 12, startedBy = { { 5 } }, requiredSkill = { 197, 50 } },
	[12] = { name = "Friendly", zoneOrSort = 12, startedBy = { { 5 } }, requiredMinRep = { 72, 3000 } },
	[13] = { name = "Instance", zoneOrSort = 1581, startedBy = { { 5 } } },
	[14] = { name = "Class sort", zoneOrSort = -81, startedBy = { { 5 } } },
	[15] = { name = "From an item", zoneOrSort = 12, startedBy = { nil, nil, { 99 } } },
	[16] = { name = "After wolves", zoneOrSort = 12, startedBy = { { 5 } }, preQuestSingle = { 1 } },
	[17] = { name = "After orcs", zoneOrSort = 12, startedBy = { { 5 } }, preQuestGroup = { 3 } },
	[18] = { name = "After A", zoneOrSort = 12, startedBy = { { 5 } }, preQuestGroup = { 6 } },
	[19] = { name = "After A or B", zoneOrSort = 12, startedBy = { { 5 } }, preQuestSingle = { 6, 7 } },
	[20] = { name = "Breadcrumb", zoneOrSort = 12, startedBy = { { 5 } }, breadcrumbForQuestId = 21 },
	[21] = { name = "Durotar", zoneOrSort = 14, startedBy = { { 5 } } },
	[22] = { name = "Loop A", zoneOrSort = 12, startedBy = { { 5 } }, preQuestGroup = { 23 } },
	[23] = { name = "Loop B", zoneOrSort = 12, startedBy = { { 5 } }, preQuestGroup = { 22 } },
	[24] = { name = "Holiday", zoneOrSort = 12, startedBy = { { 5 } } },
	[25] = { name = "Map only", zoneOrSort = 12, startedBy = { { 5 } } },
	[26] = { name = "Unmapped", zoneOrSort = 555, startedBy = { { 5 } } },
	[27] = { name = "Instance wing", zoneOrSort = 10029, startedBy = { { 5 } } },
	[28] = { name = "Alliance", zoneOrSort = 14, startedBy = { { 5 } }, requiredRaces = 77 },
	[29] = { name = "Skyborne", zoneOrSort = 14, startedBy = { { 5 } }, requiredRaces = 2 ^ 32 },
}

-- The character, as the client reports it.
local race, class, faction = HUMAN, PALADIN, "Alliance"
UnitRace = function()
	return "Race", "Race", race
end
UnitClass = function()
	return "Class", "CLASS", class
end
UnitFactionGroup = function()
	return faction
end

-- QuestieDB's public surface; tests swap parts to break the shape.
local zoneData
local function FakeQuestieDB()
	local ids = {}
	for questID in pairs(quests) do
		ids[#ids + 1] = questID
	end
	table.sort(ids)
	zoneData = {
		private = {
			areaIdToUiMapId = "return { [12] = 1429, [555] = 0, [1581] = 2000 }",
			areaIdToUiMapIdOverride = { [14] = 1411 },
			subZoneToParentZone = "return { [87] = 12 }",
			subZoneToParentZoneOverride = "return {}",
			dungeons = { [1581] = { "The Deadmines", { 10029 }, 40 } },
		},
	}
	LibQuestieDB = {
		RequireContract = function(required)
			return required >= 1 and required <= 2
		end,
		Quest = {
			Get = function(questID, key)
				local quest = quests[questID]
				return quest and quest[key]
			end,
			GetAllIds = function()
				return ids
			end,
		},
		Support = {
			Get = function(name)
				return name == "ZoneDB" and zoneData or nil
			end,
		},
	}
end

-- Questie itself: its blacklist and holidays, and whether it has finished starting.
local onReady
local function FakeQuestie(ready)
	local modules = {
		QuestieCorrections = { hiddenQuests = { [8] = true, [25] = "HIDE_ON_MAP", [1] = false } },
		QuestieEvent = {
			IsEventQuest = function(questID)
				return questID == 24
			end,
		},
	}
	QuestieLoader = {
		ImportModule = function(_, name)
			modules[name] = modules[name] or {}
			return modules[name]
		end,
	}
	Questie = {
		API = {
			isReady = ready,
			RegisterOnReady = function(callback)
				onReady = callback
			end,
		},
	}
end

local invalidated = 0
local function Load()
	local ns = {
		Data = { completion = { [1429] = {}, [1411] = {} } },
		Live = {
			Invalidate = function()
				invalidated = invalidated + 1
			end,
		},
	}
	assert(loadfile("Model.lua"))("LegacyForever", ns)
	assert(loadfile("Quests.lua"))("LegacyForever", ns)
	return ns
end

local function Names(items)
	local names = {}
	for _, item in ipairs(items or {}) do
		names[#names + 1] = item.name
	end
	return table.concat(names, ", ")
end

-- Missing: no QuestieDB at all, nothing breaks and nothing is counted.
LibQuestieDB, Questie, QuestieLoader = nil, nil, nil
local ns = Load()
equal(ns.Quests.Status(), "missing", "no QuestieDB")
equal(ns.Quests.Zone(1429), nil, "no QuestieDB, no quests")

-- QuestieDB alone: ready once loaded, with no blacklist to hide quests.
FakeQuestieDB()
ns = Load()
equal(ns.Quests.Status(), "ready", "QuestieDB alone is ready")
local alone = Names(ns.Quests.Zone(1429))
equal(alone:find("Removed", 1, true) ~= nil, true, "without Questie nothing is blacklisted")
equal(alone:find("Holiday", 1, true) ~= nil, true, "or known as a holiday's")

-- Loading: Questie is present but hasn't finished starting, so its blacklist isn't there yet.
FakeQuestie(false)
ns = Load()
equal(ns.Quests.Status(), "loading", "Questie still starting")
equal(ns.Quests.Zone(1429), false, "quests are pending until Questie is ready")
equal(type(onReady), "function", "waits for Questie to be ready")

-- Ready: the index is built on first use, with Questie's blacklist.
Questie.API.isReady = true
onReady()
equal(invalidated, 1, "Questie becoming ready redraws the map")
equal(ns.Quests.Status(), "ready", "Questie ready")
local elwynn = ns.Quests.Zone(1429)
equal(
	Names(elwynn),
	"After A or B, After wolves, Breadcrumb, Either A, Map only, Paladin, Subzone, Wolves",
	"Elwynn's quests for a Human Paladin"
)
equal(Names(ns.Quests.Zone(1411)), "Alliance, Durotar", "another zone's quests, through an override")
equal(#ns.Quests.Zone(1433), 0, "a zone with no quests")

local byName = {}
for _, item in ipairs(elwynn) do
	byName[item.name] = item
end
equal(#byName["Either A"].ids, 4, "an exclusive pair is one item listing both quests (and each partner)")
equal(byName["Breadcrumb"].ids[2], 21, "a breadcrumb is done once its target quest is")

-- Every completion surface reads Model.ZoneCompletion: the map corner and tracker percent, the
-- tooltip's category rows, the continent badges' zone counts and the zone-complete toast.
local snapshot = {
	explored = { ["0:0:10:10"] = true },
	taxis = {},
	faction = "Alliance",
	refsDone = function() end,
	reaction = function()
		return 0
	end,
	quests = function()
		return ns.Quests.Zone(1429)
	end,
	completed = { [7] = true, [21] = true },
}
local zone = { areas = { { key = "0:0:10:10", name = "Goldshire" } } }
local completion = ns.Model.ZoneCompletion(zone, snapshot)
equal(completion.quests.total, 8, "eight quests to take")
equal(completion.quests.done, 2, "the exclusive pair and the breadcrumb done")
equal(completion.quests.left[1], "After A or B", "quests still to do are named")
equal(completion.total, 9, "quests count in the zone total")
equal(completion.done, 3, "and in what's done")
equal(completion.percent, 33, "and in the percent")
equal(completion.complete, false, "so the zone isn't complete while quests are left")
local off = ns.Model.ZoneCompletion(zone, snapshot, function(key)
	return key ~= "quests"
end)
equal(off.quests, nil, "an uncounted Quests category is left out")
equal(off.percent, 100, "and the rest of the zone completes without it")
equal(
	ns.Model.ContinentCompletion({ completion, off }).complete,
	1,
	"a continent counts a zone with quests left as incomplete"
)

local allDone = {}
for _, item in ipairs(elwynn) do
	allDone[item.ids[1]] = true
end
snapshot.completed = allDone
equal(ns.Model.ZoneCompletion(zone, snapshot).percent, 100, "every quest turned in completes the zone")

snapshot.completed = nil
local unread = ns.Model.ZoneCompletion(zone, snapshot)
equal(unread.quests.pending, 8, "pending until the quest log is read")
equal(unread.complete, false, "and the zone isn't complete meanwhile")

snapshot.completed = allDone
snapshot.quests = function()
	return false
end
local loading = ns.Model.ZoneCompletion(zone, snapshot)
equal(loading.quests.pending, 1, "a zone waiting on Questie has its quests pending")
equal(loading.complete, false, "so it can't complete (or toast) before the quests are known")
snapshot.quests = function() end
equal(ns.Model.ZoneCompletion(zone, snapshot).quests, nil, "no category without QuestieDB")

-- Another character: an Orc Warrior sees the other side's and class's quests.
race, class, faction = ORC, WARRIOR, "Horde"
ns = Load()
equal(
	Names(ns.Quests.Zone(1429)),
	"After A or B, After orcs, After wolves, Breadcrumb, Either A, Map only, Orcs only, Subzone, Warrior, Wolves",
	"Elwynn's quests for an Orc Warrior"
)
equal(Names(ns.Quests.Zone(1411)), "Durotar", "the Alliance's quest left out")

-- Skyborne races have their own bits, and join their faction's whole-faction quests.
race, faction = 95, "Alliance"
ns = Load()
equal(Names(ns.Quests.Zone(1411)), "Alliance, Durotar, Skyborne", "a High Order Skyborne's quests")
race, class, faction = HUMAN, PALADIN, "Alliance"

-- A prerequisite behind an exclusive choice isn't certain, but one either side of the choice is.
quests[6].exclusiveTo, quests[7].exclusiveTo = nil, nil
quests[7].name = nil
ns = Load()
equal(Names(ns.Quests.Zone(1429)):find("After A,", 1, true) ~= nil, true, "a prerequisite with no rival counts")
quests[6].exclusiveTo, quests[7].exclusiveTo, quests[7].name = { 7 }, { 6 }, "Either B"
equal(Names(Load().Quests.Zone(1429)):find("After A,", 1, true), nil, "a quest after one side of a choice doesn't")

-- Questie present but another version: its policy is skipped, QuestieDB still counts.
QuestieLoader = { ImportModule = function() end }
ns = Load()
equal(Names(ns.Quests.Zone(1429)):find("Removed", 1, true) ~= nil, true, "an unreadable Questie is ignored")

-- Unsupported: a QuestieDB contract or shape this wasn't written for.
FakeQuestie(true)
LibQuestieDB.RequireContract = function(required)
	return required >= 3, "too old"
end
ns = Load()
equal(ns.Quests.Status(), "unsupported", "another QuestieDB contract")
equal(ns.Quests.Zone(1429), nil, "no quests from an unsupported QuestieDB")
FakeQuestieDB()
LibQuestieDB.Quest.GetAllIds = nil
equal(Load().Quests.Status(), "unsupported", "a missing QuestieDB function")

-- Data that fails partway: the category turns off and says why.
FakeQuestieDB()
zoneData.private.areaIdToUiMapId = "return {"
ns = Load()
equal(ns.Quests.Zone(1429), nil, "unreadable zone data leaves no quests")
equal(ns.Quests.Status(), "unsupported", "and marks QuestieDB unsupported")
equal(ns.Quests.Failure() ~= nil, true, "the error is kept for the audit")
FakeQuestieDB()
LibQuestieDB.Quest.Get = function()
	error("bad data")
end
ns = Load()
equal(ns.Quests.Zone(1429), nil, "a QuestieDB error leaves no quests")
equal(ns.Quests.Failure():find("bad data", 1, true) ~= nil, true, "with its message")
onReady()
equal(ns.Quests.Zone(1429), nil, "a failed index isn't retried")

print("quests_spec: " .. checks .. " checks passed")

-- Run from the repository root: luajit tests/api_spec.lua
-- LegacyForever.API over the real Model, Quests, Completion and Navigate, with the game's progress faked.
local checks = 0
local function check(condition, label)
	checks = checks + 1
	assert(condition, label)
end

-- Map 100 has two areas, a dungeon wing and five located criteria; 200 has nothing to count.
local data = {
	build = "test",
	rewards = { [10] = true, [20] = true, [30] = true },
	feeds = {},
	zones = {
		[100] = {
			{ achievement = 10, criteria = 1, kind = "explore", x = 0.1, y = 0.2 },
			{ achievement = 10, criteria = 2, kind = "explore", x = 0.3, y = 0.4 },
			{ achievement = 20, criteria = 5, kind = "kill" },
			{ achievement = 10, criteria = 3, kind = "explore", x = 0.5, y = 0.5 },
			{ achievement = 30, criteria = 7, kind = "quest", x = 0.6, y = 0.6 },
		},
	},
	completion = {
		[100] = {
			areas = { { name = "North", key = "0:0:1:1" }, { name = "South", key = "0:1:1:1" } },
			taxis = {},
			dungeons = { { name = "Wing", refs = { { 900, 1 } } } },
			raids = {},
			legacy = {},
			reputations = {},
		},
		[200] = { areas = {}, taxis = {}, dungeons = {}, raids = {}, legacy = {}, reputations = {} },
	},
}

-- Live progress: achievement 30 is finished, so not visible; criterion 3 is unknown to the game.
local visible = { [10] = true, [20] = true }
local criteria = {
	[10] = {
		[1] = { text = "Explore North", completed = false, index = 1 },
		[2] = { text = "Explore South", completed = true, index = 2 },
	},
	[20] = { [5] = { text = "Slay ogres", completed = false, quantity = 3, required = 10, index = 1 } },
}
local wingDone -- nil: the game hasn't said
local settings = {}
local timers, errors, printed, waypoints, journeys = {}, {}, {}, {}, {}

local ns = { Data = data }
local live = {}
ns.Live = {
	Visible = function()
		return visible
	end,
	Criteria = function(achievementID)
		return criteria[achievementID]
	end,
	ZoneSnapshot = function(uiMapID)
		return {
			explored = { ["0:0:1:1"] = true },
			taxis = {},
			faction = "Alliance",
			refsDone = function()
				return wingDone
			end,
			reaction = function()
				return 0
			end,
			quests = function()
				return ns.Quests.Zone(uiMapID)
			end,
			completed = { [501] = true },
		}
	end,
	OnChange = function(callback)
		live[#live + 1] = callback
	end,
	-- The real one debounces; the listeners run straight away here.
	Invalidate = function()
		for _, callback in ipairs(live) do
			callback()
		end
	end,
}
function ns.SavedTable(key)
	assert(key == "zoneCompletion")
	return settings
end
function ns.Print(msg)
	printed[#printed + 1] = msg
end
ns.Tracker = {
	AddModule = function()
		return nil
	end,
}

-- The client.
C_Timer = {
	After = function(_, callback)
		timers[#timers + 1] = callback
	end,
}
local function RunTimers()
	local due = timers
	timers = {}
	for _, callback in ipairs(due) do
		callback()
	end
end
local faction = "Alliance"
UnitFactionGroup = function()
	return faction
end
UnitRace = function()
	return "Human", "Human", 1
end
UnitClass = function()
	return "Paladin", "PALADIN", 2
end
local inCombat = false
InCombatLockdown = function()
	return inCombat
end
geterrorhandler = function()
	return function(message)
		errors[#errors + 1] = message
	end
end
GetTime = function()
	return 0
end
CreateAtlasMarkup = function()
	return ""
end
EventUtil = { ContinueOnAddOnLoaded = function() end }
AlertFrame = {
	AddQueuedAlertFrameSubSystem = function()
		return { AddAlert = function() end }
	end,
}
local canSet = true
C_Map = {
	GetMapInfo = function(uiMapID)
		return uiMapID == 100 and { name = "Elwynn Forest" } or nil
	end,
	CanSetUserWaypointOnMap = function()
		return canSet
	end,
	SetUserWaypoint = function(point)
		waypoints[#waypoints + 1] = point
	end,
}
C_SuperTrack = { SetSuperTrackedUserWaypoint = function() end }
UiMapPoint = {
	CreateFromCoordinates = function(map, x, y)
		return { uiMapID = map, x = x, y = y }
	end,
}

-- QuestieDB, installed later: quest 501 (turned in) and 502 start in area 12, which is map 100.
local scans = 0
local function InstallQuestieDB()
	local quests = {
		[501] = { name = "Wolves", zoneOrSort = 12, startedBy = { { 5 } } },
		[502] = { name = "Bears", zoneOrSort = 12, startedBy = { { 5 } } },
	}
	LibQuestieDB = {
		RequireContract = function()
			return true
		end,
		Quest = {
			Get = function(questID, key)
				return quests[questID] and quests[questID][key]
			end,
			GetAllIds = function()
				scans = scans + 1
				return { 501, 502 }
			end,
		},
		Support = {
			Get = function()
				return {
					private = {
						areaIdToUiMapId = { [12] = 100 },
						subZoneToParentZone = {},
						dungeons = {},
					},
				}
			end,
		},
	}
end

for _, file in ipairs({ "Model.lua", "Quests.lua", "Navigate.lua", "Completion.lua", "API.lua" }) do
	assert(loadfile(file))("LegacyForever", ns)
end
local API = LegacyForever.API
check(API.version == 1, "version 1")

local function Category(summary, key)
	for _, category in ipairs(summary.categories) do
		if category.key == key then
			return category
		end
	end
end

-- The zone summary: one area of two, the wing's state unknown, so pending and outside the total.
local summary = assert(API.ZoneSummary(100))
check(summary.map == 100 and summary.name == "Elwynn Forest", "the summary names its map")
check(summary.done == 1 and summary.total == 2 and summary.pending == 1, "a pending wing stays outside the total")
check(not summary.complete and summary.questsStatus == "disabled", "incomplete, quests not counted by default")
local areas, dungeons = Category(summary, "areas"), Category(summary, "dungeons")
check(areas.scope == "character" and areas.done == 1 and areas.total == 2, "areas are this character's")
check(dungeons.scope == "account" and dungeons.total == 0 and dungeons.pending == 1, "a wing is account-wide")
check(not dungeons.complete, "an all-pending category never claims complete")
check(not Category(summary, "taxis") and not Category(summary, "quests"), "empty and uncounted categories are left out")

-- Fresh copies: changing a result changes nothing the next call returns.
summary.categories[1].done, summary.done, summary.categories = 99, 99, nil
local again = assert(API.ZoneSummary(100))
check(again.done == 1 and Category(again, "areas").done == 1, "a summary is a detached copy")

-- Errors: bad input, no data, the player not known yet.
check(select(2, API.ZoneSummary("100")) == "invalid", "a string map is invalid")
check(select(2, API.ZoneSummary(100.5)) == "invalid", "a fractional map is invalid")
check(select(2, API.ZoneSummary(0 / 0)) == "invalid", "NaN is invalid")
check(select(2, API.ZoneSummary(999)) == "unsupported", "a map without data is unsupported")
faction = nil
check(select(2, API.ZoneSummary(100)) == "loading", "no faction yet is loading")
faction = "Alliance"

-- What counts: areas off leaves them out; with nothing counted, nothing is complete.
settings.count_areas = false
summary = assert(API.ZoneSummary(100))
check(not Category(summary, "areas") and summary.total == 0, "an uncounted category is left out")
wingDone = true
summary = assert(API.ZoneSummary(100))
check(summary.complete and Category(summary, "dungeons").complete, "the counted wing done is complete")
settings.count_dungeons = false
summary = assert(API.ZoneSummary(100))
check(#summary.categories == 0 and not summary.complete, "an all-disabled summary is never complete")
local empty = assert(API.ZoneSummary(200))
check(#empty.categories == 0 and empty.total == 0 and not empty.complete, "an empty zone is never complete")
settings.count_areas, settings.count_dungeons, wingDone = nil, nil, nil

-- Quests: counted without QuestieDB is missing; a cold QuestieDB reads as loading without scanning.
settings.count_quests = true
summary = assert(API.ZoneSummary(100))
check(summary.questsStatus == "missing" and not Category(summary, "quests"), "no QuestieDB, no quests")
InstallQuestieDB()
local fired = 0
local unsubscribe = API.Subscribe(function()
	fired = fired + 1
end)
summary = assert(API.ZoneSummary(100))
local quests = Category(summary, "quests")
check(summary.questsStatus == "loading" and scans == 0, "a cold QuestieDB is loading, with no scan in the read")
check(quests and quests.total == 0 and quests.pending == 1 and not quests.complete, "loading quests are pending")
API.ZoneSummary(100)
check(#timers == 1, "one build is scheduled however often the API reads")
RunTimers()
check(scans == 1 and fired == 1, "the build runs on the next frame and notifies subscribers")
summary = assert(API.ZoneSummary(100))
quests = Category(summary, "quests")
check(summary.questsStatus == "ready", "quests are ready once built")
check(quests.scope == "character" and quests.done == 1 and quests.total == 2, "quests count this character's")
-- A synchronous reader (the map, a reward check) building the index first still leaves the waiter notified.
local scansBefore = scans
assert(loadfile("Quests.lua"))("LegacyForever", ns)
check(assert(API.ZoneSummary(100)).questsStatus == "loading" and #timers == 1, "a fresh index is cold again")
ns.Quests.Zone(100)
check(scans == scansBefore + 1 and assert(API.ZoneSummary(100)).questsStatus == "ready", "another reader built it")
RunTimers()
check(fired == 2 and scans == scansBefore + 1, "the waiter still hears, and nothing is scanned twice")
settings.count_quests = nil

-- Subscribe: a settings change notifies; an erroring subscriber doesn't stop the rest; unsubscribe stops it.
local toggles = {}
local root = {}
function root.CreateTitle() end
function root.CreateButton()
	return root
end
function root.CreateCheckbox(_, _, _, toggle, key)
	toggles[key] = toggle
	return { SetEnabled = function() end, SetTooltip = function() end }
end
ns.Completion.AddMenu(root)
local unsubscribeFailing = API.Subscribe(function()
	error("subscriber bug")
end)
toggles.areas("areas")
check(settings.count_areas == false and fired == 3 and #errors == 1, "a settings change notifies every subscriber")
unsubscribe()
unsubscribe()
unsubscribeFailing()
ns.Live.Invalidate()
toggles.areas("areas")
check(fired == 3 and #errors == 1, "unsubscribing, even twice, stops the callbacks")
check(not pcall(API.Subscribe, "nope"), "a non-function subscriber is refused")

-- Targets: unfinished, known to the game and visible only; done, unknown and finished challenges are left out.
local targets = assert(API.Targets(100, 5))
check(#targets == 2, "two unfinished objectives")
check(targets[1].text == "Explore North" and targets[1].kind == "explore", "in the data's order")
check(targets[1].achievementID == 10 and targets[1].criteriaID == 1, "a target names its criterion")
check(targets[1].place.map == 100 and targets[1].place.x == 0.1 and targets[1].place.y == 0.2, "a located place")
check(targets[1].quantity == nil, "a one-step criterion has no quantity")
check(targets[2].place == nil, "no place without coordinates")
check(targets[2].quantity == 3 and targets[2].required == 10, "counted progress")
check(assert(API.Targets(100, 5))[1].key == targets[1].key, "keys are stable across calls")
targets[1].place.x, targets[1].text = 9, "changed"
check(assert(API.Targets(100, 5))[1].place.x == 0.1 and data.zones[100][1].x == 0.1, "targets are detached copies")
check(#assert(API.Targets(100, 0)) == 1 and #assert(API.Targets(100, 1.7)) == 1, "the limit is clamped up to 1")
check(#assert(API.Targets(100, 99)) == 2, "the limit is clamped to 5")
check(#assert(API.Targets(200, 5)) == 0, "a zone with nothing unfinished known is empty")
check(select(2, API.Targets(999, 5)) == "unsupported", "a map without data is unsupported")
check(select(2, API.Targets(100, "5")) == "invalid", "a string limit is invalid")

-- Navigate: re-validated, and only a journey or waypoint is success.
check(API.Navigate(100, targets[1].key) == true, "a current key navigates")
check(#waypoints == 1 and waypoints[1].x == 0.1 and waypoints[1].y == 0.2, "through the native waypoint")
local ok, reason = API.Navigate(100, targets[2].key)
check(not ok and reason == "unlocated" and #waypoints == 1, "no coordinates, no waypoint")
ok, reason = API.Navigate(100, "nonsense")
check(not ok and reason == "invalid", "a malformed key is invalid")
ok, reason = API.Navigate(999, targets[1].key)
check(not ok and reason == "invalid", "a map without data is invalid")
canSet = false
ok, reason = API.Navigate(100, targets[1].key)
check(not ok and reason == "unavailable", "a map without waypoints is unavailable")
ShortestPathForever = {
	API = {
		version = 1,
		Navigate = function(...)
			journeys[#journeys + 1] = { ... }
			return false
		end,
	},
}
inCombat = true
ok, reason = API.Navigate(100, targets[1].key)
check(not ok and reason == "combat" and #journeys == 1, "Shortest Path declining in combat is combat")
check(#printed == 0, "chat is never the result")
ShortestPathForever, canSet, inCombat = nil, true, false
criteria[10][1].completed = true
ok, reason = API.Navigate(100, targets[1].key)
check(not ok and reason == "stale" and #waypoints == 1, "a finished objective's key is stale")

print(("api_spec: %d checks passed"):format(checks))

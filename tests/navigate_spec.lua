-- Run from the repository root: luajit tests/navigate_spec.lua
local printed, waypoints, superTracked, journeys = {}, {}, {}, {}
local ns = {}
function ns.Print(msg)
	printed[#printed + 1] = msg
end

-- Shortest Path Forever's install state as the addon list reports it ("on", "off" or "missing"), and the saved
-- table the shared family suggestions (ForeverCore.Family) read.
local state = "missing"
C_AddOns = {
	IsAddOnLoaded = function(name)
		return name == "ShortestPathForever" and state == "on"
	end,
	DoesAddOnExist = function(name)
		return name ~= "ShortestPathForever" or state ~= "missing"
	end,
}
local db = {}
ns.FamilyDB = function()
	return db
end

-- The player's place on the map the map canvas is showing, for the outline's route estimates.
local playerMap, playerPosition = 1440, { 0.1, 0.2 }
local canSet = true
C_Map = {
	CanSetUserWaypointOnMap = function()
		return canSet
	end,
	SetUserWaypoint = function(point)
		waypoints[#waypoints + 1] = point
	end,
	GetMapInfo = function()
		return { name = "Ashenvale" }
	end,
	GetBestMapForUnit = function()
		return playerMap
	end,
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

-- Live progress and the discovery notice the outline journey listens to.
local explored, liveListeners = {}, {}
ns.Live = {
	OnChange = function(callback)
		liveListeners[#liveListeners + 1] = callback
	end,
	ZoneSnapshot = function()
		return { explored = explored }
	end,
}
local function Discover()
	for _, callback in ipairs(liveListeners) do
		callback()
	end
end
C_SuperTrack = {
	SetSuperTrackedUserWaypoint = function(on)
		superTracked[#superTracked + 1] = on
	end,
}
InCombatLockdown = function()
	return false
end
UiMapPoint = {
	CreateFromCoordinates = function(map, x, y)
		return { uiMapID = map, x = x, y = y }
	end,
}

local accepts = true
local estimates, estimateCalls = {}, {}
local stop, cancelled = false, {}
local function Install()
	ShortestPathForever = {
		API = {
			version = 1,
			Navigate = function(owner, map, x, y, title)
				journeys[#journeys + 1] = { owner = owner, map = map, x = x, y = y, title = title }
				return accepts
			end,
			Estimate = function(fromMap, fromX, fromY, toMap, toX, toY)
				estimateCalls[#estimateCalls + 1] = { fromMap, fromX, fromY, toMap, toX, toY }
				return estimates[toX .. ":" .. toY]
			end,
			CurrentStop = function()
				return stop and 1 or nil
			end,
			Cancel = function(owner)
				cancelled[#cancelled + 1] = owner
				return true
			end,
		},
	}
end

assert(loadfile("Locales/enUS.lua"))("LegacyForever", ns)
local coreEnv = setmetatable({
	CreateFrame = function()
		return { RegisterEvent = function() end, SetScript = function() end }
	end,
}, { __index = _G })
local core = dofile("tests/forever_core.lua")
ForeverCore = core.install(coreEnv, {
	"Core/SafeCall.lua",
	"Core/Log.lua",
	"UI/Report.lua",
	"UI/Credits.lua",
	"UI/ForeverFamily.lua",
	"UI/MapCanvas.lua",
	"Expose.lua",
})
assert(loadfile("Integrations/Navigate.lua"))("LegacyForever", ns)
local checks = 0
local function check(condition, label)
	checks = checks + 1
	assert(condition, label)
end

-- Shortest Path present and accepting: it alone guides.
Install()
check(ns.NavigateHint():find("Shortest Path Forever", 1, true), "the hint names Shortest Path when it is loaded")
check(ns.Navigate(1440, 0.25, 0.5, "Blackfathom Deeps"), "a guided click answers true")
local journey = journeys[1]
check(journey and journey.owner == "LegacyForever" and journey.map == 1440, "the journey is ours, on the pin's map")
check(journey.x == 0.25 and journey.y == 0.5 and journey.title == "Blackfathom Deeps", "the journey keeps the pin")
check(#waypoints == 0 and #printed == 0, "an accepted journey sets no native waypoint")

-- Shortest Path present but declining (combat, journeys off): the native waypoint instead.
accepts = false
ns.Navigate(1440, 0.25, 0.5, "Blackfathom Deeps")
check(#journeys == 2, "Shortest Path is asked first")
check(#waypoints == 1 and waypoints[1].uiMapID == 1440 and waypoints[1].x == 0.25, "a decline falls back")
check(superTracked[1] == true, "the fallback waypoint is super-tracked")

-- Shortest Path absent, or a different major version: the native waypoint.
ShortestPathForever = nil
check(ns.NavigateHint() == "Click to set a waypoint here.", "the hint names the waypoint without Shortest Path")
ns.Navigate(1440, 0.25, 0.5, "Blackfathom Deeps")
check(#waypoints == 2 and #journeys == 2, "no Shortest Path sets the native waypoint")
Install()
ShortestPathForever.API.version = 2
check(ns.NavigateHint() == "Click to travel here with Shortest Path Forever.", "API v2 retains navigation")
ShortestPathForever.API.version = 3
ns.Navigate(1440, 0.25, 0.5, "Blackfathom Deeps")
check(#journeys == 2 and #waypoints == 3, "an unknown API version is treated as absent")
ShortestPathForever = { API = { version = 1 } }
check(ns.NavigateHint() == "Click to set a waypoint here.", "an API without Navigate is not named in the hint")
ns.Navigate(1440, 0.25, 0.5, "Blackfathom Deeps")
check(#waypoints == 4, "an API without Navigate falls back to the native waypoint")
ShortestPathForever = {}
ns.Navigate(1440, 0.25, 0.5, "Blackfathom Deeps")
check(#waypoints == 5, "Shortest Path loaded without its API falls back to the native waypoint")

-- A map that takes no waypoint: the place in chat, never nothing.
ShortestPathForever, canSet = nil, false
ns.Navigate(1440, 0.25, 0.5, "Blackfathom Deeps")
check(#waypoints == 5 and printed[1] == "Blackfathom Deeps is at 25.0, 50.0 in Ashenvale.", "the place goes to chat")
-- The companion hint, behind the shared family switch: install while missing, nothing once installed (on or
-- turned off: the player chose that), switched off or dismissed.
local INSTALL = "Install Shortest Path Forever to have the route plotted for you."
check(ns.CompanionHint() == INSTALL, "missing: install, on by default")
state = "off"
check(ns.CompanionHint() == nil, "installed but turned off: nothing")
state = "on"
check(ns.CompanionHint() == nil, "on: nothing")
state = "missing"
db.suggestFamily = false
check(ns.CompanionHint() == nil, "switched off: nothing")
db.suggestFamily = true
db.familyDismissed = { ["LegacyForever.pinShortestPath"] = true }
check(ns.CompanionHint() == nil, "dismissed: nothing")
db.familyDismissed = { ["LegacyForever.zoneAdventureGuide"] = true }
check(ns.CompanionHint() == INSTALL, "another dismissed suggestion leaves this one")

-- An outlined area's click: Shortest Path estimates every vertex of its ground and heads for the quickest
-- route, not the nearest point.
Install()
accepts = true
local area = { key = "area", name = "Tower of Althalaxx", outline = true, rings = { { 0.2, 0.3, 0.8, 0.7 } } }
estimates = { ["0.2:0.3"] = 30, ["0.8:0.7"] = 12 }
ns.NavigateOutline(1439, area, 0.2, 0.3)
local route = journeys[#journeys]
check(route.map == 1439 and route.x == 0.8 and route.y == 0.7, "the quickest outline vertex is the destination")
check(
	route.title == "Tower of Althalaxx" and route.owner == "LegacyForever",
	"the journey is ours, named after the area"
)
check(#estimateCalls == 2, "every outline vertex is estimated")
check(
	estimateCalls[1][1] == 1440
		and estimateCalls[1][2] == 0.1
		and estimateCalls[1][3] == 0.2
		and estimateCalls[1][4] == 1439,
	"an estimate starts where the player is and ends on the area's map"
)

-- Without an estimate for any vertex (or without Shortest Path's Estimate at all), the nearest vertex is
-- the destination, as the pin shows it.
estimates = {}
ns.NavigateOutline(1439, area, 0.2, 0.3)
route = journeys[#journeys]
check(route.x == 0.2 and route.y == 0.3, "no estimate leaves the pin's own vertex")
ShortestPathForever = { API = { version = 1, Navigate = ShortestPathForever.API.Navigate } }
ns.NavigateOutline(1439, area, 0.2, 0.3)
route = journeys[#journeys]
check(route.x == 0.2 and route.y == 0.3, "an API without Estimate leaves the pin's own vertex")

-- A player on another map (no position) also keeps the pin's vertex.
Install()
playerPosition = nil
local before = #estimateCalls
ns.NavigateOutline(1439, area, 0.2, 0.3)
check(journeys[#journeys].x == 0.2 and #estimateCalls == before, "no player position keeps the pin's vertex")
playerPosition = { 0.1, 0.2 }

-- When the area is discovered, our own journey ends.
stop = true
estimates = {}
ns.NavigateOutline(1439, area, 0.2, 0.3)
explored = { [area.key] = true }
Discover()
check(#cancelled == 1 and cancelled[1] == "LegacyForever", "discovering the area cancels our journey")

-- A journey another Legacy pin starts replaces ours: discovering the outlined area leaves the dungeon's
-- journey alone, even though Shortest Path still has a stop of ours.
explored = {}
ns.NavigateOutline(1439, area, 0.2, 0.3)
check(ns.Navigate(1440, 0.25, 0.5, "Blackfathom Deeps"), "the dungeon pin's journey starts")
explored = { [area.key] = true }
Discover()
check(#cancelled == 1, "a dungeon journey started after an outline click is not cancelled by that area")

-- A click the client cannot guide leaves nothing to cancel.
accepts, canSet = false, false
explored = {}
ns.NavigateOutline(1439, area, 0.2, 0.3)
explored = { [area.key] = true }
Discover()
check(#cancelled == 1, "a click that only names the place leaves nothing to cancel")
accepts, canSet = true, true

-- A discovered area with no journey of ours left is quiet.
stop = false
explored = {}
ns.NavigateOutline(1439, area, 0.2, 0.3)
explored = { [area.key] = true }
Discover()
check(#cancelled == 1, "no journey to cancel leaves us quiet")
print(("navigate_spec: %d checks passed"):format(checks))

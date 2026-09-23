-- Run from the repository root: luajit tests/navigate_spec.lua
local printed, waypoints, superTracked, journeys = {}, {}, {}, {}
local ns = {}
function ns.Print(msg)
	printed[#printed + 1] = msg
end

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
}
C_SuperTrack = {
	SetSuperTrackedUserWaypoint = function(on)
		superTracked[#superTracked + 1] = on
	end,
}
UiMapPoint = {
	CreateFromCoordinates = function(map, x, y)
		return { uiMapID = map, x = x, y = y }
	end,
}

local accepts = true
local function Install()
	ShortestPathForever = {
		API = {
			version = 1,
			Navigate = function(owner, map, x, y, title)
				journeys[#journeys + 1] = { owner = owner, map = map, x = x, y = y, title = title }
				return accepts
			end,
		},
	}
end

assert(loadfile("Navigate.lua"))("LegacyForever", ns)
local checks = 0
local function check(condition, label)
	checks = checks + 1
	assert(condition, label)
end

-- Shortest Path present and accepting: it alone guides.
Install()
check(ns.NavigateHint():find("Shortest Path Forever", 1, true), "the hint names Shortest Path when it is loaded")
ns.Navigate(1440, 0.25, 0.5, "Blackfathom Deeps")
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
print(("navigate_spec: %d checks passed"):format(checks))

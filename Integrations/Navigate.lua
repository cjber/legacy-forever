---@type string, LegacyForeverNamespace
local _, ns = ...
local L = ns.L

if ns.broken then
	return
end

-- Passed to Shortest Path Forever so it can tell our journeys apart from the player's own.
local OWNER = "LegacyForever"

-- The area an outlined area's journey was started for, so the guidance ends when that area is discovered,
-- whichever side the player walks in from. Every other journey of ours replaces it (ns.Navigate).
---@type { uiMapID: number, key: string }?
local pending

-- The API itself, checked version first; each caller below feature-detects the one member it uses, so a
-- newer Shortest Path that keeps version 1 still counts for what it has.
---@return LegacyShortestPathAPI?
local function Api()
	local addon = ShortestPathForever
	local api = type(addon) == "table" and addon.API
	if type(api) == "table" and api.version == 1 then
		return api
	end
end

-- Only the one function called is checked, so a newer Shortest Path that keeps version 1 still counts.
---@return (fun(owner: string, map: integer, x: number, y: number, title?: string): boolean)?
local function ShortestPath()
	local api = Api()
	return api and type(api.Navigate) == "function" and api.Navigate or nil
end

-- The addon folder the TOC's OptionalDeps names.
local SHORTEST_PATH = "ShortestPathForever"

-- A grey suggestion under a pin's click hint: Shortest Path Forever plots the whole route, flights and boats
-- included, where the game's waypoint is a straight line. Only while it isn't installed and the shared
-- "Suggest my other Forever addons" switch is on (ForeverCore's family page); one installed but turned off was the
-- player's choice.
---@return string?
function ns.CompanionHint()
	if ForeverCore.Family.Hint(ns.FamilyDB(), "LegacyForever.pinShortestPath", SHORTEST_PATH) then
		return L["Install Shortest Path Forever to have the route plotted for you."]
	end
	return nil
end

-- Names what a click tries first; Navigate still falls back when Shortest Path declines.
---@return string
function ns.NavigateHint()
	return ShortestPath() and L["Click to travel here with Shortest Path Forever."]
		or L["Click to set a waypoint here."]
end

-- Shortest Path's journey when it takes one (it declines in combat, with journeys switched off or with no player
-- position), else the game's own waypoint. False, with why, when neither takes the place.
---@param uiMapID number
---@param x number
---@param y number
---@param title string
---@return boolean
---@return "combat"|"unavailable"|nil
function ns.Guide(uiMapID, x, y, title)
	local navigate = ShortestPath()
	if navigate and navigate(OWNER, uiMapID, x, y, title) then
		return true
	end
	if C_Map.CanSetUserWaypointOnMap(uiMapID) then
		C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(uiMapID, x, y))
		C_SuperTrack.SetSuperTrackedUserWaypoint(true)
		return true
	end
	return false, navigate and InCombatLockdown() and "combat" or "unavailable"
end

-- A journey or waypoint, else the place in chat, so a click always leaves the player a pointer. True when it
-- guided the player; any journey started here replaces the area an outlined one was watching.
---@param uiMapID number
---@param x number
---@param y number
---@param title string
---@return boolean guided
function ns.Navigate(uiMapID, x, y, title)
	pending = nil
	if ns.Guide(uiMapID, x, y, title) then
		return true
	end
	local info = C_Map.GetMapInfo(uiMapID)
	local place = ("%.1f, %.1f"):format(x * 100, y * 100)
	if info then
		ns.Print(L["%s is at %s in %s."]:format(title, place, info.name))
	else
		ns.Print(L["%s is at %s."]:format(title, place))
	end
	return false
end

-- The outline point a journey should head for: with Shortest Path installed, the vertex whose whole route
-- (flights, boats and walking) is quickest; otherwise the nearest one, which the pin already stands on.
---@param uiMapID number
---@param rings number[][]
---@param x number
---@param y number
---@return number x
---@return number y
local function OutlineStop(uiMapID, rings, x, y)
	local api = Api()
	local estimate = api and api.Estimate
	if type(estimate) ~= "function" then
		return x, y
	end
	local from = C_Map.GetBestMapForUnit("player")
	if not from then
		return x, y
	end
	local position = C_Map.GetPlayerMapPosition(from, "player")
	local px, py
	if position then
		px, py = position:GetXY()
	end
	if not px or not py then
		return x, y
	end
	local shortest, bestX, bestY
	for _, ring in ipairs(rings) do
		for index = 1, #ring, 2 do
			local seconds = estimate(from, px, py, uiMapID, ring[index], ring[index + 1])
			if seconds and (not shortest or seconds < shortest) then
				shortest, bestX, bestY = seconds, ring[index], ring[index + 1]
			end
		end
	end
	if bestX then
		return bestX, bestY
	end
	return x, y
end

-- Discovery is progress: when the area an outlined journey was started for is discovered, and Shortest Path
-- still has a stop of ours, cancel it. A journey another pin started cleared `pending`, and another addon's
-- journey is never ours to stop.
local function Discovered()
	local wanted = pending
	if not wanted then
		return
	end
	if not ns.Live.ZoneSnapshot(wanted.uiMapID).explored[wanted.key] then
		return
	end
	pending = nil
	local api = Api()
	local cancel, current = api and api.Cancel, api and api.CurrentStop
	if type(cancel) ~= "function" or type(current) ~= "function" or not current(OWNER) then
		return
	end
	cancel(OWNER)
end

ns.Live.OnChange(Discovered)

-- A click on an outlined area: a journey to its quickest outline point with Shortest Path, else the way of an
-- objective pin, and its end tracked so discovery stops the guidance here.
---@param uiMapID number
---@param area LegacyOutlineArea
---@param x number
---@param y number
function ns.NavigateOutline(uiMapID, area, x, y)
	local stopX, stopY = OutlineStop(uiMapID, area.rings, x, y)
	if ns.Navigate(uiMapID, stopX, stopY, area.name) then
		pending = { uiMapID = uiMapID, key = area.key }
	end
end

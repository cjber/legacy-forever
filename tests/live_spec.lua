-- Run from the repository root: luajit tests/live_spec.lua
local ns = { Data = { completion = { [2] = { taxis = { { node = 10 } } } } } }
local records = {}
function ns.SavedTable(key)
	assert(key == "flightPaths")
	return records
end

local guid
UnitGUID = function()
	return guid
end
UnitFactionGroup = function()
	return "Alliance"
end
Enum = { UIMapType = { Continent = 2 }, FlightPathState = { Unreachable = 0 } }
C_Map = {
	GetMapInfo = function(id)
		return id == 2 and { mapID = 2, mapType = 3, parentMapID = 1 } or { mapID = 1, mapType = 2 }
	end,
	GetBestMapForUnit = function()
		return 2
	end,
}
C_MapExplorationInfo = {
	GetExploredMapTextures = function()
		return nil
	end,
}
C_TaxiMap = {
	GetAllTaxiNodes = function()
		return { { nodeID = 10, state = 1 } }
	end,
}
C_Timer = { After = function() end }
tContains = function(list, value)
	for _, item in ipairs(list) do
		if item == value then
			return true
		end
	end
	return false
end
local onEvent
CreateFrame = function()
	return {
		RegisterEvent = function() end,
		SetScript = function(_, script, callback)
			assert(script == "OnEvent")
			onEvent = callback
		end,
	}
end

assert(loadfile("Live.lua"))("LegacyForever", ns)
local snapshot = ns.Live.ZoneSnapshot(2)
assert(next(records) == nil, "no GUID must not create a flight record")
assert(snapshot.taxis[10] == nil, "flight paths remain unknown without a GUID")
onEvent(nil, "TAXIMAP_OPENED")
assert(next(records) == nil, "an early flight-master event must not persist an anonymous record")
guid = "Player-test"
ns.Live.Invalidate()
snapshot = ns.Live.ZoneSnapshot(2)
assert(records[guid] and snapshot.taxis[10] == nil, "a new character has no known continents")
onEvent(nil, "TAXIMAP_OPENED")
snapshot = ns.Live.ZoneSnapshot(2)
assert(snapshot.taxis[10] == true, "a later flight-master visit records this character's known nodes")
print("live_spec: 5 checks passed")

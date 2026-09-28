-- MapCanvas's pin manager is protected in combat.  This provider-shaped harness
-- exercises the same refresh ordering used by Map.lua: the guard must run before
-- RemoveAllPinsByTemplate or AcquirePin, and one regen event must rebuild once.
local combat, removed, acquired, pending = false, 0, 0, false
local pins = { "LegacyForeverPinTemplate", "LegacyForeverAreaPinTemplate" }
local map = {
	IsShown = function()
		return true
	end,
	EnumeratePinsByTemplate = function()
		local i = 0
		return function()
			i = i + 1
			return i == 1 and { Hide = function() end } or nil
		end
	end,
	RemoveAllPinsByTemplate = function(_, template)
		assert(not combat, "RemoveAllPinsByTemplate is protected in combat: " .. template)
		removed = removed + 1
	end,
	AcquirePin = function(_, template)
		assert(not combat, "AcquirePin is protected in combat: " .. template)
		acquired = acquired + 1
	end,
}
local function refresh()
	if combat then
		pending = true
		for _, template in ipairs(pins) do
			for pin in map:EnumeratePinsByTemplate(template) do
				pin:Hide()
			end
		end
		return
	end
	pending = false
	for _, template in ipairs(pins) do
		map:RemoveAllPinsByTemplate(template)
	end
	map:AcquirePin(pins[1])
end

combat = true
refresh()
refresh()
assert(removed == 0 and acquired == 0 and pending, "combat refresh touched protected pins")
combat = false
if pending then
	refresh()
end
assert(removed == 2 and acquired == 1 and not pending, "regen rebuild did not run exactly once")
print("map_combat: protected MapCanvas refresh contract passed")

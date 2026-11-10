---@type string, LegacyForeverNamespace
local _, ns = ...

if ns.broken then
	return
end

local MODULE = "AtlasLootClassic_DungeonsAndRaids"
local attemptedSource

-- AtlasLoot owns the recommended ranges. Read its public database at runtime, never copy its data.
---@param instance number
---@return number? minimum
---@return number? maximum
---@return string? hint
function ns.DungeonLevelRange(instance)
	local atlas = AtlasLoot
	if type(instance) ~= "number" then
		return nil
	end
	if not atlas or not atlas.ItemDB then
		return nil, nil, ns.L["Install AtlasLoot for recommended levels."]
	end
	local database = atlas.ItemDB:Get(MODULE)
	if not database and atlas.Loader and attemptedSource ~= atlas and not InCombatLockdown() then
		attemptedSource = atlas
		atlas.Loader:LoadModule(MODULE)
		database = atlas.ItemDB:Get(MODULE)
	end
	if type(database) ~= "table" then
		return nil
	end
	local minimum, maximum
	for _, content in pairs(database) do
		if type(content) == "table" and content.InstanceID == instance and type(content.LevelRange) == "table" then
			local low, high = content.LevelRange[2], content.LevelRange[3]
			if
				type(low) == "number"
				and type(high) == "number"
				and low >= 1
				and high <= 60
				and low <= high
				and low % 1 == 0
				and high % 1 == 0
			then
				minimum = minimum and math.min(minimum, low) or low
				maximum = maximum and math.max(maximum, high) or high
			end
		end
	end
	return minimum, maximum
end

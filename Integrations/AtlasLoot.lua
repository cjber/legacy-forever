---@type string, LegacyForeverNamespace
local _, ns = ...

if ns.broken then
	return
end

local MODULE = "AtlasLootClassic_DungeonsAndRaids"
-- The AtlasLoot this read asked to load the module, so a missing module is asked for once.
local attemptedSource
-- The AtlasLoot whose module load is waiting for the next frame.
local loadingSource

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
	local itemDB = type(atlas) == "table" and atlas.ItemDB or nil
	if type(itemDB) ~= "table" or type(itemDB.Get) ~= "function" then
		return nil, nil, ns.L["Install AtlasLoot for recommended levels."]
	end
	local database = itemDB:Get(MODULE)
	-- The module AtlasLoot keeps its Dungeons & Raids data in loads on demand. Ask for it after this frame,
	-- never inside it: the map's pin tooltips read this while the map is drawing.
	local loader = type(atlas) == "table" and atlas.Loader or nil
	if type(loader) ~= "table" or type(loader.LoadModule) ~= "function" then
		loader = nil
	end
	if not database and loader and attemptedSource ~= atlas and loadingSource ~= atlas and not InCombatLockdown() then
		local load = loader
		loadingSource = atlas
		C_Timer.After(0, function()
			loadingSource = nil
			-- Combat can start between the hover and this frame; the next hover asks again once it ends.
			if InCombatLockdown() then
				return
			end
			attemptedSource = atlas
			load.LoadModule(load, MODULE)
		end)
	end
	if type(database) ~= "table" then
		if loader and attemptedSource ~= atlas then
			-- The module is on its way, or combat holds it off: no line yet.
			return nil
		end
		return nil, nil, ns.L["Install AtlasLoot for recommended levels."]
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

local ns = { L = setmetatable({}, {
	__index = function(_, key)
		return key
	end,
}) }
assert(loadfile("Integrations/AtlasLoot.lua"))("LegacyForever", ns)
local combat, database, loads = false, nil, 0
InCombatLockdown = function()
	return combat
end
-- The client: a module load is scheduled for the next frame, never run in the frame that reads the range.
local timers = {}
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
local function Install(text)
	return text ~= nil and text:find("Install AtlasLoot", 1, true) ~= nil
end

local low, high, hint = ns.DungeonLevelRange(189)
assert(low == nil and high == nil and Install(hint), "without AtlasLoot, one line says what to install")

AtlasLoot = {
	ItemDB = {
		Get = function(_, module)
			assert(module == "AtlasLootClassic_DungeonsAndRaids")
			return database
		end,
	},
	Loader = {
		LoadModule = function()
			loads = loads + 1
			database = {
				wing1 = { InstanceID = 189, LevelRange = { 20, 26, 36 } },
				wing2 = { InstanceID = 189, LevelRange = { 20, 35, 45 } },
				other = { InstanceID = 33, LevelRange = { 10, 18, 26 } },
				invalid = { InstanceID = 189, LevelRange = { 1, 1, math.huge } },
			}
		end,
	},
}
combat = true
low, high, hint = ns.DungeonLevelRange(189)
assert(
	low == nil and high == nil and hint == nil and loads == 0 and #timers == 0,
	"never load a companion during combat"
)
combat = false

-- The module loads on demand: the hover that misses it asks for it after the frame, not inside it, and a
-- second hover in the same frame asks once.
low, high, hint = ns.DungeonLevelRange(189)
assert(low == nil and high == nil and hint == nil and loads == 0, "the module is not loaded while drawing")
assert(#timers == 1, "one load is scheduled for the next frame")
ns.DungeonLevelRange(189)
assert(#timers == 1, "a second hover in the same frame schedules nothing more")
RunTimers()
assert(loads == 1, "the next frame loads the module")
low, high, hint = ns.DungeonLevelRange(189)
assert(low == 26 and high == 45 and hint == nil, "combine only the matching instance's recommended ranges")
low, high, hint = ns.DungeonLevelRange(999)
assert(low == nil and high == nil and hint == nil, "unknown entrances have no invented range")

-- The module missing or disabled: AtlasLoot was asked once, so the tooltip says what to install instead of
-- leaving the player with nothing.
database = nil
low, high, hint = ns.DungeonLevelRange(189)
assert(low == nil and high == nil and loads == 1, "an unavailable module is not loaded on every hover")
assert(Install(hint), "and the line names what to install")

-- AtlasLoot without the public surface this reads: the same line, never an error.
AtlasLoot = { ItemDB = {} }
low, high, hint = ns.DungeonLevelRange(189)
assert(low == nil and high == nil and Install(hint), "an ItemDB without Get is unreadable")
AtlasLoot = { ItemDB = { Get = function() end }, Loader = {} }
low, high, hint = ns.DungeonLevelRange(189)
assert(low == nil and high == nil and Install(hint) and #timers == 0, "a Loader without LoadModule cannot load it")
print("dungeon_levels_spec: passed")

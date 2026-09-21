-- Run from the repository root: luajit tests/data_spec.lua
local ns = {}
assert(loadfile("Data/Legacy.lua"))("LegacyHere", ns)
local data = ns.Data
assert(type(data) == "table", "generated data table")
assert(type(data.build) == "string" and data.build:match("^%d+%.%d+%.%d+%.%d+$"), "build format")

local function positiveInteger(value)
	return type(value) == "number" and value > 0 and value % 1 == 0
end

local rewards = 0
for achievement, value in pairs(data.rewards) do
	assert(positiveInteger(achievement) and value == true, "reward ID/set value")
	rewards = rewards + 1
end
assert(rewards > 0, "reward set is not empty")
for achievement, targets in pairs(data.feeds) do
	assert(positiveInteger(achievement) and #targets > 0, "supporting achievement and targets")
	local previous = 0
	for _, target in ipairs(targets) do
		assert(data.rewards[target] and target > previous, "feeds target is a sorted, unique reward")
		previous = target
	end
end

local kinds = { explore = true, instance = true, kill = true, quest = true, reputation = true }
local explore = 0
local samples = {}
for zone, entries in pairs(data.zones) do
	assert(positiveInteger(zone) and #entries > 0, "zone ID and entries")
	local seen = {}
	local previous
	for _, entry in ipairs(entries) do
		assert(positiveInteger(entry.achievement) and positiveInteger(entry.criteria), "objective IDs")
		assert(data.rewards[entry.achievement] or data.feeds[entry.achievement], "objective belongs to Legacy graph")
		assert(kinds[entry.kind], "closed objective kind set")
		assert((entry.x == nil) == (entry.y == nil), "coordinates both-or-neither")
		if entry.x ~= nil then
			assert(type(entry.x) == "number" and entry.x >= 0 and entry.x <= 1, "x range")
			assert(type(entry.y) == "number" and entry.y >= 0 and entry.y <= 1, "y range")
			assert(entry.kind == "explore" or entry.kind == "instance", "only client-derived pins")
		end
		if entry.kind == "instance" then
			assert(positiveInteger(entry.instance), "instance Map ID")
		else
			assert(entry.instance == nil, "only instance entries carry Map IDs")
		end
		local key = entry.achievement .. ":" .. entry.criteria
		assert(not seen[key], "duplicate objective within zone")
		seen[key] = true
		if previous then
			assert(
				previous.kind < entry.kind
					or (
						previous.kind == entry.kind
						and (
							previous.achievement < entry.achievement
							or (previous.achievement == entry.achievement and previous.criteria < entry.criteria)
						)
					),
				"entries sorted by kind, achievement, criteria"
			)
		end
		previous = entry
		if entry.kind == "explore" then
			explore = explore + 1
		end
		samples[zone .. ":" .. key] = entry
	end
end
assert(explore >= 500, "exploration join must retain at least 500 objectives")

-- Two ID-backed geography checks: hit-rectangle centres in the matching art's
-- 1002 x 668 layer, in Mulgore and Redridge (see tools/README.md).
local bloodhoof = assert(samples["1412:736:914"], "Bloodhoof Village in Mulgore")
assert(bloodhoof.x == 0.470 and bloodhoof.y == 0.624, "Bloodhoof normalisation")
local lakeshire = assert(samples["1433:780:1185"], "Lakeshire in Redridge")
assert(lakeshire.x == 0.214 and lakeshire.y == 0.453, "Lakeshire normalisation")
-- Criteria 502 still names overlay 117; matching AreaID 800 selects current
-- overlay 5129 / art 2151 for the pin on Dun Morogh.
local remapped = samples["1426:627:502"]
assert(remapped and remapped.x == 0.349 and remapped.y == 0.681, "current-art remap retains original criteria ID")
assert(samples["1412:736:911"], "Thunder Bluff reveal region uses Mulgore art")
assert(not samples["1456:736:911"], "Mulgore pixels must not become Thunder Bluff city pins")
assert(samples["1445:684:3271"].x == 0.529, "Onyxia entrance world-to-UI projection")
assert(samples["1445:64030:117792"].y == 0.777, "Onyxia second reward variant")
assert(data.rewards[62382] and data.rewards[64015], "both Explorer variants")
assert(data.feeds[627][1] == 62382 and data.feeds[627][2] == 64015, "Dun Morogh feeds both Explorers")
print("ok")

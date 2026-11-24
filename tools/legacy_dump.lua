-- Dumps the rows of a generated data file that tools/check_refresh.py's refresh guard compares, as JSON
-- lines: one per reward, feed link, zone objective and completion entry, with only the fields the guard
-- reads. Run as:
--   luajit tools/legacy_dump.lua <data-file> <out.jsonl>
-- <data-file> is a generated Data/Legacy.lua of any build. The file runs over a bare table as ns, so it
-- needs no client. JSON is hand-rolled (LuaJIT ships no cjson) and object keys are sorted, so the same
-- data dumps byte for byte identically.
local data_file, output = ...
if not data_file or not output then
	error("usage: luajit tools/legacy_dump.lua <data-file> <out.jsonl>")
end

local escapes = {
	['"'] = '\\"',
	["\\"] = "\\\\",
	["\b"] = "\\b",
	["\f"] = "\\f",
	["\n"] = "\\n",
	["\r"] = "\\r",
	["\t"] = "\\t",
}

local function json_string(value)
	local body = value:gsub('[%c"\\]', function(char)
		return escapes[char] or ("\\u%04x"):format(char:byte())
	end)
	return '"' .. body .. '"'
end

local json

local function json_table(value)
	-- An array is a table whose keys are exactly 1..n; anything else is an object with sorted keys.
	local count = 0
	local array = true
	for key in pairs(value) do
		count = count + 1
		if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > count then
			array = false
		end
	end
	if array then
		local items = {}
		for index = 1, count do
			items[index] = json(value[index])
		end
		return "[" .. table.concat(items, ",") .. "]"
	end
	local keys = {}
	for key in pairs(value) do
		keys[#keys + 1] = key
	end
	table.sort(keys)
	local parts = {}
	for _, key in ipairs(keys) do
		parts[#parts + 1] = json_string(key) .. ":" .. json(value[key])
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

function json(value)
	local kind = type(value)
	if kind == "nil" then
		return "null"
	elseif kind == "boolean" then
		return tostring(value)
	elseif kind == "number" then
		return ("%.14g"):format(value)
	elseif kind == "string" then
		return json_string(value)
	elseif kind == "table" then
		return json_table(value)
	end
	return error("cannot serialize a " .. kind)
end

local ns = {}
assert(loadfile(data_file))(data_file, ns)
local data = assert(ns.Data, data_file .. " set no ns.Data")

local lines = {}
local counts = { feeds = 0, areas = 0, taxis = 0, wings = 0, bosses = 0, legacy = 0, reputations = 0 }

local function emit(record)
	lines[#lines + 1] = json(record)
end

-- Reward-bearing challenges and their feed links, in id order.
local rewards = {}
for id in pairs(data.rewards or {}) do
	rewards[#rewards + 1] = id
end
table.sort(rewards)
for _, id in ipairs(rewards) do
	emit({ kind = "reward", id = id })
end

local feeds = {}
for id in pairs(data.feeds or {}) do
	feeds[#feeds + 1] = id
end
table.sort(feeds)
for _, id in ipairs(feeds) do
	local targets = {}
	for index, target in ipairs(data.feeds[id] or {}) do
		targets[index] = target
	end
	table.sort(targets)
	counts.feeds = counts.feeds + 1
	emit({ kind = "feed", id = id, targets = targets })
end

-- Zone objectives, in (achievement, criteria, zone) order.
local objectives = {}
for zone, entries in pairs(data.zones or {}) do
	for _, entry in ipairs(entries) do
		objectives[#objectives + 1] = { zone = zone, entry = entry }
	end
end
table.sort(objectives, function(first, second)
	local a, b = first.entry, second.entry
	if a.achievement ~= b.achievement then
		return a.achievement < b.achievement
	end
	if a.criteria ~= b.criteria then
		return a.criteria < b.criteria
	end
	return first.zone < second.zone
end)
for _, item in ipairs(objectives) do
	local entry = item.entry
	-- A place is only where the player stands: the objective's own kind, instance and raid flag say
	-- what the pin is, and key, x and y say whether it draws.
	emit({
		kind = "objective",
		zone = item.zone,
		achievement = entry.achievement,
		criteria = entry.criteria,
		obj = entry.kind,
		instance = entry.instance,
		raid = entry.raid,
		key = entry.key,
		x = entry.x,
		y = entry.y,
	})
end

-- Zone completion, in zone order and, within it, the categories' own order.
local zones = {}
for zone in pairs(data.completion or {}) do
	zones[#zones + 1] = zone
end
table.sort(zones)

local function refs(entry)
	local list = {}
	for index, ref in ipairs(entry.refs or {}) do
		list[index] = { ref[1], ref[2] }
	end
	return list
end

for _, zone in ipairs(zones) do
	local cats = data.completion[zone]
	for _, area in ipairs(cats.areas or {}) do
		counts.areas = counts.areas + 1
		emit({
			kind = "area",
			zone = zone,
			name = area.name,
			key = area.key,
			tiles = area.tiles and #area.tiles or 0,
			achievement = area.achievement,
			criteria = area.criteria,
		})
	end
	for _, taxi in ipairs(cats.taxis or {}) do
		counts.taxis = counts.taxis + 1
		emit({ kind = "taxi", node = taxi.node, zone = zone, faction = taxi.faction, name = taxi.name })
	end
	for _, wing in ipairs(cats.dungeons or {}) do
		counts.wings = counts.wings + 1
		emit({ kind = "wing", zone = zone, name = wing.name, refs = refs(wing) })
	end
	for _, raid in ipairs(cats.raids or {}) do
		for _, boss in ipairs(raid.bosses or {}) do
			counts.bosses = counts.bosses + 1
			emit({ kind = "boss", zone = zone, raid = raid.name, name = boss.name, refs = refs(boss) })
		end
	end
	for _, entry in ipairs(cats.legacy or {}) do
		counts.legacy = counts.legacy + 1
		emit({ kind = "legacy", zone = zone, name = entry.name, refs = refs(entry) })
	end
	for _, rep in ipairs(cats.reputations or {}) do
		counts.reputations = counts.reputations + 1
		emit({ kind = "reputation", zone = zone, faction = rep.faction, name = rep.name, side = rep.side })
	end
end

local file = assert(io.open(output, "w"))
for _, line in ipairs(lines) do
	assert(file:write(line, "\n"))
end
assert(file:close())
io.stderr:write(
	(
		"legacy_dump: %d rewards, %d feeds, %d objectives, %d areas, %d taxis, %d wings, %d bosses, "
		.. "%d legacy entries, %d reputations -> %s\n"
	):format(
		#rewards,
		counts.feeds,
		#objectives,
		counts.areas,
		counts.taxis,
		counts.wings,
		counts.bosses,
		counts.legacy,
		counts.reputations,
		output
	)
)

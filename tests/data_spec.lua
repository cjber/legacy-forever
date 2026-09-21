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
local instances, instancePins, spelunkerLocated, adventureLocated, raidLocated = 0, 0, 0, 0, 0
local spelunker = { [62031] = true, [62032] = true, [62033] = true, [64016] = true, [64017] = true, [64018] = true }
local located = {}
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
			instances = instances + 1
			if entry.x then
				instancePins = instancePins + 1
			end
			if spelunker[entry.achievement] then
				spelunkerLocated = spelunkerLocated + 1
			elseif entry.achievement == 62054 or entry.achievement == 64014 then
				adventureLocated = adventureLocated + 1
			else
				assert(entry.achievement == 684 or entry.achievement == 64030, "only existing Onyxia raid locations")
				raidLocated = raidLocated + 1
			end
		else
			assert(entry.instance == nil, "only instance entries carry Map IDs")
		end
		local key = entry.achievement .. ":" .. entry.criteria
		assert(not seen[key], "duplicate objective within zone")
		located[key] = entry
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
assert(explore == 549, "all exploration objectives retained")
assert(instances == 58 and instancePins == 52, "56 newly located instance objectives; six zone-only entries")
assert(spelunkerLocated == 54 and adventureLocated == 2 and raidLocated == 2, "new locations by challenge category")

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
local spire = assert(samples["1428:62033:3268"], "Upper Blackrock Spire uses curated Burning Steppes entrance")
assert(spire.kind == "instance" and spire.instance == 229 and spire.x and spire.y, "Spire entrance pin")
for _, key in ipairs({ "1428:62054:111555", "1428:64014:117727" }) do
	local valthalak = assert(samples[key], "Valthalak quest variants use the curated Upper Blackrock Spire entrance")
	assert(
		valthalak.kind == "instance" and valthalak.instance == 229,
		"Valthalak retains quest criteria and instance kind"
	)
	assert(valthalak.x == spire.x and valthalak.y == spire.y, "Valthalak shares the client Spire entrance point")
end
assert(samples["1427:62033:3266"].instance == 230, "Blackrock Depths uses Searing Gorge approach")
local dalaran = assert(samples["1416:62032:116050"], "City of Dalaran has a verified entrance zone")
assert(dalaran.instance == 2959 and dalaran.x == nil, "no fabricated corpse coordinates")
for _, key in ipairs({
	"62034:116084", -- DungeonEncounter 3339 is absent from this build.
	"64019:117764",
	"62032:116053", -- The Drowned City has no verified instance/entrance.
	"64017:117736",
	"62031:19213", -- Compound Ragefire Chasm / Hall of Thanes step.
	"64016:117733",
	"62033:116055", -- Blackmaw Hold has exterior geography but no instance Map ID.
	"64018:117761",
	"62032:116052", -- Krol'dok Stronghold: same limitation.
	"64017:117744",
	"62033:116056", -- The Shaper's Terrace: same limitation.
	"64018:117760",
	"62033:116057", -- Alcaz Prison: same limitation.
	"64018:117749",
}) do
	assert(not located[key], "unresolved client joins remain unlocated: " .. key)
end

local totals = {
	zones = 0,
	areas = 0,
	tiles = 0,
	tileless = 0,
	Alliance = 0,
	Horde = 0,
	Neutral = 0,
	wings = 0,
	refs = 0,
	legacy = 0,
	legacyRefs = 0,
	legacyCollapsed = 0,
	reputations = 0,
	reputationAlliance = 0,
}
local taxiZones, wingZones, completionAreas = {}, {}, {}
local dungeonRefs, legacyRefs, reputationZones = {}, {}, {}
local areaKeys = {}
local mirrors = { [62031] = 64016, [62032] = 64017, [62033] = 64018 }
assert(type(data.completion) == "table", "completion data")
for zone, entry in pairs(data.completion) do
	assert(positiveInteger(zone), "completion zone ID")
	assert(zone ~= 2521 and zone ~= 1459 and zone ~= 1460 and zone ~= 1461, "excluded completion maps")
	for _, category in ipairs({ "areas", "taxis", "dungeons", "legacy", "reputations" }) do
		assert(type(entry[category]) == "table", "completion categories always present, including empty lists")
	end
	assert(
		#entry.areas + #entry.taxis + #entry.dungeons + #entry.legacy + #entry.reputations > 0,
		"only populated completion zones"
	)
	assert(entry.tileWidth == 256 and entry.tileHeight == 256, "pinned build base-layer tile dimensions")
	totals.zones = totals.zones + 1
	local keys = {}
	for _, area in ipairs(entry.areas) do
		assert(type(area.name) == "string" and #area.name > 0, "area name")
		assert(type(area.key) == "string", "texture key string")
		local x, y, width, height = area.key:match("^(%-?%d+):(%-?%d+):(%-?%d+):(%-?%d+)$")
		assert(x and y and width and height, "four integer texture components")
		assert(
			area.key == string.format("%d:%d:%d:%d", tonumber(x), tonumber(y), tonumber(width), tonumber(height)),
			"canonical integer-formatted texture key"
		)
		assert(not keys[area.key], "unique texture keys within each zone")
		keys[area.key] = true
		assert(tonumber(width) > 0 and tonumber(height) > 0, "drawable texture dimensions")
		local expected = math.ceil(tonumber(width) / entry.tileWidth) * math.ceil(tonumber(height) / entry.tileHeight)
		if area.tiles == nil then
			assert(zone == 1434 and area.key == "483:8:256:256", "only overlay 5252 has zero tile rows")
			totals.tileless = totals.tileless + 1
		else
			assert(type(area.tiles) == "table" and #area.tiles == expected, "complete overlay tile grid")
			local files = {}
			for _, fileID in ipairs(area.tiles) do
				assert(positiveInteger(fileID) and not files[fileID], "positive, unique overlay file IDs")
				files[fileID] = true
				totals.tiles = totals.tiles + 1
			end
		end
		areaKeys[zone .. ":" .. area.key] = area
		completionAreas[zone .. ":" .. area.name] = area.key
		totals.areas = totals.areas + 1
	end
	for _, taxi in ipairs(entry.taxis) do
		assert(positiveInteger(taxi.node) and not taxiZones[taxi.node], "unique taxi node ID")
		assert(taxi.faction == "Alliance" or taxi.faction == "Horde" or taxi.faction == "Neutral", "taxi faction")
		assert(type(taxi.name) == "string" and #taxi.name > 0, "taxi name")
		assert(taxi.name:sub(1, 2):lower() ~= "zz", "obsolete taxis excluded")
		taxiZones[taxi.node] = zone
		totals[taxi.faction] = totals[taxi.faction] + 1
	end
	for _, wing in ipairs(entry.dungeons) do
		assert(type(wing.name) == "string" and #wing.name > 0 and not wingZones[wing.name], "unique wing name")
		assert(type(wing.refs) == "table" and #wing.refs >= 2, "wing references include both variants")
		local refs, achievements = {}, {}
		for _, ref in ipairs(wing.refs) do
			assert(#ref == 2 and spelunker[ref[1]] and positiveInteger(ref[2]), "Spelunker achievement/criteria pair")
			assert(data.rewards[ref[1]], "Spelunker reference belongs to the reward graph")
			assert(ref[2] ~= 19213 and ref[2] ~= 117733, "compound dungeon step excluded")
			local key = ref[1] .. ":" .. ref[2]
			assert(not refs[key], "unique wing reference")
			refs[key] = true
			dungeonRefs[zone .. ":" .. key] = true
			achievements[ref[1]] = true
			totals.refs = totals.refs + 1
		end
		for original, mirror in pairs(mirrors) do
			assert(achievements[original] == achievements[mirror], "both variants of every represented tier")
		end
		wingZones[wing.name] = zone
		totals.wings = totals.wings + 1
	end
	local previousName
	for _, objective in ipairs(entry.legacy) do
		assert(type(objective.name) == "string" and objective.name:find("%S"), "nonempty Legacy objective text")
		assert(not previousName or previousName <= objective.name, "Legacy entries sorted by name")
		previousName = objective.name
		assert(type(objective.refs) == "table" and #objective.refs > 0, "Legacy references")
		local previousRef
		for _, ref in ipairs(objective.refs) do
			assert(
				#ref == 2 and positiveInteger(ref[1]) and positiveInteger(ref[2]),
				"Legacy achievement/criteria pair"
			)
			local key = zone .. ":" .. ref[1] .. ":" .. ref[2]
			local source = assert(samples[key], "Legacy reference is located in this zone")
			assert(source.kind ~= "explore" and not dungeonRefs[key], "areas and dungeon wings do not count twice")
			assert(not legacyRefs[key], "Legacy reference appears once per zone")
			assert(
				not previousRef or previousRef[1] < ref[1] or (previousRef[1] == ref[1] and previousRef[2] < ref[2]),
				"Legacy references sorted and unique"
			)
			previousRef = ref
			legacyRefs[key] = objective
			totals.legacyRefs = totals.legacyRefs + 1
		end
		if #objective.refs > 1 then
			totals.legacyCollapsed = totals.legacyCollapsed + 1
		end
		totals.legacy = totals.legacy + 1
	end
	previousName = nil
	for _, reputation in ipairs(entry.reputations) do
		assert(
			positiveInteger(reputation.faction) and not reputationZones[reputation.faction],
			"faction has exactly one zone"
		)
		assert(type(reputation.name) == "string" and reputation.name:find("%S"), "nonempty Faction name")
		assert(not previousName or previousName <= reputation.name, "reputations sorted by name")
		previousName = reputation.name
		assert(
			reputation.side == nil or reputation.side == "Alliance" or reputation.side == "Horde",
			"optional reputation side"
		)
		if reputation.side then
			assert(
				reputation.faction == 589 and reputation.side == "Alliance",
				"only Wintersaber Trainers are restricted"
			)
			totals.reputationAlliance = totals.reputationAlliance + 1
		end
		reputationZones[reputation.faction] = { zone = zone, name = reputation.name, side = reputation.side }
		totals.reputations = totals.reputations + 1
	end
end
local matched, unmatched = 0, 0
for zone, entries in pairs(data.zones) do
	for _, entry in ipairs(entries) do
		if entry.kind == "explore" then
			if entry.key then
				assert(areaKeys[zone .. ":" .. entry.key], "Legacy exploration key belongs to its completion zone")
				matched = matched + 1
			else
				unmatched = unmatched + 1
			end
		else
			assert(entry.key == nil, "only exploration objectives carry area keys")
			local key = zone .. ":" .. entry.achievement .. ":" .. entry.criteria
			assert(dungeonRefs[key] or legacyRefs[key], "every located non-explore objective counts in its zone")
		end
	end
end
assert(matched == 500 and unmatched == 49, "Legacy exploration current-art area matches")
assert(totals.zones == 43 and totals.areas == 555, "current-art completion coverage")
assert(totals.Alliance == 31 and totals.Horde == 30 and totals.Neutral == 4, "65 learnable player taxis")
assert(totals.tiles == 937, "verified layer-zero overlay file IDs")
assert(totals.tileless == 1, "exactly one countable area has no shading tiles")
local zulgurub = assert(samples["1434:781:1222"], "Zul'Gurub exploration objective retained")
assert(zulgurub.key == "483:8:256:256" and zulgurub.x and zulgurub.y, "tile-less area retains its key and pin")
local redridgeTiles = assert(areaKeys["1433:0:223:635:306"], "WorldMapOverlay 363 in Redridge").tiles
for index, fileID in ipairs({ 7939713, 7939715, 7939716, 7939717, 7939718, 7939719 }) do
	assert(redridgeTiles[index] == fileID, "three-column, two-row tile order matches DB2 cells")
end
assert(bloodhoof.key == "357:328:238:206" and remapped.key == "295:385:256:128", "exact current-art keys")
assert(located["768:1050"].key == "746:125:256:256", "empty hit rectangle still links to its drawable overlay")
assert(totals.wings == 31 and totals.refs == 62, "32 individual wings, one unplaced, both variants")
assert(totals.legacy == 2 and totals.legacyRefs == 4, "four non-dungeon references become two Legacy objectives")
assert(
	totals.legacyCollapsed == 2 and totals.legacyRefs - totals.legacy == 2,
	"two variant pairs remove two duplicate entries"
)
assert(#data.completion[1428].legacy == 1, "Burning Steppes counts Valthalak once alongside its dungeon wings")
assert(
	#data.completion[1434].legacy == 0 and #data.completion[1439].legacy == 0,
	"Stranglethorn and Darkshore have no remaining located Legacy objectives"
)
local valthalak = assert(legacyRefs["1428:62054:111555"], "Valthalak Legacy objective")
assert(
	valthalak == legacyRefs["1428:64014:117727"] and #valthalak.refs == 2,
	"same Type 27 / Asset 84195 / Amount 1 collapses Valthalak variants"
)
assert(
	valthalak.name
		== "Complete the questline beginning with An Earnest Proposition, and ending with Saving the Best for Last.",
	"empty criterion descriptions use the single-step achievement description"
)
local onyxia = assert(legacyRefs["1445:684:3271"], "Onyxia Legacy objective")
assert(
	onyxia == legacyRefs["1445:64030:117792"] and #onyxia.refs == 2 and onyxia.name == "Onyxia",
	"Onyxia variants share the owning CriteriaTree description"
)
assert(
	totals.reputations == 7 and totals.reputationAlliance == 1,
	"six neutral reputations plus one Alliance-only reputation"
)
for faction, expected in pairs({
	[21] = { 1434, "Booty Bay" },
	[59] = { 1427, "Thorium Brotherhood" },
	[270] = { 1434, "Zandalar Tribe" },
	[369] = { 1446, "Gadgetzan" },
	[470] = { 1413, "Ratchet" },
	[577] = { 1452, "Everlook" },
	[589] = { 1452, "Wintersaber Trainers", "Alliance" },
}) do
	local reputation = assert(reputationZones[faction], "curated Faction ID")
	assert(
		reputation.zone == expected[1] and reputation.name == expected[2] and reputation.side == expected[3],
		"exact client faction name, home zone, and eligibility"
	)
end
for _, faction in ipairs({ 70, 87, 349, 509, 510, 529, 576, 609, 729, 730, 889, 890 }) do
	assert(not reputationZones[faction], "opposed, battleground, multi-zone, or ambiguous factions excluded")
end
assert(not wingZones["The Drowned City"], "wing without verified entrance geography remains unplaced")
assert(wingZones["Gnomeregan"] == 1426 and wingZones["The Deadmines"] == 1436, "distinct Spelunker wings")
assert(taxiZones[25] == 1413 and taxiZones[21] == 1418, "Crossroads and Kargath use their correct suffixes")
assert(taxiZones[49] == 1450 and taxiZones[69] == 1450, "curated Moonglade taxis without suffixes")
assert(taxiZones[5] == 1433 and taxiZones[11] == 1420, "curated abbreviated zone suffixes")
assert(not taxiZones[59] and not taxiZones[60], "battleground taxis excluded")
assert(completionAreas["1426:Anvilmar"] and completionAreas["2652:Forlorn Gardens"], "empty hit rectangles still count")
print("ok")

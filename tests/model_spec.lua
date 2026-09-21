-- Run from the repository root: luajit tests/model_spec.lua
local ns = {}
assert(loadfile("Model.lua"))("LegacyHere", ns)
local Model = ns.Model
local checks = 0

local function equal(actual, expected, label)
	checks = checks + 1
	assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

-- Two reward variants (100, 200) fed by one exploration achievement (10); a kill
-- criterion placed directly on reward 100; a level criterion with no place.
local data = {
	rewards = { [100] = true, [200] = true },
	feeds = { [10] = { 100, 200 } },
	zones = {
		[1] = {
			{ achievement = 10, criteria = 1, kind = "explore", x = 0.1, y = 0.2 },
			{ achievement = 10, criteria = 2, kind = "explore" },
			{ achievement = 100, criteria = 3, kind = "kill" },
		},
		[2] = { { achievement = 10, criteria = 4, kind = "explore" } },
	},
}

local live = {
	[10] = {
		[1] = { text = "Area A", completed = false, index = 1 },
		[2] = { text = "Area B", completed = true, index = 2 },
		[4] = { text = "Area C", completed = false, index = 3 },
		[8] = { text = "Unplaced area", completed = false, index = 4 },
	},
	[100] = {
		[3] = { text = "Boss", completed = false, index = 2 },
		[5] = { text = "Reach level 20", completed = false, index = 1, quantity = 12, required = 20 },
		[6] = { text = "Explore", completed = false, index = 3, type = 8, asset = 10 },
		[7] = { text = "Done already", completed = true, index = 4 },
	},
}
local function criteria(id)
	return live[id]
end

-- Ownership follows whichever variant the client lists.
equal(Model.OwningChallenge(data, 10, { [200] = true }), 200, "feeding achievement owned by visible variant")
equal(Model.OwningChallenge(data, 100, { [100] = true }), 100, "challenge owns itself")
equal(Model.OwningChallenge(data, 10, {}), nil, "no visible owner")

local visible = { [100] = true }
local groups = Model.ZoneObjectives(data, 1, visible, criteria)
equal(#groups, 2, "one group per holding achievement")
equal(groups[1].achievement, 10, "exploration group first, in data order")
equal(groups[1].challenge, 100, "exploration group credits the visible challenge")
equal(#groups[1].objectives, 1, "completed area left out")
equal(groups[1].objectives[1].text, "Area A", "live criterion text")
equal(groups[2].objectives[1].entry.kind, "kill", "direct objective kept")
equal(Model.CountObjectives(groups), 2, "count across groups")

equal(#Model.ZoneObjectives(data, 1, {}, criteria), 0, "nothing without a visible challenge")
equal(#Model.ZoneObjectives(data, 3, visible, criteria), 0, "unknown map")
local unknown = Model.ZoneObjectives(data, 1, visible, function()
	return nil
end)
equal(#unknown, 0, "unknown progress is not shown as unfinished")

-- Located criteria are excluded; "earn achievement 10" counts only 10's unplaced criteria.
local unlocated = Model.Unlocated(data, visible, criteria)
equal(#unlocated, 1, "one challenge with unplaced work")
equal(unlocated[1].challenge, 100, "unplaced challenge")
equal(unlocated[1].open, 2, "the level criterion plus the unplaced area under 10")
equal(#Model.Unlocated(data, { [200] = true }, criteria), 0, "variant without live criteria")

-- Tracker: unfinished steps in game order, with counts and sub-achievement progress.
local lines = Model.TrackerLines(100, criteria)
equal(#lines, 3, "completed step left out of the tracker")
equal(lines[1].text, "Reach level 20", "tracker follows game order")
equal(lines[1].detail, "12/20", "counted criterion shows quantity")
equal(lines[2].detail, nil, "single step has no count")
equal(lines[3].detail, "1/4", "earn-achievement step shows its criteria done")
equal(#Model.TrackerLines(999, criteria), 0, "unknown challenge has no lines")

-- Zone completion: own-faction and neutral flight paths only, unknown wings left out.
local zone = {
	areas = { { key = "0:0:10:10", name = "Kharanos" }, { key = "10:0:10:10", name = "Gol'Bolar Quarry" } },
	taxis = {
		{ node = 6, faction = "Alliance", name = "Ironforge" },
		{ node = 7, faction = "Horde", name = "Kargath" },
		{ node = 8, faction = "Neutral", name = "Ratchet" },
		{ node = 9, faction = "Neutral", name = "Unlisted" },
	},
	dungeons = {
		{ name = "Gnomeregan", refs = { { 1, 1 } } },
		{ name = "Unknown wing", refs = { { 2, 2 } } },
	},
	legacy = {
		{ name = "Lord Valthalak Laid to Rest", refs = { { 3, 3 }, { 4, 4 } } },
	},
	reputations = {
		{ faction = 21, name = "Booty Bay" },
		{ faction = 589, name = "Wintersaber Trainers", side = "Alliance" },
		{ faction = 530, name = "Darkspear Trolls", side = "Horde" },
	},
}
local snapshot = {
	explored = { ["0:0:10:10"] = true },
	taxis = { [6] = true, [7] = false, [8] = false },
	faction = "Alliance",
	refsDone = function(refs)
		if refs[1][1] == 1 then
			return false
		end
		if refs[1][1] == 3 then
			return refs[2][1] == 4
		end
	end,
	reaction = function(factionID)
		return factionID == 21 and 5 or 4
	end,
}
local completion = Model.ZoneCompletion(zone, snapshot)
equal(completion.areas.done, 1, "one area explored")
equal(completion.areas.left[1], "Gol'Bolar Quarry", "unexplored area named")
equal(completion.taxis.total, 2, "other faction's and unlisted flight paths left out")
equal(completion.taxis.pending, 1, "an unknown flight path is pending, outside the total")
equal(completion.dungeons.total, 1, "wing with unknown progress left out")
equal(completion.legacy.done, 1, "a Legacy objective is done when any variant is")
equal(completion.reputations.total, 2, "the other faction's reputation is left out")
equal(completion.reputations.done, 1, "Friendly counts, Neutral doesn't")
equal(completion.reputations.left[1], "Wintersaber Trainers", "reputation still to earn named")
equal(completion.total, 8, "items across categories")
equal(completion.percent, 50, "percent floors")
equal(Model.ZoneCompletion({}, snapshot).percent, nil, "empty zone has no percent")
local noAreas = Model.ZoneCompletion(zone, snapshot, function(key)
	return key ~= "areas"
end)
equal(noAreas.areas, nil, "an uncounted category is left out")
equal(noAreas.total, completion.total - completion.areas.total, "and drops out of the total")

-- Hovering picks the area whose centre is nearest among those whose texture holds the point.
local overlapping = {
	{ key = "0:0:100:100" },
	{ key = "50:0:100:100", hit = { 120, 40, 140, 60 } },
}
equal(Model.AreaAt(overlapping, 10, 50), 1, "only one texture holds the point")
equal(Model.AreaAt(overlapping, 70, 50), 1, "nearer the first area's centre")
equal(Model.AreaAt(overlapping, 95, 50), 2, "nearer the second area's hit rectangle")
equal(Model.AreaAt(overlapping, 200, 50), nil, "outside every texture")

-- Overlay tiles, laid out like Blizzard's exploration overlays.
local ox, oy, ow, oh = Model.OverlayRect("413:476:256:128")
equal(ox + oy + ow + oh, 413 + 476 + 256 + 128, "overlay key parses to integers")
local tiles = Model.OverlayTiles(549, 241, 256, 256)
equal(#tiles, 3, "549x241 needs three 256px tiles in one row")
equal(tiles[3].x, 512, "third tile offset")
equal(tiles[3].width, 37, "last tile keeps the remainder")
equal(tiles[3].u, 37 / 64, "partial tile samples its power-of-two file")
equal(tiles[1].u, 1, "full tile samples the whole file")
equal(#Model.OverlayTiles(512, 512, 256, 256), 4, "exact multiples add no partial tile")

snapshot.taxis = {}
local unvisited = Model.ZoneCompletion(zone, snapshot).taxis
equal(unvisited and unvisited.total, 0, "flight paths before a flight master visit are all pending")
equal(unvisited and unvisited.pending, 3, "own-faction and neutral ones")
snapshot.explored = { ["0:0:10:10"] = true, ["10:0:10:10"] = true }
local onlyKnown = Model.ZoneCompletion({ areas = zone.areas, taxis = zone.taxis }, snapshot)
equal(onlyKnown.percent, 99, "everything known done, with flight paths pending, stays under 100%")
equal(onlyKnown.complete, false, "and isn't complete")
-- A raid is done when every boss is; a boss when either of its variants is.
local raidZone = {
	raids = {
		{
			name = "Onyxia's Lair",
			bosses = { { name = "Onyxia", refs = { { 50, 1 }, { 51, 1 } } }, { name = "Whelps", refs = { { 52, 1 } } } },
		},
	},
}
local done = {}
local raidSnapshot = {
	refsDone = function(refs)
		for _, ref in ipairs(refs) do
			if done[ref[1]] then
				return true
			end
		end
		if not done.unknown then
			return false
		end
	end,
}
equal(Model.ZoneCompletion(raidZone, raidSnapshot).raids.done, 0, "no boss down, raid not done")
done[51] = true
local raids = Model.ZoneCompletion(raidZone, raidSnapshot).raids
equal(raids.done, 0, "one boss down of two, raid still not done")
equal(raids.left[1], "Onyxia's Lair", "the raid is named, not its bosses")
done[52] = true
equal(Model.ZoneCompletion(raidZone, raidSnapshot).complete, true, "every boss down by any variant")
done[52], done.unknown = nil, true
equal(Model.ZoneCompletion(raidZone, raidSnapshot).raids.pending, 1, "an unknown boss leaves the raid pending")

-- A continent counts its zones that count anything, complete or not.
local continent = Model.ContinentCompletion({
	{ total = 3, pending = 0, complete = true },
	{ total = 4, pending = 1, complete = false },
	{ total = 0, pending = 0, complete = true },
})
equal(continent.zones, 2, "a zone counting nothing is left out")
equal(continent.complete, 1, "complete zones")
equal(continent.percent, 50, "continent percent")
equal(Model.ContinentCompletion({ { total = 0, pending = 0, complete = true } }), nil, "no zone counts anything")
print(("model_spec: %d checks passed"):format(checks))

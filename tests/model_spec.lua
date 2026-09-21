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

print(("model_spec: %d checks passed"):format(checks))

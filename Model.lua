local _, ns = ...

-- Pure logic over the generated data and a snapshot of live progress; no WoW API
-- calls, so tests/model_spec.lua can exercise it under plain LuaJIT.
--
-- `visible` is the set of reward-bearing challenges the game shows this character
-- (Forever ships two variant sets and the client lists only one).
-- `criteria(achievementID)` returns { [criteriaID] = { text, completed, type, asset } }
-- or nil when the game has no data for that achievement.
local Model = {}
ns.Model = Model

-- Achievement type 8: "earn achievement X", where X is the criterion's asset.
local EARN_ACHIEVEMENT = 8

-- The visible challenge an objective counts toward, or nil if none is visible.
function Model.OwningChallenge(data, achievementID, visible)
	if visible[achievementID] then
		return achievementID
	end
	for _, reward in ipairs(data.feeds[achievementID] or {}) do
		if visible[reward] then
			return reward
		end
	end
	return nil
end

-- Unfinished objectives in one zone, grouped by the achievement that holds them
-- (a challenge, or the exploration achievement feeding it). Objectives whose live
-- progress is unknown are left out rather than shown as unfinished; Audit reports them.
function Model.ZoneObjectives(data, uiMapID, visible, criteria)
	local groups, byAchievement = {}, {}
	for _, entry in ipairs(data.zones[uiMapID] or {}) do
		local challenge = Model.OwningChallenge(data, entry.achievement, visible)
		local live = challenge and criteria(entry.achievement)
		local progress = live and live[entry.criteria]
		if progress and not progress.completed then
			local group = byAchievement[entry.achievement]
			if not group then
				group = { achievement = entry.achievement, challenge = challenge, objectives = {} }
				byAchievement[entry.achievement] = group
				groups[#groups + 1] = group
			end
			group.objectives[#group.objectives + 1] = { entry = entry, text = progress.text }
		end
	end
	return groups
end

function Model.CountObjectives(groups)
	local count = 0
	for _, group in ipairs(groups) do
		count = count + #group.objectives
	end
	return count
end

local function LocatedCriteria(data)
	local located = {}
	for _, entries in pairs(data.zones) do
		for _, entry in ipairs(entries) do
			located[entry.criteria] = true
		end
	end
	return located
end

-- Visible challenges with unfinished criteria no zone accounts for: levels, skills,
-- ranks, and anything whose location the data can't establish.
function Model.Unlocated(data, visible, criteria)
	local located = LocatedCriteria(data)
	local result = {}
	for challenge in pairs(visible) do
		local open = 0
		for criteriaID, progress in pairs(criteria(challenge) or {}) do
			local placedByChildren = progress.type == EARN_ACHIEVEMENT and data.feeds[progress.asset] ~= nil
			if not progress.completed and not located[criteriaID] and not placedByChildren then
				open = open + 1
			end
		end
		if open > 0 then
			result[#result + 1] = { challenge = challenge, open = open }
		end
	end
	table.sort(result, function(a, b)
		return a.challenge < b.challenge
	end)
	return result
end

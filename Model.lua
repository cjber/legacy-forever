local _, ns = ...

-- Pure logic over the generated data and a snapshot of live progress; no WoW API
-- calls, so tests/model_spec.lua can exercise it under plain LuaJIT.
--
-- `visible` is the set of unfinished reward-bearing challenges the game shows this
-- character (Forever ships two variant sets and the client lists only one).
-- `criteria(achievementID)` returns { [criteriaID] = { text, completed, type, asset,
-- quantity, required, index } }
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

-- Unfinished criteria no zone places, counting through "earn achievement X" into
-- X's own criteria when X is a feeding achievement (the generator rejects cycles).
local function OpenUnlocated(data, located, criteria, achievementID)
	local open = 0
	for criteriaID, progress in pairs(criteria(achievementID) or {}) do
		if not progress.completed and not located[criteriaID] then
			if progress.type == EARN_ACHIEVEMENT and data.feeds[progress.asset] then
				open = open + OpenUnlocated(data, located, criteria, progress.asset)
			else
				open = open + 1
			end
		end
	end
	return open
end

-- Visible challenges with unfinished criteria no zone accounts for: levels, skills,
-- ranks, and anything whose location the data can't establish.
function Model.Unlocated(data, visible, criteria)
	local located = LocatedCriteria(data)
	local result = {}
	for challenge in pairs(visible) do
		local open = OpenUnlocated(data, located, criteria, challenge)
		if open > 0 then
			result[#result + 1] = { challenge = challenge, open = open }
		end
	end
	table.sort(result, function(a, b)
		return a.challenge < b.challenge
	end)
	return result
end

-- A tracked challenge's unfinished steps in game order, each with its progress:
-- "3/10" for counted criteria, and done/total of X's criteria for "earn achievement X".
function Model.TrackerLines(challenge, criteria)
	local open = {}
	for _, progress in pairs(criteria(challenge) or {}) do
		if not progress.completed then
			open[#open + 1] = progress
		end
	end
	table.sort(open, function(a, b)
		return a.index < b.index
	end)
	local lines = {}
	for _, progress in ipairs(open) do
		local detail
		local sub = progress.type == EARN_ACHIEVEMENT and criteria(progress.asset)
		if sub then
			local done, total = 0, 0
			for _, step in pairs(sub) do
				total = total + 1
				done = done + (step.completed and 1 or 0)
			end
			detail = ("%d/%d"):format(done, total)
		elseif progress.required and progress.required > 1 then
			detail = ("%d/%d"):format(progress.quantity, progress.required)
		end
		lines[#lines + 1] = { text = progress.text, detail = detail }
	end
	return lines
end

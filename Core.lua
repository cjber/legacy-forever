local _, addon = ...

---@class LegacyForeverNamespace
---@field TITLE string
---@field Data LegacyData
---@field Model LegacyModel
---@field Live LegacyLive
---@field Quests LegacyQuests
---@field Tracker LegacyTracker
---@field Completion LegacyCompletion
---@field RefreshMap fun()
---@field Navigate fun(uiMapID: number, x: number, y: number, title: string)
---@field NavigateHint fun(): string
---@field Guide fun(uiMapID: number, x: number, y: number, title: string): boolean, ("combat"|"unavailable")?
local ns = addon

ns.TITLE = "Legacy Forever"

-- A table in the saved variables. The toc loads them before any file runs (LoadSavedVariablesFirst), so this
-- is safe at file scope; callers still look it up each time rather than holding on to it.
---@overload fun(key: 'tracked'): LegacyTrackingKey[]
---@overload fun(key: 'zoneCompletion'): LegacySettings
---@overload fun(key: 'flightPaths'): table<string, LegacyFlightRecord>
---@param key 'tracked'|'zoneCompletion'|'flightPaths'
---@return LegacyTrackingKey[]|LegacySettings|table<string, LegacyFlightRecord>
function ns.SavedTable(key)
	LegacyForeverDB = LegacyForeverDB or {}
	LegacyForeverDB[key] = LegacyForeverDB[key] or {}
	return LegacyForeverDB[key]
end

---@param msg string
function ns.Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99" .. ns.TITLE .. "|r " .. msg)
end

-- Compares the bundled data with what the game reports, so a data problem shows
-- up as a count and a list of IDs rather than as a silently missing pin.
---@param data LegacyData
local function AuditChallenges(data)
	local visible = ns.Live.Visible()
	local numVisible = 0
	for _ in pairs(visible) do
		numVisible = numVisible + 1
	end
	ns.Print(("%d unfinished Legacy challenges listed for this character"):format(numVisible))
	if numVisible == 0 then
		ns.Print("the game listed none unfinished; if you're below level 25 or just logged in, try again shortly.")
		return
	end

	local checked, missing = 0, {}
	for uiMapID, entries in pairs(data.zones) do
		for _, entry in ipairs(entries) do
			if ns.Model.OwningChallenge(data, entry.achievement, visible) then
				checked = checked + 1
				local live = ns.Live.Criteria(entry.achievement)
				if not (live and live[entry.criteria]) then
					missing[#missing + 1] = ("%d:%d (map %d)"):format(entry.achievement, entry.criteria, uiMapID)
				end
			end
		end
	end
	ns.Print(("%d located objectives checked, %d unknown to the game"):format(checked, #missing))
	for i = 1, math.min(#missing, 10) do
		ns.Print("  unknown criteria " .. missing[i])
	end

	local unlocated = ns.Model.Unlocated(data, visible, ns.Live.Criteria)
	ns.Print(("%d challenges have objectives with no fixed location"):format(#unlocated))
	ns.Print(
		("tracker: %d tracked, Legacy section %s"):format(
			ns.Tracker.Count(),
			ns.Tracker.IsAttached() and "in the objective tracker" or "NOT in the objective tracker"
		)
	)
end

local function Audit()
	local data = ns.Data
	local version, build = GetBuildInfo()
	ns.Print(("data from build %s, client build %s.%s"):format(data.build, version, build))
	AuditChallenges(data)
	ns.Completion.Audit()
end

-- Every criterion the game reports for one achievement, for reporting data mismatches.
---@param achievementID number
local function Criteria(achievementID)
	local count = GetAchievementNumCriteria(achievementID) or 0
	ns.Print(
		("achievement %d (%s): %d criteria"):format(achievementID, ns.Live.Name(achievementID) or "unknown", count)
	)
	for index = 1, count do
		local text, criteriaType, completed, _, _, _, _, asset, _, criteriaID =
			GetAchievementCriteriaInfo(achievementID, index)
		ns.Print(
			("  %d: id %s type %s asset %s %s%s"):format(
				index,
				tostring(criteriaID),
				tostring(criteriaType),
				tostring(asset),
				text or "",
				completed and " (done)" or ""
			)
		)
	end
end

SLASH_LEGACYFOREVER1 = "/lf"
SLASH_LEGACYFOREVER2 = "/legacyforever"
SlashCmdList.LEGACYFOREVER = function(msg)
	local command = strtrim(msg or ""):lower()
	-- Lenient: "criteria 684", "criteria <684>" and a bare "684" all work.
	local achievementID = (command:find("^criteria") or command:find("^%d+$")) and tonumber(command:match("%d+"))
	if command == "audit" then
		Audit()
	elseif achievementID then
		Criteria(achievementID)
	elseif command:find("^criteria") then
		ns.Print("usage: /lf criteria 684")
	else
		ns.Print("open the world map and use the Legacy button in its top-right corner.")
		ns.Print("/lf audit - check the bundled data against the game")
		ns.Print("/lf criteria 684 - list what the game reports for one achievement")
	end
end

function LegacyForever_OnAddonCompartmentClick()
	ToggleWorldMap()
end

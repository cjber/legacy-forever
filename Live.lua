local _, ns = ...

-- Reads progress from the game. Everything is rebuilt from live APIs each session:
-- Forever's SavedVariables don't load (forever-bugs#34), so nothing is persisted.
local Live = {}
ns.Live = Live

local LEGACY_POINTS_CURRENCY = 4225

local visible
local criteriaCache = {}
local listeners = {}

-- The unfinished challenges the game lists for this character, exactly as the Legacy
-- panel enumerates them. The game's list also holds the helper achievements that feed
-- them; only reward-bearing challenges go in this set.
-- Completed ones are dropped here: an alt's own exploration can't advance a challenge
-- the account has already earned.
function Live.Visible()
	if visible then
		return visible
	end
	visible = {}
	for _, categoryID in ipairs(GetCategoryList() or {}) do
		for index = 1, GetCategoryNumAchievements(categoryID) or 0 do
			local achievementID, _, _, completed = GetAchievementInfo(categoryID, index)
			if achievementID and ns.Data.rewards[achievementID] and not completed then
				visible[achievementID] = true
			end
		end
	end
	return visible
end

-- Criteria IDs the data places for each achievement, built once.
local locatedByAchievement
local function LocatedCriteria(achievementID)
	if not locatedByAchievement then
		locatedByAchievement = {}
		for _, entries in pairs(ns.Data.zones) do
			for _, entry in ipairs(entries) do
				local list = locatedByAchievement[entry.achievement] or {}
				list[#list + 1] = entry.criteria
				locatedByAchievement[entry.achievement] = list
			end
		end
	end
	return locatedByAchievement[achievementID]
end

-- A single-step achievement (e.g. Conqueror of the Lair) reports no criteria: the
-- achievement is the step. File its completion under the criterion the data placed,
-- or under 0 (never placed) so it still counts as unplaced work.
local function WholeAchievement(achievementID)
	local _, name, _, completed = GetAchievementInfo(achievementID)
	if not name then
		return nil
	end
	local result = {}
	for _, criteriaID in ipairs(LocatedCriteria(achievementID) or { 0 }) do
		result[criteriaID] = { text = name, completed = completed, index = 1 }
	end
	return result
end

-- Criteria by ID rather than index: DB2 order and API order need not agree.
function Live.Criteria(achievementID)
	local cached = criteriaCache[achievementID]
	if cached ~= nil then
		return cached or nil
	end
	local result
	local count = GetAchievementNumCriteria(achievementID)
	if count and count > 0 then
		result = {}
		for index = 1, count do
			local text, criteriaType, completed, quantity, required, _, _, asset, _, criteriaID =
				GetAchievementCriteriaInfo(achievementID, index)
			if criteriaID then
				result[criteriaID] = {
					text = text,
					completed = completed,
					type = criteriaType,
					asset = asset,
					quantity = quantity,
					required = required,
					index = index,
				}
			end
		end
	end
	if count == 0 then
		result = WholeAchievement(achievementID)
	end
	criteriaCache[achievementID] = result or false
	return result
end

function Live.Name(achievementID)
	local _, name = GetAchievementInfo(achievementID)
	return name
end

function Live.Points(achievementID)
	if not C_Traits or not C_Traits.GetTraitCurrencyForAchievement then
		return nil
	end
	local points = C_Traits.GetTraitCurrencyForAchievement(LEGACY_POINTS_CURRENCY, achievementID)
	return points and points > 0 and points or nil
end

-- Opens Blizzard's Legacy panel on this challenge. The panel opens on its first
-- page and only Legacy.SelectPage switches to the challenges page.
local CHALLENGES_PAGE = 2

function Live.ShowInLegacyPanel(achievementID)
	if not (LegacySystemFrame and LegacySystemFrame:IsShown()) then
		ToggleLegacySystemUI()
	end
	EventRegistry:TriggerEvent("Legacy.SelectPage", CHALLENGES_PAGE)
	if AchievementFrame_SelectAchievement then
		AchievementFrame_SelectAchievement(achievementID, true)
	end
end

function Live.OnChange(callback)
	listeners[#listeners + 1] = callback
end

-- CRITERIA_UPDATE fires in bursts (every kill, every discovered area), so
-- invalidation is immediate but listeners run once per burst.
local pending = false
local function Notify()
	pending = false
	for _, callback in ipairs(listeners) do
		callback()
	end
end

function Live.Invalidate()
	visible = nil
	criteriaCache = {}
	if not pending then
		pending = true
		C_Timer.After(0.5, Notify)
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("CRITERIA_UPDATE")
events:RegisterEvent("ACHIEVEMENT_EARNED")
events:RegisterEvent("RECEIVED_ACHIEVEMENT_LIST")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", Live.Invalidate)

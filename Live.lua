local _, ns = ...

-- Reads progress from the game. Everything is rebuilt from live APIs each session:
-- Forever's SavedVariables don't load (forever-bugs#34), so nothing is persisted.
local Live = {}
ns.Live = Live

local LEGACY_POINTS_CURRENCY = 4225

local visible
local criteriaCache = {}
local listeners = {}

-- The challenges the game lists for this character, exactly as the Legacy panel
-- enumerates them. Only reward-bearing ones count; the list also holds helpers.
function Live.Visible()
	if visible then
		return visible
	end
	visible = {}
	for _, categoryID in ipairs(GetCategoryList() or {}) do
		for index = 1, GetCategoryNumAchievements(categoryID) or 0 do
			local achievementID = GetAchievementInfo(categoryID, index)
			if achievementID and ns.Data.rewards[achievementID] then
				visible[achievementID] = true
			end
		end
	end
	return visible
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
			local text, criteriaType, completed, _, _, _, _, asset, _, criteriaID =
				GetAchievementCriteriaInfo(achievementID, index)
			if criteriaID then
				result[criteriaID] = { text = text, completed = completed, type = criteriaType, asset = asset }
			end
		end
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

function Live.IsTracked(achievementID)
	return C_ContentTracking.IsTracking(Enum.ContentTrackingType.Achievement, achievementID)
end

function Live.ToggleTracked(achievementID)
	local kind = Enum.ContentTrackingType.Achievement
	if Live.IsTracked(achievementID) then
		C_ContentTracking.StopTracking(kind, achievementID, Enum.ContentTrackingStopType.Manual)
		return
	end
	local err = C_ContentTracking.StartTracking(kind, achievementID)
	if err == Enum.ContentTrackingError.MaxTracked then
		ns.Print("you're already tracking as many things as the game allows.")
	elseif err == Enum.ContentTrackingError.Untrackable then
		ns.Print("the game doesn't allow tracking that challenge.")
	end
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
events:SetScript("OnEvent", Live.Invalidate)

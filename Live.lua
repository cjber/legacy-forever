local _, ns = ...

-- Reads progress from the game, rebuilt from live APIs each session. The one thing the
-- game won't say is which flight paths a character knows, so that is recorded (FlightRecord).
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
-- achievement is the step, described by its description. File its completion under
-- the criterion the data placed, or under 0 (never placed) so it still counts as unplaced.
local function WholeAchievement(achievementID)
	local _, name, _, completed, _, _, _, description = GetAchievementInfo(achievementID)
	if not name then
		return nil
	end
	local text = description and description ~= "" and description or name
	local result = {}
	for _, criteriaID in ipairs(LocatedCriteria(achievementID) or { 0 }) do
		result[criteriaID] = { text = text, completed = completed, index = 1 }
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

local snapshots = {}

local function Changed()
	if not pending then
		pending = true
		C_Timer.After(0.5, Notify)
	end
end

function Live.Invalidate()
	visible = nil
	criteriaCache = {}
	snapshots = {}
	Changed()
end

-- A wing or Legacy objective counts as done when any of its Legacy steps (either variant) is.
local function RefsDone(refs)
	local state
	for _, ref in ipairs(refs) do
		local progress = (Live.Criteria(ref[1]) or {})[ref[2]]
		if progress then
			if progress.completed then
				return true
			end
			state = false
		end
	end
	return state
end

-- A faction the player hasn't met yet has no data, which is simply not Friendly yet.
local function Reaction(factionID)
	local data = C_Reputation.GetFactionDataByID(factionID)
	return data and data.reaction or 0
end

local function OverlayKey(texture)
	return ("%d:%d:%d:%d"):format(texture.offsetX, texture.offsetY, texture.textureWidth, texture.textureHeight)
end

-- The continent a map sits on, or nil above continent level.
local function ContinentOf(uiMapID)
	local info = C_Map.GetMapInfo(uiMapID)
	while info and info.mapType > Enum.UIMapType.Continent do
		info = C_Map.GetMapInfo(info.parentMapID)
	end
	return info and info.mapType == Enum.UIMapType.Continent and info.mapID or nil
end

-- Which flight paths this character knows. Zone maps report every node as discovered on
-- Forever, so the only reliable source is a flight master's own list: opening one records
-- the known nodes for its continent. Until then that continent's flight paths are unknown.
local function FlightRecord()
	local records = ns.SavedTable("flightPaths")
	local guid = UnitGUID("player")
	records[guid] = records[guid] or { known = {}, continents = {} }
	return records[guid]
end

local function RecordFlightMaster()
	local continent = ContinentOf(C_Map.GetBestMapForUnit("player") or 0)
	local nodes = continent and C_TaxiMap.GetAllTaxiNodes(continent)
	if not nodes or #nodes == 0 then
		return
	end
	local record = FlightRecord()
	record.continents[continent] = true
	for _, node in ipairs(nodes) do
		record.known[node.nodeID] = node.state ~= Enum.FlightPathState.Unreachable or nil
	end
end

-- Live progress for Model.ZoneCompletion.
function Live.ZoneSnapshot(uiMapID)
	local snapshot = snapshots[uiMapID]
	if snapshot then
		return snapshot
	end
	snapshot = { taxis = {}, faction = UnitFactionGroup("player"), refsDone = RefsDone, reaction = Reaction }
	local textures = C_MapExplorationInfo.GetExploredMapTextures(uiMapID)
	if textures then
		snapshot.explored = {}
		for _, texture in ipairs(textures) do
			snapshot.explored[OverlayKey(texture)] = true
		end
	end
	local record = FlightRecord()
	if record.continents[ContinentOf(uiMapID) or 0] then
		for _, taxi in ipairs(ns.Data.completion[uiMapID].taxis or {}) do
			snapshot.taxis[taxi.node] = record.known[taxi.node] == true
		end
	end
	snapshots[uiMapID] = snapshot
	return snapshot
end

-- The zone the player is in, walking up from a cave or city sub-map to the first map
-- with completion data; nil on a continent or anywhere the data doesn't cover.
function Live.CurrentZone()
	local uiMapID = C_Map.GetBestMapForUnit("player")
	while uiMapID and not ns.Data.completion[uiMapID] do
		local info = C_Map.GetMapInfo(uiMapID)
		if not info or info.mapType <= Enum.UIMapType.Continent then
			return nil
		end
		uiMapID = info.parentMapID
	end
	return uiMapID
end

local INVALIDATING = {
	"CRITERIA_UPDATE",
	"ACHIEVEMENT_EARNED",
	"RECEIVED_ACHIEVEMENT_LIST",
	"PLAYER_ENTERING_WORLD",
	"MAP_EXPLORATION_UPDATED",
}
-- Flight paths and reputation feed only the zone snapshots.
local SNAPSHOT_CHANGES = { "TAXI_NODE_STATUS_CHANGED", "TAXIMAP_OPENED", "UPDATE_FACTION" }
local FLIGHT_MASTER = { TAXIMAP_OPENED = true, TAXI_NODE_STATUS_CHANGED = true }
-- Moving between zones changes which zone is shown, not anyone's progress.
local ZONE_CHANGES = { "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA" }

local events = CreateFrame("Frame")
for _, event in ipairs(INVALIDATING) do
	events:RegisterEvent(event)
end
for _, event in ipairs(ZONE_CHANGES) do
	events:RegisterEvent(event)
end
for _, event in ipairs(SNAPSHOT_CHANGES) do
	events:RegisterEvent(event)
end
events:SetScript("OnEvent", function(_, event)
	if tContains(ZONE_CHANGES, event) then
		Changed()
	elseif tContains(SNAPSHOT_CHANGES, event) then
		if FLIGHT_MASTER[event] then
			RecordFlightMaster()
		end
		snapshots = {}
		Changed()
	else
		Live.Invalidate()
	end
end)

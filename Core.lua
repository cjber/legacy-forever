local _, addon = ...

---@class LegacyForeverNamespace
---@field TITLE string
---@field WHATS_NEW string
---@field CompanionHint fun(): string?
---@field WhatsNew fun()
---@field L table<string, string>
---@field DEFAULTS LegacyDefaults
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
local L = ns.L

ns.TITLE = "Legacy Forever"
-- One sentence for the chat line after an update (WhatsNew.lua): the headline of the release this ships in.
ns.WHATS_NEW = L["Ready for translation, and map pins suggest Shortest Path Forever to plot the route."]

-- Every setting's default. A saved setting stays nil until the player changes it, and nil reads as the
-- default here, so an old save file and a new option always agree.
---@type LegacyDefaults
ns.DEFAULTS = {
	-- The shading is the quickest way to see what a zone still hides.
	showAreas = true,
	-- One chat line after an update, never on a first install.
	whatsNew = true,
	-- A grey line where another of the Forever addons would do more for you.
	companions = true,
	zoneCompletion = {
		-- The map is on so the feature is visible; the tracker takes screen space, so it waits to be asked.
		map = true,
		tracker = false,
		mapCollapsed = false,
		trackerCollapsed = false,
		-- Only Legacy objectives count: areas (each an "Explore <zone>" step toward Explorer), Spelunker
		-- dungeons, Conqueror raids and the zone's other Legacy steps. No Legacy challenge asks for flight
		-- paths, these reputations or quests, so they wait under "What counts" to be ticked.
		count_areas = true,
		count_taxis = false,
		count_dungeons = true,
		count_raids = true,
		count_legacy = true,
		count_reputations = false,
		count_quests = false,
	},
}

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

-- A top-level switch, its default while unset.
---@param key 'showAreas'|'whatsNew'|'companions'
---@return boolean
function ns.Setting(key)
	local value = LegacyForeverDB and LegacyForeverDB[key]
	if value == nil then
		return ns.DEFAULTS[key]
	end
	return value
end

-- A zone completion switch, its default while unset.
---@param key string
---@return boolean
function ns.ZoneSetting(key)
	local value = ns.SavedTable("zoneCompletion")[key]
	if value == nil then
		return ns.DEFAULTS.zoneCompletion[key] == true
	end
	return value
end

---@param msg string
function ns.Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99" .. ns.TITLE .. "|r " .. msg)
end

-- Art is never stretched: `atlas` at its native shape, as large as fits in maxWidth by maxHeight. The caller anchors
-- the texture by one point, so it stays centred in its box.
---@param texture Texture
---@param atlas string
---@param maxWidth number
---@param maxHeight number
function ns.FitAtlas(texture, atlas, maxWidth, maxHeight)
	texture:SetAtlas(atlas)
	local info = C_Texture.GetAtlasInfo(atlas)
	if info then
		local scale = math.min(maxWidth / info.width, maxHeight / info.height)
		texture:SetSize(info.width * scale, info.height * scale)
	end
end

-- The same inline in text, which draws whole pixels: the longest side at most `size` whose rounded short side keeps
-- the atlas's shape within 2%, trying up to two pixels smaller before settling for the closest.
---@param atlas string
---@param size integer
---@return string
function ns.AtlasMarkup(atlas, size)
	local info = C_Texture.GetAtlasInfo(atlas)
	local aspect = info and info.width / info.height or 1
	local shape = math.min(aspect, 1 / aspect)
	local long, short, best = size, size, math.huge
	for side = size, math.max(1, size - 2), -1 do
		local other = math.max(1, math.floor(side * shape + 0.5))
		local off = math.abs(other / side / shape - 1)
		if off < best then
			long, short, best = side, other, off
		end
		if off <= 0.02 then
			break
		end
	end
	if aspect < 1 then
		return CreateAtlasMarkup(atlas, short, long)
	end
	return CreateAtlasMarkup(atlas, long, short)
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
		ns.Print(L["open the world map and use the Legacy button in its top-right corner."])
		ns.Print(L["/lf audit - check the bundled data against the game"])
		ns.Print(L["/lf criteria 684 - list what the game reports for one achievement"])
	end
end

function LegacyForever_OnAddonCompartmentClick()
	ToggleWorldMap()
end

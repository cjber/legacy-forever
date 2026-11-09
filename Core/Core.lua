local _, addon = ...

---@class LegacyForeverNamespace
---@field ReportTitle string the localized title shown by the shared report window
---@field TITLE string
---@field POINTS_ICON string
---@field WHATS_NEW string
---@field CompanionHint fun(): string?
---@field WhatsNew fun()
---@field L table<string, string>
---@field Art LegacyArt
---@field Saved LegacySaved
---@field Data LegacyData
---@field Model LegacyModel
---@field Live LegacyLive
---@field Quests LegacyQuests
---@field TrackerHost ForeverTrackerHostAPI
---@field Family ForeverFamilyAPI
---@field FamilyDB fun(): LegacySavedVariables
---@field Tracker LegacyTracker
---@field ZoneCompletion LegacyZoneCompletion
---@field Completion LegacyCompletion
---@field MapContents LegacyMapContents
---@field MapCanvas ForeverMapCanvas the views of our own on the world map (UI/MapCanvas.lua)
---@field RefreshMap fun()
---@field OpenMapMenu fun()
---@field GamepadUI fun(): boolean whether the gamepad interface is on
---@field ContextMenu fun(owner: Frame, generator: function): any a menu, or a line under the gamepad interface
---@field Navigate fun(uiMapID: number, x: number, y: number, title: string)
---@field NavigateHint fun(): string
---@field DungeonLevelRange fun(instance: number): number?, number?, string? recommended range from installed AtlasLoot
---@field Guide fun(uiMapID: number, x: number, y: number, title: string): boolean, ("combat"|"unavailable")?
---@field SafeCall fun(label: string, fn: function, ...: any): boolean, ... run fn as pcall does (Core/SafeCall.lua)
---@field RecordError fun(label: string, message: any, stack?: string) keep an error caught another way, for the report
---@field CaughtErrors fun(): ForeverCaughtError[] this session's caught errors, oldest first, as copies
---@field AttachErrorJournal fun(store: table) keep the journal in the saved table, so a /reload keeps it
---@field Log fun(level: string, topic: string, message: any, ...: any) one line in the shared ring (Core/Log.lua)
---@field LogLines fun(count?: integer): string[] the newest log lines, oldest first, as copies (Core/Log.lua)
---@field AttachLog fun(store: table) keep the log ring in the saved table, so a /reload keeps it
---@field DebugCommand fun(argument?: string): boolean `/forever debug`: toggle, pin, off or show (Core/Log.lua)
---@field CutText fun(text: string, limit: integer): string text cut to `limit` bytes on a UTF-8 boundary, ending "..."
---@field Report ForeverReportModule the report window (UI/Report.lua)
---@field AuditLines fun(): string[] what /lf audit prints (Core/Report.lua)
---@field ReportLines fun(): string[] Legacy Forever's own lines in the report (Core/Report.lua)
---@field PeerStats ForeverPeerStatsNamespace
---@field LeaderboardsData ForeverLeaderboardsData the shared leaderboards' data half (Core/LeaderboardsData.lua)
---@field Leaderboards ForeverLeaderboardsAPI the shared Forever Leaderboards window (UI/Leaderboards.lua)
---@field Stats LFStats shared activity rows: sender and receiver (Core/Stats.lua)
---@field ActivityStats fun(): LFActivityRecord[] this character's observed flight paths, as rows (Core/API.lua)
local ns = addon
local L = ns.L
ns.ReportTitle = L["Legacy Forever report"]

ns.TITLE = "Legacy Forever"
-- The Legacy shield: map pins, the map button, menu entries and the zone-completion count all wear it.
ns.POINTS_ICON = "UI-Legacy-Points-icon-c60"
-- One sentence for the chat line after an update (WhatsNew.lua): the headline of the release this ships in.
ns.WHATS_NEW = L["With a gamepad, Legacy's menus no longer cause a blocked-action error."]

---@param msg string
function ns.Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99" .. ns.TITLE .. "|r " .. msg)
end

-- With the gamepad interface on, Blizzard's gamepad frame manager takes every menu that shows into its focus in the
-- same call, writing its state under the taint of whoever opened the menu. The next secure reader then has its
-- protected SetPreferredGamepadInteractTarget call refused and blames Legacy Forever. No addon code can open a
-- Blizzard menu untainted, so under the gamepad interface Legacy opens none (#339).
---@return boolean
function ns.GamepadUI()
	local enabled = InputUtil and InputUtil.IsGamepadUIEnabled
	return enabled ~= nil and enabled() == true
end

-- A Blizzard context menu from our own code: under the gamepad interface it would taint the gamepad focus, so the
-- player gets a line instead and no menu opens.
---@param owner Frame
---@param generator fun(owner: Frame, root: any)
---@return any
function ns.ContextMenu(owner, generator)
	if ns.GamepadUI() then
		UIErrorsFrame:AddMessage(L["This menu needs mouse and keyboard."], 1, 1, 0)
		return nil
	end
	return MenuUtil.CreateContextMenu(owner, generator)
end

-- /lf audit: the same lines /lf report shows (Core/Report.lua), in chat.
local function Audit()
	for _, line in ipairs(ns.AuditLines()) do
		ns.Print(line)
	end
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

-- The options live in the map's Legacy menu, so the slash command and the compartment entry both open it.
local function OpenMenu()
	if not (WorldMapFrame and WorldMapFrame:IsShown()) then
		C_Map.OpenWorldMap()
	end
	ns.OpenMapMenu()
end

SLASH_LEGACYFOREVER1 = "/lf"
SLASH_LEGACYFOREVER2 = "/legacyforever"
local function Slash(msg)
	local command = strtrim(msg or ""):lower()
	if ns.Report and ns.Report.Command and ns.Report.Command(command) then
		return
	end
	-- Lenient: "criteria 684", "criteria <684>" and a bare "684" all work.
	local achievementID = (command:find("^criteria") or command:find("^%d+$")) and tonumber(command:match("%d+"))
	if command == "audit" then
		Audit()
	elseif achievementID then
		Criteria(achievementID)
	elseif command:find("^criteria") then
		ns.Print("usage: /lf criteria 684")
	elseif command == "leaderboard" or command == "stats" then
		ns.Stats.Open()
	elseif command == "share on" or command == "share off" then
		ns.Saved.Set("statsShare", command == "share on")
	elseif command == "" then
		OpenMenu()
	else
		ns.Print(L["/lf - open the world map and its Legacy menu"])
		ns.Print(L["/lf report - show a report to copy into a bug report"])
		ns.Print(L["/lf issue - report a bug or request a feature with a ready-made GitHub issue link"])
		ns.Print(L["/lf audit - check the bundled data against the game"])
		ns.Print(L["/lf criteria 684 - list what the game reports for one achievement"])
		ns.Print(L["/lf leaderboard - open Forever Leaderboards on this addon's tab"])
		ns.Print(L["/lf share on|off - share flight-path totals, keeping your history"])
	end
end
SlashCmdList.LEGACYFOREVER = function(msg)
	ns.SafeCall("slash command", Slash, msg)
end

LegacyForever_OnAddonCompartmentClick = OpenMenu

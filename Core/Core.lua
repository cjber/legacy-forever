local addonName, addon = ...

if addon.broken then
	return
end

---@class LegacyForeverNamespace
---@field Credits ForeverCreditsData the player credits Data/Credits.lua generates for the shared Thanks page
---@field core ForeverCoreAddon the addon's own ForeverCore services: journal, log, report and map canvas
---@field broken? boolean set when an installed ForeverCore is too old, so the addon's files stop
---@field ReportTitle string the localized title shown by the shared report window
---@field TITLE string
---@field POINTS_ICON string
---@field WHATS_NEW string the headline of the release WHATS_NEW_VERSION names
---@field WHATS_NEW_VERSION string the newest release in CHANGELOG.md with a bold headline
---@field CompanionHint fun(): string?
---@field WhatsNew fun()
---@field ForeverRequire fun(ready: boolean): boolean
---@field L table<string, string>
---@field Art LegacyArt
---@field Saved LegacySaved
---@field Data LegacyData
---@field Explore LegacyExplore
---@field Model LegacyModel
---@field Live LegacyLive
---@field Quests LegacyQuests
---@field FamilyDB fun(): LegacySavedVariables
---@field Tracker LegacyTracker
---@field ZoneCompletion LegacyZoneCompletion
---@field Completion LegacyCompletion
---@field MapContents LegacyMapContents
---@field Shading LegacyShading
---@field RefreshMap fun()
---@field OpenMapMenu fun()
---@field GamepadUI fun(): boolean whether the gamepad interface is on
---@field Navigate fun(uiMapID: number, x: number, y: number, title: string): boolean
---@field NavigateOutline fun(uiMapID: number, area: LegacyOutlineArea, x: number, y: number)
---@field NavigateHint fun(): string
---@field DungeonLevelRange fun(instance: number): number?, number?, string? recommended range from installed AtlasLoot
---@field Guide fun(uiMapID: number, x: number, y: number, title: string): boolean, ("combat"|"unavailable")?
---@field AuditLines fun(): string[] what /lf audit prints (Core/Report.lua)
---@field ReportLines fun(): string[] Legacy Forever's own lines in the report (Core/Report.lua)
---@field ActivityStats fun(): LFActivityRecord[] this character's observed flight paths, as rows (Core/API.lua)
local ns = addon
local L = ns.L
ns.ReportTitle = L["Legacy Forever report"]

-- The addon's own ForeverCore services: the error journal, the debug log, the report window and the map canvas. The
-- report's own lines are read when the window opens, after Core/Report.lua has defined them.
ns.core = ForeverCore.Register(addonName, {
	title = ns.ReportTitle,
	lines = function()
		return ns.ReportLines()
	end,
})

-- Hands the generated player credits to the shared Thanks page (WFA-31). An older core has no Credits module, and the
-- addon loads as before.
if type(ForeverCore.Credits) == "table" then
	ns.core.SafeCall("credits", ForeverCore.Credits.Register, "Legacy Forever", ns.Credits)
end

ns.TITLE = "Legacy Forever"
-- The Legacy shield: map pins, the map button, menu entries and the zone-completion count all wear it.
ns.POINTS_ICON = "UI-Legacy-Points-icon-c60"
-- One sentence for the chat line after an update (WhatsNew.lua): the newest release's headline, and the version whose
-- release carries it. A core sync's maintenance entry has no headline, so this stays on the release before it and
-- WhatsNew stays quiet for the maintenance version while still remembering it.
ns.WHATS_NEW_VERSION = "2.3.3"
ns.WHATS_NEW = L["The players who helped are on the Thanks page."]

---@param msg string
function ns.Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99" .. ns.TITLE .. "|r " .. msg)
end

-- With the gamepad interface on, Blizzard's gamepad frame manager takes every Blizzard menu that shows into its focus
-- in the same call, writing its state under the taint of whoever opened the menu. The next secure reader then has its
-- protected SetPreferredGamepadInteractTarget call refused and blames Legacy Forever. ForeverCore's own context menu
-- draws in frames of its own and is safe; the map button's stock dropdown is not, so under the gamepad interface it
-- shows a line instead of opening (#339).
---@return boolean
function ns.GamepadUI()
	local enabled = InputUtil and InputUtil.IsGamepadUIEnabled
	return enabled ~= nil and enabled() == true
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

-- The options live in the map's Legacy menu, so the slash command and the compartment entry both open it. The map
-- opens through the shared secure opener: the client refuses its own C_Map.OpenWorldMap from addon code, so a map
-- that did not open leaves the menu closed with it (cjber/forever-core#333).
local function OpenMenu()
	if not (WorldMapFrame and WorldMapFrame:IsShown()) and not ForeverCore.OpenMap() then
		return
	end
	ns.OpenMapMenu()
end

SLASH_LEGACYFOREVER1 = "/lf"
SLASH_LEGACYFOREVER2 = "/legacyforever"
local function Slash(msg)
	local command = strtrim(msg or ""):lower()
	if ns.core.Report and ns.core.Report.Command and ns.core.Report.Command(command) then
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
	elseif command == "" then
		OpenMenu()
	else
		ns.Print(L["/lf - open the world map and its Legacy menu"])
		ns.Print(L["/lf report - show a report to copy into a bug report"])
		ns.Print(L["/lf issue - report a bug or request a feature with a ready-made GitHub issue link"])
		ns.Print(L["/lf audit - check the bundled data against the game"])
		ns.Print(L["/lf criteria 684 - list what the game reports for one achievement"])
	end
end
SlashCmdList.LEGACYFOREVER = function(msg)
	ns.core.SafeCall("slash command", Slash, msg)
end

LegacyForever_OnAddonCompartmentClick = OpenMenu

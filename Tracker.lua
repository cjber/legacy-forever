local _, ns = ...

-- Forever's ruleset refuses achievement tracking (C_ContentTracking reports
-- Untrackable), so tracked challenges get their own section in Blizzard's
-- objective tracker, laid out like its achievement section. Entries are whole
-- challenges or one zone's share of one (Model.ZoneKey).
local Tracker = {}
ns.Tracker = Tracker

-- Matches Blizzard's achievement section: five steps, then "...".
local MAX_STEPS = 5

local function Tracked()
	return ns.SavedTable("tracked")
end

local function IndexOf(list, value)
	for index, item in ipairs(list) do
		if item == value then
			return index
		end
	end
end

function Tracker.IsTracked(key)
	return IndexOf(Tracked(), key) ~= nil
end

local module

function Tracker.Refresh()
	if module then
		module:MarkDirty()
	end
end

function Tracker.Toggle(key)
	local tracked = Tracked()
	local index = IndexOf(tracked, key)
	if index then
		table.remove(tracked, index)
	else
		tracked[#tracked + 1] = key
	end
	Tracker.Refresh()
end

-- Everything tracked under a challenge: the whole challenge and every zone share of it.
local function StopTracking(challenge)
	local tracked, visible = Tracked(), ns.Live.Visible()
	for index = #tracked, 1, -1 do
		if ns.Model.TrackedChallenge(ns.Data, tracked[index], visible) == challenge then
			table.remove(tracked, index)
		end
	end
	Tracker.Refresh()
end

local ModuleMixin = { headerText = "Legacy" }

function ModuleMixin:OnBlockHeaderClick(block, mouseButton)
	if mouseButton ~= "RightButton" then
		ns.Live.ShowInLegacyPanel(block.id)
		return
	end
	MenuUtil.CreateContextMenu(self:GetContextMenuParent(), function(_, root)
		root:SetTag("MENU_LEGACY_HERE_TRACKER", block)
		root:CreateTitle(ns.Live.Name(block.id))
		root:CreateButton("Open in the Legacy panel", function()
			ns.Live.ShowInLegacyPanel(block.id)
		end)
		root:CreateButton("Stop tracking", function()
			StopTracking(block.id)
		end)
	end)
end

-- The challenge as the block header, then quest-style lines: "12/20 Reach level 20",
-- "0/12 Explore Felwood". A challenge the game no longer lists (earned, or not this
-- character's variant) is skipped but stays tracked.
function ModuleMixin:LayoutContents()
	local blocks = ns.Model.TrackedBlocks(ns.Data, Tracked(), ns.Live.Visible(), ns.Live.Criteria, ns.Live.Name)
	for _, tracked in ipairs(blocks) do
		local block = self:GetBlock(tracked.challenge)
		block:SetHeader(ns.Live.Name(tracked.challenge))
		for index, line in ipairs(tracked.lines) do
			if index > MAX_STEPS then
				block:AddObjective("Extra", "...", nil, nil, OBJECTIVE_DASH_STYLE_HIDE)
				break
			end
			block:AddObjective(index, line.detail and (line.detail .. " " .. line.text) or line.text)
		end
		if not self:LayoutBlock(block) then
			return
		end
	end
end

-- Attaching is a no-op until Blizzard's manager has added ObjectiveTrackerFrame as a
-- container. Its Init is scheduled as a closure over the original function, so hooking
-- Init never fires; AddContainer is looked up on the table and can be hooked.
-- uiOrder puts our sections at the top, wherever the tracker is placed.
local modules = {}

local function Attach(trackerModule)
	ObjectiveTrackerManager:SetModuleContainer(trackerModule, ObjectiveTrackerFrame)
end

local function OnContainerAdded(_, container)
	if container == ObjectiveTrackerFrame then
		for _, trackerModule in ipairs(modules) do
			Attach(trackerModule)
		end
	end
end

local function IsAttached(trackerModule)
	return ObjectiveTrackerManager:GetContainerForModule(trackerModule) ~= nil
end

function Tracker.IsAttached()
	return module ~= nil and IsAttached(module)
end

function Tracker.Count()
	return #Tracked()
end

local function Available()
	return ObjectiveTrackerManager and ObjectiveTrackerFrame
end

-- A section of our own in the objective tracker, laid out by `mixin`. Returns nil
-- when the tracker isn't available (Register reports that once).
function Tracker.AddModule(name, mixin, uiOrder)
	if not Available() then
		return nil
	end
	local trackerModule = CreateFrame("Frame", name, UIParent, "ObjectiveTrackerModuleTemplate")
	Mixin(trackerModule, mixin)
	trackerModule:SetHeader(mixin.headerText or "")
	trackerModule.uiOrder = uiOrder
	if #modules == 0 then
		hooksecurefunc(ObjectiveTrackerManager, "AddContainer", OnContainerAdded)
	end
	modules[#modules + 1] = trackerModule
	Attach(trackerModule)
	return trackerModule
end

-- The manager adds its container only once both events have fired, so checking any sooner can
-- warn about a section that is about to attach.
local function WarnIfUnattached()
	for _, trackerModule in ipairs(modules) do
		if not IsAttached(trackerModule) then
			ns.Print("couldn't add a section to the objective tracker; please report /lh audit.")
			return
		end
	end
end

local function Register()
	if not Available() then
		ns.Print("the objective tracker isn't available, so tracked challenges can't be shown.")
		return
	end
	module = Tracker.AddModule("LegacyHereObjectiveTracker", ModuleMixin, 0)
	EventUtil.ContinueAfterAllEvents(function()
		C_Timer.After(5, WarnIfUnattached)
	end, "PLAYER_ENTERING_WORLD", "VARIABLES_LOADED")
end

Register()
ns.Live.OnChange(Tracker.Refresh)

-- Run from the repository root: luajit tests/gamepad_menus_spec.lua
-- Under the gamepad interface a Blizzard menu opened from Legacy's own code takes the gamepad focus under Legacy's
-- taint, and the next secure window call then has its protected SetPreferredGamepadInteractTarget refused (#339).
-- These are the menus Legacy opens, the map button, /lf, the Legacy tracker and the zone tracker, and the source
-- guard that keeps a new one from going round the wrapper.
local checks = 0
local function check(condition, label)
	checks = checks + 1
	assert(condition, label)
end
local function noop() end

local function Read(path)
	local file = assert(io.open(path, "rb"), path)
	local text = file:read("*a")
	file:close()
	return text
end

-- The client's menu call, the screen errors and the gamepad check, read at call time by Core/Core.lua.
local menus, errors = {}, {}
_G.MenuUtil = {
	CreateContextMenu = function(owner, generator)
		local menu = { owner = owner, generator = generator }
		menus[#menus + 1] = menu
		return menu
	end,
}
_G.UIErrorsFrame = {
	AddMessage = function(_, text, r, g, b)
		errors[#errors + 1] = { text = text, r = r, g = g, b = b }
	end,
}
local gamepad = false
_G.InputUtil = {
	IsGamepadUIEnabled = function()
		return gamepad
	end,
}

local function Reset()
	menus, errors = {}, {}
end

local function OneErrorLine(text)
	check(#errors == 1, "exactly one line says the menu needs a mouse and keyboard")
	check(errors[1] and errors[1].text == text, "the line says what the menu needs")
	check(errors[1] and errors[1].r == 1 and errors[1].g == 1 and errors[1].b == 0, "in the client's error colour")
end

--[[ Core/Core.lua: the wrapper every menu of ours goes through ]]

_G.SlashCmdList = {}
local ns = {}
assert(loadfile("Locales/enUS.lua"))("LegacyForever", ns)
assert(loadfile("Core/Core.lua"))("LegacyForever", ns)
local line = ns.L["This menu needs mouse and keyboard."]
check(line ~= "", "the line has an English phrase")

local input = _G.InputUtil
_G.InputUtil = nil
check(ns.GamepadUI() == false, "a client without InputUtil reports the gamepad interface off")
_G.InputUtil = input

gamepad = true
Reset()
local owner, generator = {}, noop
check(ns.ContextMenu(owner, generator) == nil, "the wrapper opens no menu under the gamepad interface")
check(#menus == 0, "and gives the client's menu call nothing")
OneErrorLine(line)

gamepad = false
Reset()
local menu = ns.ContextMenu(owner, generator)
check(
	#menus == 1 and menus[1].owner == owner and menus[1].generator == generator,
	"the menu opens with its owner and generator"
)
check(menu == menus[1] and #errors == 0, "the wrapper returns the client's menu and says nothing")

--[[ The map button and /lf: their own OpenMenu, on the shared map harness ]]

local Kit = dofile("tests/legacy_map_kit.lua")
Kit.Install(_G)
local attach
_G.EventUtil = {
	ContinueOnAddOnLoaded = function(addon, callback)
		assert(addon == "Blizzard_WorldMap")
		attach = callback
	end,
}
_G.REPUTATION, _G.WHITE_FONT_COLOR, _G.Enum = "Reputation", {}, {}
ns.Art = { Fit = noop }
ns.Live = {
	Name = function()
		return "Defender of Elwynn"
	end,
	Points = function()
		return nil
	end,
}
ns.MapContents = {
	Drawn = function()
		return { badges = {}, pins = {} }
	end,
	Objectives = function()
		return {}, 0
	end,
	IsExploration = function()
		return false
	end,
	AreaAt = function()
		return nil
	end,
}
ns.Completion = { AddSummary = noop, AddMenu = noop }
ns.NavigateHint = function()
	return "Click to travel there."
end
ns.CompanionHint = function()
	return nil
end
ns.Navigate = noop
ns.ZoneCompletion = { OnChange = noop }
ns.Saved = {
	Get = function()
		return true
	end,
	Set = noop,
	OnChange = noop,
}

assert(loadfile("UI/MapCanvas.lua"))("LegacyForever", ns)
assert(loadfile("UI/Map.lua"))("LegacyForever", ns)
check(attach ~= nil, "UI/Map.lua waits for the world map to load")
attach()
local button = Kit.Made("LegacyForeverMapButtonTemplate")[1]
check(button ~= nil, "the map button is made")

gamepad = false
Reset()
button:OpenMenu()
check(button.opened == true, "with the gamepad interface off the map button opens its menu")
check(#errors == 0, "and says nothing")
button.opened = nil
Reset()
ns.OpenMapMenu()
check(button.opened == true, "/lf opens the map button's menu with the gamepad interface off")
check(#errors == 0, "and says nothing")

gamepad = true
Reset()
button.opened = nil
button:OpenMenu()
check(button.opened == nil, "the map button opens no menu under the gamepad interface")
OneErrorLine(line)
Reset()
button.opened = nil
ns.OpenMapMenu()
check(button.opened == nil, "/lf opens no menu under the gamepad interface")
OneErrorLine(line)

--[[ The Legacy tracker and the zone tracker: their block header right-clicks ]]

local function BaseNamespace()
	return { L = ns.L, GamepadUI = ns.GamepadUI, ContextMenu = ns.ContextMenu }
end

local function Frame(kind, name)
	local frame = { kind = kind, name = name }
	frame.SetHeader = noop
	frame.MarkDirty = noop
	frame.GetContextMenuParent = function(self)
		return self
	end
	return frame
end

local trackerModules = {}
local trackerEnv = setmetatable({
	ObjectiveTrackerFrame = {},
	ObjectiveTrackerManager = {},
	CreateFrame = function(kind, name)
		local frame = Frame(kind, name)
		if name then
			trackerModules[#trackerModules + 1] = frame
		end
		return frame
	end,
	Mixin = function(target, mixin)
		for key, value in pairs(mixin) do
			target[key] = value
		end
	end,
	EventUtil = { ContinueAfterAllEvents = noop },
	C_Timer = { After = noop },
	hooksecurefunc = noop,
}, { __index = _G })
trackerEnv._G = trackerEnv

local trackerNs = BaseNamespace()
trackerNs.SavedTable = function()
	return {}
end
trackerNs.Model = {
	TrackedBlocks = function()
		return {}
	end,
}
trackerNs.Live = {
	OnChange = noop,
	Name = function()
		return "Challenge"
	end,
	ShowInLegacyPanel = noop,
	LockPanelEntry = noop,
}
setfenv(assert(loadfile("UI/Tracker.lua")), trackerEnv)("LegacyForever", trackerNs)
local legacyTracker = trackerModules[1]
check(legacyTracker ~= nil, "the Legacy tracker section is made")

local block = { id = 10 }
gamepad = true
Reset()
legacyTracker:OnBlockHeaderClick(block, "RightButton")
check(#menus == 0, "the Legacy tracker opens no menu under the gamepad interface")
OneErrorLine(line)
gamepad = false
Reset()
legacyTracker:OnBlockHeaderClick(block, "RightButton")
check(#menus == 1 and menus[1].owner == legacyTracker, "the Legacy tracker opens its menu on the tracker")
check(#errors == 0, "and says nothing")

local completionModule
local completionEnv = setmetatable({
	DUNGEONS = "Dungeons",
	RAIDS = "Raids",
	QUESTS_LABEL = "Quests",
	CreateFrame = function(kind, name, parent, template)
		local frame = { kind = kind, name = name, parent = parent }
		frame.SetHeight = noop
		frame.SetPoint = noop
		frame.Show = noop
		frame.SetShown = noop
		if template == "ObjectiveTrackerProgressBarTemplate" then
			frame.Bar = { ClearAllPoints = noop, SetPoint = noop }
		end
		return frame
	end,
	EventUtil = { ContinueOnAddOnLoaded = noop },
	AlertFrame = {
		AddQueuedAlertFrameSubSystem = function()
			return { AddAlert = noop }
		end,
	},
}, { __index = _G })
completionEnv._G = completionEnv

local completionNs = BaseNamespace()
completionNs.POINTS_ICON = ns.POINTS_ICON
completionNs.Data = {}
completionNs.Art = {
	Markup = function()
		return ""
	end,
}
completionNs.Model = {
	COMPLETION_CATEGORIES = { "areas" },
	ZoneObjectives = function()
		return {}
	end,
}
completionNs.ZoneCompletion = {
	IsShown = function()
		return true
	end,
	IsCounted = function()
		return true
	end,
	Of = function()
		return {}
	end,
	Corner = function()
		return { point = "TOPLEFT", x = 0, y = 0 }
	end,
	OnChange = noop,
	OnComplete = noop,
}
completionNs.Saved = {
	Get = function()
		return true
	end,
	Set = noop,
}
completionNs.Live = {
	Visible = function()
		return {}
	end,
	Criteria = noop,
	CurrentZone = noop,
	ContinentOf = noop,
}
completionNs.Family = {
	Hint = function()
		return false
	end,
}
completionNs.FamilyDB = function()
	return {}
end
completionNs.Quests = {
	Status = function()
		return "ready"
	end,
}
completionNs.Tracker = {
	AddModule = function(name, mixin, uiOrder)
		local module = { name = name, uiOrder = uiOrder, Header = {} }
		for key, value in pairs(mixin) do
			module[key] = value
		end
		module.GetContextMenuParent = function(self)
			return self
		end
		module.MarkDirty = noop
		module.SetCollapsed = noop
		completionModule = module
		return module
	end,
}
setfenv(assert(loadfile("UI/Completion.lua")), completionEnv)("LegacyForever", completionNs)
check(completionModule ~= nil, "the zone tracker section is made")

gamepad = true
Reset()
completionModule:OnBlockHeaderClick(block, "RightButton")
check(#menus == 0, "the zone tracker opens no menu under the gamepad interface")
OneErrorLine(line)
gamepad = false
Reset()
completionModule:OnBlockHeaderClick(block, "RightButton")
check(#menus == 1 and menus[1].owner == completionModule, "the zone tracker opens its menu on the tracker")
check(#errors == 0, "and says nothing")

--[[ The source guard: the wrapper is the only door to a context menu, and the map button wraps its own OpenMenu ]]

local function AddonFiles()
	local files = {}
	for entry in Read("LegacyForever.toc"):gmatch("[^\r\n]+") do
		local path = entry:gsub("\\", "/"):match("^([^#].-%.lua)%s*$")
		if path then
			files[#files + 1] = path
		end
	end
	return files
end

-- A comment is not a call.
local function Code(text)
	return text:gsub("%-%-%[%[.-%]%]", ""):gsub("%-%-[^\n]*", "")
end

local menusOutsideCore = {}
for _, path in ipairs(AddonFiles()) do
	if
		path ~= "Core/Core.lua"
		and path ~= "UI/TrackerHost.lua"
		and Code(Read(path)):find("MenuUtil.CreateContextMenu", 1, true)
	then
		menusOutsideCore[#menusOutsideCore + 1] = path
	end
end
check(
	#menusOutsideCore == 0,
	"only Core/Core.lua opens a context menu directly: " .. table.concat(menusOutsideCore, ", ")
)
for _, path in ipairs({ "UI/Completion.lua", "UI/Tracker.lua" }) do
	check(Code(Read(path)):find("ns.ContextMenu(", 1, true) ~= nil, path .. " goes through ns.ContextMenu")
end
local mapSource = Code(Read("UI/Map.lua"))
check(mapSource:find("local open = self.OpenMenu", 1, true) ~= nil, "the map button captures the client's OpenMenu")
check(mapSource:find("self.OpenMenu = function(", 1, true) ~= nil, "and replaces it with the gamepad-aware wrapper")
check(mapSource:find("ns.GamepadUI()", 1, true) ~= nil, "which checks the gamepad interface")

print(("gamepad_menus_spec: %d checks passed"):format(checks))

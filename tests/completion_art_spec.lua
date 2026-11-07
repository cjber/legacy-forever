-- Run from the repository root: luajit tests/completion_art_spec.lua
-- UI/Completion.lua draws the zone's completion in the objective tracker with the tracker's own progress bar
-- (ObjectiveTrackerProgressBarTemplate's caps, fill, blue and centred percent) and one family of world map icons.
-- The world map corner overlay is gone; the continent badges keep their tooltip.
local checks = 0
local function check(condition, label)
	checks = checks + 1
	assert(condition, label)
end

-- Every frame, texture and font string this spec makes records what the addon sets on it.
local function Texture()
	local texture = { points = {} }
	function texture:SetAtlas(atlas, native)
		self.atlas, self.native = atlas, native
	end
	function texture:SetPoint(...)
		self.points[#self.points + 1] = { ... }
	end
	return texture
end

local function FontString(height)
	local fontString = { points = {}, height = height, width = 100 }
	function fontString:SetPoint(...)
		self.points[#self.points + 1] = { ... }
	end
	function fontString:ClearAllPoints()
		self.points = {}
	end
	function fontString:SetText(text)
		self.text = text
	end
	function fontString:GetStringHeight()
		return self.height
	end
	function fontString:GetStringWidth()
		return self.width
	end
	function fontString:SetShown() end
	return fontString
end

local function Frame(kind, name, parent)
	local frame = { kind = kind, name = name, parent = parent, textures = {}, points = {} }
	function frame:CreateTexture()
		local texture = Texture()
		self.textures[#self.textures + 1] = texture
		return texture
	end
	function frame:CreateFontString()
		return FontString(12)
	end
	function frame:SetHeight(height)
		self.height = height
	end
	function frame:SetPoint(...)
		self.points[#self.points + 1] = { ... }
	end
	function frame:ClearAllPoints()
		self.points = {}
	end
	function frame:SetSize(width, height)
		self.width, self.height = width, height
	end
	function frame:GetParent()
		return self.parent
	end
	function frame:SetShown() end
	function frame:Show()
		self.shown = true
	end
	function frame:Hide()
		self.shown = false
	end
	return frame
end

-- The client's ObjectiveTrackerProgressBarTemplate: a frame with the StatusBar and its centred Label, plus the
-- mixin's SetPercent.
local function ProgressBarTemplate()
	local frame = Frame("Frame")
	frame.Bar = Frame("StatusBar", nil, frame)
	frame.Bar.Label = FontString(12)
	function frame.Bar:SetValue(value)
		self.value = value
	end
	function frame:SetPercent(percent)
		self.percent = percent
		self.Bar:SetValue(percent)
		self.Bar.Label:SetText(("%d%%"):format(percent))
	end
	return frame
end

local createdTemplates = {}
CreateFrame = function(kind, name, parent, template)
	if template then
		createdTemplates[#createdTemplates + 1] = template
		local frame = ProgressBarTemplate()
		frame.kind, frame.name, frame.parent = kind, name, parent
		return frame
	end
	return Frame(kind, name, parent)
end

-- The client pieces the file reads while it loads.
DUNGEONS, QUESTS_LABEL = "Dungeons", "Quests"
local function Color(r, g, b)
	return {
		GetRGB = function()
			return r, g, b
		end,
		WrapTextInColorCode = function(_, text)
			return ("|cff%02x%02x%02x%s|r"):format(r * 255, g * 255, b * 255, text)
		end,
	}
end
NORMAL_FONT_COLOR, HIGHLIGHT_FONT_COLOR = Color(1, 0.82, 0), Color(1, 1, 1)
GREEN_FONT_COLOR, GRAY_FONT_COLOR = Color(0, 1, 0), Color(0.5, 0.5, 0.5)
C_Map = {
	GetMapInfo = function()
		return { name = "Ashenvale" }
	end,
}
EventUtil = {
	ContinueOnAddOnLoaded = function(_, callback)
		-- The collapse restore waits for its event; the bar is drawn before it runs.
		assert(type(callback) == "function")
	end,
}

local zones = { isShown = true, result = {} }
zones.result = {
	percent = 47,
	complete = false,
	total = 4,
	areas = { done = 3, total = 4, complete = false, pending = 0, left = {} },
}

local trackerModule
local ns = {
	L = setmetatable({}, {
		__index = function(_, key)
			return key
		end,
	}),
	POINTS_ICON = "UI-Legacy-Points-icon-c60",
	Art = {
		Markup = function(atlas, size)
			return ("|A:%s:%d:%d|t"):format(atlas, size, size)
		end,
	},
	Model = { COMPLETION_CATEGORIES = { "areas" } },
	ZoneCompletion = {
		IsShown = function()
			return zones.isShown
		end,
		IsCounted = function()
			return true
		end,
		Of = function()
			return zones.result
		end,
		OnChange = function() end,
		OnComplete = function() end,
	},
	Saved = {
		Get = function()
			return false
		end,
		Set = function() end,
	},
	Tracker = {
		AddModule = function(name, mixin, uiOrder)
			trackerModule = Frame("Frame", name)
			for key, value in pairs(mixin) do
				trackerModule[key] = value
			end
			trackerModule.uiOrder = uiOrder
			trackerModule.Header = Frame("Frame", name .. "Header")
			trackerModule.Header.MinimizeButton = {}
			function trackerModule:SetHeader() end
			function trackerModule:SetCollapsed() end
			function trackerModule:MarkDirty() end
			return trackerModule
		end,
	},
}
ns.Family = { Hint = function() end, FamilyDB = function() end }
ns.Live = {}
local alerts = {
	AddAlert = function() end,
}
AlertFrame = {
	AddQueuedAlertFrameSubSystem = function()
		return alerts
	end,
}

assert(loadfile("UI/Completion.lua"))("LegacyForever", ns)

--[[ The tracker section's bar: the objective tracker's own, under the header band ]]

check(trackerModule ~= nil, "the zone section is built")
check(trackerModule.uiOrder == -1, "the section sorts above the tracked challenges' blocks")
local progress = trackerModule.Header.Progress
check(progress ~= nil, "the section header holds a progress bar")
check(createdTemplates[1] == "ObjectiveTrackerProgressBarTemplate", "the bar inherits the tracker's own template")
check(progress.height == 15, "the bar keeps the tracker's 15-unit fill")
check(progress.Bar.points[1][1] == "TOPLEFT" and progress.Bar.points[1][4] == 3, "the fill starts inside the caps")
check(progress.Bar.points[2][1] == "BOTTOMRIGHT" and progress.Bar.points[2][4] == -3, "the fill ends inside the caps")
check(
	progress.points[1][1] == "TOPLEFT" and progress.points[1][2] == trackerModule.Header and progress.points[1][5] == -7,
	"the bar sits 7 under the header band"
)
check(progress.points[2][1] == "TOPRIGHT" and progress.points[2][4] == 0, "the caps span the section's width")
check(trackerModule.fromHeaderOffsetY == -(7 + 15 + 3.5 + 6), "the section starts its first line below bar and counts")

-- Drawing fills the bar and puts the percent in the tracker bar's own centred Label.
trackerModule.GetBlock = function()
	return {
		SetHeader = function() end,
		AddObjective = function() end,
	}
end
trackerModule.LayoutBlock = function()
	return true
end
ns.Live.CurrentZone = function()
	return 5
end
trackerModule:LayoutContents()
check(progress.percent == 47 and progress.Bar.value == 47, "the bar fills to the zone's percent")
check(progress.Bar.Label.text == "47%", "the percent reads centred in the bar")
zones.result.percent = nil
trackerModule:LayoutContents()
check(progress.Bar.value == 0 and progress.Bar.Label.text:find("?", 1, true), "no percent yet reads as a question mark")

--[[ One family of world map icons, at native aspect ]]

local function Atlas(key, size)
	local markup = ns.Completion.Icon(key, size)
	return markup:match("|A:([^:]+):")
end
check(Atlas("dungeons", 14) == "questlog-questtypeicon-dungeon", "dungeons wear the quest log's dungeon glyph")
check(Atlas("taxis", 14) == "taxinode_neutral", "flight paths wear the map's neutral flight node")
check(Atlas("quests", 14) == "QuestNormal", "quests wear the map's quest giver")
check(Atlas("raids", 14) == "Raid", "raids wear the map's raid entrance pin")
check(Atlas("legacy", 14) == ns.POINTS_ICON, "Legacy objectives keep the shield, which no pin replaces")
check(Atlas("areas", 14) == "islands-queue-prop-compass", "areas keep the compass, which no pin replaces")
local reputation = ns.Completion.Icon("reputations", 14)
check(reputation:find("Achievement_Reputation_01", 1, true), "reputations keep the handshake icon")

--[[ What the corner overlay left behind ]]

local function Read(path)
	local file = assert(io.open(path, "rb"), path)
	local text = file:read("*a")
	file:close()
	return text
end

local source = Read("UI/Completion.lua")
check(not source:find("LegacyForeverZoneOverlay", 1, true), "the corner overlay mixin is gone")
check(not source:find("mapCollapsed", 1, true), "its collapse state is gone")
check(not source:find("Legacy-Progressbar", 1, true), "the Legacy panel's bar is gone")
local removed = io.open("UI/Completion.xml", "rb")
if removed then
	removed:close()
end
check(removed == nil, "the overlay's XML is gone")

print(("completion_art_spec: %d checks passed"):format(checks))

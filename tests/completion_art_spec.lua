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
	function texture:SetAllPoints()
		self.allPoints = true
	end
	function texture:SetColorTexture(...)
		self.color = { ... }
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
	function fontString:SetShown(shown)
		self.shown = shown
	end
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
	function frame:SetShown(shown)
		self.shown = shown
	end
	function frame:Show()
		self.shown = true
	end
	function frame:Hide()
		self.shown = false
	end
	function frame:SetStatusBarTexture(texture)
		self.statusBarTexture = texture
	end
	function frame:SetMinMaxValues(low, high)
		self.low, self.high = low, high
	end
	function frame:SetValue(value)
		self.value = value
	end
	function frame:SetStatusBarColor(...)
		self.color = { ... }
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

-- The map's canvas and the container it is shown in, as the client sizes them: a 1000 by 700 texture drawn into
-- a 700 by 465 container, so the map opens fitted and centred.
local canvas, container = { width = 1000, height = 700 }, { width = 700, height = 465 }
function canvas:GetWidth()
	return self.width
end
function canvas:GetHeight()
	return self.height
end
function container:GetWidth()
	return self.width
end
function container:GetHeight()
	return self.height
end
local map = { mapID = 5 }
function map:GetMapID()
	return self.mapID
end
function map:GetCanvas()
	return canvas
end
function map:GetCanvasContainer()
	return container
end

-- The zone's own completion data: the area rectangles UI/Map.lua shades, keyed "x:y:width:height" in texture units.
local completion = {
	[5] = { areas = {} },
}
-- A pin per zone, as Model.ZoneObjectives gives them for a placed objective.
local pins = {}
local saved = {}

local trackerModule
local ns = {
	L = setmetatable({}, {
		__index = function(_, key)
			return key
		end,
	}),
	POINTS_ICON = "UI-Legacy-Points-icon-c60",
	Data = { completion = completion },
	Art = {
		Markup = function(atlas, size)
			return ("|A:%s:%d:%d|t"):format(atlas, size, size)
		end,
	},
	Model = {
		COMPLETION_CATEGORIES = { "areas" },
		ZoneObjectives = function(_, uiMapID)
			local groups = {}
			for _, pin in ipairs(pins[uiMapID] or {}) do
				groups[#groups + 1] = {
					objectives = { { entry = { kind = "kill", x = pin.x, y = pin.y } } },
				}
			end
			return groups
		end,
	},
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
		Corner = function()
			return { point = "TOPLEFT", x = 44, y = -18 }
		end,
		OnChange = function() end,
		OnComplete = function() end,
	},
	Saved = {
		Get = function(key)
			return saved[key] == true
		end,
		Set = function(key, value)
			saved[key] = value
		end,
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
ns.FamilyDB = function() end
ns.Live = { Visible = function() end, Criteria = function() end }
local alerts = {
	AddAlert = function() end,
}
AlertFrame = {
	AddQueuedAlertFrameSubSystem = function()
		return alerts
	end,
}
-- The tooltip the corner's hover shows.
local tooltip = {}
GameTooltip = {
	SetOwner = function(_, owner)
		tooltip.owner = owner
	end,
	GetOwner = function()
		return tooltip.owner
	end,
	AddDoubleLine = function() end,
	Show = function()
		tooltip.shown = true
	end,
	Hide = function()
		tooltip.shown, tooltip.owner = false, nil
	end,
}
GameTooltip_SetTitle, GameTooltip_AddInstructionLine, GameTooltip_AddDisabledLine =
	function() end, function() end, function() end
GameTooltip_AddColoredLine = function() end
WHITE_FONT_COLOR = Color(1, 1, 1)

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

--[[ The map corner: the zone's completion in its original look, at the corner the map gives it ]]

local overlay = Frame("Button", "LegacyForeverZoneOverlayTemplate")
overlay.Title, overlay.Counts = FontString(17), FontString(12)
overlay.GetParent = function()
	return map
end
for key, value in pairs(LegacyForeverZoneOverlayMixin) do
	overlay[key] = value
end

LegacyForeverZoneOverlayMixin.OnLoad(overlay)
local cornerBar = overlay.Progress
check(cornerBar.kind == "StatusBar", "the corner holds a progress bar")
check(cornerBar.height == 2, "the bar is the original 2-unit line")
check(cornerBar.statusBarTexture == "Interface\\Buttons\\WHITE8X8", "the line fills with the flat white texture")
check(cornerBar.low == 0 and cornerBar.high == 100, "the line counts percent")
local backing = cornerBar.textures[1]
check(
	backing.allPoints and backing.color[1] == 0 and backing.color[2] == 0 and backing.color[4] == 0.45,
	"a 45% black backing sits under the line"
)
check(
	cornerBar.points[1][1] == "TOPLEFT" and cornerBar.points[1][2] == overlay.Title and cornerBar.points[1][5] == -4,
	"the line sits 4 under the title"
)
check(cornerBar.points[2][1] == "RIGHT", "the line spans the corner's width")

zones.result.percent, zones.result.complete = 47, false
LegacyForeverZoneOverlayMixin.Refresh(overlay)
check(overlay.Title.text == "Ashenvale  47%", "the title names the zone and its percent")
check(cornerBar.value == 47, "the line fills to the percent")
check(cornerBar.color[1] == 1 and cornerBar.color[2] == 0.82, "an unfinished zone keeps the gold")
check(overlay.Counts.text:find("3/4", 1, true), "the counts row reads under the line")
check(overlay.width == 140 and overlay.height == 17 + 4 + 2 + 6 + 12, "the corner sizes to its text")
check(
	overlay.points[1][1] == "TOPLEFT"
		and overlay.points[1][2] == container
		and overlay.points[1][3] == "TOPLEFT"
		and overlay.points[1][4] == 44
		and overlay.points[1][5] == -18,
	"the box sits at the corner the placement gives it"
)
check(overlay.shown, "the corner shows with a zone to draw")

LegacyForeverZoneOverlayMixin.OnClick(overlay)
check(saved.mapCollapsed == true and overlay.Counts.shown == false, "a click collapses it and keeps the counts hidden")
check(overlay.height == 17 + 4 + 2, "collapsed, the corner is its title and line")
check(cornerBar.value == 47, "the line stays filled when collapsed")
check(tooltip.owner == overlay and tooltip.shown, "its hover shows the tooltip")
LegacyForeverZoneOverlayMixin.OnClick(overlay)
check(saved.mapCollapsed == false and overlay.Counts.shown ~= false, "a second click expands it again")

zones.result.complete = true
LegacyForeverZoneOverlayMixin.Refresh(overlay)
check(cornerBar.color[1] == 0 and cornerBar.color[2] == 1, "a finished zone fills green")
zones.result.complete = false

-- Closing the map hides the overlay without an OnLeave.
LegacyForeverZoneOverlayMixin.OnEnter(overlay)
LegacyForeverZoneOverlayMixin.OnHide(overlay)
check(tooltip.owner == nil and not tooltip.shown, "closing the map hides the corner's tooltip")

--[[ The look's own pieces: the shade and the corner's template ]]

local function Read(path)
	local file = assert(io.open(path, "rb"), path)
	local text = file:read("*a")
	file:close()
	return text
end

local source = Read("UI/Completion.lua")
check(source:find("LegacyForeverZoneOverlayMixin", 1, true) ~= nil, "the corner overlay is back")
check(source:find("mapCollapsed", 1, true) ~= nil, "its collapse state is back")
check(source:find("WHITE8X8", 1, true) ~= nil, "the corner's line is the hand-made bar again")
local xml = Read("UI/Completion.xml")
check(xml:find("media\\Shade", 1, true) ~= nil, "the corner's XML paints the shade")
check(xml:find('alpha="0.6"', 1, true) ~= nil, "the shade keeps its 0.6 alpha")
check(xml:find('inherits="GameFontNormalLarge"', 1, true) ~= nil, "the title keeps GameFontNormalLarge")
check(xml:find('inherits="GameFontHighlight"', 1, true) ~= nil, "the counts keep GameFontHighlight")
local shade = assert(io.open("media/Shade.tga", "rb"))
shade:close()

print(("completion_art_spec: %d checks passed"):format(checks))

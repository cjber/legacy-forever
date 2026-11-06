-- Run from the repository root: luajit tests/completion_art_spec.lua
-- UI/Completion.lua draws the zone's completion with the Legacy panel's own progress bar: its nine-slice recess,
-- its fill and its frame, at the sizes and anchors the client's LegacyProgressBarTemplate uses, and the corner
-- keeps no shade texture of its own.
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

CreateFrame = function(kind, name, parent)
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
		-- The collapse restore and the map attach wait for their events; the bar is drawn before either runs.
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
		AddModule = function(name)
			trackerModule = Frame("Frame", name)
			trackerModule.Header = Frame("Frame", name .. "Header")
			trackerModule.Header.MinimizeButton = {}
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

local function Atlas(texture, name)
	for _, candidate in ipairs(texture.textures) do
		if candidate.atlas == name then
			return candidate
		end
	end
end

--[[ The tracker section's bar: the Legacy panel's own, under the header band ]]

check(trackerModule ~= nil, "the zone section is built")
local bar = trackerModule.Header.Progress
check(bar ~= nil and bar.kind == "StatusBar", "the section header holds a progress bar")
check(bar.statusBarTexture == "Legacy-Progressbar-Fill", "the bar fills with the Legacy panel's own fill")
check(bar.height == 9, "the fill is the Legacy bar's 9 units")
check(bar.low == 0 and bar.high == 100, "the bar still counts percent")
local background = Atlas(bar, "Legacy-Progressbar-BG")
check(background ~= nil, "the bar draws the Legacy recess")
check(background.points[1][1] == "TOPLEFT", "the recess starts at the bar's top")
check(background.points[2][1] == "BOTTOMRIGHT" and background.points[2][3] == -3, "the recess keeps its 3-unit lip")
local frame = Atlas(bar, "Legacy-Progressbar-Frame")
check(frame ~= nil, "the bar draws the Legacy frame")
check(
	frame.points[1][1] == "TOPLEFT" and frame.points[1][2] == -8 and frame.points[1][3] == 7,
	"the frame hangs 8 by 7"
)
check(
	frame.points[2][1] == "BOTTOMRIGHT" and frame.points[2][2] == 8 and frame.points[2][3] == -10,
	"the frame hangs 8 by 10"
)
check(
	bar.points[1][1] == "TOPLEFT" and bar.points[1][2] == trackerModule.Header and bar.points[1][5] == -9,
	"the bar sits below the header band"
)
check(trackerModule.fromHeaderOffsetY == -34, "the section starts its first line below the bar's row")

--[[ The map corner's bar: the same art, in the same place under the title ]]

local map = {}
function map:GetMapID()
	return 5
end
local overlay = Frame("Button", "LegacyForeverZoneOverlayTemplate")
overlay.Title = FontString(17)
overlay.Counts = FontString(12)
overlay.GetParent = function()
	return map
end

LegacyForeverZoneOverlayMixin.OnLoad(overlay)
local corner = overlay.Progress
check(corner ~= nil and corner.statusBarTexture == "Legacy-Progressbar-Fill", "the corner fills with the same fill")
check(Atlas(corner, "Legacy-Progressbar-BG") ~= nil, "the corner draws the Legacy recess")
check(Atlas(corner, "Legacy-Progressbar-Frame") ~= nil, "the corner draws the Legacy frame")
check(
	overlay.Counts.points[1][1] == "TOPLEFT"
		and overlay.Counts.points[1][2] == corner
		and overlay.Counts.points[1][3] == "BOTTOMLEFT"
		and overlay.Counts.points[1][4] == -8
		and overlay.Counts.points[1][5] == -16,
	"the counts read under the frame, lined up with its edge"
)

LegacyForeverZoneOverlayMixin.Refresh(overlay)
check(corner.value == 47, "the corner still fills to the zone's percent")
check(corner.color[1] == 1 and corner.color[2] == 0.82, "an unfinished zone keeps the tracker's gold")
check(overlay.height == 17 + 4 + 26 + 6 + 12, "the corner leaves room for the bar's own 26")
check(corner.points[1][4] == 8 and corner.points[1][5] == -(17 + 4 + 7), "the frame spans the corner under the title")
check(corner.points[2][4] == -8, "the frame spans to the corner's right edge")

zones.result.complete = true
LegacyForeverZoneOverlayMixin.Refresh(overlay)
check(corner.color[1] == 0 and corner.color[2] == 1, "a finished zone fills green, as before")

--[[ What the corner no longer draws ]]

local function Read(path)
	local file = assert(io.open(path, "rb"), path)
	local text = file:read("*a")
	file:close()
	return text
end

local source = Read("UI/Completion.lua")
check(not source:find("WHITE8X8", 1, true), "the hand-made white bar is gone")
check(not source:find("Shade", 1, true), "the corner no longer names a shade texture")
local xml = Read("UI/Completion.xml")
check(not xml:find("Shade", 1, true), "the corner's XML keeps no shade texture")
check(not xml:find("media\\", 1, true) and not xml:find("media/", 1, true), "the corner references no shipped media")
local shade = io.open("media/Shade.tga", "rb")
if shade then
	shade:close()
end
check(shade == nil, "the shade file is gone")

print(("completion_art_spec: %d checks passed"):format(checks))

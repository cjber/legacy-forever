local _, ns = ...

-- Forever's ruleset refuses achievement tracking (C_ContentTracking reports
-- Untrackable), so tracked challenges get their own list with live progress.
local Tracker = {}
ns.Tracker = Tracker

local WIDTH = 250
local ROW_HEIGHT = 16
local LINES_PER_CHALLENGE = 8

-- Session default is empty; kept across sessions only where SavedVariables load.
local function Tracked()
	LegacyHereDB = LegacyHereDB or {}
	LegacyHereDB.tracked = LegacyHereDB.tracked or {}
	return LegacyHereDB.tracked
end

function Tracker.IsTracked(challenge)
	return tContains(Tracked(), challenge)
end

function Tracker.Toggle(challenge)
	local tracked = Tracked()
	if not tDeleteItem(tracked, challenge) then
		tracked[#tracked + 1] = challenge
	end
	Tracker.Refresh()
end

local frame = CreateFrame("Frame", "LegacyHereTracker", UIParent)
frame:SetSize(WIDTH, ROW_HEIGHT)
frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -90, -280)
frame:SetMovable(true)
frame:SetClampedToScreen(true)
frame:Hide()

local title = CreateFrame("Button", nil, frame)
title:SetPoint("TOPLEFT")
title:SetPoint("TOPRIGHT")
title:SetHeight(ROW_HEIGHT + 4)
title:RegisterForDrag("LeftButton")
title:SetScript("OnDragStart", function()
	frame:StartMoving()
end)
title:SetScript("OnDragStop", function()
	frame:StopMovingOrSizing()
end)
title:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip_SetTitle(GameTooltip, ns.TITLE)
	GameTooltip_AddInstructionLine(GameTooltip, "Drag to move.")
	GameTooltip:Show()
end)
title:SetScript("OnLeave", GameTooltip_Hide)
local titleText = title:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
titleText:SetPoint("LEFT")
titleText:SetText(CreateAtlasMarkup("UI-Legacy-Points-icon-c60", 12, 17) .. " Legacy")

local function OnHeaderClick(self, button)
	if button == "RightButton" then
		Tracker.Toggle(self.challenge)
	else
		ns.Live.ShowInLegacyPanel(self.challenge)
	end
end

local function OnHeaderEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip_SetTitle(GameTooltip, ns.Live.Name(self.challenge))
	local points = ns.Live.Points(self.challenge)
	if points then
		GameTooltip_AddNormalLine(GameTooltip, ("%d Legacy |4point:points;"):format(points))
	end
	GameTooltip_AddInstructionLine(GameTooltip, "Click to open in the Legacy panel. Right-click to stop tracking.")
	GameTooltip:Show()
end

-- Rows are reused across refreshes: a header row is a clickable challenge name,
-- a step row is indented text with its progress on the right.
local rows = {}

local function Row(index)
	local row = rows[index]
	if not row then
		row = CreateFrame("Button", nil, frame)
		row:SetHeight(ROW_HEIGHT)
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		row.Text = row:CreateFontString(nil, "OVERLAY")
		row.Text:SetJustifyH("LEFT")
		row.Text:SetWordWrap(false)
		row.Detail = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.Detail:SetPoint("RIGHT")
		row.Text:SetPoint("RIGHT", row.Detail, "LEFT", -4, 0)
		rows[index] = row
	end
	row:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -(ROW_HEIGHT + 4) - (index - 1) * ROW_HEIGHT)
	row:SetPoint("RIGHT", frame, "RIGHT")
	row:Show()
	return row
end

local function SetHeader(row, challenge)
	row.challenge = challenge
	row.Text:SetFontObject("GameFontNormal")
	row.Text:SetPoint("LEFT", 0, 0)
	row.Text:SetText(ns.Live.Name(challenge))
	row.Detail:SetText("")
	row:SetScript("OnClick", OnHeaderClick)
	row:SetScript("OnEnter", OnHeaderEnter)
	row:SetScript("OnLeave", GameTooltip_Hide)
	row:EnableMouse(true)
end

local function SetStep(row, text, detail)
	row.Text:SetFontObject("GameFontHighlightSmall")
	row.Text:SetPoint("LEFT", 10, 0)
	row.Text:SetText("- " .. text)
	row.Detail:SetText(detail or "")
	row:SetScript("OnClick", nil)
	row:SetScript("OnEnter", nil)
	row:SetScript("OnLeave", nil)
	row:EnableMouse(false)
end

-- A challenge the game no longer lists (earned, or not this character's variant)
-- drops out of view but stays tracked, so it returns if the list changes back.
function Tracker.Refresh()
	local visible = ns.Live.Visible()
	local count = 0
	for _, challenge in ipairs(Tracked()) do
		if visible[challenge] then
			count = count + 1
			SetHeader(Row(count), challenge)
			local lines = ns.Model.TrackerLines(challenge, ns.Live.Criteria)
			for i = 1, math.min(#lines, LINES_PER_CHALLENGE) do
				count = count + 1
				SetStep(Row(count), lines[i].text, lines[i].detail)
			end
			if #lines > LINES_PER_CHALLENGE then
				count = count + 1
				SetStep(Row(count), ("%d more in the Legacy panel"):format(#lines - LINES_PER_CHALLENGE))
			end
		end
	end
	for i = count + 1, #rows do
		rows[i]:Hide()
	end
	frame:SetHeight(ROW_HEIGHT + 4 + count * ROW_HEIGHT)
	frame:SetShown(count > 0)
end

ns.Live.OnChange(Tracker.Refresh)

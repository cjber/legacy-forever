local _, ns = ...

ns.TITLE = "Legacy Here"

function ns.Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99" .. ns.TITLE .. "|r " .. msg)
end

-- Compares the bundled data with what the game reports, so a data problem shows
-- up as a count and a list of IDs rather than as a silently missing pin.
local function Audit()
	local data = ns.Data
	local version, build = GetBuildInfo()
	ns.Print(("data from build %s, client build %s.%s"):format(data.build, version, build))

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
end

SLASH_LEGACYHERE1 = "/lh"
SLASH_LEGACYHERE2 = "/legacyhere"
SlashCmdList.LEGACYHERE = function(msg)
	local command = strtrim(msg or ""):lower()
	if command == "audit" then
		Audit()
	else
		ns.Print("open the world map and use the Legacy button in its top-right corner.")
		ns.Print("/lh audit - check the bundled data against the game")
	end
end

function LegacyHere_OnAddonCompartmentClick()
	ToggleWorldMap()
end

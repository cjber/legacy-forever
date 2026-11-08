-- luacheck: read globals scenario
-- The zone completion section stays in the tracker when the column below the quests is already full: it takes the
-- first slot (uiOrder -5), so the section attached before it gets what is left instead of the zone vanishing whole.
scenario("a full tracker column still shows the zone completion section", function(sim)
	sim:loadBlizzard("Blizzard_FrameXML/Mainline/AlertFrames.lua")
	sim:loadBlizzard("Blizzard_FrameXML/Mainline/AlertFrames.xml")
	sim.G.GetCategoryList = function()
		return {}
	end
	sim.gaps["Legacy fixture GetCategoryList"] = true
	sim.world.player.map = 1439
	sim.world.maps[1439] = { name = "Darkshore", parent = 1414, mapType = 3 }
	sim.world.maps[1414] = { name = "Kalimdor", parent = 947, mapType = 2 }
	-- The sim sizes a font string with two anchor points from its rect, which can come out negative; the client
	-- answers the text's own height, which is what the tracker's layout arithmetic needs.
	sim.widgets.metas.FontString.__index.GetHeight = function(self)
		return self:GetStringHeight()
	end
	sim:login({ savedVariables = { LegacyForeverDB = { zoneCompletion = { tracker = true } } } })
	local G = sim.G
	local tracker = G.ObjectiveTrackerFrame
	tracker:Show()
	tracker:SetPoint("TOPRIGHT", G.UIParent, "TOPRIGHT", 0, 0)
	tracker:SetHeight(300)
	-- An earlier Forever section, as Adventure Guide Forever's at -4, wanting more than the room it has.
	local create = G.CreateFrame
	local earlier = create("Frame", "EarlierTrackerSection", G.UIParent)
	earlier.uiOrder = -4
	function earlier:Update(available)
		self.available = available
		self.used = math.min(300, available)
	end
	function earlier:GetContentsHeight()
		return self.used or 0
	end
	function earlier:IsTruncated()
		return (self.used or 0) < 300
	end
	G.ForeverTrackerHost.Attach(earlier)
	sim:advance(2)
	local zone = G.LegacyForeverZoneTracker
	assert(zone:IsShown(), "the zone completion section draws with the column full")
	assert(zone.Header.Text:GetText() == "Darkshore", "the section header names the zone")
	assert(zone.availableHeight > 0, "the zone section is laid out before the earlier one")
	assert(earlier.used > 0, "the earlier section still shows the room left below the zone section")
end)

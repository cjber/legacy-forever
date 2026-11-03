-- luacheck: read globals scenario ADDON
-- Player commands over the TOC-loaded addon, including an old save, Questie, combat and gamepad input.
scenario("flight-path sharing keeps personal history", { stubs = { Questie = {} } }, function(sim)
	sim.impl["C_GameRules.GetCurrentGameModeRecordID"] = function()
		return 1
	end
	sim.impl["C_GameRules.IsHardcoreActive"] = function()
		return false
	end
	-- FrameXML is outside the simulator's default boot. Load its real alert container explicitly.
	sim:loadBlizzard("Blizzard_FrameXML/Mainline/AlertFrames.lua")
	sim:loadBlizzard("Blizzard_FrameXML/Mainline/AlertFrames.xml")
	-- The client API documentation omits this legacy achievement API. This fixture has no achievements.
	sim.G.GetCategoryList = function()
		return {}
	end
	sim.gaps["Legacy fixture GetCategoryList"] = true
	local guid = sim.world.player.guid
	sim:login({
		savedVariables = {
			LegacyForeverDB = {
				flightPaths = { [guid] = { known = { [10] = true }, seen = { [10] = 1000 }, continents = {} } },
			},
		},
	})
	local api = assert(sim.G.LegacyForever.API)
	assert(api.Leaderboard(0).rows[1].value == 1, "old personal history survives login")
	sim:input(function()
		sim.G.SlashCmdList.LEGACYFOREVER("share off")
	end)
	assert(not api.Leaderboard().sharing, "the player can stop sharing")
	assert(api.Leaderboard().rows[1].value == 1, "opting out retains the personal total")
	sim:setGamepad(true)
	sim:enterCombat()
	sim:hoverUnit({ name = "Defias Bandit", level = 12, friendly = false })
	sim:input(function()
		sim.G.SlashCmdList.LEGACYFOREVER("leaderboard")
	end)
	sim:gamepadNavigate()
	sim:leaveCombat()
	sim:input(function()
		sim.G.SlashCmdList.LEGACYFOREVER("share on")
	end)
	assert(api.Leaderboard().sharing, "the player can resume sharing")
	assert(sim:savedState().LegacyForeverDB.statsShare == true, "the sharing switch is saved")
	sim:expectNoErrors(ADDON)
end)

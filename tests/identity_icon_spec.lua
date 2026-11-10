-- One client icon for every in-game identity surface: the TOC declares it once, Core reads it once, and the
-- leaderboard tab draws that value. The map button's icon is checked where its frame is driven, in
-- tests/legacy_map_spec.lua.
local TOC = dofile("tests/toc_fields.lua").read("LegacyForever.toc")
local declared = TOC["X-Forever-Icon"]
assert(declared ~= nil and declared ~= "", "the TOC declares ## X-Forever-Icon")

C_AddOns = {
	GetAddOnMetadata = function(name, field)
		return name == "LegacyForever" and TOC[field] or nil
	end,
}
SlashCmdList = {}
CreateFrame = function()
	return { RegisterEvent = function() end, SetScript = function() end }
end
local function noop() end
local function Revisions()
	return 0
end
local function Rows()
	return {}
end
local boards = {}
ForeverCore = {
	Register = function()
		return {
			SafeCall = function(_, fn, ...)
				return fn(...)
			end,
			Report = {},
		}
	end,
	Leaderboards = {
		Register = function(_, key, spec)
			boards[key] = spec
		end,
		Open = noop,
	},
	PeerStats = {
		New = function()
			return {
				Sync = noop,
				Shared = Rows,
				SetEnabled = noop,
				Revision = Revisions,
				Board = Rows,
				WeekBoard = Rows,
			}
		end,
	},
}

local ns = {}
assert(loadfile("Locales/enUS.lua"))("LegacyForever", ns)
ns.Saved = {
	Get = function()
		return true
	end,
	Set = noop,
	OnChange = noop,
}
ns.Live = {
	FlightPathTotal = function()
		return 0, 0
	end,
}
ns.Print = noop
assert(loadfile("Core/Core.lua"))("LegacyForever", ns)
assert(ns.icon == declared, "Core reads the TOC icon once onto the namespace: " .. tostring(ns.icon))

assert(loadfile("Core/Stats.lua"))("LegacyForever", ns)
local board = boards.legacy
assert(board ~= nil, "the shared Forever Leaderboards window has the addon's tab")
assert(board.icon == declared, "the leaderboard tab wears the TOC's identity icon")

print("identity_icon_spec: ok")

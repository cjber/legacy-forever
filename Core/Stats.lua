---@type string, LegacyForeverNamespace
local _, ns = ...

---@class LFStats
local Stats = {}
ns.Stats = Stats

local METRIC = "flight_path_known"
local DEFAULT_LIMIT, MAX_LIMIT = 10, 25

-- Compare the client's actual mode, without guessing names or treating self-found as Ironman.
-- Unknown classification keeps personal history available but cannot send or show peer comparisons.
---@return string?
local function Ruleset()
	if not (C_GameRules and C_GameRules.GetCurrentGameModeRecordID and C_GameRules.IsHardcoreActive) then
		return nil
	end
	local ok, mode = pcall(C_GameRules.GetCurrentGameModeRecordID)
	local hcOK, hardcore = pcall(C_GameRules.IsHardcoreActive)
	if not ok or type(mode) ~= "number" or mode < 1 or mode > 1e9 or mode % 1 ~= 0 then
		return nil
	end
	if not hcOK or type(hardcore) ~= "boolean" then
		return nil
	end
	return ("%d_%d"):format(mode, hardcore and 1 or 0)
end

local function Enabled()
	return ns.Saved.Get("statsShare") and Ruleset() ~= nil
end

-- The old sharedStats cache has no ruleset information. Keep it for downgrade compatibility,
-- but never migrate unclassified peer scores into these comparisons.
local function Peers()
	local guid = UnitGUID("player")
	if not guid then
		return nil
	end
	local db = ns.FamilyDB()
	if type(db.peerStats) ~= "table" then
		db.peerStats = {}
	end
	if type(db.peerStats[guid]) ~= "table" then
		db.peerStats[guid] = {}
	end
	return db.peerStats[guid]
end

local peerStats = ns.PeerStats.New({
	addon = "legacy",
	enabled = Enabled,
	db = Peers,
	metrics = { [METRIC] = { subject = "numeric_pair" } },
	snapshot = function()
		local ruleset = Ruleset()
		local count, observedAt = ns.Live.FlightPathTotal()
		-- An old known set may have no historical timestamp. Do not invent one by polling the clock.
		return ruleset
				and count > 0
				and observedAt > 0
				and { { metric = METRIC, subject = ruleset, value = count, eventUnix = observedAt } }
			or {}
	end,
})

function Stats.Sync()
	peerStats:Sync()
end

function Stats.Shared()
	return peerStats:Shared()
end

---@param enabled boolean
function Stats.SetEnabled(enabled)
	peerStats:SetEnabled(enabled == true)
end

---@class LFFlightLeaderboardRow
---@field rank integer
---@field name string
---@field value integer
---@field eventUnix? integer
---@field self? boolean

---@class LFFlightLeaderboard
---@field metric string
---@field scope string
---@field ruleset? string client mode ID and Hardcore flag
---@field sharing boolean
---@field total integer
---@field rows LFFlightLeaderboardRow[]

---@param limit? integer
---@return LFFlightLeaderboard?
---@return LFReadError?
function Stats.Leaderboard(limit)
	if limit == nil then
		limit = DEFAULT_LIMIT
	elseif type(limit) ~= "number" or limit < 0 or limit % 1 ~= 0 then
		return nil, "invalid"
	end
	limit = math.min(limit, MAX_LIMIT)
	local ruleset = Ruleset()
	local count, observedAt = ns.Live.FlightPathTotal()
	local ranked = peerStats:Board(METRIC, ruleset or "unknown", count, observedAt)
	local rows = {}
	for _, row in ipairs(ranked) do
		if row.rank <= limit or row.self then
			rows[#rows + 1] = {
				rank = row.rank,
				name = row.name,
				value = row.value,
				eventUnix = row.eventUnix,
				self = row.self == true or nil,
			}
		end
	end
	return {
		metric = METRIC,
		scope = "guild_group",
		ruleset = ruleset,
		sharing = Enabled(),
		total = #ranked,
		rows = rows,
	}
end

function Stats.Print()
	local L = ns.L
	local board = Stats.Leaderboard() --[[@as LFFlightLeaderboard]]
	ns.Print(L["Observed flight paths: guild and group"])
	ns.Print(L["Current client ruleset only. Other players' totals are player-reported."])
	for _, row in ipairs(board.rows) do
		local text = row.self and L["%d. %s: %d (you)"] or L["%d. %s: %d (player-reported)"]
		ns.Print(text:format(row.rank, row.name, row.value))
	end
	if not board.ruleset then
		ns.Print(L["Ruleset unavailable. Only your personal record is shown."])
	elseif not board.sharing then
		ns.Print(L["Sharing is off. Only your personal record is shown."])
	elseif board.total == 1 then
		ns.Print(L["No peer totals received. Open a flight master's map to record your known paths."])
	end
end

ns.Saved.OnChange(function(key, value)
	if key == "statsShare" then
		Stats.SetEnabled(value)
	end
end)

-- Defer the snapshot until Live has consumed the taxi event, independent of frame dispatch order.
local events = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "TAXIMAP_OPENED", "TAXI_NODE_STATUS_CHANGED" }) do
	events:RegisterEvent(event)
end
events:SetScript("OnEvent", function(_, event)
	if C_Timer and C_Timer.After then
		C_Timer.After(event == "PLAYER_LOGIN" and 1 or 0, Stats.Sync)
	end
end)

return Stats

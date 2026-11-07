-- Legacy's adapter: actual saved switch, transport and slash handler, with taxi observations supplied by Live.
local checks = 0
local function check(value, label)
	checks = checks + 1
	assert(value, label)
end
local function boot(saved, mode, hardcore, guid)
	local frames, timers, sent, lines = {}, {}, {}, {}
	local count, stamp, now = 3, 1000, 2000
	local env = setmetatable({ SlashCmdList = {} }, { __index = _G })
	env._G = env
	env.GetServerTime = function()
		return now
	end
	env.GetTime = function()
		return now
	end
	env.GetNormalizedRealmName = function()
		return "Home"
	end
	env.UnitName = function()
		return "Me"
	end
	env.UnitClass = function()
		return "Me", "WARRIOR"
	end
	env.UnitGUID = function()
		if guid == false then
			return nil
		end
		return guid or "Player-1"
	end
	env.IsInGuild = function()
		return true
	end
	env.IsInGroup = function()
		return false
	end
	env.IsInRaid = function()
		return false
	end
	env.C_GameRules = {
		GetCurrentGameModeRecordID = function()
			return mode
		end,
		IsHardcoreActive = function()
			return hardcore
		end,
	}
	env.C_Timer = {
		After = function(_, callback)
			timers[#timers + 1] = callback
		end,
	}
	env.C_ChatInfo = {
		SendAddonMessage = function(_, payload, channel)
			sent[#sent + 1] = { payload = payload, channel = channel }
			return true
		end,
	}
	env.CreateFrame = function()
		local frame = { events = {} }
		function frame:RegisterEvent(event)
			self.events[event] = true
		end
		function frame:SetScript(_, callback)
			self.callback = callback
		end
		frames[#frames + 1] = frame
		return frame
	end
	env.strtrim = function(text)
		return text:match("^%s*(.-)%s*$")
	end
	env.LegacyForeverDB = saved or {}
	local ns = {}
	for _, path in ipairs({
		"Locales/enUS.lua",
		"Core/SafeCall.lua",
		"Core/Core.lua",
		"Core/Saved.lua",
		"Core/PeerStats.lua",
		"Core/LeaderboardsData.lua",
		"UI/Leaderboards.lua",
	}) do
		setfenv(assert(loadfile(path)), env)("LegacyForever", ns)
	end
	ns.Live = {
		FlightPathTotal = function()
			return count, stamp
		end,
	}
	ns.Print = function(text)
		lines[#lines + 1] = text
	end
	setfenv(assert(loadfile("Core/Stats.lua")), env)("LegacyForever", ns)
	local kit = { ns = ns, env = env, sent = sent, lines = lines }
	function kit.fire(event, ...)
		for _, frame in ipairs(frames) do
			if frame.events[event] and frame.callback then
				frame.callback(frame, event, ...)
			end
		end
	end
	function kit.flush()
		local rounds = 0
		while #timers > 0 do
			rounds = rounds + 1
			assert(rounds < 100, "bounded timer work")
			local due = timers
			timers = {}
			for _, callback in ipairs(due) do
				callback()
			end
		end
	end
	function kit.hear(sender, subject, value, eventUnix)
		now = now + 2
		kit.fire(
			"CHAT_MSG_ADDON",
			"WFAStats",
			("1|legacy|flight_path_known|%s|%d|%d"):format(subject, value, eventUnix or 1000),
			"GUILD",
			sender
		)
	end
	function kit.observe(value, unix)
		count, stamp = value, unix
	end
	return kit
end

local kit = boot(nil, 1, false)
local stats = kit.ns.Stats
check(kit.ns.Saved.Get("statsShare"), "participation defaults on")
kit.fire("PLAYER_LOGIN")
kit.flush()
check(
	#kit.sent == 1 and kit.sent[1].payload == "1|legacy|flight_path_known|1_0|3|1000",
	"cumulative classified snapshot is sent"
)
kit.fire("TAXIMAP_OPENED")
kit.flush()
check(#kit.sent == 1, "opening the same map does not resend unchanged observations")
kit.observe(4, 1500)
kit.fire("TAXI_NODE_STATUS_CHANGED")
kit.flush()
check(#kit.sent == 2 and kit.sent[2].payload:find("|4|1500$"), "new distinct history is sent after the taxi event")
kit.hear("Bob-Home", "1_0", 8)
kit.hear("Alice-Home", "1_0", 8)
kit.hear("Hardcore-Home", "1_1", 99)
kit.hear("DifferentMode-Home", "2_0", 99)
kit.hear("OldUnclassified-Home", "all", 99)
local board = stats.Leaderboard()
check(
	board.total == 3 and board.rows[1].name == "Alice" and board.rows[2].name == "Bob",
	"same ruleset ranks deterministically, other and unclassified scores stay out"
)
check(board.rows[3].self and board.rows[3].value == 4, "personal row is present")
check(
	#stats.Leaderboard(1).rows == 2 and stats.Leaderboard(1).rows[2].rank == 3,
	"personal row survives a bounded top list"
)
board.rows[1].value = -1
check(stats.Leaderboard().rows[1].value == 8, "public results are copies")
check(stats.Leaderboard(-1) == nil and stats.Leaderboard(0 / 0) == nil, "bad limits rejected")

-- The shared Forever Leaderboards registration.
local leaderboards = kit.ns.Leaderboards
check(type(leaderboards) == "table" and type(leaderboards.boards.legacy) == "table", "shares a board")
local spec = leaderboards.boards.legacy
check(spec.title == "Legacy Forever", "the tab carries the addon's title")
check(spec.metric == "Flight paths", "the board names its metric")
check(spec.icon == "Interface\\Icons\\Achievement_General", "the tab wears the game's own icon")
check(type(spec.revision) == "function" and spec.revision() >= 0, "the board has a revision callback")
check(spec.sharing(), "sharing reads the saved switch")
local allRows = spec.board("all")
check(allRows[1].name == "Alice" and allRows[1].value == 8, "the all-time board ranks the peers")
check(allRows[1].class == nil, "a peer's class stays unknown")
check(allRows[3].you == true and allRows[3].class == nil, "rows leave class to the shared window")
kit.hear("Bob-Home", "1_0", 12, 1500)
local weeklyRows = spec.board("week")
local bobRow
for _, row in ipairs(weeklyRows) do
	if row.name == "Bob" then
		bobRow = row
	end
end
check(bobRow and bobRow.value == 4 and bobRow.extra == "12 total", "the weekly board shows progress and the total")
kit.observe(5, 1600)
stats.Sync()
kit.env.SlashCmdList.LEGACYFOREVER("share off")
kit.flush()
check(#kit.sent == 2, "opt-out cancels queued snapshots")
check(
	#stats.Leaderboard().rows == 1 and not stats.Leaderboard().sharing,
	"opt-out hides cached peers and preserves the personal row"
)
check(not spec.sharing(), "the shared board reads the saved opt-out")
kit.hear("Ignored-Home", "1_0", 100)
check(next(stats.Shared()) == nil, "opt-out exposes no peer cache")
local saved = kit.env.LegacyForeverDB
local reloaded = boot(saved, 1, false)
reloaded.fire("PLAYER_LOGIN")
reloaded.flush()
check(#reloaded.sent == 0 and not reloaded.ns.Stats.Leaderboard().sharing, "saved opt-out survives reload")
reloaded.env.SlashCmdList.LEGACYFOREVER("share on")
reloaded.flush()
check(
	#reloaded.sent == 1 and reloaded.ns.Stats.Leaderboard().total == 3,
	"re-enable restores eligible cached peers and sends history"
)
local opened
reloaded.ns.Leaderboards.Open = function(_, key)
	opened = key
end
reloaded.env.SlashCmdList.LEGACYFOREVER("leaderboard")
check(opened == "legacy", "the leaderboard command opens the shared window on this addon's tab")
check(#reloaded.lines == 0, "and writes nothing to chat")
opened = nil
reloaded.env.SlashCmdList.LEGACYFOREVER("stats")
check(opened == "legacy", "stats is an alias")
for _, inputs in ipairs({ { nil, false }, { 1, nil }, { 0, false }, { 1.5, false }, { math.huge, false } }) do
	local unknown = boot(nil, inputs[1], inputs[2])
	unknown.fire("PLAYER_LOGIN")
	unknown.flush()
	unknown.hear("Bob", "1_0", 99)
	check(
		#unknown.sent == 0 and unknown.ns.Stats.Leaderboard().total == 1,
		"unknown classification retains only personal history"
	)
end
local hc = boot(nil, 1, true)
hc.fire("PLAYER_LOGIN")
hc.flush()
check(hc.sent[1].payload:find("|1_1|", 1, true), "hardcore uses its own subject")
local other = boot(saved, 1, false, "Player-2")
check(other.ns.Stats.Leaderboard().total == 1, "peer cache is character scoped")
local missing = boot(nil, 1, false, false)
missing.fire("PLAYER_LOGIN")
missing.flush()
check(#missing.sent == 0, "no GUID cannot send")
local old = boot(
	{ sharedStats = { Bob = { legacy = { flight_path_known = { all = { value = 99, eventUnix = 1000 } } } } } },
	1,
	false
)
check(
	old.ns.Stats.Leaderboard().total == 1 and old.env.LegacyForeverDB.sharedStats.Bob ~= nil,
	"unclassified old cache is preserved but never compared"
)
local invalidBoard, invalidReason = stats.Leaderboard(-1)
check(invalidBoard == nil and invalidReason == "invalid", "invalid limit follows the public reader error contract")
for _, setup in ipairs({
	function(env)
		env.C_GameRules = nil
	end,
	function(env)
		env.C_GameRules.GetCurrentGameModeRecordID = function()
			error("unavailable")
		end
	end,
	function(env)
		env.C_GameRules.IsHardcoreActive = function()
			error("unavailable")
		end
	end,
}) do
	local unavailable = boot(nil, 1, false)
	setup(unavailable.env)
	unavailable.fire("PLAYER_LOGIN")
	unavailable.flush()
	check(
		#unavailable.sent == 0 and unavailable.ns.Stats.Leaderboard().total == 1,
		"missing or throwing ruleset APIs fail closed"
	)
end
hc.hear("Normal", "1_0", 99)
check(hc.ns.Stats.Leaderboard().total == 1, "Hardcore never ranks normal peers")
hc.hear("Hardcore", "1_1", 8)
check(hc.ns.Stats.Leaderboard().total == 2, "Hardcore ranks its own peers")
hc.env.C_GameRules.IsHardcoreActive = function()
	return false
end
check(
	hc.ns.Stats.Leaderboard().total == 2 and hc.ns.Stats.Leaderboard().rows[1].name == "Normal",
	"ruleset changes switch eligible peers"
)
local unstamped = boot(nil, 1, false)
unstamped.observe(3, 0)
unstamped.fire("PLAYER_LOGIN")
unstamped.flush()
check(#unstamped.sent == 0, "history without a timestamp is not broadcast")
unstamped.observe(3, 1700)
unstamped.fire("TAXIMAP_OPENED")
unstamped.flush()
check(#unstamped.sent == 1, "a real observation makes upgraded history shareable")
print(("stats_spec: %d checks passed"):format(checks))

---@type string, LegacyForeverNamespace
local _, ns = ...

---@class LFStats
local Stats = {}
ns.Stats = Stats

local PREFIX = "WFAStats"
local CHANNELS = { GUILD = true, PARTY = true, RAID = true, INSTANCE_CHAT = true }
local METRICS = {
	spf = {
		distance_yards = true,
		routes_completed = true,
		transports_used = true,
		flights_taken = true,
		portals_used = true,
	},
	fieldguide = {
		creature_kills = true,
		rare_kills = true,
		shiny_finds = true,
		first_sighting = true,
		first_kill = true,
		first_rare = true,
		first_shiny = true,
		boss_sightings = true,
		boss_kills = true,
		boss_first_sighting = true,
		boss_first_kill = true,
	},
	agf = { quest_turn_ins = true, quest_turn_in = true },
	legacy = { flight_path_known = true },
	skillup = { recipes_observed_learned = true },
}
local queue, sent = {}, {}
local sending, lastReceive = false, {}
local SEND_GAP, RECEIVE_GAP = 1.5, 0.2
local FIRST = {
	first_sighting = true,
	first_kill = true,
	first_rare = true,
	first_shiny = true,
	boss_first_sighting = true,
	boss_first_kill = true,
}

local function DB()
	if type(AdventureGuideForeverDB) ~= "table" then
		return nil
	end
	local db = AdventureGuideForeverDB
	if type(db.sharedStats) ~= "table" then
		db.sharedStats = {}
	end
	return db
end

local function Enabled()
	return ns.Setting("statsShare") ~= false
end

local function UnixNow()
	if type(GetServerTime) == "function" then
		return GetServerTime()
	end
	return type(time) == "function" and time() or 0
end

local function Distributions()
	local result = {}
	if IsInGuild and IsInGuild() then
		result[#result + 1] = "GUILD"
	end
	if IsInGroup and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
		result[#result + 1] = "INSTANCE_CHAT"
	elseif IsInRaid and IsInRaid() then
		result[#result + 1] = "RAID"
	elseif IsInGroup and IsInGroup() then
		result[#result + 1] = "PARTY"
	end
	return result
end

local function Pump()
	if sending or #queue == 0 or not C_Timer or not C_Timer.After then
		return
	end
	sending = true
	local function Flush()
		if not Enabled() or not C_ChatInfo or not C_ChatInfo.SendAddonMessage then
			queue, sending = {}, false
			return
		end
		local item = table.remove(queue, 1)
		if not item then
			sending = false
			return
		end
		local stillAvailable = false
		for _, channel in ipairs(Distributions()) do
			stillAvailable = stillAvailable or channel == item.channel
		end
		if stillAvailable then
			local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, item.payload, item.channel)
			local codes = Enum and Enum.SendAddonMessageResult
			if codes and ok and (result == codes.AddonMessageThrottle or result == codes.ChannelThrottle) then
				table.insert(queue, 1, item)
				C_Timer.After(SEND_GAP * 2, Flush)
				return
			end
		end
		if #queue > 0 then
			C_Timer.After(SEND_GAP, Flush)
		else
			sending = false
		end
	end
	C_Timer.After(SEND_GAP, Flush)
end

local function Queue(row, channel)
	if not (row and row.metric and row.subject and row.value and row.eventUnix and channel) then
		return
	end
	local key = row.metric .. "|" .. row.subject .. "|" .. channel
	local old = sent[key]
	if old and old.value >= row.value then
		return
	end
	local payload = string.format("1|agf|%s|%s|%d|%d", row.metric, row.subject, row.value, row.eventUnix)
	queue[#queue + 1] = { key = key, value = row.value, payload = payload, channel = channel }
	sent[key] = { value = row.value }
	Pump()
end

function Stats.Sync()
	if not Enabled() then
		return
	end
	local rows = ns.ActivityStats and ns.ActivityStats() or {}
	local channels = Distributions()
	for _, row in ipairs(rows) do
		if row.subject == "all" then
			for _, channel in ipairs(channels) do
				Queue(row, channel)
			end
		end
	end
end

local function IsFirst(metric)
	return FIRST[metric] or metric:match("^first_") ~= nil or metric:match("_first_") ~= nil
end

local function IsSelf(sender)
	local name = UnitName and UnitName("player")
	local realm = GetRealmName and GetRealmName()
	return sender == name or sender == (name and realm and (name .. "-" .. realm))
end

function Stats.Receive(prefix, payload, channel, sender)
	if not (Enabled() and prefix == PREFIX and CHANNELS[channel]) then
		return
	end
	if type(sender) ~= "string" or #sender < 1 or #sender > 64 or IsSelf(sender) then
		return
	end
	if type(payload) ~= "string" or #payload > 128 then
		return
	end
	local version, addon, metric, subject, value, eventUnix =
		payload:match("^(%d)|([%a%d_]+)|([%a%d_]+)|([%w_%-]+)|(%d+)|(%d+)$")
	if
		version ~= "1"
		or not ADDONS[addon]
		or not (METRICS[addon] and METRICS[addon][metric])
		or #metric > 32
		or #subject > 32
		or not metric:match("^[a-z][a-z0-9_]*$")
		or not subject:match("^[a-z0-9_%-]+$")
	then
		return
	end
	value, eventUnix = tonumber(value), tonumber(eventUnix)
	local now = UnixNow()
	if not value or not eventUnix or value > 1000000000 or eventUnix < 1 or eventUnix > now + 300 then
		return
	end
	local monotonic = GetTime and GetTime() or now
	if lastReceive[sender] and monotonic - lastReceive[sender] < RECEIVE_GAP then
		return
	end
	lastReceive[sender] = monotonic
	local db = DB()
	if not db then
		return
	end
	local peers = db.sharedStats
	local peer = peers[sender]
	if not peer then
		local count = 0
		for _ in pairs(peers) do
			count = count + 1
		end
		if count >= 200 then
			return
		end
		peer = {}
		peers[sender] = peer
	end
	local addonRows = peer[addon] or {}
	peer[addon] = addonRows
	local metrics = addonRows[metric] or {}
	addonRows[metric] = metrics
	local current = metrics[subject]
	if IsFirst(metric) then
		if not current or eventUnix < current.eventUnix then
			metrics[subject] = { value = 1, eventUnix = eventUnix }
		end
	elseif not current or value > current.value then
		metrics[subject] = { value = value, eventUnix = eventUnix }
	end
end

function Stats.Shared()
	local db = DB()
	local copy = {}
	for sender, addons in pairs(db and db.sharedStats or {}) do
		copy[sender] = {}
		for addon, metrics in pairs(addons) do
			copy[sender][addon] = {}
			for metric, subjects in pairs(metrics) do
				copy[sender][addon][metric] = {}
				for subject, record in pairs(subjects) do
					copy[sender][addon][metric][subject] = { value = record.value, eventUnix = record.eventUnix }
				end
			end
		end
	end
	return copy
end

function Stats.SetEnabled(enabled)
	if enabled then
		Stats.Sync()
	else
		queue, sent = {}, {}
	end
end

local events = CreateFrame("Frame")
for _, event in ipairs({
	"PLAYER_LOGIN",
	"PLAYER_ENTERING_WORLD",
	"GROUP_ROSTER_UPDATE",
	"GUILD_ROSTER_UPDATE",
	"PLAYER_GUILD_UPDATE",
	"QUEST_TURNED_IN",
	"CHAT_MSG_ADDON",
}) do
	events:RegisterEvent(event)
end
events:SetScript("OnEvent", function(_, event, ...)
	if event == "CHAT_MSG_ADDON" then
		Stats.Receive(...)
	elseif event == "PLAYER_LOGIN" and C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
		pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
		if C_Timer and C_Timer.After then
			C_Timer.After(1, Stats.Sync)
		end
	elseif event == "QUEST_TURNED_IN" then
		if C_Timer and C_Timer.After then
			C_Timer.After(0, Stats.Sync)
		end
	else
		Stats.Sync()
	end
end)

return Stats

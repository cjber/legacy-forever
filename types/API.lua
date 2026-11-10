---@meta

-- LegacyForever.API, version 1, minor 3: the contract other addons read (docs/api.md). API.lua implements it.

---@alias LFCategory "areas"|"taxis"|"dungeons"|"raids"|"legacy"|"reputations"|"quests"
-- `"loading"` is ForeverCore.APIKit's not-ready reason; `"none"` is a call with no map and no current zone; the
-- other two are wrong arguments or an unsupported map.
---@alias LFReadError "invalid"|"loading"|"unsupported"|"none"
---@alias LFNavError "invalid"|"stale"|"unlocated"|"combat"|"unavailable"
-- The names Subscribe's changes table sets, as docs/api.md lists them.
---@alias LFAPIChange "zone"|"summary"|"targets"|"tracked"
---@alias LFAPIChanges table<LFAPIChange, true>

---@class LFCounts
---@field done integer
---@field total integer
---@field pending integer
---@field complete boolean

---@class LFCategorySummary: LFCounts
---@field key LFCategory
---@field scope "character"|"account"

---@class LFZoneSummary: LFCounts
---@field map integer
---@field name string
---@field categories LFCategorySummary[]
---@field questsStatus "disabled"|"ready"|"loading"|"missing"|"unsupported"

---@class LFPoint
---@field map integer
---@field x number
---@field y number

---@class LFTarget
---@field key string
---@field text string
---@field kind "explore"|"instance"|"kill"|"quest"|"reputation"
---@field achievementID integer
---@field achievementName string
---@field criteriaID integer
---@field points? integer Legacy points the achievement awards, left out when the game reports none
---@field quantity? number
---@field required? number
---@field place? LFPoint

---@class LFAPI
---@field version 1
---@field minor 3
---@field Leaderboard fun(limit?: integer): LFFlightLeaderboard?, LFReadError?
---@field ZoneSummary fun(map?: integer): LFZoneSummary?, LFReadError?
---@field Targets fun(map?: integer, limit?: number): LFTarget[]?, LFReadError?
---@field IsTracked fun(key: string): boolean?, LFReadError?
---@field SetTracked fun(key: string, tracked: boolean): boolean?, LFReadError?
---@field Navigate fun(map: integer, key: string): boolean, LFNavError?
---@field Subscribe fun(callback: fun(changes: LFAPIChanges)): fun() unsubscribes, safe to call twice
---@field Stats fun(): LFActivityRecord[] Character flight paths observed from opened flight-master maps.

---@class LFActivityRecord
---@field addon "LegacyForever"
---@field metric "flight_path_known"
---@field subject string flight node ID
---@field value 1
---@field eventUnix? integer last flight-master map snapshot time

---@meta

-- LegacyForever.API, version 1: the contract other addons read (docs/api.md). API.lua implements it.

---@alias LFCategory "areas"|"taxis"|"dungeons"|"raids"|"legacy"|"reputations"|"quests"
---@alias LFReadError "invalid"|"loading"|"unsupported"
---@alias LFNavError "invalid"|"stale"|"unlocated"|"combat"|"unavailable"

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
---@field criteriaID integer
---@field quantity? number
---@field required? number
---@field place? LFPoint

---@class LFAPI
---@field version 1
---@field ZoneSummary fun(map: integer): LFZoneSummary?, LFReadError?
---@field Targets fun(map: integer, limit: integer): LFTarget[]?, LFReadError?
---@field Navigate fun(map: integer, key: string): boolean, LFNavError?
---@field Subscribe fun(callback: fun()): fun()

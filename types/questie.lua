---@meta

-- The parts of QuestieDB 1.0.3 (contract 2, github.com/Questie/QuestieDB) and Questie 12.0
-- (github.com/Questie/Questie) that Quests.lua reads. Both are optional dependencies, so each is
-- checked at runtime before use.

---@class LibQuestieDBEntity
---@field Get fun(id: number, key: string): any
---@field GetAllIds fun(hashmap?: boolean): number[]

---@class LibQuestieDBSupportModule
---@field [string] table<string, string|table> `private` holds the zone tables

---@class LibQuestieDBSupport
---@field Get fun(moduleName: string): LibQuestieDBSupportModule?

---@class LibQuestieDB
---@field Quest LibQuestieDBEntity
---@field Support LibQuestieDBSupport
---@field RequireContract fun(required: integer): boolean, string?

---@type LibQuestieDB?
LibQuestieDB = nil

---@class QuestieAPI
---@field isReady boolean
---@field RegisterOnReady fun(callback: fun())

---@class QuestieAddon
---@field API QuestieAPI

---@type QuestieAddon?
Questie = nil

---@class QuestieCorrections
---@field hiddenQuests table<number, boolean|string>

---@class QuestieEvent
---@field IsEventQuest fun(questID: number): boolean

---@class QuestieLoader
QuestieLoader = {}

---@generic T
---@param name `T`
---@return T
function QuestieLoader:ImportModule(name) end

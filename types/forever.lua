---@meta

-- Forever's Legacy panel and trait currency extension are absent from the retail annotations.
---@type Frame?
LegacySystemFrame = nil
function ToggleLegacySystemUI() end

---@param currencyID number
---@param achievementID number
---@return number?
function C_Traits.GetTraitCurrencyForAchievement(currencyID, achievementID) end

-- This localized global is supplied by the client but absent from the pinned annotations.
---@type string
OTHER = nil

-- FrameXML's UiMapPoint factory (ObjectAPI/UiMapPoint.lua) is absent from the pinned Core annotations.
---@class LegacyUiMapPointFactory
---@field CreateFromCoordinates fun(uiMapID: number, x: number, y: number, z?: number): UiMapPoint
---@type LegacyUiMapPointFactory
UiMapPoint = nil

-- Shortest Path Forever's public API, when that addon is loaded; Navigate.lua feature-detects each member it calls.
---@class LegacyShortestPathAPI
---@field version? integer
---@field Navigate? fun(owner: string, map: integer, x: number, y: number, title?: string): boolean

---@type {API: LegacyShortestPathAPI?}?
ShortestPathForever = nil

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

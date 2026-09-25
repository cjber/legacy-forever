---@type string, LegacyForeverNamespace
local _, ns = ...

-- English phrases are the keys, so a phrase no locale translates reads as itself.
ns.L = setmetatable({}, {
	__index = function(_, key)
		return key
	end,
})

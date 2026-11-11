---@type string, LegacyForeverNamespace
local _, ns = ...

-- English phrases are the keys, so a phrase no locale translates reads as itself.
ns.L = setmetatable({}, {
	__index = function(_, key)
		return key
	end,
})
ns.L["Undiscovered areas shade above Leatrix Maps' unexplored tint again."] =
	"Undiscovered areas shade above Leatrix Maps' unexplored tint again."
ns.L["This menu needs mouse and keyboard."] = "This menu needs mouse and keyboard."
ns.L["Show where to discover areas"] = "Show where to discover areas"
ns.L["%d yards away"] = "%d yards away"
ns.L["A gold glow along the real ground of each undiscovered area, with a pin at its nearest edge. Areas without terrain data keep the shading."] =
	"A gold glow along the real ground of each undiscovered area, with a pin at its nearest edge. Areas without terrain data keep the shading."

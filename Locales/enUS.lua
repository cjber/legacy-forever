---@type string, LegacyForeverNamespace
local _, ns = ...

-- English phrases are the keys, so a phrase no locale translates reads as itself.
ns.L = setmetatable({}, {
	__index = function(_, key)
		return key
	end,
})
ns.L["This menu needs mouse and keyboard."] = "This menu needs mouse and keyboard."
ns.L["Show where to discover areas"] = "Show where to discover areas"
ns.L["%d yards away"] = "%d yards away"
ns.L["Shades each undiscovered area's real ground, with a pin at its edge. Areas without terrain data keep the shading."] =
	"Shades each undiscovered area's real ground, with a pin at its edge. Areas without terrain data keep the shading."
ns.L["Terrain shading now follows each area's real ground with smooth native fades."] =
	"Terrain shading now follows each area's real ground with smooth native fades."

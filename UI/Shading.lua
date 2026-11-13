---@type string, LegacyForeverNamespace
local _, ns = ...

if ns.broken then
	return
end

---@class LegacyShading
local Shading = {}
ns.Shading = Shading

---@class LegacyShadingCanvas
---@field drawn table<string, Texture[]>
---@field feathers table<string, Texture[]>
---@field width number
---@field height number
---@field shadeAlpha number
---@field outline? LegacyOutline
---@field Acquire fun(self: LegacyShadingCanvas): Texture

-- A single generated alpha field covers an area's ground and its outward fade. Independent edge gradients
-- overlap at concave corners and leave gaps at convex corners; the mask stores distance to the whole boundary.
---@param pin LegacyShadingCanvas
---@param area LegacyOutlineArea
function Shading.Area(pin, area)
	local zone = pin.outline and ns.ShadingMasks[pin.outline.uiMapID]
	local mask = zone and zone[area.key]
	if not mask then
		return
	end
	local texture = pin:Acquire()
	-- art-ok: generated terrain alpha mask, scaled with the map canvas as a shading fill
	texture:SetTexture(mask[5], nil, nil, "TRILINEAR")
	texture:ClearVertexOffsets()
	texture:SetTexCoord(0, 1, 0, 1)
	texture:SetSize(mask[3] * pin.width / 1002, mask[4] * pin.height / 668)
	texture:ClearAllPoints()
	texture:SetPoint("TOPLEFT", mask[1] * pin.width / 1002, -mask[2] * pin.height / 668)
	texture:SetVertexColor(0, 0, 0, pin.shadeAlpha)
	texture:Show()
	-- An area with tile shading under its terrain fill keeps both in one list, so a hover brightens both.
	local textures = pin.drawn[area.key]
	if not textures then
		textures = {}
		pin.drawn[area.key] = textures
	end
	textures[#textures + 1] = texture
end

---@param pin LegacyShadingCanvas
---@param key string
---@param alpha number
function Shading.Alpha(pin, key, alpha)
	for _, texture in ipairs(pin.drawn[key] or {}) do
		texture:SetVertexColor(0, 0, 0, alpha)
	end
end

---@type string, LegacyForeverNamespace
local _, ns = ...

if ns.broken then
	return
end

-- The world map's terrain shading textures: an outlined area's real ground is a white pixel tinted the shading's
-- black, stretched over each fill triangle and over a feather band along each edge. UI/Map.lua's AreaPin owns the
-- frame, the tile shading and the hover; this file draws what replaces the map-art tiles for an area with terrain.
---@class LegacyShading
local Shading = {}
ns.Shading = Shading

-- The parts of the map's area pin a terrain fill is drawn onto.
---@class LegacyShadingCanvas
---@field drawn table<string, Texture[]>
---@field feathers table<string, Texture[]>
---@field width number
---@field height number
---@field shadeAlpha number
---@field Acquire fun(self: LegacyShadingCanvas): Texture

-- A white pixel, tinted black at the shading's alpha. Its triangles stretch it, as the shading is a fill by design.
local SHADE_FILE = "Interface\\Buttons\\WHITE8X8"
-- How far an outlined area's edge fades out, as a share of the map canvas's width, matching the soft edge
-- Blizzard's tile shading gets from its exploration overlay art. Measured from those overlays' alpha at the
-- traced terrain edges across Ashenvale's 18 areas: full shading at the edge, half at 26 of the map art's
-- 1002 pixels, and nothing at a median 40 (quartiles 29 and 57), so 40 / 1002. The fill fades over the same
-- band instead of ending in a hard triangle edge.
local FEATHER = 40 / 1002

-- A gradient colour for the shading: black at `alpha`. The pinned FrameXML annotation infers CreateColor's
-- ColorMixin, which SetGradient's colorRGBA parameter does not take.
---@param alpha number
---@return colorRGBA
local function ShadeColor(alpha)
	return CreateColor(0, 0, 0, alpha) --[[@as colorRGBA]]
end

-- A quad drawn on one pooled texture: its four points in canvas pixels, in the texture corners' order, upper
-- left, lower left, upper right, lower right. The texture covers their bounding box, and
-- Texture:SetVertexOffset moves each corner onto its point: its y is in UI units up from the corner, as
-- SetPoint's is, so the corner's screen-down y is subtracted.
---@param texture Texture
---@param upperLeft number[] x, y
---@param lowerLeft number[] x, y
---@param upperRight number[] x, y
---@param lowerRight number[] x, y
local function PlaceQuad(texture, upperLeft, lowerLeft, upperRight, lowerRight)
	local left = math.min(upperLeft[1], lowerLeft[1], upperRight[1], lowerRight[1])
	local top = math.min(upperLeft[2], lowerLeft[2], upperRight[2], lowerRight[2])
	local width = math.max(upperLeft[1], lowerLeft[1], upperRight[1], lowerRight[1]) - left
	local height = math.max(upperLeft[2], lowerLeft[2], upperRight[2], lowerRight[2]) - top
	texture:SetSize(width, height)
	texture:ClearAllPoints()
	texture:SetPoint("TOPLEFT", left, -top)
	texture:SetVertexOffset(UPPER_LEFT_VERTEX, upperLeft[1] - left, top - upperLeft[2])
	texture:SetVertexOffset(LOWER_LEFT_VERTEX, lowerLeft[1] - left, top + height - lowerLeft[2])
	texture:SetVertexOffset(UPPER_RIGHT_VERTEX, upperRight[1] - left - width, top - upperRight[2])
	texture:SetVertexOffset(LOWER_RIGHT_VERTEX, lowerRight[1] - left - width, top + height - lowerRight[2])
end

-- One triangle of an area's real ground, drawn as the tile shading is: a white texture tinted the shading's
-- black at its alpha. The texture covers the triangle's bounding box, and PlaceQuad moves each corner onto the
-- triangle's own points, one corner collapsed onto another, so the quad's four corners are the triangle's three.
---@param pin LegacyShadingCanvas
---@param triangle number[] u1, v1, u2, v2, u3, v3
---@return Texture
local function DrawTriangle(pin, triangle)
	local one = { triangle[1] * pin.width, triangle[2] * pin.height }
	local two = { triangle[3] * pin.width, triangle[4] * pin.height }
	local three = { triangle[5] * pin.width, triangle[6] * pin.height }
	local texture = pin:Acquire()
	-- art-ok: one white pixel, stretched to a shading fill the way the map tiles are drawn
	texture:SetTexture(SHADE_FILE)
	texture:SetTexCoord(0, 1, 0, 1)
	texture:SetVertexColor(0, 0, 0, pin.shadeAlpha)
	texture:Show()
	PlaceQuad(texture, one, three, two, two)
	return texture
end

-- One ring edge's feather: a quad whose upper corners are the edge and whose lower corners lie the feather
-- distance outward, fading from the shading's alpha at the edge to nothing outside. Outward is away from the
-- ring's interior, which its winding gives.
---@param pin LegacyShadingCanvas
---@param a number[] start point in canvas pixels
---@param b number[] end point in canvas pixels
---@param normal number[] outward unit normal
---@return Texture
local function DrawFeather(pin, a, b, normal)
	local reach = FEATHER * pin.width
	local outerA = { a[1] + normal[1] * reach, a[2] + normal[2] * reach }
	local outerB = { b[1] + normal[1] * reach, b[2] + normal[2] * reach }
	local texture = pin:Acquire()
	-- art-ok: one white pixel, stretched to a feather band the way the map tiles are drawn
	texture:SetTexture(SHADE_FILE)
	texture:SetTexCoord(0, 1, 0, 1)
	-- SetGradient's vertical colours take the second argument as the top, the edge's, and the first as the
	-- bottom, outside: the shading's alpha at the edge fading to nothing.
	texture:SetGradient("VERTICAL", ShadeColor(0), ShadeColor(pin.shadeAlpha))
	texture:Show()
	PlaceQuad(texture, a, outerA, b, outerB)
	return texture
end

-- One feather per edge of a ring, outward from its interior: the ring's signed area says which way it winds.
---@param pin LegacyShadingCanvas
---@param ring number[] flat u, v pairs
---@param into Texture[]
local function Feather(pin, ring, into)
	local count = #ring / 2
	if count < 3 then
		return
	end
	local area = 0
	for index = 1, count do
		local following = index % count + 1
		area = area + ring[index * 2 - 1] * ring[following * 2] - ring[following * 2 - 1] * ring[index * 2]
	end
	local turn = area < 0 and -1 or 1
	for index = 1, count do
		local following = index % count + 1
		local ax, ay = ring[index * 2 - 1] * pin.width, ring[index * 2] * pin.height
		local bx, by = ring[following * 2 - 1] * pin.width, ring[following * 2] * pin.height
		local tx, ty = bx - ax, by - ay
		local length = math.sqrt(tx * tx + ty * ty)
		if length > 0 then
			into[#into + 1] = DrawFeather(pin, { ax, ay }, { bx, by }, { turn * ty / length, -turn * tx / length })
		end
	end
end

-- One outlined area's terrain fill and edge feathers, from the ear clipping UI/Map.lua keeps on the area's rings.
---@param pin LegacyShadingCanvas
---@param area LegacyOutlineArea
function Shading.Area(pin, area)
	local triangles = {}
	for _, triangle in ipairs(ns.MapContents.Triangles(area.rings)) do
		triangles[#triangles + 1] = DrawTriangle(pin, triangle)
	end
	pin.drawn[area.key] = triangles
	local feathers = {}
	for _, ring in ipairs(area.rings) do
		Feather(pin, ring, feathers)
	end
	pin.feathers[area.key] = feathers
end

-- The alpha of one area's drawing: its terrain fill and its edge feathers brighten together.
---@param pin LegacyShadingCanvas
---@param key string
---@param alpha number
function Shading.Alpha(pin, key, alpha)
	for _, texture in ipairs(pin.drawn[key] or {}) do
		texture:SetVertexColor(0, 0, 0, alpha)
	end
	for _, texture in ipairs(pin.feathers[key] or {}) do
		texture:SetGradient("VERTICAL", ShadeColor(0), ShadeColor(alpha))
	end
end

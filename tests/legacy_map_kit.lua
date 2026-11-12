-- Legacy XML templates for the shared read-only world-map harness.
local core = os.getenv("FOREVER_CORE") or "../forever-core"
local Kit = dofile(core .. "/tests/strict_map.lua")

-- The client's four texture vertex indices (Blizzard_FrameXMLBase/Constants.lua) and each corner's natural place
-- in its texture, as a fraction of the width and height. Screen y points down here; SetVertexOffset's y points up.
local CORNERS = { { 0, 0 }, { 0, 1 }, { 1, 0 }, { 1, 1 } }

-- The strict harness's regions record only what a spec has read so far. Every one made after this also records
-- what a shading texture is drawn with, so a spec can read a triangle's corners as well as its colour.
local install = Kit.Install
function Kit.Install(env)
	install(env)
	-- The client's world map registers these pin levels in this order: exploration (20 here, 2002 in the client),
	-- fog of war (25/2006), then every marker from quest blobs up, with dungeon entrances at 28/2015 and area
	-- points of interest at 30/2023. Core's strict map lists only the two its own canvas spec reads, so the rest
	-- are filled in for the layers Legacy draws against.
	local levels = Kit.map:GetPinFrameLevelsManager()
	local valid = levels.GetValidFrameLevel
	local levelsByName = {
		PIN_FRAME_LEVEL_FOG_OF_WAR = 25,
		PIN_FRAME_LEVEL_DUNGEON_ENTRANCE = 28,
	}
	rawset(levels, "GetValidFrameLevel", function(self, levelType)
		return valid(self, levelType) or levelsByName[levelType]
	end)
	-- The constants the client defines for Texture:SetVertexOffset.
	env.UPPER_LEFT_VERTEX, env.LOWER_LEFT_VERTEX = 1, 2
	env.UPPER_RIGHT_VERTEX, env.LOWER_RIGHT_VERTEX = 3, 4
	-- CreateColor's ColorMixin, as far as a gradient reads it: the four channels.
	---@param r number
	---@param g number
	---@param b number
	---@param a number
	---@return colorRGBA
	env.CreateColor = function(r, g, b, a)
		return { r = r, g = g, b = b, a = a } --[[@as colorRGBA]]
	end
	local region = Kit.Region
	function Kit.Region()
		local made = region()
		made.SetTexture = function(self, file)
			self.file = file
		end
		made.SetGradient = function(self, orientation, minColor, maxColor)
			self.gradient = { orientation = orientation, min = minColor, max = maxColor }
		end
		made.SetTexCoord = function(self, ...)
			self.texcoord = { ... }
		end
		made.SetSize = function(self, width, height)
			self.width, self.height = width, height
		end
		made.ClearAllPoints = function(self)
			rawset(self, "point", nil)
		end
		made.SetPoint = function(self, ...)
			rawset(self, "point", { ... })
		end
		made.ClearVertexOffsets = function(self)
			rawset(self, "offsets", nil)
		end
		made.SetVertexOffset = function(self, index, x, y)
			local offsets = rawget(self, "offsets")
			if not offsets then
				offsets = {}
				rawset(self, "offsets", offsets)
			end
			offsets[index] = { x, y }
		end
		-- Where a vertex lands on screen, in screen-down pixels: its natural corner from the texture's TOPLEFT
		-- point and size, plus its offset, whose y is UI units up and so subtracts from that screen-down place.
		made.Corner = function(self, index)
			local point, natural = rawget(self, "point"), CORNERS[index]
			local left, top = point[2], -point[3]
			local offset = (rawget(self, "offsets") or {})[index] or { 0, 0 }
			return left + natural[1] * rawget(self, "width") + offset[1],
				top + natural[2] * rawget(self, "height") - offset[2]
		end
		return made
	end
end

Kit.templates = {
	LegacyForeverPinTemplate = function(frame)
		frame.Icon, frame.Portal, frame.Highlight = Kit.Region(), Kit.Region(), Kit.Region()
		frame.Highlight.shown = false
	end,
	LegacyForeverMapButtonTemplate = function(frame)
		frame.Icon, frame.Count = Kit.Region(), Kit.Region()
		Mixin(frame, LegacyForeverMapButtonMixin)
		-- As DropdownButtonMixin:SetupMenu: the menu is built at once while the button shows.
		frame.SetupMenu = function(self, generator)
			if self.shown then
				generator(self, Kit.MenuRoot())
			end
		end
		frame.IsMenuOpen = function()
			return false
		end
		frame.OpenMenu = function(self)
			self.opened = true
		end
		frame:OnLoad()
		-- Map.xml's OnShow: the client runs it as the frame is made, when it is made shown with no parent.
		if not frame.parent then
			frame:OnShow()
		end
	end,
	LegacyForeverZoneOverlayTemplate = function(frame)
		frame.Title, frame.Counts = Kit.Region(), Kit.Region()
		Mixin(frame, LegacyForeverZoneOverlayMixin)
		frame:OnLoad()
	end,
}

return Kit

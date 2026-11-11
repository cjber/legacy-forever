-- Legacy XML templates for the shared read-only world-map harness.
local core = os.getenv("FOREVER_CORE") or "../forever-core"
local Kit = dofile(core .. "/tests/strict_map.lua")

-- The strict harness's frames have no CreateLine. Every frame made after this gets one, returning a region
-- that records the edge it draws, so a spec can read the glow.
local install = Kit.Install
function Kit.Install(env)
	install(env)
	local create = env.CreateFrame
	env.CreateFrame = function(...)
		local frame = create(...)
		frame.lines = {}
		frame.CreateLine = function()
			local line = Kit.Region()
			line.SetStartPoint = function(self, point, relative, x, y)
				self.start = { point, relative, x, y }
			end
			line.SetEndPoint = function(self, point, relative, x, y)
				self.finish = { point, relative, x, y }
			end
			line.SetThickness = function(self, thickness)
				self.thickness = thickness
			end
			line.SetAlpha = function(self, alpha)
				self.alpha = alpha
			end
			frame.lines[#frame.lines + 1] = line
			return line
		end
		return frame
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

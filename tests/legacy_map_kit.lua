-- Legacy XML templates for the shared read-only world-map harness.
local Kit = dofile("tests/strict_map.lua")

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

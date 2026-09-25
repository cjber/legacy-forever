---@type string, LegacyForeverNamespace
local addonName, ns = ...

-- One chat line after an update: the new version and ns.WHATS_NEW. A first install stays quiet (there is no
-- version to compare with), and so does a checkout, whose version the packager never filled in.
function ns.WhatsNew()
	local version = C_AddOns.GetAddOnMetadata(addonName, "Version")
	if not version or version:find("^@") then
		return
	end
	-- Forever's beta client can start without the saved variables loaded; that reads as a first install.
	local saved = LegacyForeverDB or {}
	LegacyForeverDB = saved
	local last = saved.lastVersion
	saved.lastVersion = version
	if last and last ~= version and ns.Setting("whatsNew") then
		ns.Print(("updated to %s. %s"):format(version, ns.WHATS_NEW))
	end
end

local login = CreateFrame("Frame")
login:RegisterEvent("PLAYER_LOGIN")
login:SetScript("OnEvent", ns.WhatsNew)

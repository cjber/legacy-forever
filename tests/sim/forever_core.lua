-- Registers the ForeverCore checkout with a scenario's client before login, so the addon's UI builds. FOREVER_CORE
-- names the checkout, or the sibling ../forever-core is used for local runs. A packaged build carries its own core
-- under Libs/ForeverCore (the embed step writes Libs/ForeverCore/bundle.json), which is what a player without the
-- standalone addon runs, so no checkout is added beside it: an unpackaged checkout reads as an older standalone and
-- would put the loader's outdated notice in the run.
local Core = {}

---@param sim table the scenario's simulator
function Core.install(sim)
	local bundle = io.open("Libs/ForeverCore/bundle.json", "rb")
	if bundle then
		bundle:close()
		return
	end
	sim:addon(os.getenv("FOREVER_CORE") or "../forever-core", "ForeverCore")
end

return Core

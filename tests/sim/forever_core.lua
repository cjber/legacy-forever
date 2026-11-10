-- Registers the ForeverCore checkout with a scenario's client before login. A scenario's own addon requires it with
-- ## Dependencies, so the loader loads core first; FOREVER_CORE names the checkout, or the sibling ../forever-core is
-- used for local runs.
local Core = {}

---@param sim table the scenario's simulator
function Core.install(sim)
	sim:addon(os.getenv("FOREVER_CORE") or "../forever-core", "ForeverCore")
end

return Core

local _, ns = ...

-- The game refuses to load this addon when ForeverCore is absent (## Dependencies), but an older ForeverCore still
-- loads. Its API version and the members added since say whether it has everything this addon calls, so an
-- out-of-date one stops the addon's own files here. The warning itself is Core/ForeverRequire.lua, shared by every
-- Forever addon. It names the addon to update, never ForeverCore.
--
-- API 1 has the tracker host, the family suggestions, the map, settings and context menu openers, the leaderboards,
-- peer stats and the report window, all of which this addon calls. APIKit.Hub arrived with the kit in ForeverCore
-- 1.1.0 and is what Core/API.lua builds this addon's own API on. Publishing to the suite's list (APIKit.Publish) is
-- guarded by its minor, so an older kit is not a reason to stop.
local ready = ForeverCore ~= nil
	and (ForeverCore.API or 0) >= 1
	and ForeverCore.APIKit ~= nil
	and type(ForeverCore.APIKit.Hub) == "function"

ns.ForeverRequire(ready)

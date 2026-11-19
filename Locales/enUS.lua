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
ns.L["Routes keep working with Shortest Path Forever when its shared leaderboard features are removed."] =
	"Routes keep working with Shortest Path Forever when its shared leaderboard features are removed."

ns.L["Count account quests"] = "Count account quests"

ns.L["Count quests completed by any character. The quests counted still match this character's race and class."] =
	"Count quests completed by any character. The quests counted still match this character's race and class."

ns.L["Account quest completion is unavailable on this client. Only this character's quests count."] =
	"Account quest completion is unavailable on this client. Only this character's quests count."
ns.L["Stratholme: Live tracks again."] = "Stratholme: Live tracks again."

ns.L["Tracked Legacy challenges"] = "Tracked Legacy challenges"
ns.L["Turn it back on in Settings > AddOns > Legacy Forever > Objective tracker."] =
	"Turn it back on in Settings > AddOns > Legacy Forever > Objective tracker."
ns.L["open the Legacy panel"] = "open the Legacy panel"
ns.L["open the map"] = "open the map"
ns.L["The current zone is not known yet."] = "The current zone is not known yet."

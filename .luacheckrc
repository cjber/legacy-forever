std = "lua51"
max_line_length = 120
exclude_files = { "tools/.cache/**", ".release/**" }
ignore = { "212/_.*", "212/self" } -- unused args prefixed with _, and self on mixin handlers

globals = {
	"LegacyHereAreaPinMixin",
	"LegacyHereMapButtonMixin",
	"LegacyHereZoneOverlayMixin",
	"LegacyHereZonePercentPinMixin",
	"LegacyHereDB",
	"LegacyHerePinMixin",
	"LegacyHere_OnAddonCompartmentClick",
	"SLASH_LEGACYHERE1",
	"SLASH_LEGACYHERE2",
	"SlashCmdList",
}

read_globals = {
	"AchievementFrame_SelectAchievement", "C_Map", "C_MapExplorationInfo", "C_TaxiMap", "C_Timer", "C_Traits", "CreateAtlasMarkup",
	"CreateFrame", "CreateFramePool", "CreateFromMixins", "CreateTexturePool", "DEFAULT_CHAT_FRAME", "Enum", "EventRegistry", "EventUtil", "GameTooltip",
	"GameTooltip_AddColoredLine", "GameTooltip_AddDisabledLine", "GREEN_FONT_COLOR", "HIGHLIGHT_FONT_COLOR", "NORMAL_FONT_COLOR", "GameTooltip_AddHighlightLine", "GameTooltip_AddInstructionLine",
	"GameTooltip_AddNormalLine", "GameTooltip_SetTitle", "GetAchievementCategory", "GetAchievementCriteriaInfo", "GetAchievementInfo",
	"GetAchievementNumCriteria", "GetBuildInfo", "GetCategoryInfo", "GetCategoryList", "GetCategoryNumAchievements", "hooksecurefunc",
	"LegacySystemFrame", "MenuUtil", "OTHER", "Mixin", "OBJECTIVE_DASH_STYLE_HIDE", "ObjectiveTrackerFrame",
	"ObjectiveTrackerManager", "MapCanvasDataProviderMixin", "MapCanvasPinMixin", "strtrim",
	"tContains", "ToggleLegacySystemUI", "ToggleWorldMap", "OpenWorldMap", "UnitFactionGroup", "UIParent", "WHITE_FONT_COLOR", "WorldMapFrame",
}

files["Data/Legacy.lua"] = { max_line_length = false }
files["tests/"] = { std = "+luajit", globals = { "arg" } }

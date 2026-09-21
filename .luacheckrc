std = "lua51"
max_line_length = 120
exclude_files = { "tools/.cache/**", ".release/**" }
ignore = { "212/_.*", "212/self" } -- unused args prefixed with _, and self on mixin handlers

globals = {
	"LegacyHereMapButtonMixin",
	"LegacyHereDB",
	"LegacyHerePinMixin",
	"LegacyHere_OnAddonCompartmentClick",
	"SLASH_LEGACYHERE1",
	"SLASH_LEGACYHERE2",
	"SlashCmdList",
}

read_globals = {
	"AchievementFrame_SelectAchievement", "C_ContentTracking", "C_Map", "C_Timer", "C_Traits", "CreateAtlasMarkup",
	"CreateFrame", "CreateFromMixins", "DEFAULT_CHAT_FRAME", "Enum", "EventRegistry", "EventUtil", "GameTooltip",
	"GameTooltip_AddColoredLine", "GameTooltip_AddHighlightLine", "GameTooltip_AddInstructionLine",
	"GameTooltip_AddNormalLine", "GameTooltip_SetTitle", "GetAchievementCriteriaInfo", "GetAchievementInfo",
	"GetAchievementNumCriteria", "GetBuildInfo", "GetCategoryList", "GetCategoryNumAchievements",
	"IsShiftKeyDown", "LegacySystemFrame", "MapCanvasDataProviderMixin", "MapCanvasPinMixin", "strtrim",
	"ToggleLegacySystemUI", "ToggleWorldMap", "WHITE_FONT_COLOR", "WorldMapFrame",
}

files["Data/Legacy.lua"] = { max_line_length = false }
files["tests/"] = { std = "+luajit", globals = { "arg" } }

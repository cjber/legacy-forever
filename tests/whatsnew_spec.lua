-- Run from the repository root: luajit tests/whatsnew_spec.lua
-- The chat line after an update: once per new version, never on a first install, in a checkout or when switched off.
local checks = 0
local function check(condition, label)
	checks = checks + 1
	assert(condition, label)
end

local version, onLogin
local printed = {}
local TOC = dofile("tests/toc_fields.lua").read("LegacyForever.toc")
C_AddOns = {
	GetAddOnMetadata = function(name, field)
		assert(name == "LegacyForever", "reads its own metadata")
		if field == "Version" then
			return version
		end
		return TOC[field]
	end,
}
CreateFrame = function()
	return {
		RegisterEvent = function(_, event)
			assert(event == "PLAYER_LOGIN", "waits for login")
		end,
		SetScript = function(_, _, handler)
			onLogin = handler
		end,
	}
end
-- ForeverCore loads in a client of its own, so its error-handler frame never meets this spec's one-frame stub.
geterrorhandler = function()
	return error
end
seterrorhandler = function() end
strtrim = function(text)
	return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end
local coreEnv = setmetatable({
	CreateFrame = function()
		return { RegisterEvent = function() end, SetScript = function() end }
	end,
}, { __index = _G })
ForeverCore = dofile("tests/forever_core.lua").install(coreEnv, {
	"Core/SafeCall.lua",
	"Core/Log.lua",
	"UI/Report.lua",
	"UI/MapCanvas.lua",
	"Expose.lua",
})
SlashCmdList = {}
local ns = {}
assert(loadfile("Locales/enUS.lua"))("LegacyForever", ns)
ns.core = ForeverCore.Register("LegacyForever", {})
assert(loadfile("Core/Core.lua"))("LegacyForever", ns)
assert(loadfile("Core/Saved.lua"))("LegacyForever", ns)
function ns.Print(msg)
	printed[#printed + 1] = msg
end
assert(loadfile("UI/WhatsNew.lua"))("LegacyForever", ns)
check(onLogin == ns.WhatsNew, "runs at login")

-- A first install, even with no saved variables loaded at all: silent, and the version is remembered.
LegacyForeverDB, version = nil, "0.6.0"
ns.WhatsNew()
check(#printed == 0, "a first install says nothing")
check(LegacyForeverDB and LegacyForeverDB.lastVersion == "0.6.0", "the version is remembered")

-- The same version again: silent.
ns.WhatsNew()
check(#printed == 0, "the same version says nothing")

-- A new version with a headline: one line, then remembered.
local shippedVersion = ns.WHATS_NEW_VERSION
ns.WHATS_NEW_VERSION = "0.7.0"
version = "0.7.0"
ns.WhatsNew()
check(#printed == 1 and printed[1] == "updated to 0.7.0. " .. ns.WHATS_NEW, "an update says what's new once")
ns.WhatsNew()
check(#printed == 1 and LegacyForeverDB.lastVersion == "0.7.0", "and not again")

-- A maintenance release above it, with no headline: silent, but the version still moves on.
LegacyForeverDB, version = { lastVersion = "0.7.0" }, "0.7.1"
ns.WhatsNew()
check(#printed == 1, "a maintenance release says nothing new")
check(LegacyForeverDB.lastVersion == "0.7.1", "a maintenance release is still remembered")

-- Switched off: silent, but still remembered.
LegacyForeverDB.whatsNew, version = false, "0.8.0"
ns.WhatsNew()
check(#printed == 1 and LegacyForeverDB.lastVersion == "0.8.0", "switched off says nothing")

-- A checkout: the packager's keyword is still there, so nothing is said or stored.
LegacyForeverDB, version = { lastVersion = "0.8.0" }, "@project-version@"
ns.WhatsNew()
check(#printed == 1 and LegacyForeverDB.lastVersion == "0.8.0", "a checkout says and stores nothing")
version = nil
ns.WhatsNew()
check(#printed == 1, "no version says nothing")

-- The newest release with a bold lead, skipping the maintenance entries a core sync adds above it. Each entry is its
-- heading and the text up to the next versioned heading.
local function Releases(text)
	local found = {}
	local nextSearch = 1
	while true do
		local start, finish, release = text:find("\n## %[(%d+%.%d+%.%d+)%] %- %d%d%d%d%-%d%d%-%d%d\n", nextSearch)
		if not start then
			return found
		end
		local following = text:find("\n## %[", finish + 1)
		found[#found + 1] = { version = release, body = text:sub(finish + 1, (following or #text + 1) - 1) }
		nextSearch = finish + 1
	end
end

-- The packager ships text files with CRLF line endings, so the packaged CHANGELOG.md is read the same way.
local function Headline(text)
	for _, release in ipairs(Releases("\n" .. (text:gsub("\r\n", "\n")))) do
		local headline = release.body:match("%- %*%*(.-)%*%*")
		if headline then
			return release.version, headline
		end
	end
end

-- The shipped headline and version are the newest release's with a bold lead, so a release that forgets to rewrite
-- them fails here instead of announcing the release before it.
ns.WHATS_NEW_VERSION = shippedVersion
local changelog = assert(io.open("CHANGELOG.md")):read("*a")
local newestVersion, newestHeadline = Headline(changelog)
check(
	newestVersion == ns.WHATS_NEW_VERSION,
	"WHATS_NEW_VERSION is the newest headline release, not " .. tostring(newestVersion)
)
check(newestHeadline == ns.WHATS_NEW, "WHATS_NEW is that release's headline")

-- A core sync's maintenance entry has no bold lead, so the headline above it is the one a player still sees.
local maintenance = table.concat({
	"## [9.9.9] - 2026-11-12",
	"",
	"<!-- forever-core-sync -->",
	"",
	"- Ships with the same shared code as your other Forever addons, so they keep working together.",
	"",
	"## [9.9.8] - 2026-11-11",
	"",
	"- **A real headline.** What it says.",
}, "\n")
local maintenanceVersion, maintenanceHeadline = Headline(maintenance)
check(maintenanceVersion == "9.9.8", "a maintenance entry on top is skipped for the newest version")
check(maintenanceHeadline == "A real headline.", "and for its headline")

print(("whatsnew_spec: %d checks passed"):format(checks))

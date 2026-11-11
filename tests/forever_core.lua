-- ForeverCore's files, loaded the way the client loads them: its TOC's entries, in order, under its own namespace.
-- A spec that used to load a vendored copy from this repository asks for it here instead. The checkout is the one in
-- FOREVER_CORE, or the sibling ../forever-core used for local runs.
--
--   local core = dofile("tests/forever_core.lua")
--   local ForeverCore = core.install(env, { "Core/SafeCall.lua", "Core/Log.lua", "UI/Report.lua",
--       "UI/Credits.lua", "UI/MapCanvas.lua", "Expose.lua" })
--
-- `install` returns the ForeverCore global, so a spec can register through it. With no file list, every file the TOC
-- names loads. `enUS.lua` always loads first: its phrases are the keys every core module reads.
local Core = {}

---@return string
local function root()
	return os.getenv("FOREVER_CORE") or "../forever-core"
end

---@return string[]
function Core.files()
	local toc = root() .. "/ForeverCore.toc"
	local file = assert(io.open(toc, "rb"), "ForeverCore is not at " .. toc .. "; set FOREVER_CORE")
	local files = {}
	for line in file:lines() do
		line = line:gsub("\r$", "")
		if not (line:match("^%s*$") or line:match("^%s*#")) then
			files[#files + 1] = (line:gsub("\\", "/"))
		end
	end
	file:close()
	return files
end

---@param names string[]?
---@return table<string, boolean>
local function wanted(names)
	local set = { ["Locales/enUS.lua"] = true }
	for _, name in ipairs(names or {}) do
		set[name] = true
	end
	return set
end

-- Loads ForeverCore into `ns`, a namespace of its own, and runs its chunks in `env`. Returns the namespace.
---@param names string[]? core files to load, in TOC order; every file when nil
---@param ns table
---@param env table
---@return table
function Core.load(names, ns, env)
	env = env or _G
	local selected = names and wanted(names) or nil
	for _, path in ipairs(Core.files()) do
		if selected == nil or selected[path] then
			-- Core's own quest section needs the full native tracker template; a spec without one skips that optional
			-- section, as core's own api_spec does. A spec with no GetLocale skips the translations after enUS, whose
			-- guard would stop on the missing client call.
			local native = env.ObjectiveTrackerFrame
			local translated = path:match("^Locales/") and path ~= "Locales/enUS.lua"
			if path ~= "UI/TrackerQuests.lua" or native ~= nil then
				if not (translated and type(env.GetLocale) ~= "function") then
					local chunk = assert(loadfile(root() .. "/" .. path), path)
					setfenv(chunk, env)
					chunk("ForeverCore", ns)
				end
			end
			env.ObjectiveTrackerFrame = native
		end
	end
	return ns
end

-- Loads ForeverCore into a namespace of its own, in `env`, and returns the global its TOC publishes.
---@param env table?
---@param names string[]?
---@return ForeverCoreAPI
function Core.install(env, names)
	env = env or _G
	local ns = {}
	Core.load(names, ns, env)
	return assert(env.ForeverCore or _G.ForeverCore, "ForeverCore did not publish its global")
end

return Core

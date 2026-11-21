-- Initialization must tolerate an ordinary load and the files running after the loading events, as they do when the
-- bundled ForeverCore activates at PLAYER_LOGIN or later (cjber/forever-core#980). The EventUtil stub waits as the
-- client does: only an event fired after the wait was asked counts toward it.
local checks = 0
local function noop() end
local cases = {
	{ label = "ordinary load", seen = {}, fire = { "PLAYER_ENTERING_WORLD", "VARIABLES_LOADED" } },
	{
		label = "files run at login, world entry to come",
		deferred = true,
		seen = {},
		fire = { "PLAYER_ENTERING_WORLD", "VARIABLES_LOADED" },
	},
	{
		label = "files run after every loading event",
		deferred = true,
		seen = { PLAYER_ENTERING_WORLD = true, VARIABLES_LOADED = true },
		fire = {},
	},
}
for _, case in ipairs(cases) do
	local waits, timers, warnings, modules, owners = {}, {}, {}, {}, {}
	local native = {}
	local function region()
		return { SetHeader = noop }
	end
	local env = setmetatable({
		ObjectiveTrackerFrame = native,
		ObjectiveTrackerManager = setmetatable({}, {
			__index = function()
				error("must not register with native manager")
			end,
		}),
		CreateFrame = function(_, name)
			local frame = region()
			if name then
				modules[#modules + 1] = frame
			end
			return frame
		end,
		Mixin = function(target, source)
			for key, value in pairs(source) do
				target[key] = value
			end
		end,
		EventUtil = {
			ContinueAfterAllEvents = function(fn, ...)
				waits[#waits + 1] = { fn = fn, events = { ... }, seen = {} }
			end,
		},
		IsLoggedIn = function()
			return case.deferred == true
		end,
		ForeverCoreLoader = {
			Seen = function(event)
				return case.seen[event] == true
			end,
		},
		C_Timer = {
			After = function(delay, fn)
				if delay == 0 then
					timers[#timers + 1] = fn
				elseif delay == 5 then
					warnings[#warnings + 1] = fn
				end
			end,
		},
		hooksecurefunc = function()
			error("native methods must stay unhooked")
		end,
	}, { __index = _G })
	local shown, tracked = true, { 10 }
	local savedListener, refreshes = nil, 0
	local opened = {}
	local ns = {
		SavedTable = function()
			return tracked
		end,
		Model = {
			TrackedChallenge = function(_, key)
				return key
			end,
		},
		Saved = {
			OnChange = function(callback)
				savedListener = callback
			end,
			Get = function()
				return shown
			end,
			Set = function(key, value)
				shown = value
				savedListener(key)
			end,
			LegacyTrackerSettings = function()
				return nil
			end,
			ClearLegacyTrackerSettings = noop,
		},
		core = {
			SafeCall = function(_, fn, ...)
				return true, fn(...)
			end,
		},
		L = setmetatable({}, {
			__index = function(_, key)
				return key
			end,
		}),
		Live = {
			OnChange = noop,
			Visible = function()
				return {}
			end,
			Name = function()
				return "Challenge"
			end,
		},
	}
	env.ForeverCore = {
		Open = function(addon, where)
			opened[#opened + 1] = { addon = addon, where = where }
			return false, "Panel locked"
		end,
		TrackerHost = {
			Attach = function(module, show, contract)
				module.show = show
				module.contract = contract
				module.MarkDirty = function()
					refreshes = refreshes + 1
				end
				owners[module] = native
			end,
			IsAttached = function(module)
				return owners[module] == native
			end,
		},
	}
	env._G = env
	setfenv(assert(loadfile("Core/ForeverRequire.lua")), env)("LegacyForever", ns)
	if case.deferred then
		ns.ForeverCoreHostAfter, ns.ForeverCoreHostDeferred = {}, true
	end
	setfenv(assert(loadfile("UI/Tracker.lua")), env)("LegacyForever", ns)
	assert(owners[modules[1]] == native, "private host attachment is independent of Blizzard")
	if case.deferred then
		local after = ns.ForeverCoreHostAfter
		ns.ForeverCoreHostAfter = nil
		for _, fn in ipairs(after) do
			fn()
		end
	end
	for _, event in ipairs(case.fire) do
		for index = #waits, 1, -1 do
			local waiting = waits[index]
			waiting.seen[event] = true
			local ready = true
			for _, name in ipairs(waiting.events) do
				ready = ready and waiting.seen[name] == true
			end
			if ready then
				table.remove(waits, index)
				waiting.fn()
			end
		end
	end
	assert(#waits == 0, case.label .. ": no wait is left for an event that already fired")
	assert(#timers == 1, case.label .. ": the attach pass is scheduled")
	assert(#warnings == 1, case.label .. ": the unattached check is scheduled")
	for _, fn in ipairs(timers) do
		fn()
	end
	assert(owners[modules[1]] == native, "private ownership survives initialization and late loading")
	local section = modules[1]
	assert(section.show.get() == true)
	section.show.set(false)
	assert(shown == false, "hide writes the saved section switch")
	assert(refreshes == 1, "menu hide refreshes exactly once")
	section:LayoutContents() -- hidden challenges must not read or render the model
	local accepted, reason = section.contract.click({ kind = "block", id = 10 }, "LeftButton")
	assert(accepted == nil and reason == nil, "click leaves refusal reporting to ForeverCore.Open")
	section.contract.click({ kind = "section" }, "LeftButton")
	assert(opened[1].addon == "LegacyForever" and opened[1].where == 10, "block click opens the named challenge")
	assert(opened[2].addon == "LegacyForever" and opened[2].where == nil, "section click opens the named panel")
	local slots, actions = {}, {}
	local openAddon, openWhere
	local menu = {}
	function menu:Open(label, addon, where)
		slots[#slots + 1] = "Open:" .. label
		openAddon, openWhere = addon, where
	end
	for _, slot in ipairs({ "Title", "End" }) do
		menu[slot] = function(_, label, action)
			slots[#slots + 1] = slot .. ":" .. label
			actions[slot] = action
		end
	end
	section.contract.menu({ kind = "block", id = 10 }, menu)
	assert(table.concat(slots, "|") == "Title:Challenge|Open:Open in the Legacy panel|End:Stop tracking")
	assert(openAddon == "LegacyForever" and openWhere == 10, "block menu opens the named challenge")
	actions.End()
	assert(#tracked == 0, "End stops tracking the challenge")
	slots = {}
	section.contract.menu({ kind = "section" }, menu)
	assert(
		table.concat(slots, "|") == "Title:Legacy|Open:Open in the Legacy panel",
		"section header supplies its title"
	)
	assert(openAddon == "LegacyForever" and openWhere == nil, "section menu opens the named panel")
	tracked[1], tracked[2] = 10, 11
	slots = {}
	section.contract.menu({ kind = "section" }, menu)
	assert(slots[3] == "End:Stop tracking all", "a section with tracked challenges offers Stop tracking all")
	actions.End()
	assert(#tracked == 0, "Stop tracking all clears every tracked challenge")
	checks = checks + 1
end
print("tracker_lifecycle_spec: " .. checks .. " load-order cases passed")

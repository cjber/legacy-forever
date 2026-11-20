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
	local panelLocked, opened = false, {}
	env.LEGACY_MICRO_BUTTON_LOCKED_TOOLTIP = "Panel locked"
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
			PanelLocked = function()
				return panelLocked
			end,
			ShowInLegacyPanel = function(id)
				opened[#opened + 1] = id or "section"
			end,
		},
	}
	env.ForeverCore = {
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
	setfenv(assert(loadfile("Core/ForeverRequire.lua")), env)("Addon", ns)
	if case.deferred then
		ns.ForeverCoreHostAfter, ns.ForeverCoreHostDeferred = {}, true
	end
	setfenv(assert(loadfile("UI/Tracker.lua")), env)("Addon", ns)
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
	section.contract.click({ kind = "block", id = 10 }, "LeftButton")
	section.contract.click({ kind = "section" }, "LeftButton")
	assert(opened[1] == 10 and opened[2] == "section", "click opens the challenge or panel")
	local slots, actions = {}, {}
	local menu = {}
	for _, slot in ipairs({ "Title", "Open", "End" }) do
		menu[slot] = function(_, label, action)
			slots[#slots + 1] = slot .. ":" .. label
			actions[slot] = action
		end
	end
	section.contract.menu({ kind = "block", id = 10 }, menu)
	assert(table.concat(slots, "|") == "Title:Challenge|Open:Open in the Legacy panel|End:Stop tracking")
	panelLocked = true
	local accepted, reason = actions.Open()
	assert(accepted == false and reason == "Panel locked", "Open reports why the panel refused")
	actions.End()
	assert(#tracked == 0, "End stops tracking the challenge")
	slots = {}
	section.contract.menu({ kind = "section" }, menu)
	assert(
		table.concat(slots, "|") == "Title:Legacy|Open:Open in the Legacy panel",
		"section header supplies its title"
	)
	tracked[1], tracked[2] = 10, 11
	slots = {}
	section.contract.menu({ kind = "section" }, menu)
	assert(slots[3] == "End:Stop tracking all", "a section with tracked challenges offers Stop tracking all")
	actions.End()
	assert(#tracked == 0, "Stop tracking all clears every tracked challenge")
	checks = checks + 1
end
print("tracker_lifecycle_spec: " .. checks .. " load-order cases passed")

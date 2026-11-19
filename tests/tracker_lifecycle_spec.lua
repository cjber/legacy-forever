-- Initialization must tolerate either native event order and an addon loaded after login.
local checks = 0
local function noop() end
for _, readyAtLoad in ipairs({ false, true }) do
	local callbacks, timers, modules, owners = {}, {}, {}, {}
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
			ContinueAfterAllEvents = function(fn, first, second)
				assert(first == "PLAYER_ENTERING_WORLD" and second == "VARIABLES_LOADED")
				if readyAtLoad then
					fn()
				else
					callbacks[#callbacks + 1] = fn
				end
			end,
		},
		C_Timer = {
			After = function(delay, fn)
				if delay == 0 then
					timers[#timers + 1] = fn
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
	setfenv(assert(loadfile("UI/Tracker.lua")), env)("Addon", ns)
	if not readyAtLoad then
		assert(owners[modules[1]] == native, "private host attachment is independent of Blizzard")
		for _, fn in ipairs(callbacks) do
			fn()
		end
	end
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

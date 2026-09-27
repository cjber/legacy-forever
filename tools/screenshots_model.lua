-- Run by tools/screenshots.py from the repository root: luajit tools/screenshots_model.lua <character.lua>
-- The addon's own Data/Legacy.lua and Model.lua answer what the screenshots draw, for the character
-- screenshots.py writes as a Lua table; the answers go to stdout as JSON.
local ns = {}
assert(loadfile("Data/Legacy.lua"))("LegacyForever", ns)
assert(loadfile("Model.lua"))("LegacyForever", ns)
local Model, data = ns.Model, ns.Data
local character = assert(loadfile(arg[1]))()

---@param achievementID number
---@return LegacyCriteria?
local function Criteria(achievementID)
	return character.criteria[achievementID]
end

---@param achievementID number
---@return string
local function Name(achievementID)
	return character.names[achievementID]
end

-- Live.lua's RefsDone: done when any ref is, unknown when the game reports none of them.
---@param refs LegacyRefs
---@return boolean?
local function RefsDone(refs)
	local state
	for _, ref in ipairs(refs) do
		local progress = (Criteria(ref[1]) or {})[ref[2]]
		if progress then
			if progress.completed then
				return true
			end
			state = false
		end
	end
	return state
end

local function Encode(value)
	local kind = type(value)
	if kind == "string" then
		return '"' .. value:gsub('[%c"\\]', function(char)
			return ("\\u%04x"):format(char:byte())
		end) .. '"'
	elseif kind == "number" then
		return value == math.floor(value) and ("%d"):format(value) or ("%.17g"):format(value)
	elseif kind == "boolean" then
		return tostring(value)
	elseif kind == "nil" then
		return "null"
	end
	local parts = {}
	if next(value) == nil or #value > 0 then
		for _, item in ipairs(value) do
			parts[#parts + 1] = Encode(item)
		end
		return "[" .. table.concat(parts, ",") .. "]"
	end
	for key, item in pairs(value) do
		parts[#parts + 1] = Encode(tostring(key)) .. ":" .. Encode(item)
	end
	table.sort(parts)
	return "{" .. table.concat(parts, ",") .. "}"
end

local objectives = {}
for _, uiMapID in ipairs(character.zones) do
	local groups = Model.ZoneObjectives(data, uiMapID, character.visible, Criteria)
	for _, group in ipairs(groups) do
		group.zoneKey = Model.ZoneKey(group)
	end
	objectives[#objectives + 1] = { uiMapID = uiMapID, groups = groups, count = Model.CountObjectives(groups) }
end

local counted = function(key)
	return character.counted[key] == true
end
local completion = {}
for _, uiMapID in ipairs(character.completion) do
	local snapshot = {
		explored = character.explored,
		taxis = character.taxis,
		faction = character.faction,
		refsDone = RefsDone,
		reaction = function()
			return 4
		end,
	}
	completion[#completion + 1] =
		{ uiMapID = uiMapID, result = Model.ZoneCompletion(data.completion[uiMapID], snapshot, counted) }
end

print(Encode({
	objectives = objectives,
	unlocated = Model.Unlocated(data, character.visible, Criteria),
	tracked = Model.TrackedBlocks(data, character.tracked, character.visible, Criteria, Name),
	completion = completion,
}))

---@type string, LegacyForeverNamespace
local _, ns = ...

-- Caught errors for the report window (cjber/adventure-guide-forever docs/report-window.md). ns.SafeCall runs a
-- callback as pcall does, keeps the last few errors with a short stack for /lf report, and still hands each one to the
-- game's error handler, so BugSack and the default error frame see exactly what they saw before. Nothing here knows
-- about the rest of the addon: the file copies across the Forever addons as is.

local MAX_ERRORS = 5
local MAX_MESSAGE = 300
local STACK_LINES = 4

---@class LegacyCaughtError
---@field label string where it was caught, e.g. "route listener"
---@field message string the error, cut to 300 characters
---@field stack string up to four stack lines, outermost last
---@field count integer how many times this label and message were caught this session
---@field time number GetTime() when it was last caught

-- Oldest first; a repeat moves to the end with its count raised.
---@type LegacyCaughtError[]
local caught = {}

---@param text string
---@param limit integer
---@return string
local function Cut(text, limit)
	return #text > limit and text:sub(1, limit - 3) .. "..." or text
end

-- Keep `message` from `label`, with `stack` (a traceback) cut to its first lines that name a file.
---@param label string
---@param message any
---@param stack? string
function ns.RecordError(label, message, stack)
	message = Cut(tostring(message), MAX_MESSAGE)
	local lines = {}
	for line in (stack or ""):gmatch("[^\n]+") do
		line = strtrim(line)
		if #lines < STACK_LINES and line:find("%.lua:%d+") then
			lines[#lines + 1] = line
		end
	end
	local entry
	for index, old in ipairs(caught) do
		if old.label == label and old.message == message then
			entry = table.remove(caught, index)
			break
		end
	end
	entry = entry or { label = label, message = message, count = 0 }
	entry.stack, entry.count, entry.time = table.concat(lines, "\n"), entry.count + 1, GetTime()
	caught[#caught + 1] = entry
	if #caught > MAX_ERRORS then
		table.remove(caught, 1)
	end
end

-- The errors caught this session, oldest first, as copies.
---@return LegacyCaughtError[]
function ns.CaughtErrors()
	local copies = {}
	for index, entry in ipairs(caught) do
		copies[index] = {
			label = entry.label,
			message = entry.message,
			stack = entry.stack,
			count = entry.count,
			time = entry.time,
		}
	end
	return copies
end

---@return table
local function Pack(...)
	return { n = select("#", ...), ... } -- multi-value: every result
end

local stack
local function Trace(message)
	stack = debugstack and debugstack(2) or debug.traceback()
	return message
end

-- Run fn(...) as pcall would: true and its results, or false and the error. A failure is kept for the report and
-- passed on to the game's error handler, never swallowed.
---@param label string where this call is made from, as the report names it
---@param fn function
---@return boolean ok, any ...
function ns.SafeCall(label, fn, ...)
	local results = Pack(xpcall(fn, Trace, ...))
	if not results[1] then
		local message = results[2]
		ns.RecordError(label, message, stack)
		stack = nil
		local handler = geterrorhandler()
		pcall(handler, message)
	end
	return unpack(results, 1, results.n) -- multi-value: every result, as pcall
end

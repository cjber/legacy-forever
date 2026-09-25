-- Run from the repository root: luajit tests/locale_spec.lua
-- Every phrase a player reads goes through L, so CurseForge's Localization page can translate it: a text sink in
-- the shipped Lua (outside Locales/) never gets a bare English literal, and Locales/phrases.txt, the list pasted
-- into CurseForge, is what tools/phrases.py prints today.
local checks = 0
local function check(condition, label)
	checks = checks + 1
	assert(condition, label)
end

-- The argument positions that reach the screen, by call name.
local SINKS = {
	Print = { 1 },
	SetText = { 1 },
	SetHeader = { 1 },
	AddLine = { 1 },
	AddDoubleLine = { 1, 2 },
	AddObjective = { 2 },
	CreateTitle = { 1 },
	CreateButton = { 1 },
	CreateCheckbox = { 1 },
	GameTooltip_SetTitle = { 2 },
	GameTooltip_AddNormalLine = { 2 },
	GameTooltip_AddHighlightLine = { 2 },
	GameTooltip_AddInstructionLine = { 2 },
	GameTooltip_AddDisabledLine = { 2 },
	GameTooltip_AddColoredLine = { 2 },
	GameTooltip_AddErrorLine = { 2 },
}

-- /lf audit and /lf criteria: output for reporting a data problem, left in English on purpose.
local DEBUG = {
	["%d unfinished Legacy challenges listed for this character"] = true,
	["the game listed none unfinished; if you're below level 25 or just logged in, try again shortly."] = true,
	["%d located objectives checked, %d unknown to the game"] = true,
	["  unknown criteria "] = true,
	["%d challenges have objectives with no fixed location"] = true,
	["tracker: %d tracked, Legacy section %s"] = true,
	["data from build %s, client build %s.%s"] = true,
	["achievement %d (%s): %d criteria"] = true,
	["  %d: id %s type %s asset %s %s%s"] = true,
	["usage: /lf criteria 684"] = true,
	["zone completion: no data for the zone you're in."] = true,
	["quests from QuestieDB: %s"] = true,
	["zone completion for %s (map %d): %s"] = true,
	["  explored area not in the data: "] = true,
	["  the game reports nothing explored in this zone"] = true,
	["  flight path %d (%s): %s"] = true,
}

-- Names, strings (with their quotes kept off) and single punctuation; comments dropped.
local function Tokens(source)
	local tokens, i = {}, 1
	while i <= #source do
		local c = source:sub(i, i)
		if source:find("^%-%-%[(=*)%[", i) then
			local equals = source:match("^%-%-%[(=*)%[", i)
			i = select(2, source:find("]" .. equals .. "]", i, true)) + 1
		elseif source:find("^%-%-", i) then
			i = (source:find("\n", i) or #source) + 1
		elseif c == '"' or c == "'" then
			local j = i + 1
			while source:sub(j, j) ~= c do
				j = j + (source:sub(j, j) == "\\" and 2 or 1)
			end
			tokens[#tokens + 1] = { kind = "string", value = source:sub(i + 1, j - 1) }
			i = j + 1
		elseif c:find("[%a_]") then
			local name = source:match("^[%w_]+", i)
			tokens[#tokens + 1] = { kind = "name", value = name }
			i = i + #name
		elseif c:find("%s") then
			i = i + 1
		else
			tokens[#tokens + 1] = { kind = "punct", value = c }
			i = i + 1
		end
	end
	return tokens
end

-- A literal a player would read: letters left once colour codes and format specifiers are gone.
local function IsWords(text)
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("%%[-%d%.]*[sdfgx%%]", "")
	return text:find("%a") ~= nil
end

-- The bare literals in a call's text arguments, or in `headerText = "..."`.
local function BareLiterals(tokens)
	local found = {}
	-- Only the argument's own literals: one passed to another call ("mapCollapsed") is a key, but a
	-- parenthesised format string, ("%s left"):format(n), is the text.
	local function Scan(from, to)
		local depth = 0
		for k = from, to do
			local token = tokens[k]
			local value = token.kind == "punct" and token.value
			if value == "(" or value == "{" or value == "[" then
				depth = depth + 1
			elseif value == ")" or value == "}" or value == "]" then
				depth = depth - 1
			end
			local translated = tokens[k - 1].value == "[" and tokens[k - 2].value == "L"
			local before = tokens[k - 2]
			local keyword = before.value == "and"
				or before.value == "or"
				or before.value == "not"
				or before.value == "return"
			local call = (before.kind == "name" and not keyword) or before.value == ")" or before.value == "]"
			local wrapped = tokens[k - 1].value == "(" and tokens[k + 1].value == ")" and depth == 1 and not call
			local shown = token.kind == "string" and (depth == 0 or wrapped) and not translated
			if shown and IsWords(token.value) and not DEBUG[token.value] then
				found[#found + 1] = token.value
			end
		end
	end
	for k, token in ipairs(tokens) do
		local positions = token.kind == "name" and SINKS[token.value]
		if positions and tokens[k + 1] and tokens[k + 1].value == "(" then
			local depth, argument, start = 0, 1, k + 2
			local wanted = {}
			for _, position in ipairs(positions) do
				wanted[position] = true
			end
			for j = k + 1, #tokens do
				local value = tokens[j].kind == "punct" and tokens[j].value
				if value == "(" or value == "{" or value == "[" then
					depth = depth + 1
				elseif value == ")" or value == "}" or value == "]" then
					depth = depth - 1
				end
				local ends = depth == 0 or (depth == 1 and value == ",")
				if ends then
					if wanted[argument] then
						Scan(start, j - 1)
					end
					argument, start = argument + 1, j + 1
					if depth == 0 then
						break
					end
				end
			end
		elseif token.value == "headerText" and tokens[k + 1].value == "=" then
			Scan(k + 2, k + 2)
		end
	end
	return found
end

-- The guard itself: a bare phrase in each kind of sink is caught, a translated one or a colour code is not.
local caught = BareLiterals(Tokens([[
ns.Print(("Hello %s"):format(name))
GameTooltip_AddInstructionLine(tooltip, Setting("key") and "Click me" or L["Click"])
root:CreateCheckbox(L["Shown"], IsShown, Toggle, "tracker")
block:AddObjective("Extra", "...")
root:CreateTitle("|cff808080" .. L["Nothing"] .. "|r") -- "a comment" is not a literal
local Mixin = { headerText = "Section" }
]]))
check(#caught == 3, "three bare phrases caught, not " .. #caught)
check(caught[1] == "Hello %s" and caught[2] == "Click me" and caught[3] == "Section", "the right three")

local shipped = {}
for line in io.lines("LegacyForever.toc") do
	local file = line:match("^([^#].-%.lua)%s*$")
	if file and not file:find("^Locales") then
		shipped[#shipped + 1] = file:gsub("\\", "/")
	end
end
check(#shipped > 5, "the TOC lists the shipped Lua")
for _, file in ipairs(shipped) do
	local handle = assert(io.open(file))
	local bare = BareLiterals(Tokens(handle:read("*a")))
	handle:close()
	check(#bare == 0, ("%s shows without L[]: %s"):format(file, table.concat(bare, " | ")))
end

local handle = assert(io.open("Locales/phrases.txt"))
local committed = handle:read("*a")
handle:close()
local pipe = assert(io.popen("python3 tools/phrases.py"))
local printed = pipe:read("*a")
pipe:close()
check(printed ~= "", "tools/phrases.py prints the phrases")
check(committed == printed, "Locales/phrases.txt is stale: python3 tools/phrases.py > Locales/phrases.txt")

-- The English fallback: a phrase no locale translates reads as itself.
local ns = {}
assert(loadfile("Locales/enUS.lua"))("LegacyForever", ns)
check(ns.L["Stop tracking"] == "Stop tracking", "an untranslated phrase is its English key")

print(("locale_spec: %d checks passed"):format(checks))

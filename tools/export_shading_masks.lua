-- Export the runtime manifest for generated previews without parsing Lua text.
local ns = {}
assert(loadfile(arg[1]))("LegacyForever", ns)
for zone, areas in pairs(ns.ShadingMasks) do
	for key, mask in pairs(areas) do
		io.write(zone, "\t", key)
		for _, value in ipairs(mask) do
			io.write("\t", value)
		end
		io.write("\n")
	end
end

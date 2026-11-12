local ns = {}
assert(loadfile(arg[1]))("LegacyForever", ns)
for zoneID, zone in pairs(ns.Explore.zones) do
	for key, rings in pairs(zone.areas) do
		for _, ring in ipairs(rings) do
			io.write(zoneID, "\t", key, "\t1")
			for _, value in ipairs(ring) do
				io.write("\t", value)
			end
			io.write("\n")
		end
	end
end

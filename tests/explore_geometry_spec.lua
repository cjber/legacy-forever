-- Generated terrain must triangulate to exactly its polygon area. Per-vertex clamping at map edges previously
-- produced overlapping triangles, including Feralas's 404:256:256:320 ring.
local ns = {}
assert(loadfile("Data/Explore.lua"))("LegacyForever", ns)
assert(loadfile("UI/MapContents.lua"))("LegacyForever", ns)
local checked = 0
for map, zone in pairs(ns.Explore.zones) do
	for key, rings in pairs(zone.areas) do
		for _, ring in ipairs(rings) do
			local polygon = 0
			for i = 1, #ring, 2 do
				local j = (i + 1) % #ring + 1
				polygon = polygon + ring[i] * ring[j + 1] - ring[j] * ring[i + 1]
			end
			polygon = math.abs(polygon) / 2
			local triangles = 0
			for _, t in ipairs(ns.MapContents.Triangles({ ring })) do
				triangles = triangles + math.abs((t[3] - t[1]) * (t[6] - t[2]) - (t[4] - t[2]) * (t[5] - t[1])) / 2
			end
			assert(
				math.abs(triangles - polygon) < 1e-9,
				("map %d area %s: polygon %.10f, triangles %.10f"):format(map, key, polygon, triangles)
			)
			checked = checked + 1
		end
	end
end
assert(checked > 0, "no generated terrain rings checked")
print(("explore_geometry_spec: %d rings passed"):format(checked))

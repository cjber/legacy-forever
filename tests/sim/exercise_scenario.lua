-- luacheck: read globals scenario
scenario("every surface, in and out of combat and across a reload", function(sim)
	dofile("tests/sim/forever_core.lua").install(sim)
	sim:exercise()
end)

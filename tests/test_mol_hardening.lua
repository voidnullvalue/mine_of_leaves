local templates = {
	"corridor",
	"chamber",
	"vestibule",
	"hallway_narrow",
	"corridor_bent",
	"stair_segment",
	"column_hall",
	"resource_room",
}

local function lua_files_under_mods()
	local files = {}
	local root = rawget(_G, "PROJECT_ROOT") or "."
	local pipe = io.popen("find " .. root .. "/mods -name '*.lua' -type f | sort")
	if not pipe then return files end
	for path in pipe:lines() do
		files[#files + 1] = path
	end
	pipe:close()
	return files
end

local bad_seed_tonumber = {}
for _, path in ipairs(lua_files_under_mods()) do
	local fh = io.open(path, "r")
	if fh then
		local text = fh:read("*a")
		fh:close()
		if string.find(text, "tonumber%s*%(%s*minetest%.get_mapgen_setting", 1) then
			bad_seed_tonumber[#bad_seed_tonumber + 1] = path
		end
	end
end
assert_eq(#bad_seed_tonumber, 0, "production code never tonumber()s full world seed")

for _, template_name in ipairs(templates) do
	local room_def = mol.rooms.generate(template_name, 8675309, {})
	assert_true(room_def ~= nil, template_name .. " hardening generates")
	assert_true(#room_def.door_slots >= 1, template_name .. " hardening has at least one door slot")
	assert_true(#room_def.arrival >= 2, template_name .. " hardening has at least two arrival positions")
end

for _, coord in ipairs({-mol.CELL_MAX_COORD, mol.CELL_MAX_COORD}) do
	local world = mol.cell_to_world(coord, coord, coord)
	local round_trip = mol.world_to_cell(world)
	assert_eq(round_trip, {x = coord, y = coord, z = coord}, "cell boundary round trip " .. coord)
	assert_true(world.x >= -2147483648 and world.x <= 2147483647, "cell boundary x int32 " .. coord)
	assert_true(world.y >= -2147483648 and world.y <= 2147483647, "cell boundary y int32 " .. coord)
	assert_true(world.z >= -2147483648 and world.z <= 2147483647, "cell boundary z int32 " .. coord)
end

assert_eq(mol.INTERIOR_ORIGIN.x % mol.MAPBLOCK_SIZE, 0, "interior origin x is MapBlock-aligned")
assert_eq(mol.INTERIOR_ORIGIN.y % mol.MAPBLOCK_SIZE, 0, "interior origin y is MapBlock-aligned")
assert_eq(mol.INTERIOR_ORIGIN.z % mol.MAPBLOCK_SIZE, 0, "interior origin z is MapBlock-aligned")

mol.graph.init_world("500")
local previous_room = "room_objective"
local previous_slot = 3
for i = 1, 84 do
	local room_id = "perf_room_" .. i
	mol.graph.add_room(room_id, "corridor", 100000 + i)
	mol.graph.connect(previous_room .. ":slot_" .. previous_slot, room_id, 1, true)
	previous_room = room_id
	previous_slot = 2
end
local started = os.clock()
local result = mol.graph.validate({skip_aesthetic = true})
local elapsed = os.clock() - started
assert_true(result.ok, "100-room graph validates")
assert_true(elapsed < 0.100, "100-room graph validation completes under 100ms")

-- The performance graph above intentionally mutates the active graph. The
-- softlock checks below each call init_world(), which clears that state.
for _, seed in ipairs({"0", "1", "500"}) do
	mol.graph.init_world(seed)
	local validation = mol.graph.validate({skip_aesthetic = true})
	assert_true(validation.ok, "softlock BFS validates seed " .. seed)
end

mol.graph.init_world("12345")
local mutation_result = mol.mutations.apply({
	type = "reroute",
	from_door_id = "room_orient:slot_2",
	to_room_id = "room_hazard",
	to_slot = 1,
	reason = "hardening_scripted_route",
})
assert_true(mutation_result.ok, "scripted mutation preserves viable objective route")

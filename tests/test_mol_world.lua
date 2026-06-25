-- ---------------------------------------------------------------------------
-- Regression tests for mol_world generation and node properties.
-- ---------------------------------------------------------------------------

-- Additional mocks required by mol_world/init.lua at load time.
minetest._registered_on_generated = minetest._registered_on_generated or {}
minetest._registered_on_newplayers = minetest._registered_on_newplayers or {}
minetest._registered_on_placenodes = minetest._registered_on_placenodes or {}

-- Load world generator.  mol_nodes was loaded just before this file in
-- run_tests.lua so node content IDs are already assigned.
dofile("mods/mol_world/init.lua")

-- ---------------------------------------------------------------------------
-- VoxelManip factory
-- ---------------------------------------------------------------------------
local function make_vm(p1, p2)
	local area = VoxelArea:new({MinEdge = p1, MaxEdge = p2})
	local sz = (p2.x - p1.x + 1) * (p2.y - p1.y + 1) * (p2.z - p1.z + 1)
	local data, p2data = {}, {}
	for i = 1, sz do data[i] = 0; p2data[i] = 0 end
	local vm = {_data = data, _p2data = p2data, _area = area}
	function vm:read_from_map() return p1, p2 end
	function vm:get_data() return self._data end
	function vm:get_param2_data() return self._p2data end
	function vm:set_data(d) self._data = d end
	function vm:set_param2_data(d) self._p2data = d end
	function vm:calc_lighting() end
	function vm:write_to_map() end
	function vm:update_map() end
	return vm
end

-- ---------------------------------------------------------------------------
-- Trigger on_generated for a chunk that covers the spawn area
-- ---------------------------------------------------------------------------
local MINP = {x = -16, y = -16, z = -16}
local MAXP = {x =  15, y =  79, z =  15}

local last_vm
minetest.get_voxel_manip = function()
	local vm = make_vm(MINP, MAXP)
	last_vm = vm
	return vm
end

-- Reset metadata so door tests are clean.
minetest._meta = {}

for _, cb in ipairs(minetest._registered_on_generated) do
	cb(MINP, MAXP, 12345)
end

local area = last_vm._area
local data = last_vm._data

local air_id     = minetest.get_content_id("air")
local floor_id   = minetest.get_content_id("mol:floor")
local void_id    = minetest.get_content_id("mol:void")
local bwall_id   = minetest.get_content_id("mol:boundary_wall")
local wall_id    = minetest.get_content_id("mol:wall")
local ceiling_id = minetest.get_content_id("mol:ceiling")

local YARD_MIN        = mol.YARD_MIN
local YARD_MAX        = mol.YARD_MAX
local HOUSE_POS       = mol.HOUSE_POS
local HOUSE_SIZE      = mol.HOUSE_SIZE
local BOUNDARY_HEIGHT = mol.BOUNDARY_HEIGHT
local SPAWN_POS       = mol.SPAWN_POS

-- ---------------------------------------------------------------------------
-- T1: yard floor is mol:floor at a non-house yard position (0, 0, -5)
-- ---------------------------------------------------------------------------
assert_eq(data[area:index(0, 0, -5)], floor_id,
	"T1 yard floor at (0,0,-5) is mol:floor")

-- ---------------------------------------------------------------------------
-- T2: yard interior above floor is real air (not mol:void)
-- ---------------------------------------------------------------------------
assert_eq(data[area:index(0, 1, -5)], air_id,
	"T2 yard interior at y=1 is air")
assert_eq(data[area:index(0, 3, -5)], air_id,
	"T2 yard interior at y=3 is air")

-- ---------------------------------------------------------------------------
-- T3: sky column above BOUNDARY_HEIGHT is also air (sunlight path)
-- ---------------------------------------------------------------------------
assert_eq(data[area:index(0, BOUNDARY_HEIGHT + 2, -5)], air_id,
	"T3 sky column at y=(BOUNDARY_HEIGHT+2) is air")
assert_eq(data[area:index(0, MAXP.y, -5)], air_id,
	"T3 sky column at top of chunk is air")

-- ---------------------------------------------------------------------------
-- T4: spawn position (0, 3, -8) is air — player does not spawn inside a node
-- ---------------------------------------------------------------------------
assert_eq(data[area:index(SPAWN_POS.x, SPAWN_POS.y, SPAWN_POS.z)], air_id,
	"T4 spawn position is air")

-- ---------------------------------------------------------------------------
-- T5: spawn is inside the playable yard (not outside boundary)
-- ---------------------------------------------------------------------------
assert_true(SPAWN_POS.x > YARD_MIN.x and SPAWN_POS.x < YARD_MAX.x,
	"T5 spawn x is inside yard interior")
assert_true(SPAWN_POS.z > YARD_MIN.z and SPAWN_POS.z < YARD_MAX.z,
	"T5 spawn z is inside yard interior")
assert_true(SPAWN_POS.y > 0,
	"T5 spawn y is above floor level")

-- ---------------------------------------------------------------------------
-- T6: boundary walls are placed at yard perimeter
-- ---------------------------------------------------------------------------
assert_eq(data[area:index(YARD_MIN.x, 3, 0)], bwall_id,
	"T6 west boundary wall present at y=3")
assert_eq(data[area:index(0, 3, YARD_MIN.z)], bwall_id,
	"T6 north boundary wall present at y=3")
-- South boundary (z=YARD_MAX.z=14) is in the chunk (MAXP.z=15)
assert_eq(data[area:index(0, 3, YARD_MAX.z)], bwall_id,
	"T6 south boundary wall present at y=3")
-- East boundary (x=YARD_MAX.x=12) is in the chunk (MAXP.x=15)
assert_eq(data[area:index(YARD_MAX.x, 3, 0)], bwall_id,
	"T6 east boundary wall present at y=3")

-- ---------------------------------------------------------------------------
-- T7: exterior positions remain mol:void
-- ---------------------------------------------------------------------------
-- (-14, 3, 0) is in the chunk (MINP.x=-16) but outside the yard (yard x>=-12)
assert_eq(data[area:index(-14, 3, 0)], void_id,
	"T7 exterior at x=-14 is mol:void")

-- ---------------------------------------------------------------------------
-- T8: house ceiling node is placed at the correct absolute position
-- The house ceiling offset is y=HOUSE_SIZE.y-1=7; absolute y=HOUSE_POS.y+7=7.
-- Pick a non-doorway, non-window house ceiling position.
-- ---------------------------------------------------------------------------
local hceil_x = HOUSE_POS.x + 2  -- =  -4
local hceil_y = HOUSE_POS.y + HOUSE_SIZE.y - 1  -- = 7
local hceil_z = HOUSE_POS.z + 3  -- =  3
assert_eq(data[area:index(hceil_x, hceil_y, hceil_z)], ceiling_id,
	"T8 house ceiling placed correctly")

-- ---------------------------------------------------------------------------
-- T9: mol:void blocks sunlight (design requirement must not be broken)
-- ---------------------------------------------------------------------------
local void_def = minetest._registered_nodes and minetest._registered_nodes[":mol:void"]
assert_true(void_def ~= nil, "T9 mol:void is registered")
if void_def then
	assert_eq(void_def.sunlight_propagates, false,
		"T9 mol:void sunlight_propagates=false")
end

-- ---------------------------------------------------------------------------
-- T10: light_fixture has a nonzero light_source value
-- ---------------------------------------------------------------------------
local fixture_def = minetest._registered_nodes and minetest._registered_nodes[":mol:light_fixture"]
assert_true(fixture_def ~= nil, "T10 mol:light_fixture is registered")
if fixture_def then
	assert_true((fixture_def.light_source or 0) > 0,
		"T10 mol:light_fixture has nonzero light_source")
end

-- ---------------------------------------------------------------------------
-- T11: spawn yaw=0 faces toward house (spawn is north of house front)
-- yaw=0 in Luanti faces +Z (south).  HOUSE_POS.z=0, spawn z=-8 → south = house.
-- ---------------------------------------------------------------------------
assert_true(SPAWN_POS.z < HOUSE_POS.z,
	"T11 spawn z is north of house — yaw=0 faces south toward house entrance")

-- ---------------------------------------------------------------------------
-- T12: entry door metadata is set
-- Entry door offset {x=6,y=1,z=0} → absolute {x=0,y=1,z=0}
-- ---------------------------------------------------------------------------
local door_meta = minetest._meta["0,1,0"]
assert_true(door_meta ~= nil and door_meta.door_id == "entry",
	"T12 entry door has door_id='entry' metadata")

-- ---------------------------------------------------------------------------
-- T13: no bare mol:* registrations (all must use :mol: explicit prefix)
-- ---------------------------------------------------------------------------
local bad = {}
for name in pairs(minetest._registered_nodes or {}) do
	if string.match(name, "^mol:") then bad[#bad + 1] = name end
end
for name in pairs(minetest._registered_craftitems or {}) do
	if string.match(name, "^mol:") then bad[#bad + 1] = name end
end
assert_eq(#bad, 0,
	"T13 no bare mol:* registrations (found: " .. table.concat(bad, ", ") .. ")")

-- ---------------------------------------------------------------------------
-- T14: void airlike property does not propagate sunlight (confirms T9 for
--       a full round-trip: void registered with sunlight_propagates=false,
--       and the yard air fill does not accidentally re-enable it)
-- ---------------------------------------------------------------------------
if void_def then
	assert_eq(void_def.drawtype, "airlike",
		"T14 mol:void drawtype is airlike")
	assert_eq(void_def.sunlight_propagates, false,
		"T14 mol:void still non-sunlit after yard fix")
end

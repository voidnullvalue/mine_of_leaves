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

local function offset_in_bounds(offset)
	return offset and
		offset.x >= 0 and offset.x <= 63 and
		offset.y >= 0 and offset.y <= 63 and
		offset.z >= 0 and offset.z <= 63
end

for _, template_name in ipairs(templates) do
	local room_def = mol.rooms.generate(template_name, 42, {})
	assert_true(room_def ~= nil, template_name .. " generates")
	assert_true(#room_def.door_slots >= 1, template_name .. " has a door slot")
	assert_true(#room_def.arrival >= 2, template_name .. " has arrival positions")
	assert_true(#room_def.nodes > 0, template_name .. " has nodes")
	assert_true(mol.rooms.template_status[template_name], template_name .. " startup validation passed")

	local all_offsets_in_bounds = true
	for _, spec in ipairs(room_def.nodes) do
		all_offsets_in_bounds = all_offsets_in_bounds and offset_in_bounds(spec.offset)
	end
	for _, slot in ipairs(room_def.door_slots) do
		all_offsets_in_bounds = all_offsets_in_bounds and offset_in_bounds(slot.offset)
	end
	for _, arrival in ipairs(room_def.arrival) do
		all_offsets_in_bounds = all_offsets_in_bounds and offset_in_bounds(arrival.offset)
	end
	assert_true(all_offsets_in_bounds, template_name .. " offsets in bounds")

	local same_a = mol.rooms.generate(template_name, 1, {})
	local same_b = mol.rooms.generate(template_name, 1, {})
	assert_true(test_same_value(same_a.nodes, same_b.nodes), template_name .. " same seed produces same nodes")

	if template_name ~= "vestibule" then
		local diff_a = mol.rooms.generate(template_name, 1, {})
		local diff_b = mol.rooms.generate(template_name, 2, {})
		assert_true(not test_same_value(diff_a.nodes, diff_b.nodes), template_name .. " different seeds produce different nodes")
	end
end

local chamber = mol.rooms.generate("chamber", 42, {})
-- The chamber template currently registers seven explicit door directions in
-- mods/mol_rooms/templates/chamber.lua. This assertion documents the existing
-- template shape; Stage 9 does not change room topology.
assert_eq(#chamber.door_slots, 7, "chamber has seven door slots")

local vestibule_a = mol.rooms.generate("vestibule", 1, {})
local vestibule_b = mol.rooms.generate("vestibule", 2, {})
assert_eq(#vestibule_a.door_slots, 2, "vestibule seed 1 has exactly 2 door slots")
assert_eq(#vestibule_b.door_slots, 2, "vestibule seed 2 has exactly 2 door slots")

local before_unknown_logs = #test_logs
assert_eq(mol.rooms.generate("missing_template", 42, {}), nil, "unknown template returns nil")
local saw_unknown_log = false
for i = before_unknown_logs + 1, #test_logs do
	if test_logs[i].level == "error" and string.find(test_logs[i].message, "unknown template", 1, true) then
		saw_unknown_log = true
	end
end
assert_true(saw_unknown_log, "unknown template logs an error")

local function make_mock_vm()
	local min_edge = {x = 1023, y = -65, z = -1}
	local max_edge = {x = 1088, y = 0, z = 64}
	local sx = max_edge.x - min_edge.x + 1
	local sy = max_edge.y - min_edge.y + 1
	local sz = max_edge.z - min_edge.z + 1
	local data = {}
	local param2 = {}
	for i = 1, sx * sy * sz do
		data[i] = 999
		param2[i] = 0
	end
	local vm = {
		data = data,
		param2 = param2,
		read_from_map = function(self, minp, maxp)
			return min_edge, max_edge
		end,
		get_data = function(self)
			return self.data, {x = sx, y = sy, z = sz}
		end,
		get_param2_data = function(self)
			return self.param2
		end,
		set_data = function(self, new_data)
			self.data = new_data
		end,
		set_param2_data = function(self, new_param2)
			self.param2 = new_param2
		end,
		calc_lighting = function() end,
		write_to_map = function() end,
		update_map = function() end,
	}
	return vm
end

local vm = make_mock_vm()
minetest._voxel_manip = vm
local before_build_logs = #test_logs
mol.cells.build({x = 0, y = 0, z = 0}, {
	room_id = "oob_test_room",
	template = "test",
	nodes = {
		{offset = {x = 1, y = 1, z = 1}, name = "mol:floor"},
		{offset = {x = 64, y = 1, z = 1}, name = "mol:wall"},
	},
})

local saw_oob_log = false
for i = before_build_logs + 1, #test_logs do
	if test_logs[i].level == "error" and string.find(test_logs[i].message, "out-of-bounds", 1, true) then
		saw_oob_log = true
	end
end
assert_true(saw_oob_log, "cell build logs out-of-bounds offsets")

local area = VoxelArea:new({MinEdge = {x = 1023, y = -65, z = -1}, MaxEdge = {x = 1088, y = 0, z = 64}})
local floor_id = minetest.get_content_id("mol:floor")
local wall_id = minetest.get_content_id("mol:wall")
assert_eq(vm.data[area:index(1025, -63, 1)], floor_id, "cell build writes in-bounds node")
assert_true(vm.data[area:index(1088, -63, 1)] ~= wall_id, "cell build skips out-of-bounds node")

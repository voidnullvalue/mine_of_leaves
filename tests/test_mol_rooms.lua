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

-- ---------------------------------------------------------------------------
-- Playability hardening tests (tests 1-8)
-- ---------------------------------------------------------------------------

local SOLID_NODES = {
	["mol:wall"] = true,
	["mol:floor"] = true,
	["mol:ceiling"] = true,
	["mol:dark_void"] = true,
	["mol:boundary_wall"] = true,
	["mol:hedge"] = true,
	["mol:door_frame"] = true,
}

local all_templates = {
	"corridor", "chamber", "vestibule", "hallway_narrow",
	"corridor_bent", "stair_segment", "column_hall", "resource_room",
}

for _, template_name in ipairs(all_templates) do
	local room_def = mol.rooms.generate(template_name, 42, {})

	-- Test 1: each door slot occupies a unique base position
	local slot_positions = {}
	for i, slot in ipairs(room_def.door_slots) do
		local key = slot.offset.x .. "," .. slot.offset.y .. "," .. slot.offset.z
		assert_true(not slot_positions[key], template_name .. " slot " .. i .. " has unique base position")
		slot_positions[key] = i
	end

	-- Test 2: portal contains door nodes at base, base+1, base+2
	local node_index = {}
	for _, spec in ipairs(room_def.nodes) do
		local k = spec.offset.x .. "," .. spec.offset.y .. "," .. spec.offset.z
		node_index[k] = spec
	end
	for i, slot in ipairs(room_def.door_slots) do
		local ox, oy, oz = slot.offset.x, slot.offset.y, slot.offset.z
		for dy = 0, 2 do
			local k = ox .. "," .. (oy + dy) .. "," .. oz
			local spec = node_index[k]
			assert_true(spec and spec.name == "mol:door_closed",
				template_name .. " slot " .. i .. " has door_closed at base+" .. dy)
		end
	end

	-- Tests 3-5: arrival physical validity (floor below, feet clear, head clear)
	for i, arrival in ipairs(room_def.arrival) do
		local ax, ay, az = arrival.offset.x, arrival.offset.y, arrival.offset.z
		local floor_k = ax .. "," .. (ay - 1) .. "," .. az
		local feet_k  = ax .. "," .. ay .. "," .. az
		local head_k  = ax .. "," .. (ay + 1) .. "," .. az
		local floor_spec = node_index[floor_k]
		local feet_spec  = node_index[feet_k]
		local head_spec  = node_index[head_k]
		-- Test 3: floor immediately below arrival
		assert_true(floor_spec and floor_spec.name == "mol:floor",
			template_name .. " arrival " .. i .. " has floor below (got " .. tostring(floor_spec and floor_spec.name) .. ")")
		-- Test 4: feet space is not solid
		assert_true(not SOLID_NODES[feet_spec and feet_spec.name],
			template_name .. " arrival " .. i .. " feet clear (got " .. tostring(feet_spec and feet_spec.name) .. ")")
		-- Test 5: head space is not solid
		assert_true(not SOLID_NODES[head_spec and head_spec.name],
			template_name .. " arrival " .. i .. " head clear (got " .. tostring(head_spec and head_spec.name) .. ")")
	end

	-- Test 6: no mol:void in navigable interior (mol:void is reserved for unallocated cell space)
	local found_void = false
	for _, spec in ipairs(room_def.nodes) do
		if spec.name == "mol:void" then found_void = true; break end
	end
	assert_true(not found_void, template_name .. " uses air not mol:void for navigable space")
end

-- Test 7: vestibule arrivals are physically valid (covered implicitly by tests 3-5 above)
-- Re-run for additional seeds to be sure.
for _, seed in ipairs({1, 2, 42, 8675309}) do
	local vdef = mol.rooms.generate("vestibule", seed, {})
	local vidx = {}
	for _, spec in ipairs(vdef.nodes) do
		local k = spec.offset.x .. "," .. spec.offset.y .. "," .. spec.offset.z
		vidx[k] = spec
	end
	for i, arrival in ipairs(vdef.arrival) do
		local ax, ay, az = arrival.offset.x, arrival.offset.y, arrival.offset.z
		local floor_spec = vidx[ax .. "," .. (ay - 1) .. "," .. az]
		local feet_spec  = vidx[ax .. "," .. ay .. "," .. az]
		local head_spec  = vidx[ax .. "," .. (ay + 1) .. "," .. az]
		assert_true(floor_spec and floor_spec.name == "mol:floor",
			"vestibule seed " .. seed .. " arrival " .. i .. " has floor below")
		assert_true(not SOLID_NODES[feet_spec and feet_spec.name],
			"vestibule seed " .. seed .. " arrival " .. i .. " feet clear")
		assert_true(not SOLID_NODES[head_spec and head_spec.name],
			"vestibule seed " .. seed .. " arrival " .. i .. " head clear")
	end
end

-- Test 8: graph prepare_room_def stamps all three portal nodes with canonical door_id
mol.graph.init_world("12345")
local ent_room = mol.graph.get_room("room_entrance")
if ent_room and ent_room.template and ent_room.room_seed then
	local ent_def = mol.rooms.generate(ent_room.template, ent_room.room_seed, {})
	ent_def.room_id = "room_entrance"
	mol.graph.prepare_room_def(ent_def, "room_entrance")
	local ent_idx = {}
	for _, spec in ipairs(ent_def.nodes) do
		local k = spec.offset.x .. "," .. spec.offset.y .. "," .. spec.offset.z
		ent_idx[k] = spec
	end
	for i, slot in ipairs(ent_def.door_slots) do
		local expected = "room_entrance:slot_" .. i
		local ox, oy, oz = slot.offset.x, slot.offset.y, slot.offset.z
		for dy = 0, 2 do
			local k = ox .. "," .. (oy + dy) .. "," .. oz
			local spec = ent_idx[k]
			local has_meta = spec and spec.meta and spec.meta.door_id == expected
			assert_true(has_meta,
				"room_entrance slot " .. i .. " canonical door_id at base+" .. dy)
		end
	end
end

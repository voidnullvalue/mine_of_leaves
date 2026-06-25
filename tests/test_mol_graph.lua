local critical_rooms = {
	"room_yard",
	"room_entrance",
	"room_foyer",
	"room_hall",
	"room_threshold",
	"room_orient",
	"room_contradict",
	"room_resource",
	"room_deep",
	"room_hazard",
	"room_objective",
	"room_escape",
}

local function has_room(room_id)
	return mol.graph.get_room(room_id) ~= nil
end

local function contains_error(result, text)
	for _, err in ipairs(result.errors) do
		if string.find(err, text, 1, true) then return true end
	end
	return false
end

local function graph_signature()
	local rooms = {}
	for _, room_id in ipairs(mol.graph.room_order) do
		local room = mol.graph.get_room(room_id)
		rooms[#rooms + 1] = room.room_id .. ":" .. tostring(room.template) .. ":" .. tostring(room.room_seed)
	end
	local edges = {}
	for _, edge_id in ipairs(mol.graph.edge_order) do
		local edge = mol.graph.edges[edge_id]
		edges[#edges + 1] = edge.edge_id .. ":" .. edge.from_door_id .. ":" .. edge.to_room_id .. ":" .. edge.to_slot
	end
	return table.concat(rooms, "|") .. "\n" .. table.concat(edges, "|")
end

mol.graph.init_world("12345")
assert_true(#mol.graph.room_order >= 12, "graph seed 12345 has at least 12 rooms")
for _, room_id in ipairs(critical_rooms) do
	assert_true(has_room(room_id), "graph contains " .. room_id)
end

local valid = mol.graph.validate()
assert_true(valid.ok, "generated graph validates")
assert_eq(#valid.errors, 0, "generated graph has no validation errors")

mol.graph.add_room("room_orphan_test", "chamber", 1)
local orphan = mol.graph.validate()
assert_true(not orphan.ok, "orphan graph is invalid")
assert_true(contains_error(orphan, "room_orphan_test"), "orphan error names room")

mol.graph.init_world("12345")
mol.graph.edges.self_link_test = {
	edge_id = "self_link_test",
	from_door_id = "room_entrance:slot_6",
	to_room_id = "room_entrance",
	to_slot = 6,
	reciprocal = false,
}
mol.graph.edge_order[#mol.graph.edge_order + 1] = "self_link_test"
local self_link = mol.graph.validate()
assert_true(not self_link.ok, "self-link graph is invalid")
assert_true(contains_error(self_link, "self-link"), "self-link error is reported")

mol.graph.init_world("12345")
local removed
for _, edge_id in ipairs(mol.graph.edge_order) do
	local edge = mol.graph.edges[edge_id]
	if edge.from_door_id == "room_entrance:slot_1" then
		removed = edge_id
		break
	end
end
mol.graph.edges[removed] = nil
local missing_recip = mol.graph.validate()
assert_true(not missing_recip.ok, "missing reciprocal graph is invalid")
assert_true(contains_error(missing_recip, "missing reciprocal"), "missing reciprocal error is reported")

mol.graph.init_world("12345")
assert_true(mol.graph.get_destination("room_entrance:slot_1") ~= nil, "room_entrance slot 1 has destination")
local entry_dest = mol.graph.get_destination("entry")
assert_eq(entry_dest.room_id, "room_entrance", "entry resolves to entrance")
assert_eq(entry_dest.to_slot, 1, "entry resolves to slot 1")

mol.graph.init_world("12345")
local sig_a = graph_signature()
mol.graph.init_world("12345")
local sig_b = graph_signature()
assert_eq(sig_a, sig_b, "same seed produces identical graph")

mol.graph.init_world("99999")
local valid_99999 = mol.graph.validate()
assert_true(valid_99999.ok, "generated graph seed 99999 validates")

local pass_count = 0
for seed = 1, 100 do
	mol.graph.init_world(tostring(seed))
	local result = mol.graph.validate()
	if result.ok then
		pass_count = pass_count + 1
	else
		print("Large-sample seed " .. seed .. " failed: " .. table.concat(result.errors, "; "))
	end
end
assert_eq(pass_count, 100, "large-sample graph validation passed 100/100")
print("mol_graph large-sample validation: " .. pass_count .. "/100 seeds passed")

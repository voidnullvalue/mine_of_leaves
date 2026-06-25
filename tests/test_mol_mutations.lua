local function reset_persist()
	local store = {}
	mol.persist = {
		get = function(ns, key)
			return store[ns .. ":" .. key]
		end,
		set = function(ns, key, value)
			store[ns .. ":" .. key] = value
		end,
		delete = function(ns, key)
			store[ns .. ":" .. key] = nil
		end,
	}
	return store
end

local function reset_mutation_state()
	reset_persist()
	mol.players = {}
	mol.graph.init_world("12345")
	mol.mutations.log = {}
	mol.mutations.overrides = {reroutes = {}, seals = {}, seq = 0}
	mol.mutations.MAX_LOG = 1000
	minetest._us_time = 0
end

local function graph_signature()
	local edges = {}
	for _, edge_id in ipairs(mol.graph.edge_order) do
		local edge = mol.graph.edges[edge_id]
		edges[#edges + 1] = edge.from_door_id .. ">" .. edge.to_room_id .. ":" .. edge.to_slot
	end
	return table.concat(edges, "|")
end

local function apply_or_fail(mutation, label)
	local result = mol.mutations.apply(mutation)
	assert_true(result.ok, label .. " succeeds")
	return result
end

reset_mutation_state()
apply_or_fail({
	type = "reroute",
	from_door_id = "room_hall:slot_2",
	to_room_id = "room_hazard",
	to_slot = 1,
	reason = "test",
}, "valid reroute")
local rerouted = mol.graph.get_destination("room_hall:slot_2")
assert_eq(rerouted.room_id, "room_hazard", "valid reroute updates destination room")
assert_eq(rerouted.to_slot, 1, "valid reroute updates destination slot")

reset_mutation_state()
mol.graph.add_room("room_test_leaf", "corridor", 777)
mol.graph.disconnect("room_hall:slot_2")
mol.graph.connect("room_hall:slot_2", "room_test_leaf", 1, true)
local before_orphan = graph_signature()
local before_dest = mol.graph.get_destination("room_hall:slot_2")
local orphan_result = mol.mutations.apply({
	type = "reroute",
	from_door_id = "room_hall:slot_2",
	to_room_id = "room_hazard",
	to_slot = 1,
	reason = "test_orphan",
})
assert_true(not orphan_result.ok, "orphaning reroute fails")
assert_eq(graph_signature(), before_orphan, "orphaning reroute rolls back graph")
local after_dest = mol.graph.get_destination("room_hall:slot_2")
assert_eq(after_dest.room_id, before_dest.room_id, "rollback restores original destination room")
assert_eq(after_dest.to_slot, before_dest.to_slot, "rollback restores original destination slot")

reset_mutation_state()
local before_invalid = graph_signature()
local invalid_result = mol.mutations.apply({
	type = "reroute",
	from_door_id = "room_missing:slot_1",
	to_room_id = "room_hazard",
	to_slot = 1,
})
assert_true(not invalid_result.ok, "invalid from_door_id fails")
assert_eq(graph_signature(), before_invalid, "invalid from_door_id does not modify graph")

reset_mutation_state()
local entrance_before_seal = graph_signature()
local entrance_seal_result = mol.mutations.seal("room_entrance:slot_2")
assert_true(not entrance_seal_result.ok, "orphaning seal fails")
assert_eq(graph_signature(), entrance_before_seal, "orphaning seal rolls back graph")
local original = mol.graph.get_destination("room_escape:slot_2")
local seal_result = mol.mutations.seal("room_escape:slot_2")
assert_true(seal_result.ok, "seal succeeds")
assert_eq(mol.graph.get_destination("room_escape:slot_2"), nil, "seal removes destination")
local unseal_result = mol.mutations.unseal("room_escape:slot_2")
assert_true(unseal_result.ok, "unseal succeeds")
local restored = mol.graph.get_destination("room_escape:slot_2")
assert_eq(restored.room_id, original.room_id, "unseal restores base destination room")
assert_eq(restored.to_slot, original.to_slot, "unseal restores base destination slot")

reset_mutation_state()
for i = 1, 1005 do
	minetest._us_time = i
	local target = i % 2 == 0 and "room_threshold" or "room_hazard"
	local slot = i % 2 == 0 and 1 or 1
	apply_or_fail({
		type = "reroute",
		from_door_id = "room_hall:slot_2",
		to_room_id = target,
		to_slot = slot,
		reason = "log_bound",
	}, "bounded log mutation " .. i)
end
assert_true(#mol.mutations.log <= mol.mutations.MAX_LOG, "mutation log is bounded")
assert_eq(mol.mutations.overrides.seq, 1005, "mutation sequence grows monotonically")
assert_eq(mol.mutations.log[#mol.mutations.log].seq, 1005, "bounded log keeps newest entry")
assert_true(mol.mutations.log[1].seq > 1, "trimmed log drops oldest entries")

reset_mutation_state()
apply_or_fail({
	type = "reroute",
	from_door_id = "room_hall:slot_2",
	to_room_id = "room_hazard",
	to_slot = 1,
	reason = "roundtrip",
}, "roundtrip reroute")
assert_true(mol.mutations.seal("room_orient:slot_2").ok, "roundtrip seal succeeds")
local serialized = minetest.serialize(mol.mutations.overrides)
local deserialized = minetest.deserialize(serialized)
assert_true(test_same_value(deserialized, mol.mutations.overrides), "doors:overrides serialization round-trip preserves data")
local mutated_signature = graph_signature()
mol.graph.init_world("12345")
mol.mutations.apply_overrides(deserialized)
assert_eq(graph_signature(), mutated_signature, "deserialized overrides replay onto fresh base graph")

reset_mutation_state()
mol.players.player = {current_room_id = "room_hall"}
local occupied_result = mol.mutations.apply({
	type = "reroute",
	from_door_id = "room_hall:slot_2",
	to_room_id = "room_hazard",
	to_slot = 1,
	reason = "occupied",
})
assert_true(not occupied_result.ok, "occupied affected room rejects mutation")
assert_eq(occupied_result.error, "room occupied", "occupied mutation reports room occupied")

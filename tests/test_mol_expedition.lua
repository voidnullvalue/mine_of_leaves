local function reset_expedition_persist()
	local store = {}
	mol.persist = {
		get = function(ns, key) return store[ns .. ":" .. key] end,
		set = function(ns, key, value) store[ns .. ":" .. key] = value end,
		delete = function(ns, key) store[ns .. ":" .. key] = nil end,
	}
	return store
end

local function reset_expedition_state()
	reset_expedition_persist()
	mol.players = {}
	mol.graph.init_world("12345")
	mol.expedition.records = {}
	mol.expedition.index = {}
	minetest._us_time = 0
	test_logs = {}
end

local function make_player(name, pos)
	local player = {
		name = name,
		pos = pos or {x = 0, y = 3, z = -8},
		set_pos_calls = {},
		yaw = 0,
	}
	function player:get_player_name() return self.name end
	function player:get_pos() return self.pos end
	function player:set_pos(pos)
		self.pos = {x = pos.x, y = pos.y, z = pos.z}
		self.set_pos_calls[#self.set_pos_calls + 1] = self.pos
	end
	function player:set_look_horizontal(yaw) self.yaw = yaw end
	minetest._players[name] = player
	return player
end

reset_expedition_state()
local created = mol.expedition.create("alice", "exp_a")
assert_eq(created.expedition_id, "exp_a", "expedition record has id")
assert_eq(created.house_id, "mol_v1", "expedition record has house id")
assert_eq(created.schema_version, "1", "expedition record has schema version")
assert_true(type(created.expedition_seed) == "number", "expedition record has seed")
assert_true(type(created.participants) == "table", "expedition record has participants")
assert_true(type(created.logical_positions) == "table", "expedition record has logical positions")
assert_true(type(created.topology_overrides) == "table", "expedition record has topology overrides")
assert_true(type(created.objective_state) == "table", "expedition record has objective state")
assert_true(type(created.event_log) == "table", "expedition record has event log")
assert_true(type(created.timestamps) == "table", "expedition record has timestamps")
assert_eq(created.lifecycle, "active", "expedition record is active")

reset_expedition_state()
mol.expedition.create("alice", "exp_a")
mol.expedition.create("bob", "exp_b")
local scoped = mol.mutations.apply({
	type = "reroute",
	from_door_id = "room_hall:slot_2",
	to_room_id = "room_hazard",
	to_slot = 1,
	reason = "test",
}, "exp_a")
assert_true(scoped.ok, "scoped mutation succeeds")
assert_true(mol.expedition.records.exp_a.topology_overrides.reroutes["room_hall:slot_2"] ~= nil, "expedition A has override")
assert_eq(mol.expedition.records.exp_b.topology_overrides.reroutes["room_hall:slot_2"], nil, "expedition B has no override")
local dest_a = mol.graph.get_destination("room_hall:slot_2", "exp_a")
local dest_b = mol.graph.get_destination("room_hall:slot_2", "exp_b")
assert_eq(dest_a.room_id, "room_hazard", "expedition A destination is rerouted")
assert_true(dest_b.room_id ~= "room_hazard", "expedition B destination remains base")

local serialized = minetest.serialize(mol.expedition.records.exp_a)
local deserialized = minetest.deserialize(serialized)
assert_true(test_same_value(deserialized, mol.expedition.records.exp_a), "expedition serialization round-trip preserves data")

reset_expedition_state()
local store = reset_expedition_persist()
store["expedition:index"] = {"future"}
store["expedition:future"] = {
	schema_version = "2",
	expedition_id = "future",
	timestamps = {created = 1, last_active = 1},
	topology_overrides = {reroutes = {}, seals = {}, seq = 0},
}
mol.expedition.load_all()
assert_eq(mol.expedition.records.future.lifecycle, "abandoned", "schema mismatch marks abandoned")
local saw_warning = false
for _, record in ipairs(test_logs) do
	if record.level == "warning" and string.find(record.message, "schema mismatch", 1, true) then saw_warning = true end
end
assert_true(saw_warning, "schema mismatch logs warning")

reset_expedition_state()
local old = mol.expedition.create("old", "old_exp")
old.timestamps.last_active = 0
minetest._us_time = 25 * 3600 * 1000000
mol.expedition.scan_abandoned()
assert_eq(old.lifecycle, "abandoned", "inactive expedition is abandoned")

reset_expedition_state()
for i = 1, 101 do
	local record = mol.expedition.create("p" .. i, "cap_" .. i)
	record.lifecycle = "abandoned"
	record.timestamps.last_active = i
	mol.expedition.save(record.expedition_id)
end
mol.expedition.enforce_cap()
assert_eq(#mol.expedition.index, 100, "expedition cap keeps 100 records")
assert_eq(mol.expedition.records.cap_1, nil, "expedition cap deletes oldest abandoned")

reset_expedition_state()
local reconnect = mol.expedition.create("alice", "reconnect")
reconnect.logical_positions.alice = "room_hall"
mol.expedition.save("reconnect")
mol.persist.set("player", "expedition:alice", "reconnect")
local alice = make_player("alice")
mol.expedition.restore_player(alice)
assert_eq(mol.players.alice.expedition_id, "reconnect", "reconnect restores expedition id")
assert_eq(mol.players.alice.current_room_id, "room_hall", "reconnect restores logical position")

reset_expedition_state()
local recovery = mol.expedition.create("alice", "recovery")
mol.players.alice = {expedition_id = "recovery", current_room_id = "room_hall"}
mol.expedition.store_traversal_recovery("alice", {
	source_pos = {x = 11, y = 12, z = 13},
	source_yaw = 2,
})
mol.persist.set("player", "expedition:alice", "recovery")
local recovering = make_player("alice")
mol.expedition.restore_player(recovering)
assert_eq(recovering.pos, {x = 11, y = 12, z = 13}, "mid-traversal reconnect restores source position")

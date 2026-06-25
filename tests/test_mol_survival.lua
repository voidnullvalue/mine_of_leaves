local function reset_survival_graph()
	mol.players = {}
	mol.graph.init_world("12345")
	mol.survival.invalidate_cold_cache()
end

local function assert_ge(value, min_value, label)
	assert_true(value >= min_value, label)
end

reset_survival_graph()
assert_eq(mol.survival.get_cold_level("room_entrance"), 0, "entrance cold level is zero")

local objective_cold = mol.survival.get_cold_level("room_objective")
assert_true(objective_cold > 0, "objective cold level is above zero")
assert_ge(mol.survival.hop_distance("room_objective"), 5, "objective is at least five hops from entrance")

reset_survival_graph()
for i = 1, 7 do
	local room_id = "room_mock_" .. i
	mol.graph.add_room(room_id, "corridor", 9000 + i)
	mol.cells.alloc[room_id] = {x = 0, y = 0, z = i}
end
mol.graph.connect("room_entrance:slot_6", "room_mock_1", 1, false)
for i = 1, 6 do
	mol.graph.connect("room_mock_" .. i .. ":slot_2", "room_mock_" .. (i + 1), 1, false)
end
mol.survival.invalidate_cold_cache()
assert_eq(mol.survival.hop_distance("room_mock_7"), 7, "mock graph depth uses hops")
assert_eq(mol.survival.get_cold_level("room_mock_7"), 3, "cold level ignores nearby Y coordinate")

reset_survival_graph()
local before = mol.survival.hop_distance("room_objective")
mol.graph.connect("room_entrance:slot_6", "room_objective", 1, false)
local after = mol.survival.hop_distance("room_objective")
assert_true(after < before, "cold cache invalidates after mutation")

reset_survival_graph()
local error_a = mol.survival.compass_error("room_objective", 1234)
local error_b = mol.survival.compass_error("room_objective", 1234)
assert_eq(error_a, error_b, "compass drift deterministic for fixed room and minute")
assert_eq(mol.survival.compass_error("room_foyer", 1234), 0, "compass drift is zero at shallow depth")

local state = {light_charge = 3, light_timer = 0}
local a = mol.survival.consume_light_charge(state, 10, true)
local b = mol.survival.consume_light_charge(state, 20, true)
assert_true(a < 3 and b <= a, "light charge decreases monotonically")
assert_eq(b, 0, "light charge reaches zero")

local teleported
local hp_after
local player = {
	name = "survivor",
	hp = 1,
	get_player_name = function(self) return self.name end,
	get_hp = function(self) return self.hp end,
	set_hp = function(self, hp) hp_after = hp self.hp = hp end,
	set_pos = function(self, pos) teleported = pos end,
	set_properties = function() end,
	set_physics_override = function() end,
	set_sky = function() end,
}
minetest._players.survivor = player
local hp_change = mol.survival.handle_hpchange(player, -1, {type = "test"})
assert_eq(hp_change, 0, "failure damage is intercepted")
assert_eq(teleported, mol.SPAWN_POS, "failure recovery teleports to yard")
assert_eq(hp_after, 10, "failure recovery restores HP to ten")

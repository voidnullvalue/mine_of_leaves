local function reset_door_state()
	mol.doors.traversing = {}
	mol.doors.cooldown = {}
	mol.doors.last_check = {}
	mol.doors.index_clear()
	minetest._players = {}
	minetest._chat_messages = {}
	minetest._after_calls = {}
	minetest._emerge_calls = {}
	minetest._emerge_mode = nil
	minetest._hold_after = nil
	minetest._us_time = 0
end

local function make_player(name, pos)
	local player = {
		name = name,
		pos = pos or {x = 0, y = 0, z = 0},
		yaw = 1.25,
		sky_calls = {},
		set_pos_calls = {},
	}
	function player:get_player_name() return self.name end
	function player:get_pos() return {x = self.pos.x, y = self.pos.y, z = self.pos.z} end
	function player:get_look_horizontal() return self.yaw end
	function player:set_look_horizontal(yaw) self.yaw = yaw end
	function player:set_sky(sky) self.sky_calls[#self.sky_calls + 1] = sky end
	function player:set_pos(pos)
		self.pos = {x = pos.x, y = pos.y, z = pos.z}
		self.set_pos_calls[#self.set_pos_calls + 1] = self.pos
	end
	minetest._players[name] = player
	return player
end

local function set_door_id(pos, door_id)
	minetest.get_meta(pos):set_string("door_id", door_id)
end

reset_door_state()
local guard_pos = {x = 1, y = 2, z = 3}
set_door_id(guard_pos, "entry")
mol.graph.get_destination = function() return {room_id = "room_yard", to_slot = 1} end
minetest._emerge_mode = "hold"
local guard_player = make_player("guard", {x = 1.4, y = 2, z = 3})
assert_true(mol.doors.traverse(guard_player, guard_pos), "door traversal guard first call starts traversal")
assert_true(mol.doors.traversing.guard ~= nil, "door traversal guard flag is set")
assert_true(not mol.doors.traverse(guard_player, guard_pos), "door traversal guard second call returns immediately")
assert_eq(#minetest._emerge_calls, 1, "door traversal guard prevents second emerge")

reset_door_state()
local fail_pos = {x = 4, y = 2, z = 3}
set_door_id(fail_pos, "room_a:slot_1")
mol.graph.get_destination = function() return {room_id = "room_b", to_slot = 1} end
mol.graph.ensure_placed = function() error("boom") end
local fail_player = make_player("fail", {x = 4, y = 2, z = 3})
assert_true(not mol.doors.traverse(fail_player, fail_pos), "door traversal generation failure returns false")
assert_eq(mol.doors.traversing.fail, nil, "door traversal generation failure clears flag")
assert_eq(#fail_player.set_pos_calls, 0, "door traversal generation failure does not teleport")
assert_eq(fail_player.sky_calls[#fail_player.sky_calls].base_color, {r = 5, g = 5, b = 8, a = 255}, "door traversal generation failure restores sky")
assert_eq(minetest._chat_messages[#minetest._chat_messages].message, "[mol] The passage did not open.", "door traversal generation failure chats recovery message")

reset_door_state()
local cooldown_pos = {x = 7, y = 2, z = 3}
set_door_id(cooldown_pos, "entry")
mol.graph.get_destination = function() return {room_id = "room_yard", to_slot = 1} end
local cooldown_player = make_player("cool", {x = 7.5, y = 2, z = 3})
assert_true(mol.doors.traverse(cooldown_player, cooldown_pos), "door traversal cooldown first traversal succeeds")
assert_true(mol.doors.cooldown.cool ~= nil, "door traversal cooldown is set after completion")
assert_true(not mol.doors.traverse(cooldown_player, cooldown_pos), "door traversal cooldown blocks immediate retraversal")

reset_door_state()
mol.doors.index_add_door({x = 0, y = 0, z = 0}, "a")
mol.doors.index_add_door({x = 16, y = 0, z = 0}, "b")
mol.doors.index_add_door({x = -1, y = 0, z = 0}, "c")
assert_eq(#mol.doors.index["0,0,0"], 1, "door spatial index maps positive origin mapblock")
assert_eq(#mol.doors.index["1,0,0"], 1, "door spatial index maps adjacent positive mapblock")
assert_eq(#mol.doors.index["-1,0,0"], 1, "door spatial index maps negative mapblock")

reset_door_state()
mol.doors.index_add_door({x = 1, y = 0, z = 1}, "near_a")
mol.doors.index_add_door({x = 17, y = 0, z = 1}, "near_b")
mol.doors.index_add_door({x = 64, y = 0, z = 1}, "far")
local nearby = mol.doors.nearby_index_entries({x = 1, y = 0, z = 1})
local seen = {}
for _, entry in ipairs(nearby) do
	seen[entry.door_id] = true
end
assert_true(seen.near_a, "door spatial lookup includes same mapblock door")
assert_true(seen.near_b, "door spatial lookup includes neighboring mapblock door")
assert_true(not seen.far, "door spatial lookup excludes non-neighbor mapblock door")

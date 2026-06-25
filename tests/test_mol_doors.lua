local function reset_door_state()
	mol.doors.traversing = {}
	mol.doors.cooldown = {}
	mol.doors.suppressed = {}
	mol.doors.last_check = {}
	mol.doors.index_clear()
	minetest._players = {}
	minetest._chat_messages = {}
	minetest._after_calls = {}
	minetest._emerge_calls = {}
	minetest._emerge_mode = nil
	minetest._hold_after = nil
	minetest._us_time = 0
	minetest.get_node_or_nil = function()
		return {name = "mol:door_closed"}
	end
end

local function make_player(name, pos)
	local player = {
		name = name,
		pos = pos or {x = 0, y = 0, z = 0},
		yaw = 1.25,
		sky_calls = {},
		set_pos_calls = {},
		set_velocity_calls = {},
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
	function player:set_velocity(velocity)
		self.set_velocity_calls[#self.set_velocity_calls + 1] = {x = velocity.x, y = velocity.y, z = velocity.z}
	end
	minetest._players[name] = player
	return player
end

local function set_node_map(map)
	minetest.get_node_or_nil = function(pos)
		local key = math.floor(pos.x + 0.5) .. "," .. math.floor(pos.y + 0.5) .. "," .. math.floor(pos.z + 0.5)
		return {name = map[key] or "air"}
	end
end

local function key(pos)
	return math.floor(pos.x + 0.5) .. "," .. math.floor(pos.y + 0.5) .. "," .. math.floor(pos.z + 0.5)
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
local function make_destination_room(facing)
	local origin = mol.cells.get_origin({x = 0, y = 0, z = 0})
	local room_def = {
		room_id = "room_dest",
		template = "test",
		size = {x = 8, y = 6, z = 8},
		nodes = {},
		door_slots = {{offset = {x = 3, y = 1, z = 0}, facing = facing}},
		arrival = {{offset = {x = 3, y = 1, z = 1}}},
	}
	local map = {}
	for x = 1, 6 do
		for z = 1, 6 do
			map[key({x = origin.x + x, y = origin.y, z = origin.z + z})] = "mol:floor"
			map[key({x = origin.x + x, y = origin.y + 1, z = origin.z + z})] = "air"
			map[key({x = origin.x + x, y = origin.y + 2, z = origin.z + z})] = "air"
		end
	end
	local door_pos = {x = origin.x + 3, y = origin.y + 1, z = origin.z}
	map[key(door_pos)] = "mol:door_closed"
	set_node_map(map)
	return room_def, door_pos
end

local dest_def, dest_door_pos = make_destination_room("n")
mol.cells.alloc.room_dest = {x = 0, y = 0, z = 0}
local source_pos = {x = -20, y = 1, z = -20}
set_door_id(source_pos, "source:slot_1")
mol.graph.get_destination = function() return {room_id = "room_dest", to_slot = 1} end
mol.graph.ensure_placed = function() return {room_id = "room_dest", cell_coord = {x = 0, y = 0, z = 0}, template = "test", room_seed = 1} end
mol.graph.get_room = function() return {room_id = "room_dest", cell_coord = {x = 0, y = 0, z = 0}, template = "test", room_seed = 1} end
mol.rooms.generate = function() return dest_def end
local arrival_player = make_player("arrival", {x = source_pos.x, y = source_pos.y, z = source_pos.z})
assert_true(mol.doors.traverse(arrival_player, source_pos), "door traversal to generated room succeeds")
assert_true(vector.distance(arrival_player.pos, dest_door_pos) > 1.5, "arrival is outside trigger radius")
assert_eq(arrival_player.set_velocity_calls[#arrival_player.set_velocity_calls], {x = 0, y = 0, z = 0}, "velocity is zeroed on arrival")
assert_eq(arrival_player.yaw, mol.door_inward_yaw("n"), "destination yaw is derived from destination facing")
assert_eq(mol.doors.suppressed.arrival.door_id, "room_dest:slot_1", "destination suppression stores canonical door id")

minetest._us_time = 300000
arrival_player.pos = {x = dest_door_pos.x, y = dest_door_pos.y, z = dest_door_pos.z + 0.5}
mol.doors.index_clear()
mol.doors.index_add_door(dest_door_pos, "room_dest:slot_1")
for _, callback in ipairs(minetest._registered_globalsteps) do callback(0.3) end
assert_eq(#arrival_player.set_pos_calls, 1, "stationary suppressed player does not auto reverse")
assert_true(mol.doors.suppressed.arrival ~= nil, "suppression remains while player is inside exit radius")

minetest._us_time = 600000
arrival_player.pos = {x = dest_door_pos.x, y = dest_door_pos.y, z = dest_door_pos.z + 2.5}
for _, callback in ipairs(minetest._registered_globalsteps) do callback(0.3) end
assert_eq(mol.doors.suppressed.arrival, nil, "suppression clears after moving beyond exit radius")

reset_door_state()
local yard_source = {x = 5, y = 2, z = 5}
set_door_id(yard_source, "room_a:slot_1")
mol.graph.get_destination = function() return {room_id = "room_yard", to_slot = 1} end
local yard_player = make_player("yard", yard_source)
assert_true(mol.doors.traverse(yard_player, yard_source), "yard return traversal succeeds")
assert_true(not test_same_value(yard_player.pos, mol.SPAWN_POS), "yard return does not use global spawn")
local front_anchor = {x = mol.HOUSE_POS.x + 6, y = mol.HOUSE_POS.y + 1, z = mol.HOUSE_POS.z}
assert_true(vector.distance(yard_player.pos, front_anchor) > 1.5, "yard return is outside entry trigger radius")
assert_eq(yard_player.yaw, math.pi, "yard return faces away from front door")

reset_door_state()
local original_traverse = mol.doors.traverse
local traversals = 0
mol.doors.traverse = function()
	traversals = traversals + 1
	return true
end
mol.doors.index_add_door({x = 0, y = 1, z = 0}, "entry")
mol.doors.index_add_door({x = 1, y = 1, z = 0}, "entry")
local wide_player = make_player("wide", {x = 0.5, y = 1, z = 0})
for _, callback in ipairs(minetest._registered_globalsteps) do callback(0.3) end
assert_eq(traversals, 1, "two-wide portal produces only one traversal call")
mol.doors.traverse = original_traverse

local closed_def = minetest._registered_nodes[":mol:door_closed"]
assert_true(closed_def and closed_def.walkable, "closed portal node is physically walkable")
assert_eq(closed_def and closed_def.drawtype, "nodebox", "closed portal uses nodebox drawtype")
assert_eq(closed_def and closed_def.paramtype2, "facedir", "closed portal uses facedir orientation")
local fixed = closed_def and closed_def.collision_box and closed_def.collision_box.fixed and closed_def.collision_box.fixed[1]
assert_true(fixed and (fixed[6] - fixed[3]) < 0.25, "closed portal collision is a thin plane")

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

-- ---------------------------------------------------------------------------
-- Tests 9-10: fall / void recovery (mol.doors.is_void_unsafe)
-- ---------------------------------------------------------------------------

-- Temporarily override alloc so we control which cells are "allocated".
local saved_alloc = mol.cells.alloc
mol.cells.alloc = {}

-- Test 9: a position inside an allocated cell is NOT flagged unsafe.
mol.cells.alloc["recovery_test_room"] = {x = 2, y = 0, z = 0}
local origin_safe = mol.cell_to_world(2, 0, 0)
local safe_pos = {x = origin_safe.x + 10, y = origin_safe.y + 5, z = origin_safe.z + 10}
assert_true(not mol.doors.is_void_unsafe(safe_pos),
	"fall recovery: allocated-cell position is not flagged unsafe")

-- Test 10: a position in unallocated interior space IS flagged unsafe.
-- Cell (3,0,0) is deliberately not in alloc.
local origin_unsafe = mol.cell_to_world(3, 0, 0)
local unsafe_pos = {x = origin_unsafe.x + 5, y = origin_unsafe.y + 5, z = origin_unsafe.z + 5}
assert_true(mol.doors.is_void_unsafe(unsafe_pos),
	"fall recovery: unallocated void position is flagged unsafe")

-- A yard position must never be flagged unsafe.
local yard_pos = {x = 0, y = 1, z = 0}
assert_true(not mol.doors.is_void_unsafe(yard_pos),
	"fall recovery: yard position is not flagged unsafe")

mol.cells.alloc = saved_alloc

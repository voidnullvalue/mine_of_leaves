mol.doors = mol.doors or {}
mol.players = mol.players or {}

mol.doors.traversing = mol.doors.traversing or {}
mol.doors.cooldown = mol.doors.cooldown or {}
mol.doors.suppressed = mol.doors.suppressed or {}
mol.doors.last_check = mol.doors.last_check or {}
mol.doors.index = mol.doors.index or {}

local CHECK_INTERVAL = 0.25
local COOLDOWN_US = 250000
local PROXIMITY_RADIUS = 1.5
local EXIT_RADIUS = 2.35
local ARRIVAL_CLEARANCE = 2.15
local RECOVERY_INTERVAL = 0.25
-- Luanti 5.10 ObjectRef:set_sky accepts set_sky(sky_parameters). For
-- type="plain", base_color controls both fog and sky.
local NORMAL_SKY = {type = "plain", base_color = {r = 5, g = 5, b = 8, a = 255}}
local BLACKOUT_SKY = {type = "plain", base_color = {r = 0, g = 0, b = 0, a = 255}}
local OUTDOOR_SKY = {type = "regular"}

local elapsed_time = 0
local recovery_elapsed = 0
local recovery_in_progress = {}

local function copy_pos(pos)
	if not pos then return nil end
	return {x = pos.x, y = pos.y, z = pos.z}
end

local function now_us()
	if minetest.get_us_time then return minetest.get_us_time() end
	return math.floor(elapsed_time * 1000000)
end

local function clear_traversal(player_name)
	mol.doors.traversing[player_name] = nil
end

local function clear_suppression(player_name)
	mol.doors.suppressed[player_name] = nil
end

local function reveal_player(player)
	player:set_sky(NORMAL_SKY)
end

local function conceal_player(player)
	player:set_sky(BLACKOUT_SKY)
end

local function chat(player_name, message)
	if minetest.chat_send_player then
		minetest.chat_send_player(player_name, message)
	end
end

function mol.doors.mapblock_key(pos)
	return math.floor(pos.x / mol.MAPBLOCK_SIZE) .. "," ..
		math.floor(pos.y / mol.MAPBLOCK_SIZE) .. "," ..
		math.floor(pos.z / mol.MAPBLOCK_SIZE)
end

function mol.doors.index_clear()
	mol.doors.index = {}
end

function mol.doors.index_add_door(pos, door_id)
	if not (pos and door_id and door_id ~= "") then return end
	local key = mol.doors.mapblock_key(pos)
	local bucket = mol.doors.index[key] or {}
	for _, entry in ipairs(bucket) do
		if entry.door_id == door_id and
			entry.pos.x == pos.x and entry.pos.y == pos.y and entry.pos.z == pos.z then
			return
		end
	end
	bucket[#bucket + 1] = {pos = copy_pos(pos), door_id = door_id}
	mol.doors.index[key] = bucket
end

local function room_def_for(room)
	if not room or not room.template then return nil end
	local room_def = mol.rooms.generate(room.template, room.room_seed, {})
	if room_def then
		room_def.room_id = room.room_id
		mol.graph.prepare_room_def(room_def, room.room_id)
	end
	return room_def
end

function mol.doors.index_add_room(room_id)
	local room = mol.graph.get_room(room_id)
	if not (room and room.cell_coord and room.template) then return false end
	local room_def = room_def_for(room)
	if not (room_def and room_def.door_slots) then return false end

	local origin = mol.cells.get_origin(room.cell_coord)
	for index, slot in ipairs(room_def.door_slots) do
		local offset = slot.offset
		if offset then
			mol.doors.index_add_door({
				x = origin.x + offset.x,
				y = origin.y + offset.y,
				z = origin.z + offset.z,
			}, room_id .. ":slot_" .. index)
		end
	end
	return true
end

local function add_house_doors()
	local house = mol.HOUSE_POS
	mol.doors.index_add_door({x = house.x + 6, y = house.y + 1, z = house.z}, "entry")
	mol.doors.index_add_door({x = house.x + 6, y = house.y + 1, z = house.z + 5}, "interior_1")
	mol.doors.index_add_door({x = house.x + 6, y = house.y + 1, z = house.z + mol.HOUSE_SIZE.z - 2}, "threshold_1")
end

function mol.doors.rebuild_index()
	mol.doors.index_clear()
	add_house_doors()
	for _, room_id in ipairs(mol.graph.room_order or {}) do
		if mol.cells.is_built(room_id) then
			mol.doors.index_add_room(room_id)
		end
	end
end

function mol.doors.nearby_index_entries(pos)
	local entries = {}
	local bx = math.floor(pos.x / mol.MAPBLOCK_SIZE)
	local by = math.floor(pos.y / mol.MAPBLOCK_SIZE)
	local bz = math.floor(pos.z / mol.MAPBLOCK_SIZE)
	for dx = -1, 1 do
		for dy = -1, 1 do
			for dz = -1, 1 do
				local bucket = mol.doors.index[(bx + dx) .. "," .. (by + dy) .. "," .. (bz + dz)]
				if bucket then
					for _, entry in ipairs(bucket) do
						entries[#entries + 1] = entry
					end
				end
			end
		end
	end
	return entries
end

local function facing_axis(facing)
	if facing == "n" or facing == "s" then return "x" end
	if facing == "e" or facing == "w" then return "z" end
	return nil
end

local function is_door_segment(name)
	return type(name) == "string" and (
		name == "mol:door_closed" or
		string.sub(name, 1, 16) == "mol:door_closed_" or
		name == "mol:door_open"
	)
end

local function offset_bounds(origin, arrival, center)
	if type(arrival) ~= "table" or #arrival == 0 then return nil end
	local bounds
	for _, spec in ipairs(arrival) do
		if spec.offset then
			local p = {
				x = origin.x + spec.offset.x,
				y = origin.y + spec.offset.y,
				z = origin.z + spec.offset.z,
			}
			if vector.distance(p, center) <= 1.6 then
				if not bounds then
					bounds = {min = copy_pos(p), max = copy_pos(p)}
				else
					bounds.min.x = math.min(bounds.min.x, p.x)
					bounds.min.y = math.min(bounds.min.y, p.y)
					bounds.min.z = math.min(bounds.min.z, p.z)
					bounds.max.x = math.max(bounds.max.x, p.x)
					bounds.max.y = math.max(bounds.max.y, p.y)
					bounds.max.z = math.max(bounds.max.z, p.z)
				end
			end
		end
	end
	if bounds and bounds.min.x == bounds.max.x and bounds.min.z == bounds.max.z then
		bounds.min.x = bounds.min.x - 0.75
		bounds.max.x = bounds.max.x + 0.75
		bounds.min.z = bounds.min.z - 0.75
		bounds.max.z = bounds.max.z + 0.75
	end
	return bounds
end

local function clamp(value, min_value, max_value)
	if value < min_value then return min_value end
	if value > max_value then return max_value end
	return value
end

local function round_node_coord(value)
	return math.floor(value + 0.5)
end

local function node_pos_for_player_pos(pos)
	return {
		x = round_node_coord(pos.x),
		y = round_node_coord(pos.y),
		z = round_node_coord(pos.z),
	}
end

local function node_name_at(pos)
	local node = minetest.get_node_or_nil and minetest.get_node_or_nil(pos)
	return node and node.name or nil
end

local function is_walkable_node(name)
	if not name or name == "air" then return false end
	local nodes = minetest.registered_nodes or minetest._registered_nodes
	local def = nodes and (nodes[name] or nodes[":" .. name])
	if def and def.walkable ~= nil then return def.walkable end
	return name ~= "air"
end

local function clear_player_motion(player)
	if not player then return end
	if player.set_velocity then
		pcall(function() player:set_velocity({x = 0, y = 0, z = 0}) end)
	end
	if player.set_acceleration then
		pcall(function() player:set_acceleration({x = 0, y = 0, z = 0}) end)
	end
end

local function valid_arrival_position(pos)
	local feet = node_pos_for_player_pos(pos)
	local floor = {x = feet.x, y = feet.y - 1, z = feet.z}
	local head = {x = feet.x, y = feet.y + 1, z = feet.z}
	return is_walkable_node(node_name_at(floor)) and
		not is_walkable_node(node_name_at(feet)) and
		not is_walkable_node(node_name_at(head))
end

local function nearest_arrival(origin, room_def, door_pos)
	local best
	local best_dist
	for _, arrival in ipairs(room_def.arrival or {}) do
		if arrival.offset then
			local pos = {
				x = origin.x + arrival.offset.x,
				y = origin.y + arrival.offset.y,
				z = origin.z + arrival.offset.z,
			}
			local dist = vector.distance(pos, door_pos)
			if not best_dist or dist < best_dist then
				best = pos
				best_dist = dist
			end
		end
	end
	return best
end

local function clamp_to_room_interior(pos, origin, room_def)
	if not (room_def and room_def.size) then return pos end
	pos.x = clamp(pos.x, origin.x + 1, origin.x + room_def.size.x - 2)
	pos.z = clamp(pos.z, origin.z + 1, origin.z + room_def.size.z - 2)
	return pos
end

local function source_lateral_offset(player_pos, door_pos, source_facing)
	local axis = facing_axis(source_facing)
	if axis == "x" then return player_pos.x - door_pos.x end
	if axis == "z" then return player_pos.z - door_pos.z end
	if math.abs(player_pos.x - door_pos.x) >= math.abs(player_pos.z - door_pos.z) then
		return player_pos.x - door_pos.x
	end
	return player_pos.z - door_pos.z
end

local function compute_entry_position(room, room_def, slot_index, source)
	if not (room and room.cell_coord and room_def and room_def.door_slots) then
		return nil, "missing room definition"
	end
	local slot = room_def.door_slots[slot_index]
	if not (slot and slot.offset) then
		return nil, "missing destination door slot"
	end

	local origin = mol.cells.get_origin(room.cell_coord)
	local door_pos = {
		x = origin.x + slot.offset.x,
		y = origin.y + slot.offset.y,
		z = origin.z + slot.offset.z,
	}
	local entry_pos = nearest_arrival(origin, room_def, door_pos)
	if not entry_pos then return nil, "missing arrival zone" end

	local axis = facing_axis(slot.facing)
	local offset = source and source.lateral_offset or 0
	local dir = mol.door_inward_dir(slot.facing)
	local base_y = entry_pos.y
	local lateral_offsets = {offset, 0, -0.5, 0.5, -1, 1}
	local inward_distances = {ARRIVAL_CLEARANCE, EXIT_RADIUS, EXIT_RADIUS + 0.35, PROXIMITY_RADIUS + 0.2}

	for _, distance in ipairs(inward_distances) do
		for _, lateral in ipairs(lateral_offsets) do
			local candidate = {
				x = door_pos.x + dir.x * distance,
				y = base_y,
				z = door_pos.z + dir.z * distance,
			}
			if axis == "x" then
				candidate.x = candidate.x + lateral
			elseif axis == "z" then
				candidate.z = candidate.z + lateral
			end
			clamp_to_room_interior(candidate, origin, room_def)
			if vector.distance(candidate, door_pos) > PROXIMITY_RADIUS and valid_arrival_position(candidate) then
				return candidate
			end
		end
	end

	return nil, "no safe arrival candidate"
end

local function abort_traversal(player_name, message)
	local player = minetest.get_player_by_name(player_name)
	if player then
		reveal_player(player)
	end
	if message then chat(player_name, message) end
	clear_traversal(player_name)
	clear_suppression(player_name)
	return false
end

local function set_cooldown(player_name)
	mol.doors.cooldown[player_name] = now_us() + COOLDOWN_US
end

local function cooldown_active(player_name)
	local expires = mol.doors.cooldown[player_name]
	return expires and expires > now_us()
end

local function emerge_then_set_pos(player_name, entry_pos, yaw, done)
	local completed = false
	-- Luanti 5.10 emerge_area callback signature is
	-- (blockpos, action, calls_remaining, param); calls_remaining == 0 marks
	-- the final callback for this queued area.
	minetest.emerge_area(
		vector.subtract(entry_pos, 8),
		vector.add(entry_pos, 8),
		function(blockpos, action, calls_remaining, param)
			if calls_remaining and calls_remaining > 0 then return end
			if completed then return end
			completed = true
			local player = minetest.get_player_by_name(param.player_name)
			if not player then
				clear_traversal(param.player_name)
				clear_suppression(param.player_name)
				return
			end
			clear_player_motion(player)
			player:set_pos(param.entry_pos)
			clear_player_motion(player)
			if player.set_look_horizontal then
				player:set_look_horizontal(param.yaw)
			end
			done(player)
		end,
		{player_name = player_name, entry_pos = entry_pos, yaw = yaw}
	)
end

local function suppress_destination(player_name, door_id, door_pos)
	if not (door_id and door_pos) then return end
	mol.doors.suppressed[player_name] = {
		door_id = door_id,
		pos = copy_pos(door_pos),
		exit_radius = EXIT_RADIUS,
		guard_until = now_us() + COOLDOWN_US,
	}
end

local function finish_traversal(player_name, entry_pos, yaw, dest_room_id, dest_door_id, dest_door_pos)
	emerge_then_set_pos(player_name, entry_pos, yaw, function(player)
		mol.players[player_name] = mol.players[player_name] or {}
		mol.players[player_name].current_room_id = dest_room_id
		if mol.expedition and mol.expedition.update_player_room then
			mol.expedition.update_player_room(player_name, dest_room_id, entry_pos)
		end
		minetest.after(0.3, function()
			local current = minetest.get_player_by_name(player_name)
			if current then
				if dest_room_id == "room_yard" then
					current:set_sky(OUTDOOR_SKY)
				else
					reveal_player(current)
				end
			end
			set_cooldown(player_name)
			suppress_destination(player_name, dest_door_id, dest_door_pos)
			clear_traversal(player_name)
		end)
	end)
end

local function entry_for_yard(source)
	local pos = {
		x = mol.HOUSE_POS.x + 6.5,
		y = mol.HOUSE_POS.y + 1,
		z = mol.HOUSE_POS.z - ARRIVAL_CLEARANCE,
	}
	if source and source.lateral_offset then
		pos.x = clamp(pos.x + source.lateral_offset, mol.HOUSE_POS.x + 6.15, mol.HOUSE_POS.x + 6.85)
	end
	return pos
end

function mol.doors.traverse(player, door_pos)
	if not player then return false end
	local player_name = player:get_player_name()
	if mol.doors.traversing[player_name] or cooldown_active(player_name) then return false end

	local player_pos = player:get_pos()
	mol.doors.traversing[player_name] = {
		timestamp = now_us(),
		source_pos = copy_pos(player_pos),
	}

	local meta = minetest.get_meta(door_pos)
	local door_id = meta:get_string("door_id")
	if door_id == "" then
		clear_traversal(player_name)
		return false
	end
	mol.doors.traversing[player_name].door_id = door_id

	if door_id == "entry" and mol.expedition and mol.expedition.join then
		local state = mol.players[player_name]
		if not (state and state.expedition_id and mol.expedition.get(state.expedition_id)) then
			mol.expedition.join(player_name)
		end
	end
	local expedition_id = mol.players[player_name] and mol.players[player_name].expedition_id
	local dest = mol.graph.get_destination(door_id, expedition_id)
	if not dest then
		chat(player_name, "[mol] This door leads nowhere.")
		clear_traversal(player_name)
		return false
	end

	local source_room_id, source_slot = string.match(door_id, "^(.*):slot_(%d+)$")
	local source_facing
	if source_room_id then
		local source_room = mol.graph.get_room(source_room_id)
		local ok_source, source_def = pcall(room_def_for, source_room)
		if not ok_source then source_def = nil end
		local slot = source_def and source_def.door_slots[tonumber(source_slot)]
		source_facing = slot and slot.facing
	end
	local source = {
		lateral_offset = source_lateral_offset(player_pos, door_pos, source_facing),
	}

	conceal_player(player)

	local entry_pos
	local yaw
	local dest_door_id
	local dest_door_pos
	if dest.room_id == "room_yard" then
		entry_pos = entry_for_yard(source)
		yaw = math.pi
		dest_door_id = "entry"
		dest_door_pos = {x = mol.HOUSE_POS.x + 6, y = mol.HOUSE_POS.y + 1, z = mol.HOUSE_POS.z}
	else
		local ok, room_or_err = pcall(mol.graph.ensure_placed, dest.room_id)
		if not ok or not (room_or_err and room_or_err.cell_coord) then
			return abort_traversal(player_name, "[mol] The passage did not open.")
		end
		local ok_index, index_err = pcall(mol.doors.index_add_room, dest.room_id)
		if not ok_index then
			minetest.log("error", "[mol_doors] index update failed for " .. tostring(dest.room_id) .. ": " .. tostring(index_err))
		end

		local room = mol.graph.get_room(dest.room_id)
		local room_def
		local ok_entry, computed_or_err, err = pcall(function()
			room_def = room_def_for(room)
			return compute_entry_position(room, room_def, dest.to_slot, source)
		end)
		if not ok_entry or not computed_or_err then
			minetest.log("error", "[mol_doors] entry computation failed for " .. tostring(dest.room_id) .. ": " .. tostring(ok_entry and err or computed_or_err))
			return abort_traversal(player_name, "[mol] The passage did not open.")
		end
		entry_pos = computed_or_err
		local slot = room_def and room_def.door_slots and room_def.door_slots[dest.to_slot]
		yaw = mol.door_inward_yaw(slot and slot.facing)
		if slot and slot.offset then
			local origin = mol.cells.get_origin(room.cell_coord)
			dest_door_id = dest.room_id .. ":slot_" .. tostring(dest.to_slot)
			dest_door_pos = {
				x = origin.x + slot.offset.x,
				y = origin.y + slot.offset.y,
				z = origin.z + slot.offset.z,
			}
		end
	end

	finish_traversal(player_name, entry_pos, yaw, dest.room_id, dest_door_id, dest_door_pos)
	return true
end

function mol.doors.on_rightclick(pos, node, clicker)
	return mol.doors.traverse(clicker, pos)
end

local function is_door_node(name)
	return is_door_segment(name)
end

local function suppressed_for_entry(player_name, entry, pos)
	local suppressed = mol.doors.suppressed[player_name]
	if not suppressed then return false end
	local dist = vector.distance(pos, suppressed.pos)
	if dist >= (suppressed.exit_radius or EXIT_RADIUS) then
		clear_suppression(player_name)
		return false
	end
	return entry and entry.door_id == suppressed.door_id
end

local function check_player_proximity(player, now)
	local name = player:get_player_name()
	if mol.doors.traversing[name] or cooldown_active(name) then return end
	if (mol.doors.last_check[name] or 0) + CHECK_INTERVAL > now then return end
	mol.doors.last_check[name] = now

	local pos = player:get_pos()
	for _, entry in ipairs(mol.doors.nearby_index_entries(pos)) do
		if suppressed_for_entry(name, entry, pos) then
			return
		end
		if vector.distance(pos, entry.pos) <= PROXIMITY_RADIUS then
			local node = minetest.get_node_or_nil(entry.pos)
			if node and is_door_node(node.name) then
				mol.doors.traverse(player, entry.pos)
				return
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- Fall / void recovery
-- ---------------------------------------------------------------------------

local function pos_in_yard(pos)
	return pos.x >= mol.YARD_MIN.x - 1 and pos.x <= mol.YARD_MAX.x + 1 and
		pos.z >= mol.YARD_MIN.z - 1 and pos.z <= mol.YARD_MAX.z + 1 and
		pos.y >= -2 and pos.y <= mol.BOUNDARY_HEIGHT + 4
end

local function pos_in_allocated_cell(pos)
	if not (mol.cells and mol.cells.alloc) then return false end
	local cell = mol.world_to_cell(pos)
	for _, cell_coord in pairs(mol.cells.alloc) do
		if type(cell_coord) == "table" and
			cell_coord.x == cell.x and cell_coord.y == cell.y and cell_coord.z == cell.z then
			return true
		end
	end
	return false
end

-- Exposed for tests.
function mol.doors.is_void_unsafe(pos)
	if pos_in_yard(pos) then return false end
	if pos_in_allocated_cell(pos) then return false end
	return true
end

local function recover_player_to_spawn(player)
	local player_name = player:get_player_name()
	if recovery_in_progress[player_name] then return end
	recovery_in_progress[player_name] = true
	local spawn = {x = mol.SPAWN_POS.x, y = mol.SPAWN_POS.y, z = mol.SPAWN_POS.z}
	minetest.emerge_area(
		vector.subtract(spawn, 8),
		vector.add(spawn, 8),
		function(blockpos, action, calls_remaining, param)
			if calls_remaining and calls_remaining > 0 then return end
			local p = minetest.get_player_by_name(param.player_name)
			if not p then
				recovery_in_progress[param.player_name] = nil
				return
			end
			p:set_pos(param.spawn)
			if p.set_velocity then
				pcall(function() p:set_velocity({x = 0, y = 0, z = 0}) end)
			end
			mol.players[param.player_name] = mol.players[param.player_name] or {}
			mol.players[param.player_name].current_room_id = "room_yard"
			p:set_sky(OUTDOOR_SKY)
			recovery_in_progress[param.player_name] = nil
			minetest.log("action", "[mol_doors] recovered " .. param.player_name .. " from void")
		end,
		{player_name = player_name, spawn = spawn}
	)
end

local function check_void_recovery(player)
	local player_name = player:get_player_name()
	if mol.doors.traversing[player_name] then return end
	if recovery_in_progress[player_name] then return end
	local pos = player:get_pos()
	if not mol.doors.is_void_unsafe(pos) then return end
	recover_player_to_spawn(player)
end

minetest.register_globalstep(function(dtime)
	elapsed_time = elapsed_time + dtime
	recovery_elapsed = recovery_elapsed + dtime
	local do_recovery = recovery_elapsed >= RECOVERY_INTERVAL
	if do_recovery then recovery_elapsed = 0 end
	for _, player in ipairs(minetest.get_connected_players()) do
		check_player_proximity(player, elapsed_time)
		if do_recovery then
			check_void_recovery(player)
		end
	end
end)

minetest.register_on_leaveplayer(function(player)
	local player_name = player:get_player_name()
	local state = mol.doors.traversing[player_name]
	if state then
		mol.players[player_name] = mol.players[player_name] or {}
		mol.players[player_name].pending_recovery = {
			room_id = mol.players[player_name].current_room_id,
			recovery_pos = copy_pos(state.source_pos),
		}
		clear_traversal(player_name)
	end
	clear_suppression(player_name)
end)

minetest.register_on_joinplayer(function(player)
	local player_name = player:get_player_name()
	local state = mol.players[player_name] and mol.players[player_name].pending_recovery
	if not (state and state.recovery_pos) then return end
	minetest.after(0.5, function()
		local current = minetest.get_player_by_name(player_name)
		if not current then return end
		local pos = state.recovery_pos
		local completed = false
		minetest.emerge_area(vector.subtract(pos, 8), vector.add(pos, 8), function(blockpos, action, calls_remaining)
			if calls_remaining and calls_remaining > 0 then return end
			if completed then return end
			completed = true
			local joined = minetest.get_player_by_name(player_name)
			if not joined then return end
			joined:set_pos(pos)
			mol.players[player_name].pending_recovery = nil
		end)
	end)
end)

mol.doors.rebuild_index()

-- ---------------------------------------------------------------------------
-- One-time playability migration (v2)
-- Rebuilds existing rooms with corrected geometry (3-tall portals, air interiors).
-- Preserves room IDs, graph topology, cell allocation, and player progression.
-- ---------------------------------------------------------------------------
minetest.register_on_mods_loaded(function()
	if mol.persist.get("migrations", "playability_v2") then return end
	local rebuilt = 0
	for _, room_id in ipairs(mol.graph.room_order or {}) do
		if room_id ~= "room_yard" then
			local room = mol.graph.get_room(room_id)
			if room and room.template and room.room_seed then
				local cell = mol.cells and mol.cells.alloc and mol.cells.alloc[room_id]
				if type(cell) == "table" then
					local ok, room_def = pcall(mol.rooms.generate, room.template, room.room_seed, {})
					if ok and room_def then
						room_def.room_id = room_id
						mol.graph.prepare_room_def(room_def, room_id)
						mol.cells.build(cell, room_def, true)
						rebuilt = rebuilt + 1
					end
				end
			end
		end
	end
	mol.persist.set("migrations", "playability_v2", true)
	minetest.log("action", "[mol] playability_v2 migration rebuilt " .. rebuilt .. " rooms")
end)

local function pos_to_string(pos)
	return "(" .. tostring(pos.x) .. "," .. tostring(pos.y) .. "," .. tostring(pos.z) .. ")"
end

local function set_door_node(pos, name, facing, door_id)
	if minetest.set_node then
		minetest.set_node(pos, {name = name, param2 = mol.door_facedir(facing)})
	end
	if minetest.get_node_or_nil then
		local node = minetest.get_node_or_nil(pos)
		if not node then
			return false, "node unavailable after set_node"
		end
		if node.name ~= name then
			return false, "node write did not persist; expected " .. tostring(name) .. ", got " .. tostring(node.name)
		end
	end
	local meta = minetest.get_meta(pos)
	if not meta then
		return false, "metadata unavailable"
	end
	meta:set_string("door_id", door_id)
	return true
end

local function house_portal_specs()
	local h = mol.HOUSE_POS
	local front_x = h.x + 6
	local front_z = h.z
	local interior_x = h.x + 6
	local interior_z = h.z + 5
	local threshold_z = h.z + mol.HOUSE_SIZE.z - 2
	local specs = {}
	for dy = 0, 2 do
		local left_name = ({[0] = "mol:door_closed_left_bottom", "mol:door_closed_left_middle", "mol:door_closed_left_top"})[dy]
		local right_name = ({[0] = "mol:door_closed_right_bottom", "mol:door_closed_right_middle", "mol:door_closed_right_top"})[dy]
		local single_name = ({[0] = "mol:door_closed_bottom", "mol:door_closed_middle", "mol:door_closed_top"})[dy]
		specs[#specs + 1] = {pos = {x = front_x, y = h.y + 1 + dy, z = front_z}, name = left_name, facing = "n", door_id = "entry"}
		specs[#specs + 1] = {pos = {x = front_x + 1, y = h.y + 1 + dy, z = front_z}, name = right_name, facing = "n", door_id = "entry"}
		specs[#specs + 1] = {pos = {x = interior_x, y = h.y + 1 + dy, z = interior_z}, name = single_name, facing = "s", door_id = "interior_1"}
		specs[#specs + 1] = {pos = {x = interior_x, y = h.y + 1 + dy, z = threshold_z}, name = single_name, facing = "s", door_id = "threshold_1"}
	end
	return specs
end

local function bounds_for_specs(specs, margin)
	local minp = copy_pos(specs[1].pos)
	local maxp = copy_pos(specs[1].pos)
	for _, spec in ipairs(specs) do
		local pos = spec.pos
		minp.x = math.min(minp.x, pos.x)
		minp.y = math.min(minp.y, pos.y)
		minp.z = math.min(minp.z, pos.z)
		maxp.x = math.max(maxp.x, pos.x)
		maxp.y = math.max(maxp.y, pos.y)
		maxp.z = math.max(maxp.z, pos.z)
	end
	return vector.subtract(minp, margin), vector.add(maxp, margin)
end

local function migrate_house_portals(done)
	local specs = house_portal_specs()
	local minp, maxp = bounds_for_specs(specs, 2)
	local completed = false

	minetest.emerge_area(minp, maxp, function(blockpos, action, calls_remaining)
		if calls_remaining and calls_remaining > 0 then
			return
		end
		if completed then
			return
		end
		completed = true

		for _, spec in ipairs(specs) do
			local ok, reason = set_door_node(spec.pos, spec.name, spec.facing, spec.door_id)
			if not ok then
				done(false, pos_to_string(spec.pos) .. ": " .. tostring(reason))
				return
			end
		end
		done(true)
	end)
end

minetest.register_on_mods_loaded(function()
	if mol.persist.get("migrations", "portal_safety_v3") then return end
	local rebuilt = 0
	for _, room_id in ipairs(mol.graph.room_order or {}) do
		if room_id ~= "room_yard" then
			local room = mol.graph.get_room(room_id)
			local cell = mol.cells and mol.cells.alloc and mol.cells.alloc[room_id]
			if room and room.template and room.room_seed and type(cell) == "table" then
				local ok, room_def = pcall(mol.rooms.generate, room.template, room.room_seed, {})
				if ok and room_def then
					room_def.room_id = room_id
					mol.graph.prepare_room_def(room_def, room_id)
					mol.cells.build(cell, room_def, true)
					rebuilt = rebuilt + 1
				end
			end
		end
	end
	migrate_house_portals(function(success, error_message)
		if not success then
			minetest.log("error", "[mol] portal_safety_v3 migration failed updating house portals at " .. tostring(error_message))
			return
		end
		mol.doors.rebuild_index()
		mol.persist.set("migrations", "portal_safety_v3", true)
		minetest.log("action", "[mol] portal_safety_v3 migration rebuilt " .. rebuilt .. " rooms and updated house portals")
	end)
end)

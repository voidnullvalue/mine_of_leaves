mol.doors = mol.doors or {}
mol.players = mol.players or {}

mol.doors.traversing = mol.doors.traversing or {}
mol.doors.cooldown = mol.doors.cooldown or {}
mol.doors.last_check = mol.doors.last_check or {}
mol.doors.index = mol.doors.index or {}

local CHECK_INTERVAL = 0.25
local COOLDOWN_US = 1000000
local PROXIMITY_RADIUS = 1.5
-- Luanti 5.10 ObjectRef:set_sky accepts set_sky(sky_parameters). For
-- type="plain", base_color controls both fog and sky.
local NORMAL_SKY = {type = "plain", base_color = {r = 5, g = 5, b = 8, a = 255}}
local BLACKOUT_SKY = {type = "plain", base_color = {r = 0, g = 0, b = 0, a = 255}}

local elapsed_time = 0

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

	local bounds = offset_bounds(origin, room_def.arrival, entry_pos)
	if not bounds then return nil, "missing arrival bounds" end

	local axis = facing_axis(slot.facing)
	local offset = source and source.lateral_offset or 0
	if axis == "x" then
		entry_pos.x = entry_pos.x + offset
	elseif axis == "z" then
		entry_pos.z = entry_pos.z + offset
	end
	entry_pos.x = clamp(entry_pos.x, bounds.min.x, bounds.max.x)
	entry_pos.y = clamp(entry_pos.y, bounds.min.y, bounds.max.y)
	entry_pos.z = clamp(entry_pos.z, bounds.min.z, bounds.max.z)
	return entry_pos
end

local function abort_traversal(player_name, message)
	local player = minetest.get_player_by_name(player_name)
	if player then
		reveal_player(player)
	end
	if message then chat(player_name, message) end
	clear_traversal(player_name)
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
				return
			end
			player:set_pos(param.entry_pos)
			if player.set_look_horizontal then
				player:set_look_horizontal(param.source_yaw)
			end
			done(player)
		end,
		{player_name = player_name, entry_pos = entry_pos, source_yaw = yaw}
	)
end

local function finish_traversal(player_name, entry_pos, yaw, dest_room_id)
	emerge_then_set_pos(player_name, entry_pos, yaw, function(player)
		mol.players[player_name] = mol.players[player_name] or {}
		mol.players[player_name].current_room_id = dest_room_id
		if mol.expedition and mol.expedition.update_player_room then
			mol.expedition.update_player_room(player_name, dest_room_id, entry_pos)
		end
		minetest.after(0.3, function()
			local current = minetest.get_player_by_name(player_name)
			if current then reveal_player(current) end
			set_cooldown(player_name)
			clear_traversal(player_name)
		end)
	end)
end

local function entry_for_yard(source)
	local pos = copy_pos(mol.SPAWN_POS)
	if source and source.lateral_offset then
		pos.x = pos.x + source.lateral_offset
	end
	return pos
end

function mol.doors.traverse(player, door_pos)
	if not player then return false end
	local player_name = player:get_player_name()
	if mol.doors.traversing[player_name] or cooldown_active(player_name) then return false end

	local player_pos = player:get_pos()
	local yaw = player:get_look_horizontal()
	mol.doors.traversing[player_name] = {
		timestamp = now_us(),
		source_pos = copy_pos(player_pos),
		source_yaw = yaw,
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
	if dest.room_id == "room_yard" then
		entry_pos = entry_for_yard(source)
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
		local ok_entry, computed_or_err, err = pcall(function()
			local room_def = room_def_for(room)
			return compute_entry_position(room, room_def, dest.to_slot, source)
		end)
		if not ok_entry or not computed_or_err then
			minetest.log("error", "[mol_doors] entry computation failed for " .. tostring(dest.room_id) .. ": " .. tostring(ok_entry and err or computed_or_err))
			return abort_traversal(player_name, "[mol] The passage did not open.")
		end
		entry_pos = computed_or_err
	end

	finish_traversal(player_name, entry_pos, yaw, dest.room_id)
	return true
end

function mol.doors.on_rightclick(pos, node, clicker)
	return mol.doors.traverse(clicker, pos)
end

local function is_door_node(name)
	return name == "mol:door_closed" or name == "mol:door_open"
end

local function check_player_proximity(player, now)
	local name = player:get_player_name()
	if mol.doors.traversing[name] or cooldown_active(name) then return end
	if (mol.doors.last_check[name] or 0) + CHECK_INTERVAL > now then return end
	mol.doors.last_check[name] = now

	local pos = player:get_pos()
	for _, entry in ipairs(mol.doors.nearby_index_entries(pos)) do
		if vector.distance(pos, entry.pos) <= PROXIMITY_RADIUS then
			local node = minetest.get_node_or_nil(entry.pos)
			if node and is_door_node(node.name) then
				mol.doors.traverse(player, entry.pos)
				return
			end
		end
	end
end

minetest.register_globalstep(function(dtime)
	elapsed_time = elapsed_time + dtime
	for _, player in ipairs(minetest.get_connected_players()) do
		check_player_proximity(player, elapsed_time)
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

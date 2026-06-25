mol.expedition = mol.expedition or {}
mol.players = mol.players or {}

local expedition = mol.expedition

expedition.SCHEMA_VERSION = "1"
expedition.HOUSE_ID = "mol_v1"
expedition.ABANDONED_RETENTION = 7 * 24 * 3600
expedition.MAX_EXPEDITIONS = 100
expedition.records = expedition.records or {}
expedition.index = expedition.index or {}

local RECOVERY_PREFIX = "__recovery:"

local function copy_plain(value)
	if type(value) ~= "table" then return value end
	local copy = {}
	for key, child in pairs(value) do
		copy[copy_plain(key)] = copy_plain(child)
	end
	return copy
end

local function now_seconds()
	if minetest.get_us_time then return math.floor(minetest.get_us_time() / 1000000) end
	return 0
end

local function normalize_overrides(overrides)
	overrides = type(overrides) == "table" and copy_plain(overrides) or {}
	overrides.reroutes = type(overrides.reroutes) == "table" and overrides.reroutes or {}
	overrides.seals = type(overrides.seals) == "table" and overrides.seals or {}
	overrides.seq = tonumber(overrides.seq) or 0
	return overrides
end

local function normalize_objective(state)
	state = type(state) == "table" and copy_plain(state) or {}
	state.notebook_found = state.notebook_found and true or false
	state.escaped = state.escaped and true or false
	return state
end

local function normalize_timestamps(timestamps)
	timestamps = type(timestamps) == "table" and copy_plain(timestamps) or {}
	local now = now_seconds()
	timestamps.created = tonumber(timestamps.created) or now
	timestamps.last_active = tonumber(timestamps.last_active) or timestamps.created
	return timestamps
end

local function normalize_record(record)
	record.topology_overrides = normalize_overrides(record.topology_overrides)
	record.objective_state = normalize_objective(record.objective_state)
	record.logical_positions = type(record.logical_positions) == "table" and copy_plain(record.logical_positions) or {}
	record.last_safe_positions = type(record.last_safe_positions) == "table" and copy_plain(record.last_safe_positions) or {}
	record.event_log = type(record.event_log) == "table" and copy_plain(record.event_log) or {}
	record.timestamps = normalize_timestamps(record.timestamps)
	record.participants = type(record.participants) == "table" and copy_plain(record.participants) or {}
	record.lifecycle = record.lifecycle or "active"
	record.house_id = record.house_id or expedition.HOUSE_ID
	record.schema_version = record.schema_version or expedition.SCHEMA_VERSION
	return record
end

local function persistable_record(record)
	local copy = copy_plain(record)
	copy.participants = nil
	return copy
end

local function index_contains(expedition_id)
	for _, id in ipairs(expedition.index) do
		if id == expedition_id then return true end
	end
	return false
end

local function add_to_index(expedition_id)
	if index_contains(expedition_id) then return end
	expedition.index[#expedition.index + 1] = expedition_id
	mol.persist.set("expedition", "index", expedition.index)
end

local function save_index()
	mol.persist.set("expedition", "index", expedition.index)
end

function expedition.save(expedition_id)
	local record = expedition.records[expedition_id]
	if not record then return false end
	mol.persist.set("expedition", expedition_id, persistable_record(record))
	save_index()
	return true
end

local function log_event(record, event)
	record.event_log = record.event_log or {}
	local seq = (record.event_log[#record.event_log] and record.event_log[#record.event_log].seq or 0) + 1
	record.event_log[#record.event_log + 1] = {
		seq = seq,
		timestamp = now_seconds(),
		event = event,
	}
end

function expedition.new_id(player_name)
	local world_seed = minetest.get_mapgen_setting("seed") or ""
	local seed = mol.derive_seed(world_seed, "expedition:" .. os.time() .. ":" .. tostring(player_name or ""))
	return string.format("%08x", seed % 0x100000000)
end

function expedition.create(player_name, expedition_id)
	expedition_id = expedition_id or expedition.new_id(player_name)
	local now = now_seconds()
	local world_seed = minetest.get_mapgen_setting("seed") or ""
	local record = normalize_record({
		schema_version = expedition.SCHEMA_VERSION,
		expedition_id = expedition_id,
		house_id = expedition.HOUSE_ID,
		expedition_seed = mol.derive_seed(world_seed, "expedition:" .. expedition_id),
		participants = {},
		logical_positions = {},
		topology_overrides = {reroutes = {}, seals = {}, seq = 0},
		objective_state = {notebook_found = false, escaped = false},
		event_log = {},
		timestamps = {created = now, last_active = now},
		lifecycle = "active",
		last_safe_positions = {},
	})
	expedition.records[expedition_id] = record
	add_to_index(expedition_id)
	log_event(record, "created")
	expedition.save(expedition_id)
	return record
end

function expedition.get(expedition_id)
	return expedition.records[expedition_id]
end

function expedition.get_overrides(expedition_id)
	local record = expedition.records[expedition_id]
	return record and record.topology_overrides or nil
end

local function active_record(expedition_id)
	local record = expedition.records[expedition_id]
	if record and record.lifecycle == "active" then return record end
	return nil
end

function expedition.active_for_join()
	for _, id in ipairs(expedition.index) do
		local record = active_record(id)
		if record then return record end
	end
	return nil
end

local function add_participant(record, player_name)
	record.participants = record.participants or {}
	for _, participant in ipairs(record.participants) do
		if participant == player_name then return end
	end
	record.participants[#record.participants + 1] = player_name
end

local function remove_participant(record, player_name)
	for index = #(record.participants or {}), 1, -1 do
		if record.participants[index] == player_name then table.remove(record.participants, index) end
	end
end

function expedition.join(player_name, expedition_id)
	local record = expedition_id and active_record(expedition_id) or expedition.active_for_join()
	if not record then record = expedition.create(player_name, expedition_id) end
	add_participant(record, player_name)
	record.timestamps.last_active = now_seconds()
	mol.players[player_name] = mol.players[player_name] or {}
	mol.players[player_name].expedition_id = record.expedition_id
	mol.players[player_name].current_room_id = record.logical_positions[player_name] or mol.players[player_name].current_room_id or "room_yard"
	record.logical_positions[player_name] = mol.players[player_name].current_room_id
	mol.persist.set("player", "expedition:" .. player_name, record.expedition_id)
	log_event(record, "joined:" .. player_name)
	expedition.save(record.expedition_id)
	return record
end

function expedition.leave(player_name)
	local state = mol.players[player_name]
	local record = state and active_record(state.expedition_id)
	if not record then return end
	record.timestamps.last_active = now_seconds()
	if state.current_room_id then record.logical_positions[player_name] = state.current_room_id end
	remove_participant(record, player_name)
	log_event(record, "left:" .. player_name)
	expedition.save(record.expedition_id)
end

function expedition.update_player_room(player_name, room_id, pos)
	local state = mol.players[player_name]
	local record = state and active_record(state.expedition_id)
	if not record then return end
	record.logical_positions[player_name] = room_id
	if pos then
		record.last_safe_positions[player_name] = {x = pos.x, y = pos.y, z = pos.z}
	end
	record.timestamps.last_active = now_seconds()
	expedition.save(record.expedition_id)
end

function expedition.store_traversal_recovery(player_name, traversal)
	local state = mol.players[player_name]
	local record = state and active_record(state.expedition_id)
	if not (record and traversal and traversal.source_pos) then return false end
	record.logical_positions[RECOVERY_PREFIX .. player_name] = {
		room_id = state.current_room_id,
		source_pos = copy_plain(traversal.source_pos),
		source_yaw = traversal.source_yaw,
	}
	record.timestamps.last_active = now_seconds()
	log_event(record, "mid-traversal-disconnect:" .. player_name)
	expedition.save(record.expedition_id)
	return true
end

local function pop_recovery(record, player_name)
	local key = RECOVERY_PREFIX .. player_name
	local recovery = record.logical_positions and record.logical_positions[key]
	record.logical_positions[key] = nil
	return recovery
end

local function same_cell(a, b)
	return a and b and a.x == b.x and a.y == b.y and a.z == b.z
end

function expedition.room_id_for_position(pos)
	if not (pos and mol.cells and mol.cells.alloc) then return nil end
	local cell = mol.world_to_cell(pos)
	for room_id, allocated in pairs(mol.cells.alloc) do
		if same_cell(cell, allocated) then return room_id end
	end
	return nil
end

local function restore_position(player_name, player, record)
	local room_id = expedition.room_id_for_position(player:get_pos())
	if room_id then
		record.logical_positions[player_name] = room_id
		mol.players[player_name].current_room_id = room_id
		return
	end
	local safe = record.last_safe_positions and record.last_safe_positions[player_name]
	if player.set_pos then player:set_pos(safe or mol.SPAWN_POS) end
end

function expedition.restore_player(player)
	local player_name = player:get_player_name()
	local expedition_id = mol.persist.get("player", "expedition:" .. player_name)
	local record = expedition_id and active_record(expedition_id)
	if not record then
		mol.players[player_name] = mol.players[player_name] or {current_room_id = "room_yard"}
		return nil
	end
	add_participant(record, player_name)
	mol.players[player_name] = mol.players[player_name] or {}
	mol.players[player_name].expedition_id = expedition_id
	mol.players[player_name].current_room_id = record.logical_positions[player_name] or "room_yard"
	local recovery = pop_recovery(record, player_name)
	if recovery and recovery.source_pos then
		minetest.after(0.5, function()
			local current = minetest.get_player_by_name(player_name)
			if not current then return end
			current:set_pos(recovery.source_pos)
			if current.set_look_horizontal and recovery.source_yaw then current:set_look_horizontal(recovery.source_yaw) end
			log_event(record, "player recovered from mid-traversal disconnect:" .. player_name)
			expedition.save(expedition_id)
		end)
	else
		restore_position(player_name, player, record)
	end
	record.timestamps.last_active = now_seconds()
	expedition.save(expedition_id)
	return record
end

function expedition.apply_mutation(expedition_id, mutation)
	local record = active_record(expedition_id)
	if not record then return {ok = false, error = "expedition not active"} end
	local overrides = normalize_overrides(record.topology_overrides)
	local valid = mol.mutations.validate_scoped_mutation(mutation, overrides)
	if not valid.ok then return valid end
	overrides.seq = (tonumber(overrides.seq) or 0) + 1
	overrides.reroutes[mutation.from_door_id] = {
		to_room_id = mutation.to_room_id,
		to_slot = tonumber(mutation.to_slot),
	}
	overrides.seals[mutation.from_door_id] = nil
	record.topology_overrides = overrides
	record.timestamps.last_active = now_seconds()
	log_event(record, "mutation:" .. tostring(mutation.from_door_id))
	expedition.save(expedition_id)
	return {ok = true}
end

function expedition.mark_objective(player_name, key, value)
	local state = mol.players[player_name]
	local record = state and active_record(state.expedition_id)
	if not record then return false end
	record.objective_state[key] = value and true or false
	record.timestamps.last_active = now_seconds()
	log_event(record, "objective:" .. tostring(key))
	expedition.save(record.expedition_id)
	return true
end

function expedition.load_all()
	expedition.records = {}
	expedition.index = copy_plain(mol.persist.get("expedition", "index") or {})
	for _, expedition_id in ipairs(expedition.index) do
		local record = mol.persist.get("expedition", expedition_id)
		if type(record) == "table" then
			record.expedition_id = record.expedition_id or expedition_id
			if record.schema_version ~= expedition.SCHEMA_VERSION then
				minetest.log("warning", "[mol_expedition] schema mismatch for " .. tostring(expedition_id))
				record.lifecycle = "abandoned"
			end
			record.participants = {}
			expedition.records[expedition_id] = normalize_record(record)
		end
	end
end

function expedition.scan_abandoned()
	local now = now_seconds()
	for _, id in ipairs(expedition.index) do
		local record = expedition.records[id]
		if record then
			local last_active = record.timestamps and record.timestamps.last_active or 0
			if record.lifecycle == "active" and now - last_active > 24 * 3600 then
				record.lifecycle = "abandoned"
				log_event(record, "abandoned:inactive")
				minetest.log("warning", "[mol_expedition] abandoned inactive expedition " .. id)
				expedition.save(id)
			elseif record.lifecycle == "completed" and now - last_active > 3600 then
				record.lifecycle = "abandoned"
				log_event(record, "abandoned:completed")
				minetest.log("warning", "[mol_expedition] abandoned completed expedition " .. id)
				expedition.save(id)
			end
		end
	end
end

function expedition.enforce_cap()
	local now = now_seconds()
	local kept = {}
	for _, id in ipairs(expedition.index) do
		local record = expedition.records[id]
		if record and record.lifecycle == "abandoned" and now - (record.timestamps.last_active or 0) > expedition.ABANDONED_RETENTION then
			mol.persist.delete("expedition", id)
			expedition.records[id] = nil
		else
			kept[#kept + 1] = id
		end
	end
	expedition.index = kept
	while #expedition.index > expedition.MAX_EXPEDITIONS do
		local oldest_index, oldest_time
		for index, id in ipairs(expedition.index) do
			local record = expedition.records[id]
			if record and record.lifecycle == "abandoned" then
				local last_active = record.timestamps.last_active or 0
				if not oldest_time or last_active < oldest_time then
					oldest_time = last_active
					oldest_index = index
				end
			end
		end
		if not oldest_index then
			minetest.log("warning", "[mol_expedition] MAX_EXPEDITIONS exceeded but no abandoned records are deletable")
			break
		end
		local id = table.remove(expedition.index, oldest_index)
		minetest.log("warning", "[mol_expedition] deleting oldest abandoned expedition " .. id)
		mol.persist.delete("expedition", id)
		expedition.records[id] = nil
	end
	save_index()
end

function expedition.recover_player(expedition_id, player_name)
	local record = expedition.records[expedition_id]
	local player = minetest.get_player_by_name(player_name)
	if not player then return false, "Player not found" end
	local pos = record and record.last_safe_positions and record.last_safe_positions[player_name] or mol.SPAWN_POS
	player:set_pos(pos)
	return true, "Recovered " .. player_name
end

function expedition.abandon(expedition_id)
	local record = expedition.records[expedition_id]
	if not record then return false, "Unknown expedition" end
	record.lifecycle = "abandoned"
	record.timestamps.last_active = now_seconds()
	log_event(record, "abandoned:admin")
	expedition.save(expedition_id)
	return true, "Abandoned " .. expedition_id
end

expedition.load_all()
expedition.scan_abandoned()
expedition.enforce_cap()

minetest.register_on_joinplayer(function(player)
	expedition.restore_player(player)
end)

minetest.register_on_leaveplayer(function(player)
	local player_name = player:get_player_name()
	local state = mol.doors and mol.doors.traversing and mol.doors.traversing[player_name]
	if state then expedition.store_traversal_recovery(player_name, state) end
	expedition.leave(player_name)
end)

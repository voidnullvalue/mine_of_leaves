mol.graph = mol.graph or {}
mol.mutations = mol.mutations or {}

local GEN_VERSION = "1"
local SEED_PREFIX = "mol:graph:v1:"
local REMOVED_SENTINEL = "__removed"

local rooms = {}
local room_order = {}
local edges = {}
local edge_order = {}
local base_edges_by_door = {}

mol.graph.rooms = rooms
mol.graph.room_order = room_order
mol.graph.edges = edges
mol.graph.edge_order = edge_order
mol.graph.base_edges_by_door = base_edges_by_door

mol.mutations.MAX_LOG = mol.mutations.MAX_LOG or 1000
mol.mutations.log = mol.mutations.log or {}
mol.mutations.overrides = mol.mutations.overrides or {reroutes = {}, seals = {}, seq = 0}

local function clear()
	rooms = {}
	room_order = {}
	edges = {}
	edge_order = {}
	mol.graph.rooms = rooms
	mol.graph.room_order = room_order
	mol.graph.edges = edges
	mol.graph.edge_order = edge_order
end

local function shallow_copy(value)
	if type(value) ~= "table" then return value end
	local copy = {}
	for key, child in pairs(value) do
		copy[key] = shallow_copy(child)
	end
	return copy
end

local function override_destination(door_id, overrides)
	overrides = type(overrides) == "table" and overrides or nil
	if not overrides then return nil, false end
	local seals = type(overrides.seals) == "table" and overrides.seals or {}
	if seals[door_id] then return nil, true end
	local reroutes = type(overrides.reroutes) == "table" and overrides.reroutes or {}
	local target = reroutes[door_id]
	if type(target) == "table" then
		if target[REMOVED_SENTINEL] then return nil, true end
		return {room_id = target.to_room_id, to_slot = target.to_slot, slot = target.to_slot}, true
	end
	return nil, false
end

local function split_door_id(door_id)
	local room_id, slot = string.match(tostring(door_id or ""), "^(.*):slot_(%d+)$")
	if not room_id then return nil, nil end
	return room_id, tonumber(slot)
end

local function door_id(room_id, slot)
	return room_id .. ":slot_" .. slot
end

local function edge_id(from_door_id, to_room_id, to_slot)
	return from_door_id .. "->" .. to_room_id .. ":slot_" .. to_slot
end

local function remove_ordered_value(list, value)
	for index = #list, 1, -1 do
		if list[index] == value then
			table.remove(list, index)
		end
	end
end

local function find_edge_by_door(from_door_id)
	for _, eid in ipairs(edge_order) do
		local edge = edges[eid]
		if edge and edge.from_door_id == from_door_id then
			return edge, eid
		end
	end
	return nil, nil
end

local function remove_edge_id(eid)
	local edge = edges[eid]
	if not edge then return nil end
	edges[eid] = nil
	remove_ordered_value(edge_order, eid)
	return edge
end

local function reset_base_edges()
	base_edges_by_door = {}
	for _, eid in ipairs(edge_order) do
		local edge = edges[eid]
		if edge then
			base_edges_by_door[edge.from_door_id] = {
				from_door_id = edge.from_door_id,
				to_room_id = edge.to_room_id,
				to_slot = edge.to_slot,
				reciprocal = edge.reciprocal and true or false,
			}
		end
	end
	mol.graph.base_edges_by_door = base_edges_by_door
end

local function room_seed(world_seed_str, room_id)
	return mol.derive_seed(world_seed_str, SEED_PREFIX .. room_id)
end

local function clone_cell(cell)
	if not cell then return nil end
	return {x = cell.x, y = cell.y, z = cell.z}
end

local function hydrate_cell(room)
	if room and not room.cell_coord and mol.cells and mol.cells.alloc then
		room.cell_coord = clone_cell(mol.cells.alloc[room.room_id])
	end
	return room
end

local function add_error(errors, message)
	errors[#errors + 1] = message
end

local function required_slots_by_room()
	local required = {}
	for _, eid in ipairs(edge_order) do
		local edge = edges[eid]
		if edge then
			local from_room_id, from_slot = split_door_id(edge.from_door_id)
			if from_room_id and from_slot then
				required[from_room_id] = math.max(required[from_room_id] or 0, from_slot)
			end
			if edge.to_room_id and edge.to_slot then
				required[edge.to_room_id] = math.max(required[edge.to_room_id] or 0, edge.to_slot)
			end
		end
	end
	return required
end

local function invalidate_survival_cold_cache()
	if mol.survival and mol.survival.invalidate_cold_cache then
		mol.survival.invalidate_cold_cache()
	end
end

function mol.graph.add_room(room_id, template, seed)
	if rooms[room_id] then
		error("duplicate room_id " .. tostring(room_id))
	end
	local room = {
		room_id = room_id,
		template = template,
		room_seed = seed,
		cell_coord = nil,
		door_slots = {},
		gen_version = GEN_VERSION,
	}
	rooms[room_id] = room
	room_order[#room_order + 1] = room_id
	return room
end

function mol.graph.connect(from_door_id, to_room_id, to_slot, reciprocal)
	local from_room_id, from_slot = split_door_id(from_door_id)
	if not from_room_id then
		error("malformed from_door_id " .. tostring(from_door_id))
	end
	if not rooms[from_room_id] then
		error("unknown from room " .. tostring(from_room_id))
	end
	if not rooms[to_room_id] then
		error("unknown destination room " .. tostring(to_room_id))
	end
	local id = edge_id(from_door_id, to_room_id, to_slot)
	if edges[id] then
		error("duplicate edge_id " .. id)
	end
	local edge = {
		edge_id = id,
		from_door_id = from_door_id,
		to_room_id = to_room_id,
		to_slot = to_slot,
		reciprocal = reciprocal and true or false,
	}
	edges[id] = edge
	edge_order[#edge_order + 1] = id

	local room = rooms[from_room_id]
	room.door_slots[from_slot] = "slot_" .. from_slot

	if reciprocal then
		local reverse_door_id = door_id(to_room_id, to_slot)
		local reverse_id = edge_id(reverse_door_id, from_room_id, from_slot)
		if not edges[reverse_id] then
			local reverse = {
				edge_id = reverse_id,
				from_door_id = reverse_door_id,
				to_room_id = from_room_id,
				to_slot = from_slot,
				reciprocal = true,
			}
			edges[reverse_id] = reverse
			edge_order[#edge_order + 1] = reverse_id
			rooms[to_room_id].door_slots[to_slot] = "slot_" .. to_slot
		end
	end
	invalidate_survival_cold_cache()
	return edge
end

function mol.graph.disconnect(from_door_id)
	local removed = {}
	local edge = find_edge_by_door(from_door_id)
	if not edge then return removed end

	local from_room_id, from_slot = split_door_id(edge.from_door_id)
	if edge.reciprocal and from_room_id and from_slot then
		local reverse_id = edge_id(door_id(edge.to_room_id, edge.to_slot), from_room_id, from_slot)
		local reverse = remove_edge_id(reverse_id)
		if reverse then removed[#removed + 1] = reverse end
	end

	local _, eid = find_edge_by_door(from_door_id)
	local direct = eid and remove_edge_id(eid)
	if direct then removed[#removed + 1] = direct end
	if #removed > 0 then invalidate_survival_cold_cache() end
	return removed
end

function mol.graph.get_destination(id, expedition_id)
	if id == "entry" then id = "room_yard:slot_1" end
	if expedition_id and mol.expedition and mol.expedition.get_overrides then
		local destination, found = override_destination(id, mol.expedition.get_overrides(expedition_id))
		if found then return destination end
	end
	for _, eid in ipairs(edge_order) do
		local edge = edges[eid]
		if edge.from_door_id == id then
			return {room_id = edge.to_room_id, to_slot = edge.to_slot, slot = edge.to_slot}
		end
	end
	return nil
end

function mol.graph.get_room(room_id)
	return hydrate_cell(rooms[room_id])
end

local function set_room_door_ids(room_def, room_id)
	if not (room_def and room_def.door_slots) then return end
	for index, slot in ipairs(room_def.door_slots) do
		local offset = slot.offset
		slot.slot_id = "slot_" .. index
		local canonical_id = door_id(room_id, index)
		for _, spec in ipairs(room_def.nodes or {}) do
			if spec.offset and spec.offset.x == offset.x and spec.offset.z == offset.z then
				local dy = spec.offset.y - offset.y
				if dy >= 0 and dy <= 2 and spec.name == "mol:door_closed" then
					spec.meta = {door_id = canonical_id}
				end
			end
		end
	end
end

function mol.graph.prepare_room_def(room_def, room_id)
	set_room_door_ids(room_def, room_id)
	return room_def
end

function mol.graph.ensure_placed(room_id)
	local room = rooms[room_id]
	if not room then return nil end
	if not room.template then return hydrate_cell(room) end
	if room.cell_coord then return room end

	local cell = mol.cells.allocate(room_id)
	if not cell then return nil end
	local room_def = mol.rooms.generate(room.template, room.room_seed, {})
	if not room_def then return nil end
	room_def.room_id = room_id
	mol.graph.prepare_room_def(room_def, room_id)
	mol.cells.build(cell, room_def)
	room.cell_coord = clone_cell(cell)
	mol.graph.save()
	return room
end

local function neighbors(room_id)
	local list = {}
	for _, eid in ipairs(edge_order) do
		local edge = edges[eid]
		if edge then
			local from_room_id = split_door_id(edge.from_door_id)
			if from_room_id == room_id then
				list[#list + 1] = edge.to_room_id
			end
		end
	end
	return list
end

local function bfs(start_room_id)
	local distance = {}
	local parent = {}
	local queue = {}
	local head = 1
	if not rooms[start_room_id] then return distance, parent end
	distance[start_room_id] = 0
	queue[#queue + 1] = start_room_id
	while head <= #queue do
		local current = queue[head]
		head = head + 1
		for _, next_room in ipairs(neighbors(current)) do
			if rooms[next_room] and distance[next_room] == nil then
				distance[next_room] = distance[current] + 1
				parent[next_room] = current
				queue[#queue + 1] = next_room
			end
		end
	end
	return distance, parent
end

local function has_cycle()
	local visited = {}
	local function visit(room_id, from)
		visited[room_id] = true
		for _, next_room in ipairs(neighbors(room_id)) do
			if rooms[next_room] then
				if not visited[next_room] then
					if visit(next_room, room_id) then return true end
				elseif next_room ~= from then
					return true
				end
			end
		end
		return false
	end
	return rooms["room_entrance"] and visit("room_entrance", nil) or false
end

function mol.graph.validate(options)
	options = options or {}
	local errors = {}
	local seen_rooms = {}
	for _, room_id in ipairs(room_order) do
		if seen_rooms[room_id] then
			add_error(errors, "duplicate room ID: " .. room_id)
		end
		seen_rooms[room_id] = true
		if not rooms[room_id] then
			add_error(errors, "room order references missing room: " .. room_id)
		end
	end
	for room_id in pairs(rooms) do
		if not seen_rooms[room_id] then
			add_error(errors, "room missing from order: " .. room_id)
		end
	end

	local seen_edges = {}
	local degree = {}
	for _, eid in ipairs(edge_order) do
		if seen_edges[eid] then
			add_error(errors, "duplicate edge ID: " .. eid)
		end
		seen_edges[eid] = true
		local edge = edges[eid]
		if edge then
			local from_room_id, from_slot = split_door_id(edge.from_door_id)
			if not from_room_id or not from_slot then
				add_error(errors, "malformed edge door ID: " .. tostring(edge.from_door_id))
			elseif from_room_id == edge.to_room_id then
				add_error(errors, "invalid self-link: " .. edge.edge_id)
			end
			if from_room_id then degree[from_room_id] = (degree[from_room_id] or 0) + 1 end
			if edge.reciprocal and from_room_id and from_slot then
				local reverse_id = edge_id(door_id(edge.to_room_id, edge.to_slot), from_room_id, from_slot)
				if not edges[reverse_id] then
					add_error(errors, "missing reciprocal edge for " .. edge.edge_id)
				end
			end
		else
			add_error(errors, "edge order references missing edge: " .. eid)
		end
	end
	for eid in pairs(edges) do
		if not seen_edges[eid] then
			add_error(errors, "edge missing from order: " .. eid)
		end
	end

	for room_id, required_slot in pairs(required_slots_by_room()) do
		local room = rooms[room_id]
		if room and room.template then
			local room_def = mol.rooms.generate(room.template, room.room_seed, {})
			local physical_slots = room_def and room_def.door_slots and #room_def.door_slots or 0
			if physical_slots < required_slot then
				add_error(errors, "room graph references slot " .. required_slot .. " but template has " .. physical_slots .. " door slots: " .. room_id)
			end
		end
	end

	local from_yard = bfs("room_yard")
	local from_entrance = bfs("room_entrance")
	local from_objective = bfs("room_objective")
	if from_yard.room_entrance == nil then
		add_error(errors, "yard cannot reach room_entrance")
	end
	if from_entrance.room_objective == nil then
		add_error(errors, "room_entrance cannot reach room_objective")
	end
	if from_objective.room_escape == nil then
		add_error(errors, "room_objective cannot reach room_escape")
	end

	local objective = from_entrance.room_objective

	for _, room_id in ipairs(room_order) do
		if room_id ~= "room_yard" and from_entrance[room_id] == nil then
			add_error(errors, "orphan room unreachable from room_entrance: " .. room_id)
		end
	end

	local dead_ends = 0
	local dead_end_room_count = 0
	for _, room_id in ipairs(room_order) do
		local count = degree[room_id] or 0
		if count > 6 then
			add_error(errors, "room degree exceeds 6: " .. room_id)
		end
		if count == 0 and room_id ~= "room_yard" then
			add_error(errors, "room has no edges: " .. room_id)
		end
		if room_id ~= "room_yard" then
			dead_end_room_count = dead_end_room_count + 1
			if count == 1 then dead_ends = dead_ends + 1 end
		end
	end
	if not options.skip_aesthetic and dead_end_room_count > 0 and dead_ends / dead_end_room_count > 0.30 then
		add_error(errors, "too many dead ends: " .. dead_ends .. " of " .. dead_end_room_count)
	end

	if not objective or objective < 4 or objective > 20 then
		add_error(errors, "route length room_entrance to room_objective out of bounds: " .. tostring(objective))
	end
	if not has_cycle() then
		add_error(errors, "graph has no cycle")
	end

	return {ok = #errors == 0, errors = errors}
end

local function choice(prng, list)
	return list[prng:next(1, #list)]
end

local function add_seeded_room(world_seed_str, room_id, template)
	return mol.graph.add_room(room_id, template, room_seed(world_seed_str, room_id))
end

local function connect_rooms(a, a_slot, b, b_slot)
	mol.graph.connect(door_id(a, a_slot), b, b_slot, true)
end

function mol.graph.init_world(world_seed_str)
	clear()
	local prng = mol.new_prng(mol.derive_seed(world_seed_str, SEED_PREFIX .. "prng"))
	local critical = {
		{"room_yard", nil},
		{"room_entrance", "vestibule"},
		{"room_foyer", choice(prng, {"chamber", "hallway_narrow"})},
		{"room_hall", "corridor"},
		{"room_threshold", "vestibule"},
		{"room_orient", "chamber"},
		{"room_contradict", choice(prng, {"column_hall", "chamber"})},
		{"room_resource", "resource_room"},
		{"room_deep", "stair_segment"},
		{"room_hazard", "chamber"},
		{"room_objective", "chamber"},
		{"room_escape", "corridor"},
	}
	for _, spec in ipairs(critical) do
		add_seeded_room(world_seed_str, spec[1], spec[2])
	end

	connect_rooms("room_yard", 1, "room_entrance", 1)
	connect_rooms("room_entrance", 2, "room_foyer", 1)
	connect_rooms("room_foyer", 2, "room_hall", 1)
	connect_rooms("room_hall", 2, "room_threshold", 1)
	connect_rooms("room_threshold", 2, "room_orient", 1)
	connect_rooms("room_orient", 2, "room_contradict", 1)
	connect_rooms("room_contradict", 2, "room_resource", 1)
	connect_rooms("room_resource", 2, "room_deep", 1)
	connect_rooms("room_deep", 2, "room_hazard", 1)
	connect_rooms("room_hazard", 2, "room_objective", 1)
	connect_rooms("room_objective", 2, "room_escape", 1)
	mol.graph.connect(door_id("room_escape", 2), "room_orient", 3, false)

	local branch_templates = {"chamber", "corridor_bent", "hallway_narrow", "column_hall", "resource_room"}
	local loop_branch_templates = {"chamber", "corridor_bent", "hallway_narrow", "column_hall"}
	local orient_branches = prng:next(2, 4)
	for i = 1, orient_branches do
		local id = i == 1 and "room_branch_a" or ("room_orient_branch_" .. i)
		add_seeded_room(world_seed_str, id, choice(prng, i == 1 and loop_branch_templates or branch_templates))
		connect_rooms("room_orient", 3 + i, id, 1)
	end

	local hazard_branches = prng:next(1, 2)
	for i = 1, hazard_branches do
		local id = "room_hazard_branch_" .. i
		add_seeded_room(world_seed_str, id, choice(prng, branch_templates))
		connect_rooms("room_hazard", 2 + i, id, 1)
	end

	local loop_mid = "room_loop_link"
	add_seeded_room(world_seed_str, loop_mid, choice(prng, {"corridor", "corridor_bent", "hallway_narrow"}))
	connect_rooms("room_branch_a", 2, loop_mid, 1)
	connect_rooms(loop_mid, 2, "room_resource", 3)

	local result = mol.graph.validate()
	if not result.ok then
		for _, err in ipairs(result.errors) do
			minetest.log("error", "[mol_graph] init_world validation failed: " .. err)
		end
		clear()
		return nil, result.errors
	end
	reset_base_edges()
	return true
end

function mol.graph.save()
	local room_records = {}
	for _, room_id in ipairs(room_order) do
		local room = rooms[room_id]
		room_records[#room_records + 1] = {
			room_id = room.room_id,
			template = room.template,
			room_seed = room.room_seed,
			cell_coord = nil,
			door_slots = room.door_slots,
			gen_version = room.gen_version,
		}
	end
	local edge_records = {}
	for _, eid in ipairs(edge_order) do
		local edge = edges[eid]
		edge_records[#edge_records + 1] = {
			edge_id = edge.edge_id,
			from_door_id = edge.from_door_id,
			to_room_id = edge.to_room_id,
			to_slot = edge.to_slot,
			reciprocal = edge.reciprocal,
		}
	end
	mol.persist.set("graph", "rooms", room_records)
	mol.persist.set("graph", "edges", edge_records)
end

function mol.graph.load()
	clear()
	local room_records = mol.persist.get("graph", "rooms") or {}
	local edge_records = mol.persist.get("graph", "edges") or {}
	for _, record in ipairs(room_records) do
		local room = {
			room_id = record.room_id,
			template = record.template,
			room_seed = record.room_seed,
			cell_coord = clone_cell(record.cell_coord),
			door_slots = record.door_slots or {},
			gen_version = record.gen_version or GEN_VERSION,
		}
		rooms[room.room_id] = room
		room_order[#room_order + 1] = room.room_id
		hydrate_cell(room)
	end
	for _, record in ipairs(edge_records) do
		local edge = {
			edge_id = record.edge_id or edge_id(record.from_door_id, record.to_room_id, record.to_slot),
			from_door_id = record.from_door_id,
			to_room_id = record.to_room_id,
			to_slot = record.to_slot,
			reciprocal = record.reciprocal and true or false,
		}
		edges[edge.edge_id] = edge
		edge_order[#edge_order + 1] = edge.edge_id
	end
	reset_base_edges()
	return #room_order > 0
end

function mol.graph.dump_lines()
	local lines = {}
	for _, room_id in ipairs(room_order) do
		local room = hydrate_cell(rooms[room_id])
		lines[#lines + 1] = room.room_id .. " template=" .. tostring(room.template)
	end
	for _, eid in ipairs(edge_order) do
		local edge = edges[eid]
		lines[#lines + 1] = edge.from_door_id .. " -> " .. edge.to_room_id .. ":slot_" .. edge.to_slot
	end
	return lines
end

local function current_time_us()
	if minetest.get_us_time then return minetest.get_us_time() end
	return 0
end

local function normalize_overrides(overrides)
	overrides = type(overrides) == "table" and overrides or {}
	overrides.reroutes = type(overrides.reroutes) == "table" and overrides.reroutes or {}
	overrides.seals = type(overrides.seals) == "table" and overrides.seals or {}
	overrides.seq = tonumber(overrides.seq) or 0
	return overrides
end

local function persist_overrides()
	mol.persist.set("doors", "overrides", mol.mutations.overrides)
end

local function persist_log()
	mol.persist.set("mutations", "log", mol.mutations.log)
end

local function max_logged_seq()
	local seq = mol.mutations.overrides.seq or 0
	for _, record in ipairs(mol.mutations.log or {}) do
		if record.seq and record.seq > seq then seq = record.seq end
	end
	return seq
end

local function trim_log_if_needed()
	if #mol.mutations.log <= mol.mutations.MAX_LOG then return end
	local trim_count = math.min(200, #mol.mutations.log)
	for i = 1, trim_count do
		table.remove(mol.mutations.log, 1)
	end
	minetest.log("warning", "[mol_mutations] mutation log exceeded " ..
		mol.mutations.MAX_LOG .. "; trimmed " .. trim_count .. " oldest entries")
end

local function record_mutation(mutation)
	local seq = max_logged_seq() + 1
	local record = {
		seq = seq,
		timestamp = current_time_us(),
		mutation = shallow_copy(mutation),
	}
	mol.mutations.log[#mol.mutations.log + 1] = record
	mol.mutations.overrides.seq = seq
	trim_log_if_needed()
	persist_log()
	return record
end

local function snapshot_edges()
	return {
		edges = shallow_copy(edges),
		edge_order = shallow_copy(edge_order),
	}
end

local function restore_edges(snapshot)
	edges = snapshot.edges
	edge_order = snapshot.edge_order
	mol.graph.edges = edges
	mol.graph.edge_order = edge_order
end

local function room_door_slot_count(room_id)
	local room = rooms[room_id]
	if not room then return 0 end
	if room.template and mol.rooms then
		local ok, room_def = pcall(mol.rooms.generate, room.template, room.room_seed, {})
		if ok and room_def and room_def.door_slots then
			return #room_def.door_slots
		end
	end
	local max_slot = 0
	for index in pairs(room.door_slots or {}) do
		if type(index) == "number" and index > max_slot then max_slot = index end
	end
	for _, edge in pairs(edges) do
		local edge_room_id, edge_slot = split_door_id(edge.from_door_id)
		if edge_room_id == room_id and edge_slot and edge_slot > max_slot then
			max_slot = edge_slot
		end
		if edge.to_room_id == room_id and edge.to_slot and edge.to_slot > max_slot then
			max_slot = edge.to_slot
		end
	end
	return max_slot
end

local function affected_rooms(mutation)
	local affected = {}
	local from_room_id = split_door_id(mutation.from_door_id)
	if from_room_id then affected[from_room_id] = true end
	local current = find_edge_by_door(mutation.from_door_id)
	if current then affected[current.to_room_id] = true end
	if mutation.to_room_id then affected[mutation.to_room_id] = true end
	return affected
end

local function affected_rooms_for_overrides(mutation, overrides)
	local affected = {}
	local from_room_id = split_door_id(mutation.from_door_id)
	if from_room_id then affected[from_room_id] = true end
	local current = mol.graph.get_destination(mutation.from_door_id)
	local override_current, found = override_destination(mutation.from_door_id, overrides)
	if found then current = override_current end
	if current then affected[current.room_id] = true end
	if mutation.to_room_id then affected[mutation.to_room_id] = true end
	return affected
end

local function occupied_room(affected)
	for _, state in pairs(mol.players or {}) do
		local room_id = state and state.current_room_id
		if room_id and affected[room_id] then
			return room_id
		end
	end
	return nil
end

function mol.mutations.validate_mutation(mutation)
	if type(mutation) ~= "table" then
		return {ok = false, error = "mutation must be a table"}
	end
	if mutation.type ~= "reroute" then
		return {ok = false, error = "unsupported mutation type"}
	end

	local from_room_id, from_slot = split_door_id(mutation.from_door_id)
	if not from_room_id or not from_slot then
		return {ok = false, error = "invalid from_door_id"}
	end
	if not rooms[from_room_id] or from_slot < 1 or from_slot > room_door_slot_count(from_room_id) then
		return {ok = false, error = "from door does not exist"}
	end
	if not find_edge_by_door(mutation.from_door_id) then
		return {ok = false, error = "from door does not exist"}
	end
	if not rooms[mutation.to_room_id] then
		return {ok = false, error = "destination room does not exist"}
	end
	local to_slot = tonumber(mutation.to_slot)
	if not to_slot or to_slot < 1 or to_slot > room_door_slot_count(mutation.to_room_id) then
		return {ok = false, error = "destination slot does not exist"}
	end

	local occupied = occupied_room(affected_rooms(mutation))
	if occupied then
		return {ok = false, error = "room occupied"}
	end
	return {ok = true}
end

function mol.mutations.validate_scoped_mutation(mutation, overrides)
	if type(mutation) ~= "table" then
		return {ok = false, error = "mutation must be a table"}
	end
	if mutation.type ~= "reroute" then
		return {ok = false, error = "unsupported mutation type"}
	end

	local from_room_id, from_slot = split_door_id(mutation.from_door_id)
	if not from_room_id or not from_slot then
		return {ok = false, error = "invalid from_door_id"}
	end
	if not rooms[from_room_id] or from_slot < 1 or from_slot > room_door_slot_count(from_room_id) then
		return {ok = false, error = "from door does not exist"}
	end
	if not mol.graph.get_destination(mutation.from_door_id) then
		return {ok = false, error = "from door does not exist"}
	end
	if not rooms[mutation.to_room_id] then
		return {ok = false, error = "destination room does not exist"}
	end
	local to_slot = tonumber(mutation.to_slot)
	if not to_slot or to_slot < 1 or to_slot > room_door_slot_count(mutation.to_room_id) then
		return {ok = false, error = "destination slot does not exist"}
	end

	local occupied = occupied_room(affected_rooms_for_overrides(mutation, overrides))
	if occupied then
		return {ok = false, error = "room occupied"}
	end
	return {ok = true}
end

local function validation_error_text(result)
	if result and result.errors then
		return table.concat(result.errors, "; ")
	end
	return "graph validation failed"
end

local function store_reroute_override(from_door_id, to_room_id, to_slot)
	mol.mutations.overrides.reroutes[from_door_id] = {to_room_id = to_room_id, to_slot = to_slot}
	mol.mutations.overrides.seals[from_door_id] = nil
end

local function store_removed_override(from_door_id)
	mol.mutations.overrides.reroutes[from_door_id] = {[REMOVED_SENTINEL] = true}
	mol.mutations.overrides.seals[from_door_id] = nil
end

local function clear_override(from_door_id)
	mol.mutations.overrides.reroutes[from_door_id] = nil
	mol.mutations.overrides.seals[from_door_id] = nil
end

local function apply_reroute_in_memory(mutation)
	mol.graph.disconnect(mutation.from_door_id)
	mol.graph.connect(mutation.from_door_id, mutation.to_room_id, tonumber(mutation.to_slot), false)
end

local function apply_scoped_mutation(mutation, expedition_id)
	if not (mol.expedition and mol.expedition.apply_mutation) then
		return {ok = false, error = "expedition manager unavailable"}
	end
	return mol.expedition.apply_mutation(expedition_id, mutation)
end

function mol.mutations.apply(mutation, expedition_id)
	if expedition_id then
		return apply_scoped_mutation(mutation, expedition_id)
	end
	local valid = mol.mutations.validate_mutation(mutation)
	if not valid.ok then return valid end

	local snapshot = snapshot_edges()
	local ok, err = pcall(apply_reroute_in_memory, mutation)
	if not ok then
		restore_edges(snapshot)
		minetest.log("error", "[mol_mutations] apply failed: " .. tostring(err))
		return {ok = false, error = tostring(err)}
	end

	local graph_valid = mol.graph.validate({skip_aesthetic = true})
	if not graph_valid.ok then
		restore_edges(snapshot)
		local error_text = validation_error_text(graph_valid)
		minetest.log("error", "[mol_mutations] validation failed; rolled back: " .. error_text)
		return {ok = false, error = error_text}
	end

	store_reroute_override(mutation.from_door_id, mutation.to_room_id, tonumber(mutation.to_slot))
	record_mutation(mutation)
	persist_overrides()
	invalidate_survival_cold_cache()
	return {ok = true}
end

function mol.graph.mutate(from_door_id, new_to_room_id, new_to_slot)
	return mol.mutations.apply({
		type = "reroute",
		from_door_id = from_door_id,
		to_room_id = new_to_room_id,
		to_slot = new_to_slot,
		reason = "graph.mutate",
	})
end

function mol.mutations.disconnect(from_door_id)
	local from_room_id, from_slot = split_door_id(from_door_id)
	if not from_room_id or not from_slot or not rooms[from_room_id] or from_slot > room_door_slot_count(from_room_id) then
		return {ok = false, error = "from door does not exist"}
	end
	local current = find_edge_by_door(from_door_id)
	local affected = {}
	affected[from_room_id] = true
	if current then affected[current.to_room_id] = true end
	local occupied = occupied_room(affected)
	if occupied then return {ok = false, error = "room occupied"} end

	if current then mol.graph.disconnect(from_door_id) end
	store_removed_override(from_door_id)
	persist_overrides()
	invalidate_survival_cold_cache()
	return {ok = true}
end

function mol.mutations.seal(from_door_id)
	local from_room_id, from_slot = split_door_id(from_door_id)
	if not from_room_id or not from_slot or not rooms[from_room_id] or from_slot > room_door_slot_count(from_room_id) then
		return {ok = false, error = "from door does not exist"}
	end
	local current = find_edge_by_door(from_door_id)
	local affected = {}
	affected[from_room_id] = true
	if current then affected[current.to_room_id] = true end
	local occupied = occupied_room(affected)
	if occupied then return {ok = false, error = "room occupied"} end

	local snapshot = snapshot_edges()
	if current then mol.graph.disconnect(from_door_id) end
	local graph_valid = mol.graph.validate({skip_aesthetic = true})
	if not graph_valid.ok then
		restore_edges(snapshot)
		local error_text = validation_error_text(graph_valid)
		minetest.log("error", "[mol_mutations] seal validation failed; rolled back: " .. error_text)
		return {ok = false, error = error_text}
	end

	mol.mutations.overrides.reroutes[from_door_id] = nil
	mol.mutations.overrides.seals[from_door_id] = true
	record_mutation({type = "seal", from_door_id = from_door_id})
	persist_overrides()
	invalidate_survival_cold_cache()
	return {ok = true}
end

function mol.mutations.unseal(from_door_id)
	local from_room_id, from_slot = split_door_id(from_door_id)
	if not from_room_id or not from_slot or not rooms[from_room_id] or from_slot > room_door_slot_count(from_room_id) then
		return {ok = false, error = "from door does not exist"}
	end
	local base = base_edges_by_door[from_door_id]
	local affected = {}
	affected[from_room_id] = true
	if base then affected[base.to_room_id] = true end
	local occupied = occupied_room(affected)
	if occupied then return {ok = false, error = "room occupied"} end

	local snapshot = snapshot_edges()
	mol.graph.disconnect(from_door_id)
	if base then
		mol.graph.connect(from_door_id, base.to_room_id, base.to_slot, base.reciprocal)
	end
	local graph_valid = mol.graph.validate({skip_aesthetic = true})
	if not graph_valid.ok then
		restore_edges(snapshot)
		local error_text = validation_error_text(graph_valid)
		minetest.log("error", "[mol_mutations] unseal validation failed; rolled back: " .. error_text)
		return {ok = false, error = error_text}
	end

	clear_override(from_door_id)
	record_mutation({type = "unseal", from_door_id = from_door_id})
	persist_overrides()
	invalidate_survival_cold_cache()
	return {ok = true}
end

function mol.mutations.apply_overrides(overrides)
	overrides = normalize_overrides(overrides)
	local snapshot = snapshot_edges()
	local ok, err = pcall(function()
		for from_door_id in pairs(overrides.seals) do
			mol.graph.disconnect(from_door_id)
		end
		for from_door_id, target in pairs(overrides.reroutes) do
			mol.graph.disconnect(from_door_id)
			if type(target) == "table" and not target[REMOVED_SENTINEL] then
				mol.graph.connect(from_door_id, target.to_room_id, target.to_slot, false)
			end
		end
	end)
	if not ok then
		restore_edges(snapshot)
		minetest.log("error", "[mol_mutations] override replay failed; rolled back: " .. tostring(err))
		return {ok = false, error = tostring(err)}
	end
	mol.mutations.overrides = overrides
	invalidate_survival_cold_cache()
	return {ok = true, overrides = overrides}
end

local function load_mutation_state()
	mol.mutations.log = mol.persist.get("mutations", "log") or {}
	mol.mutations.overrides = normalize_overrides(mol.persist.get("doors", "overrides"))
end

local resource_check_elapsed = 0
local function resource_visit_seen()
	for _, state in pairs(mol.players or {}) do
		if state and state.current_room_id == "room_resource" then
			return true, state.expedition_id
		end
	end
	return false, nil
end

local function register_scripted_mutation()
	minetest.register_globalstep(function(dtime)
		resource_check_elapsed = resource_check_elapsed + dtime
		if resource_check_elapsed < 1 then return end
		resource_check_elapsed = 0
		local seen, expedition_id = resource_visit_seen()
		if not seen then return end
		local event_key = expedition_id and ("resource_visited:" .. expedition_id) or "resource_visited"
		if mol.persist.get("events", event_key) == true then return end
		mol.persist.set("events", event_key, true)
		minetest.after(30, function()
			local result = mol.mutations.apply({
				type = "reroute",
				from_door_id = "room_orient:slot_2",
				to_room_id = "room_hazard",
				to_slot = 1,
				reason = "scripted_resource_visit",
			}, expedition_id)
			if not result.ok then
				minetest.log("warning", "[mol_mutations] scripted resource mutation failed: " .. tostring(result.error))
			end
		end)
	end)
end

local seed = minetest.get_mapgen_setting("seed")
local ok = mol.graph.init_world(seed)
if ok then
	load_mutation_state()
	mol.mutations.apply_overrides(mol.mutations.overrides)
	local result = mol.graph.validate({skip_aesthetic = true})
	if not result.ok then
		for _, err in ipairs(result.errors) do
			minetest.log("error", "[mol_graph] persisted override validation failed: " .. err)
		end
	end
	mol.graph.save()
	mol.persist.set("world", "initialized", "true")
end
register_scripted_mutation()

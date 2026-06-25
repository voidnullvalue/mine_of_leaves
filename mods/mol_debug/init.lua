local CELL_PATTERN = "^%s*(-?%d+)%s+(-?%d+)%s+(-?%d+)%s*$"

local function parse_cell_args(param)
	local cx, cy, cz = string.match(param or "", CELL_PATTERN)
	if not cx then return nil end
	return tonumber(cx), tonumber(cy), tonumber(cz)
end

local function parse_room_id(param)
	local room_id = string.match(param or "", "^%s*(%S+)%s*$")
	return room_id
end

local function parse_door_args(param)
	local from_door_id, to_room_id, to_slot = string.match(param or "", "^%s*(%S+)%s+(%S+)%s+(%d+)%s*$")
	if not from_door_id then return nil end
	return from_door_id, to_room_id, tonumber(to_slot)
end

local function parse_two_args(param)
	local a, b = string.match(param or "", "^%s*(%S+)%s+(%S+)%s*$")
	return a, b
end

local function same_cell(a, b)
	return a and b and a.x == b.x and a.y == b.y and a.z == b.z
end

local function room_id_for_position(pos)
	local cell = mol.world_to_cell(pos)
	for room_id, allocated in pairs(mol.cells.alloc or {}) do
		if same_cell(cell, allocated) then return room_id, cell end
	end
	return nil, cell
end

minetest.register_chatcommand("mol_cell", {
	params = "<cx> <cy> <cz>",
	description = "Teleport to a mineofleaves cell origin.",
	privs = {server = true},
	func = function(name, param)
		local cx, cy, cz = parse_cell_args(param)
		if not cx then
			return false, "Usage: /mol_cell <cx> <cy> <cz>"
		end

		local origin = mol.cells.get_origin(cx, cy, cz)
		local player = minetest.get_player_by_name(name)
		if player then
			player:set_pos({x = origin.x, y = origin.y + 2, z = origin.z})
		end

		return true, "Cell origin: " .. origin.x .. ", " .. origin.y .. ", " .. origin.z
	end,
})

minetest.register_chatcommand("mol_build", {
	params = "<room_id>",
	description = "Build a graph room.",
	privs = {server = true},
	func = function(name, param)
		local room_id = parse_room_id(param)
		if not room_id then return false, "Usage: /mol_build <room_id>" end
		local room = mol.graph.get_room(room_id)
		if not room then return false, "Unknown graph room " .. room_id end
		if not room.template then return false, room_id .. " has no physical room template" end
		if mol.cells.is_built(room_id) then return true, room_id .. " is already built" end
		room = mol.graph.ensure_placed(room_id)
		if not (room and room.cell_coord) then return false, "Unable to build " .. room_id end
		if mol.doors and mol.doors.index_add_room then mol.doors.index_add_room(room_id) end
		local cell = room.cell_coord
		return true, "Built " .. room_id .. " at cell " .. cell.x .. ", " .. cell.y .. ", " .. cell.z
	end,
})

minetest.register_chatcommand("mol_regen", {
	params = "<room_id>",
	description = "Regenerate an allocated chamber room in place.",
	privs = {server = true},
	func = function(name, param)
		local room_id = parse_room_id(param)
		if not room_id then return false, "Usage: /mol_regen <room_id>" end
		local cell = mol.cells.alloc[room_id]
		if not cell then return false, room_id .. " is not allocated" end
		local room = mol.graph.get_room(room_id)
		if not (room and room.template) then return false, "Unknown physical graph room " .. room_id end
		local room_def = mol.rooms.generate(room.template, room.room_seed, {})
		if not room_def then return false, "Unable to generate room" end
		room_def.room_id = room_id
		mol.graph.prepare_room_def(room_def, room_id)
		mol.cells.build(cell, room_def, true)
		if mol.doors and mol.doors.index_add_room then mol.doors.index_add_room(room_id) end
		return true, "Regenerated " .. room_id .. " at cell " .. cell.x .. ", " .. cell.y .. ", " .. cell.z
	end,
})

minetest.register_chatcommand("mol_graph", {
	params = "",
	description = "Print the current room graph.",
	privs = {server = true},
	func = function(name, param)
		return true, table.concat(mol.graph.dump_lines(), "\n")
	end,
})

minetest.register_chatcommand("mol_door", {
	params = "<from_door_id> <to_room_id> <to_slot>",
	description = "Reroute a graph door edge.",
	privs = {server = true},
	func = function(name, param)
		local from_door_id, to_room_id, to_slot = parse_door_args(param)
		if not from_door_id then
			return false, "Usage: /mol_door <from_door_id> <to_room_id> <to_slot>"
		end
		local result = mol.mutations.apply({
			type = "reroute",
			from_door_id = from_door_id,
			to_room_id = to_room_id,
			to_slot = to_slot,
			reason = "debug",
		})
		if result.ok then return true, "Rerouted " .. from_door_id .. " -> " .. to_room_id .. ":slot_" .. to_slot end
		return false, "Mutation failed: " .. tostring(result.error)
	end,
})

minetest.register_chatcommand("mol_seal", {
	params = "<from_door_id>",
	description = "Seal a graph door edge.",
	privs = {server = true},
	func = function(name, param)
		local from_door_id = parse_room_id(param)
		if not from_door_id then return false, "Usage: /mol_seal <from_door_id>" end
		local result = mol.mutations.seal(from_door_id)
		if result.ok then return true, "Sealed " .. from_door_id end
		return false, "Seal failed: " .. tostring(result.error)
	end,
})

minetest.register_chatcommand("mol_unseal", {
	params = "<from_door_id>",
	description = "Unseal a graph door edge.",
	privs = {server = true},
	func = function(name, param)
		local from_door_id = parse_room_id(param)
		if not from_door_id then return false, "Usage: /mol_unseal <from_door_id>" end
		local result = mol.mutations.unseal(from_door_id)
		if result.ok then return true, "Unsealed " .. from_door_id end
		return false, "Unseal failed: " .. tostring(result.error)
	end,
})

minetest.register_chatcommand("mol_mutations", {
	params = "",
	description = "Print recent graph mutations.",
	privs = {server = true},
	func = function(name, param)
		local log = mol.mutations.log or {}
		if #log == 0 then return true, "No mutations recorded" end
		local lines = {}
		local first = math.max(1, #log - 19)
		for i = first, #log do
			local record = log[i]
			local mutation = record.mutation or {}
			lines[#lines + 1] = "#" .. tostring(record.seq) ..
				" t=" .. tostring(record.timestamp) ..
				" " .. tostring(mutation.type) ..
				" " .. tostring(mutation.from_door_id) ..
				(mutation.to_room_id and (" -> " .. mutation.to_room_id .. ":slot_" .. tostring(mutation.to_slot)) or "")
		end
		return true, table.concat(lines, "\n")
	end,
})

minetest.register_chatcommand("mol_expeditions", {
	params = "",
	description = "List expeditions.",
	privs = {server = true},
	func = function(name, param)
		if not (mol.expedition and mol.expedition.index) then return true, "No expedition manager" end
		local lines = {}
		for _, id in ipairs(mol.expedition.index) do
			local record = mol.expedition.records[id]
			if record then
				lines[#lines + 1] = id ..
					" lifecycle=" .. tostring(record.lifecycle) ..
					" participants=" .. tostring(#(record.participants or {})) ..
					" last_active=" .. tostring(record.timestamps and record.timestamps.last_active)
			end
		end
		if #lines == 0 then return true, "No expeditions" end
		return true, table.concat(lines, "\n")
	end,
})

minetest.register_chatcommand("mol_expedition_dump", {
	params = "<expedition_id>",
	description = "Dump an expedition record.",
	privs = {server = true},
	func = function(name, param)
		local expedition_id = parse_room_id(param)
		local record = mol.expedition and mol.expedition.records[expedition_id]
		if not record then return false, "Unknown expedition" end
		return true, minetest.serialize(record)
	end,
})

minetest.register_chatcommand("mol_expedition_recover", {
	params = "<expedition_id> <player_name>",
	description = "Teleport a player to their expedition safe position.",
	privs = {server = true},
	func = function(name, param)
		local expedition_id, player_name = parse_two_args(param)
		if not expedition_id then return false, "Usage: /mol_expedition_recover <expedition_id> <player_name>" end
		return mol.expedition.recover_player(expedition_id, player_name)
	end,
})

minetest.register_chatcommand("mol_expedition_abandon", {
	params = "<expedition_id>",
	description = "Mark an expedition abandoned.",
	privs = {server = true},
	func = function(name, param)
		local expedition_id = parse_room_id(param)
		if not expedition_id then return false, "Usage: /mol_expedition_abandon <expedition_id>" end
		return mol.expedition.abandon(expedition_id)
	end,
})

minetest.register_chatcommand("mol_where", {
	params = "",
	description = "Print current logical room and world position.",
	privs = {server = true},
	func = function(name, param)
		local player = minetest.get_player_by_name(name)
		if not player then return false, "Player not found" end
		local pos = player:get_pos()
		local room_id, cell = room_id_for_position(pos)
		local survival = mol.survival
		local extra = ""
		if survival and survival.hop_distance then
			local hops = survival.hop_distance(room_id) or 0
			local physical = 0
			local entrance = mol.graph.get_room("room_entrance")
			if entrance and entrance.cell_coord then
				physical = math.floor(vector.distance(pos, mol.cells.get_origin(entrance.cell_coord)))
			end
			extra = " entrance_doors=" .. tostring(hops) .. " entrance_nodes=" .. tostring(physical)
		end
		return true, "room=" .. tostring(room_id or "unknown") ..
			" cell=" .. cell.x .. "," .. cell.y .. "," .. cell.z ..
			" pos=" .. math.floor(pos.x * 100) / 100 .. "," ..
				math.floor(pos.y * 100) / 100 .. "," ..
				math.floor(pos.z * 100) / 100 ..
			extra
	end,
})

minetest.register_chatcommand("mol_templates", {
	params = "",
	description = "List registered room templates.",
	privs = {server = true},
	func = function(name, param)
		local names = {}
		for template_name in pairs(mol.rooms.template_status or {}) do
			names[#names + 1] = template_name
		end
		table.sort(names)
		local parts = {}
		for _, template_name in ipairs(names) do
			parts[#parts + 1] = template_name .. "=" .. (mol.rooms.template_status[template_name] and "valid" or "invalid")
		end
		return true, table.concat(parts, ", ")
	end,
})

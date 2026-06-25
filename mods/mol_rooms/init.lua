mol.rooms = mol.rooms or {}
mol.rooms.templates = mol.rooms.templates or {}
mol.rooms.template_status = mol.rooms.template_status or {}

local function log_error(message)
	minetest.log("error", "[mol_rooms] " .. message)
end

local function offset_in_bounds(offset)
	return type(offset) == "table" and
		type(offset.x) == "number" and offset.x >= 0 and offset.x <= mol.CELL_SIZE - 1 and
		type(offset.y) == "number" and offset.y >= 0 and offset.y <= mol.CELL_SIZE - 1 and
		type(offset.z) == "number" and offset.z >= 0 and offset.z <= mol.CELL_SIZE - 1
end

function mol.rooms.validate_room_def(name, room_def)
	if type(room_def) ~= "table" then
		return false, "template did not return a room_def"
	end
	if type(room_def.nodes) ~= "table" or #room_def.nodes == 0 then
		return false, "room_def has no nodes"
	end
	if type(room_def.door_slots) ~= "table" or #room_def.door_slots < 1 then
		return false, "room_def has no door slots"
	end
	if type(room_def.arrival) ~= "table" or #room_def.arrival < 2 then
		return false, "room_def has fewer than 2 arrival positions"
	end
	for index, spec in ipairs(room_def.nodes) do
		if not offset_in_bounds(spec.offset) then
			return false, "node " .. index .. " has out-of-bounds offset"
		end
	end
	for index, slot in ipairs(room_def.door_slots) do
		if not offset_in_bounds(slot.offset) then
			return false, "door slot " .. index .. " has out-of-bounds offset"
		end
	end
	for index, arrival in ipairs(room_def.arrival) do
		if not offset_in_bounds(arrival.offset) then
			return false, "arrival " .. index .. " has out-of-bounds offset"
		end
	end
	return true
end

function mol.rooms.validate_template(name, template_fn)
	local ok, room_def = pcall(template_fn, mol.new_prng(1337), {})
	if not ok then
		log_error("invalid template " .. name .. ": " .. tostring(room_def))
		mol.rooms.template_status[name] = false
		return false
	end
	local valid, reason = mol.rooms.validate_room_def(name, room_def)
	if not valid then
		log_error("invalid template " .. name .. ": " .. reason)
		mol.rooms.template_status[name] = false
		return false
	end
	mol.rooms.template_status[name] = true
	return true
end

function mol.rooms.register_template(name, template_fn)
	if mol.rooms.validate_template(name, template_fn) then
		mol.rooms.templates[name] = template_fn
	end
end

function mol.rooms.generate(template_name, room_seed, options)
	local template_fn = mol.rooms.templates[template_name]
	if not template_fn then
		log_error("unknown template " .. tostring(template_name))
		return nil
	end
	return template_fn(mol.new_prng(room_seed), options or {})
end

dofile(minetest.get_modpath("mol_rooms") .. "/templates/common.lua")
dofile(minetest.get_modpath("mol_rooms") .. "/templates/corridor.lua")
dofile(minetest.get_modpath("mol_rooms") .. "/templates/chamber.lua")
dofile(minetest.get_modpath("mol_rooms") .. "/templates/vestibule.lua")
dofile(minetest.get_modpath("mol_rooms") .. "/templates/hallway_narrow.lua")
dofile(minetest.get_modpath("mol_rooms") .. "/templates/corridor_bent.lua")
dofile(minetest.get_modpath("mol_rooms") .. "/templates/stair_segment.lua")
dofile(minetest.get_modpath("mol_rooms") .. "/templates/column_hall.lua")
dofile(minetest.get_modpath("mol_rooms") .. "/templates/resource_room.lua")

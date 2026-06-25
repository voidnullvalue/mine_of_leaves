mol.rooms.common = {}

local common = mol.rooms.common

function common.round_to_multiple(value, multiple)
	return math.max(multiple, math.floor(value / multiple) * multiple)
end

function common.new_room(template, size, meta)
	return {
		template = template,
		size = size,
		nodes = {},
		door_slots = {},
		arrival = {},
		meta = meta or {},
	}
end

function common.key(offset)
	return offset.x .. "," .. offset.y .. "," .. offset.z
end

function common.in_bounds(offset)
	return offset.x >= 0 and offset.x <= 63 and
		offset.y >= 0 and offset.y <= 63 and
		offset.z >= 0 and offset.z <= 63
end

function common.add_node(room, offset, name, param2, meta)
	if not common.in_bounds(offset) then return end
	room._index = room._index or {}
	local key = common.key(offset)
	local spec = {offset = offset, name = name, param2 = param2, meta = meta}
	if room._index[key] then
		room.nodes[room._index[key]] = spec
	else
		room._index[key] = #room.nodes + 1
		room.nodes[#room.nodes + 1] = spec
	end
end

function common.add_door(room, offset, facing)
	if not common.in_bounds(offset) then return end
	local slot_id = #room.door_slots
	room.door_slots[#room.door_slots + 1] = {offset = offset, facing = facing, slot_id = slot_id}
	common.add_node(room, offset, "mol:door_closed", nil, {door_id = room.template .. "_" .. slot_id})
end

function common.add_arrival(room, offset)
	if common.in_bounds(offset) then
		room.arrival[#room.arrival + 1] = {offset = offset}
	end
end

function common.finish(room)
	room._index = nil
	local narrative = {
		chamber = {narrative_slot = "survey_case", journal_ref = "chamber_shift"},
		column_hall = {narrative_slot = "tripod", journal_ref = "column_echo"},
		corridor = {narrative_slot = "chalk_bag", journal_ref = "corridor_count"},
		corridor_bent = {narrative_slot = "tape_reel", journal_ref = "bent_return"},
		hallway_narrow = {narrative_slot = "field_pack", journal_ref = "narrow_listening"},
		resource_room = {narrative_slot = "document_crate", journal_ref = "resource_inventory"},
		stair_segment = {narrative_slot = "broken_level", journal_ref = "stair_measure"},
	}
	local meta = narrative[room.template]
	if meta then
		room.meta = room.meta or {}
		for key, value in pairs(meta) do
			if room.meta[key] == nil then room.meta[key] = value end
		end
	end
	return room
end

function common.hollow_box(room, sx, sy, sz)
	for x = 0, sx - 1 do
		for z = 0, sz - 1 do
			common.add_node(room, {x = x, y = 0, z = z}, "mol:floor")
			common.add_node(room, {x = x, y = sy - 1, z = z}, "mol:ceiling")
		end
	end
	for y = 1, sy - 2 do
		for x = 0, sx - 1 do
			common.add_node(room, {x = x, y = y, z = 0}, "mol:wall")
			common.add_node(room, {x = x, y = y, z = sz - 1}, "mol:wall")
		end
		for z = 0, sz - 1 do
			common.add_node(room, {x = 0, y = y, z = z}, "mol:wall")
			common.add_node(room, {x = sx - 1, y = y, z = z}, "mol:wall")
		end
	end
	for x = 1, sx - 2 do
		for y = 1, sy - 2 do
			for z = 1, sz - 2 do
				common.add_node(room, {x = x, y = y, z = z}, "mol:void")
			end
		end
	end
end

function common.add_door_frame(room, offset, facing)
	local x, y, z = offset.x, offset.y, offset.z
	local side
	if facing == "n" or facing == "s" then
		side = {
			{x = x - 1, y = y, z = z},
			{x = x + 1, y = y, z = z},
			{x = x, y = y + 3, z = z},
		}
	else
		side = {
			{x = x, y = y, z = z - 1},
			{x = x, y = y, z = z + 1},
			{x = x, y = y + 3, z = z},
		}
	end
	for _, pos in ipairs(side) do
		common.add_node(room, pos, "mol:door_frame")
	end
end

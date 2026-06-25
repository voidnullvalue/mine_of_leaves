mol.rooms.register_template("column_hall", function(prng, options)
	local common = mol.rooms.common
	local sx = common.round_to_multiple(prng:next(20, 40), 4)
	local sz = common.round_to_multiple(prng:next(20, 40), 4)
	local height = 10
	local room = common.new_room("column_hall", {x = sx, y = height, z = sz})

	common.hollow_box(room, sx, height, sz)
	local column_count = prng:next(4, 16)
	for i = 1, column_count do
		local x = common.round_to_multiple(prng:next(4, sx - 5), 4)
		local z = common.round_to_multiple(prng:next(4, sz - 5), 4)
		for y = 1, height - 2 do
			common.add_node(room, {x = x, y = y, z = z}, "mol:wall")
			common.add_node(room, {x = x + 1, y = y, z = z}, "mol:wall")
			common.add_node(room, {x = x, y = y, z = z + 1}, "mol:wall")
			common.add_node(room, {x = x + 1, y = y, z = z + 1}, "mol:wall")
		end
	end

	local slots = {
		{offset = {x = math.floor(sx / 2), y = 1, z = 0}, facing = "n", arrival = {x = math.floor(sx / 2), y = 1, z = 1}},
		{offset = {x = math.floor(sx / 2), y = 1, z = sz - 1}, facing = "s", arrival = {x = math.floor(sx / 2), y = 1, z = sz - 2}},
		{offset = {x = 0, y = 1, z = math.floor(sz / 2)}, facing = "w", arrival = {x = 1, y = 1, z = math.floor(sz / 2)}},
		{offset = {x = sx - 1, y = 1, z = math.floor(sz / 2)}, facing = "e", arrival = {x = sx - 2, y = 1, z = math.floor(sz / 2)}},
	}
	for i = 1, prng:next(3, 4) do
		common.add_door_frame(room, slots[i].offset, slots[i].facing)
		common.add_door(room, slots[i].offset, slots[i].facing)
		common.add_arrival(room, slots[i].arrival)
	end
	while #room.arrival < 4 do
		common.add_arrival(room, {x = math.floor(sx / 2), y = 1, z = math.floor(sz / 2)})
	end
	for _, pos in ipairs({{x = 3, z = 3}, {x = sx - 4, z = 3}, {x = 3, z = sz - 4}, {x = sx - 4, z = sz - 4}}) do
		common.add_node(room, {x = pos.x, y = height - 2, z = pos.z}, "mol:light_fixture")
	end

	return common.finish(room)
end)

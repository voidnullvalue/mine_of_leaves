mol.rooms.register_template("chamber", function(prng, options)
	local common = mol.rooms.common
	local side = math.min(prng:next(10, 30), 46)
	local height = math.max(8, math.floor(side / 2))
	local room = common.new_room("chamber", {x = side, y = height, z = side})

	common.hollow_box(room, side, height, side)
	local low = math.max(3, math.floor(side / 3))
	local high = math.min(side - 4, math.floor(side * 2 / 3))
	local dirs = {
		{facing = "n", offset = {x = low, y = 1, z = 0}, arrival = {x = low, y = 1, z = 1}},
		{facing = "s", offset = {x = high, y = 1, z = side - 1}, arrival = {x = high, y = 1, z = side - 2}},
		{facing = "w", offset = {x = 0, y = 1, z = low}, arrival = {x = 1, y = 1, z = low}},
		{facing = "e", offset = {x = side - 1, y = 1, z = high}, arrival = {x = side - 2, y = 1, z = high}},
		{facing = "n", offset = {x = high, y = 1, z = 0}, arrival = {x = high, y = 1, z = 1}},
		{facing = "s", offset = {x = low, y = 1, z = side - 1}, arrival = {x = low, y = 1, z = side - 2}},
		{facing = "w", offset = {x = 0, y = 1, z = high}, arrival = {x = 1, y = 1, z = high}},
	}
	for _, dir in ipairs(dirs) do
		common.add_door_frame(room, dir.offset, dir.facing)
		common.add_door(room, dir.offset, dir.facing)
		common.add_arrival(room, dir.arrival)
	end

	for i = 1, prng:next(2, 6) do
		common.add_node(room, {
			x = prng:next(2, side - 3),
			y = height - 2,
			z = prng:next(2, side - 3),
		}, "mol:light_fixture")
	end

	return common.finish(room)
end)

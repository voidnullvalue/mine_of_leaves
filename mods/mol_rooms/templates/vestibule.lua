mol.rooms.register_template("vestibule", function(prng, options)
	local common = mol.rooms.common
	local room = common.new_room("vestibule", {x = 6, y = 4, z = 6})

	for x = 0, 5 do
		for y = 0, 3 do
			for z = 0, 5 do
				common.add_node(room, {x = x, y = y, z = z}, "mol:dark_void")
			end
		end
	end

	-- Each traversable path position needs floor below + two clear vertical nodes.
	-- (3,1,4) is the secondary arrival that lies off the main L-path.
	for _, pos in ipairs({
		{x = 2, y = 1, z = 0}, {x = 2, y = 1, z = 1}, {x = 2, y = 1, z = 2},
		{x = 3, y = 1, z = 2}, {x = 4, y = 1, z = 2}, {x = 4, y = 1, z = 3},
		{x = 4, y = 1, z = 4}, {x = 3, y = 1, z = 4}, {x = 4, y = 1, z = 5},
	}) do
		common.add_node(room, {x = pos.x, y = 0, z = pos.z}, "mol:floor")
		common.add_node(room, pos, "air")
		common.add_node(room, {x = pos.x, y = 2, z = pos.z}, "air")
	end

	common.add_door(room, {x = 2, y = 1, z = 0}, "n")
	common.add_door(room, {x = 4, y = 1, z = 5}, "s")
	common.add_arrival(room, {x = 4, y = 1, z = 4})
	common.add_arrival(room, {x = 3, y = 1, z = 4})

	return common.finish(room)
end)

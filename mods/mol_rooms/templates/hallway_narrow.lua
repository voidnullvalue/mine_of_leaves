mol.rooms.register_template("hallway_narrow", function(prng, options)
	local common = mol.rooms.common
	local length = prng:next(8, 32)
	local room = common.new_room("hallway_narrow", {x = 4, y = 5, z = length})

	common.hollow_box(room, 4, 5, length)
	for z = 4, length - 3, 10 do
		common.add_node(room, {x = 1, y = 3, z = z}, "mol:light_fixture")
	end
	common.add_door(room, {x = 1, y = 1, z = 0}, "n")
	common.add_door(room, {x = 2, y = 1, z = length - 1}, "s")
	common.add_arrival(room, {x = 1, y = 1, z = 1})
	common.add_arrival(room, {x = 2, y = 1, z = length - 2})

	return common.finish(room)
end)

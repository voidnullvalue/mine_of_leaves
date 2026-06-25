mol.rooms.register_template("corridor", function(prng, options)
	local common = mol.rooms.common
	local length = common.round_to_multiple(prng:next(16, 48), 4)
	local width = 6
	local height = 6
	local room = common.new_room("corridor", {x = width, y = height, z = length})

	common.hollow_box(room, width, height, length)
	for z = 4, length - 5, 8 do
		common.add_node(room, {x = 1, y = height - 2, z = z}, "mol:light_fixture")
		common.add_node(room, {x = 2, y = height - 2, z = z}, "mol:light_fixture")
	end

	common.add_door_frame(room, {x = 2, y = 1, z = 0}, "n")
	common.add_door(room, {x = 2, y = 1, z = 0}, "n")
	common.add_door_frame(room, {x = 3, y = 1, z = length - 1}, "s")
	common.add_door(room, {x = 3, y = 1, z = length - 1}, "s")
	common.add_arrival(room, {x = 2, y = 1, z = 1})
	common.add_arrival(room, {x = 3, y = 1, z = length - 2})

	return common.finish(room)
end)

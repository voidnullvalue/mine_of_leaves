mol.rooms.register_template("resource_room", function(prng, options)
	local common = mol.rooms.common
	local sx = prng:next(8, 12)
	local sz = prng:next(8, 12)
	local height = 6
	local room = common.new_room("resource_room", {x = sx, y = height, z = sz}, {is_resource = "true"})

	common.hollow_box(room, sx, height, sz)
	common.add_door_frame(room, {x = math.floor(sx / 2), y = 1, z = 0}, "n")
	common.add_door(room, {x = math.floor(sx / 2), y = 1, z = 0}, "n")
	common.add_door_frame(room, {x = math.floor(sx / 2), y = 1, z = sz - 1}, "s")
	common.add_door(room, {x = math.floor(sx / 2), y = 1, z = sz - 1}, "s")
	common.add_door_frame(room, {x = sx - 1, y = 1, z = math.floor(sz / 2)}, "e")
	common.add_door(room, {x = sx - 1, y = 1, z = math.floor(sz / 2)}, "e")
	common.add_arrival(room, {x = math.floor(sx / 2), y = 1, z = 1})
	common.add_arrival(room, {x = math.floor(sx / 2) - 1, y = 1, z = 1})
	common.add_arrival(room, {x = math.floor(sx / 2), y = 1, z = sz - 2})
	common.add_arrival(room, {x = sx - 2, y = 1, z = math.floor(sz / 2)})
	for x = 2, sx - 3, 3 do
		for z = 2, sz - 3, 3 do
			common.add_node(room, {x = x, y = height - 2, z = z}, "mol:light_fixture")
		end
	end

	return common.finish(room)
end)

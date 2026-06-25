mol.rooms.register_template("stair_segment", function(prng, options)
	local common = mol.rooms.common
	local up = prng:next(0, 1) == 0
	local rise = prng:next(4, 12)
	local width = 6
	local length = rise + 6
	local height = rise + 5
	local room = common.new_room("stair_segment", {x = width, y = height, z = length}, {direction = up and "up" or "down"})

	for z = 0, length - 1 do
		local step_y = math.min(rise, math.max(0, z - 2))
		if not up then step_y = rise - step_y end
		for x = 1, width - 2 do
			common.add_node(room, {x = x, y = step_y, z = z}, "mol:floor")
			common.add_node(room, {x = x, y = height - 1, z = z}, "mol:ceiling")
			for y = step_y + 1, height - 2 do
				common.add_node(room, {x = x, y = y, z = z}, "air")
			end
		end
		for y = 0, height - 2 do
			common.add_node(room, {x = 0, y = y, z = z}, "mol:wall")
			common.add_node(room, {x = width - 1, y = y, z = z}, "mol:wall")
		end
	end
	common.add_door(room, {x = 2, y = up and 1 or rise + 1, z = 0}, "n")
	common.add_door(room, {x = 3, y = up and rise + 1 or 1, z = length - 1}, "s")
	common.add_arrival(room, {x = 2, y = up and 1 or rise + 1, z = 1})
	common.add_arrival(room, {x = 3, y = up and rise + 1 or 1, z = length - 2})
	common.add_node(room, {x = 2, y = height - 2, z = math.floor(length / 2)}, "mol:light_fixture")

	return common.finish(room)
end)

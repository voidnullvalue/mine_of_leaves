mol.rooms.register_template("corridor_bent", function(prng, options)
	local common = mol.rooms.common
	local a = prng:next(8, 24)
	local b = prng:next(8, 24)
	local width = 4
	local height = 6
	local sx = a
	local sz = b
	local room = common.new_room("corridor_bent", {x = sx, y = height, z = sz})
	local open = {}
	local function mark(x, z)
		open[x .. "," .. z] = true
	end

	for x = 0, a - 1 do
		for z = 0, width - 1 do mark(x, z) end
	end
	for x = a - width, a - 1 do
		for z = 0, b - 1 do mark(x, z) end
	end

	for x = 0, sx - 1 do
		for z = 0, sz - 1 do
			if open[x .. "," .. z] then
				common.add_node(room, {x = x, y = 0, z = z}, "mol:floor")
				common.add_node(room, {x = x, y = height - 1, z = z}, "mol:ceiling")
				for y = 1, height - 2 do
					common.add_node(room, {x = x, y = y, z = z}, "air")
				end
			end
		end
	end
	for x = 0, sx - 1 do
		for z = 0, sz - 1 do
			if open[x .. "," .. z] then
				for _, n in ipairs({{x = x - 1, z = z}, {x = x + 1, z = z}, {x = x, z = z - 1}, {x = x, z = z + 1}}) do
					if n.x >= 0 and n.x < sx and n.z >= 0 and n.z < sz and not open[n.x .. "," .. n.z] then
						for y = 1, height - 2 do
							common.add_node(room, {x = n.x, y = y, z = n.z}, "mol:wall")
						end
					end
				end
			end
		end
	end

	common.add_door(room, {x = 0, y = 1, z = 1}, "w")
	common.add_door(room, {x = a - 2, y = 1, z = b - 1}, "s")
	common.add_arrival(room, {x = 1, y = 1, z = 1})
	common.add_arrival(room, {x = a - 2, y = 1, z = b - 2})
	common.add_node(room, {x = a - 2, y = height - 2, z = 1}, "mol:light_fixture")

	return common.finish(room)
end)

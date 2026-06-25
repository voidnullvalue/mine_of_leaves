local HOUSE_POS = mol.HOUSE_POS
local HOUSE_SIZE = mol.HOUSE_SIZE
local YARD_MIN = mol.YARD_MIN
local YARD_MAX = mol.YARD_MAX
local BOUNDARY_HEIGHT = mol.BOUNDARY_HEIGHT

local house_max = {
	x = HOUSE_POS.x + HOUSE_SIZE.x - 1,
	y = HOUSE_POS.y + HOUSE_SIZE.y - 1,
	z = HOUSE_POS.z + HOUSE_SIZE.z - 1,
}

local footprint_min = {
	x = math.min(YARD_MIN.x, HOUSE_POS.x),
	y = 0,
	z = math.min(YARD_MIN.z, HOUSE_POS.z),
}

local footprint_max = {
	x = math.max(YARD_MAX.x, house_max.x),
	y = math.max(BOUNDARY_HEIGHT, house_max.y),
	z = math.max(YARD_MAX.z, house_max.z),
}

local function intersects(a_min, a_max, b_min, b_max)
	return a_min.x <= b_max.x and a_max.x >= b_min.x and
		a_min.y <= b_max.y and a_max.y >= b_min.y and
		a_min.z <= b_max.z and a_max.z >= b_min.z
end

local function clamp(value, min_value, max_value)
	if value < min_value then return min_value end
	if value > max_value then return max_value end
	return value
end

local function key_for_pos(pos)
	return pos.x .. "," .. pos.y .. "," .. pos.z
end

local function add_node(list, index, offset, name, param2, meta)
	local key = key_for_pos(offset)
	local existing = index[key]
	local spec = {offset = offset, name = name, param2 = param2, meta = meta}
	if existing then
		list[existing] = spec
		return
	end
	index[key] = #list + 1
	list[#list + 1] = spec
end

local function make_house_nodes()
	local nodes = {}
	local index = {}
	local min_x = 0
	local max_x = HOUSE_SIZE.x - 1
	local min_z = 0
	local max_z = HOUSE_SIZE.z - 1
	local min_y = 0
	local max_y = HOUSE_SIZE.y - 1
	local front_door_x = 6
	local front_door_z = min_z
	local interior_door_x = 6
	local interior_wall_z = 5
	local threshold_x = 6
	local threshold_z = max_z - 1

	local function is_front_door_gap(x, y, z)
		return z == front_door_z and (x == front_door_x or x == front_door_x + 1) and y >= 1 and y <= 3
	end

	local function is_window_gap(x, y, z)
		if z ~= front_door_z or y < 3 or y > 4 then return false end
		return (x >= 2 and x <= 3) or (x >= 9 and x <= 10)
	end

	for x = min_x, max_x do
		for z = min_z, max_z do
			add_node(nodes, index, {x = x, y = 1, z = z}, "mol:floor")
			add_node(nodes, index, {x = x, y = max_y, z = z}, "mol:ceiling")
		end
	end

	for y = min_y, max_y do
		for x = min_x, max_x do
			if not is_front_door_gap(x, y, min_z) and not is_window_gap(x, y, min_z) then
				add_node(nodes, index, {x = x, y = y, z = min_z}, "mol:wall")
			end
			add_node(nodes, index, {x = x, y = y, z = max_z}, "mol:wall")
		end
		for z = min_z, max_z do
			add_node(nodes, index, {x = min_x, y = y, z = z}, "mol:wall")
			add_node(nodes, index, {x = max_x, y = y, z = z}, "mol:wall")
		end
	end

	for _, x in ipairs({2, 3, 9, 10}) do
		for y = 3, 4 do
			add_node(nodes, index, {x = x, y = y, z = front_door_z}, "mol:dark_void")
		end
	end

	for x = 1, max_x - 1 do
		for y = 1, 5 do
			if not (x == interior_door_x and y >= 1 and y <= 3) then
				add_node(nodes, index, {x = x, y = y, z = interior_wall_z}, "mol:wall")
			end
			if not (x == threshold_x and y >= 1 and y <= 3) then
				add_node(nodes, index, {x = x, y = y, z = threshold_z}, "mol:wall")
			end
		end
	end

	for _, pos in ipairs({
		{x = front_door_x - 1, y = 1, z = front_door_z},
		{x = front_door_x + 2, y = 1, z = front_door_z},
		{x = front_door_x, y = 4, z = front_door_z},
		{x = front_door_x + 1, y = 4, z = front_door_z},
		{x = interior_door_x - 1, y = 1, z = interior_wall_z},
		{x = interior_door_x + 1, y = 1, z = interior_wall_z},
		{x = interior_door_x, y = 4, z = interior_wall_z},
		{x = threshold_x - 1, y = 1, z = threshold_z},
		{x = threshold_x + 1, y = 1, z = threshold_z},
		{x = threshold_x, y = 4, z = threshold_z},
	}) do
		add_node(nodes, index, pos, "mol:door_frame")
	end

	add_node(nodes, index, {x = front_door_x, y = 1, z = front_door_z}, "mol:door_closed", nil, {door_id = "entry"})
	add_node(nodes, index, {x = interior_door_x, y = 1, z = interior_wall_z}, "mol:door_closed", nil, {door_id = "interior_1"})
	add_node(nodes, index, {x = threshold_x, y = 1, z = threshold_z}, "mol:door_closed", nil, {door_id = "threshold_1"})

	for _, pos in ipairs({
		{x = 3, y = 6, z = 3},
		{x = 8, y = 6, z = 3},
		{x = 3, y = 6, z = 7},
		{x = 8, y = 6, z = 7},
	}) do
		add_node(nodes, index, pos, "mol:light_fixture")
	end

	return nodes
end

local house_nodes = make_house_nodes()

local function write_node(data, param2_data, area, ids, pos, name, param2)
	local id = ids[name]
	if not id then
		id = minetest.get_content_id(name)
		ids[name] = id
	end
	local index = area:index(pos.x, pos.y, pos.z)
	data[index] = id
	if param2 then param2_data[index] = param2 end
end

local function pos_in_range(pos, minp, maxp)
	return pos.x >= minp.x and pos.x <= maxp.x and
		pos.y >= minp.y and pos.y <= maxp.y and
		pos.z >= minp.z and pos.z <= maxp.z
end

local function build_yard_and_house(minp, maxp)
	-- Luanti 5.10 supports core.get_voxel_manip([p1, p2]), but the
	-- no-arg form plus read_from_map(minp, maxp) keeps on_generated writes
	-- strictly inside the callback's provided mapchunk bounds.
	local vm = minetest.get_voxel_manip()
	local emin, emax = vm:read_from_map(minp, maxp)
	local area = VoxelArea:new({MinEdge = emin, MaxEdge = emax})
	local data = vm:get_data()
	local param2_data = vm:get_param2_data()
	local ids = {}
	local door_meta = {}

	for x = minp.x, maxp.x do
		for y = minp.y, maxp.y do
			for z = minp.z, maxp.z do
				write_node(data, param2_data, area, ids, {x = x, y = y, z = z}, "mol:void")
			end
		end
	end

	if minp.y <= 0 and maxp.y >= 0 then
		for x = clamp(minp.x, YARD_MIN.x, YARD_MAX.x), clamp(maxp.x, YARD_MIN.x, YARD_MAX.x) do
			for z = clamp(minp.z, YARD_MIN.z, YARD_MAX.z), clamp(maxp.z, YARD_MIN.z, YARD_MAX.z) do
				write_node(data, param2_data, area, ids, {x = x, y = 0, z = z}, "mol:floor")
			end
		end
	end

	-- Replace the playable yard interior above the floor with real air so that
	-- sunlight can reach the yard surface.  The column extends to the top of this
	-- mapchunk so the sky opening is unbroken for calc_lighting.  Boundary walls
	-- and house nodes placed in subsequent steps overwrite the positions they need.
	local air_id = minetest.get_content_id("air")
	local sky_xmin = clamp(minp.x, YARD_MIN.x + 1, YARD_MAX.x - 1)
	local sky_xmax = clamp(maxp.x, YARD_MIN.x + 1, YARD_MAX.x - 1)
	local sky_zmin = clamp(minp.z, YARD_MIN.z + 1, YARD_MAX.z - 1)
	local sky_zmax = clamp(maxp.z, YARD_MIN.z + 1, YARD_MAX.z - 1)
	local sky_ymin = math.max(minp.y, 1)
	if sky_xmin <= sky_xmax and sky_zmin <= sky_zmax and sky_ymin <= maxp.y then
		for x = sky_xmin, sky_xmax do
			for y = sky_ymin, maxp.y do
				for z = sky_zmin, sky_zmax do
					data[area:index(x, y, z)] = air_id
				end
			end
		end
	end

	for y = clamp(minp.y, 1, BOUNDARY_HEIGHT), clamp(maxp.y, 1, BOUNDARY_HEIGHT) do
		for x = clamp(minp.x, YARD_MIN.x, YARD_MAX.x), clamp(maxp.x, YARD_MIN.x, YARD_MAX.x) do
			if minp.z <= YARD_MIN.z and maxp.z >= YARD_MIN.z then
				write_node(data, param2_data, area, ids, {x = x, y = y, z = YARD_MIN.z}, "mol:boundary_wall")
			end
			if minp.z <= YARD_MAX.z and maxp.z >= YARD_MAX.z then
				write_node(data, param2_data, area, ids, {x = x, y = y, z = YARD_MAX.z}, "mol:boundary_wall")
			end
		end
		for z = clamp(minp.z, YARD_MIN.z, YARD_MAX.z), clamp(maxp.z, YARD_MIN.z, YARD_MAX.z) do
			if minp.x <= YARD_MIN.x and maxp.x >= YARD_MIN.x then
				write_node(data, param2_data, area, ids, {x = YARD_MIN.x, y = y, z = z}, "mol:boundary_wall")
			end
			if minp.x <= YARD_MAX.x and maxp.x >= YARD_MAX.x then
				write_node(data, param2_data, area, ids, {x = YARD_MAX.x, y = y, z = z}, "mol:boundary_wall")
			end
		end
	end

	for _, spec in ipairs(house_nodes) do
		local pos = {
			x = HOUSE_POS.x + spec.offset.x,
			y = HOUSE_POS.y + spec.offset.y,
			z = HOUSE_POS.z + spec.offset.z,
		}
		if pos_in_range(pos, minp, maxp) then
			write_node(data, param2_data, area, ids, pos, spec.name, spec.param2)
			if spec.meta then
				door_meta[#door_meta + 1] = {pos = pos, meta = spec.meta}
			end
		end
	end

	vm:set_data(data)
	vm:set_param2_data(param2_data)
	vm:calc_lighting()
	vm:write_to_map()
	vm:update_map()

	for _, spec in ipairs(door_meta) do
		local meta = minetest.get_meta(spec.pos)
		for key, value in pairs(spec.meta) do
			meta:set_string(key, value)
		end
	end
end

local function range_intersects_built_cell(minp, maxp)
	if not (mol.cells and mol.cells.built_cells) then return false end
	for _, cell in pairs(mol.cells.built_cells) do
		local origin = mol.cell_to_world(cell.x, cell.y, cell.z)
		local cell_max = {
			x = origin.x + mol.CELL_SIZE - 1,
			y = origin.y + mol.CELL_SIZE - 1,
			z = origin.z + mol.CELL_SIZE - 1,
		}
		if intersects(minp, maxp, origin, cell_max) then return true end
	end
	return false
end

local function fill_with_void(minp, maxp)
	-- Luanti 5.10 VoxelManip API: read_from_map() returns the actual emerged
	-- area, which may be larger than requested; only minp..maxp is edited.
	local vm = minetest.get_voxel_manip()
	local emin, emax = vm:read_from_map(minp, maxp)
	local area = VoxelArea:new({MinEdge = emin, MaxEdge = emax})
	local data = vm:get_data()
	local void_id = minetest.get_content_id("mol:void")
	local air_id  = minetest.get_content_id("air")

	-- Compute the yard sky-column bounds clipped to this chunk.
	-- Chunks above the yard footprint (y > footprint_max.y) land here and
	-- must also carry air in the yard column so that sunlight can propagate
	-- downward through an unbroken column of air into the yard.
	local sc_xmin = math.max(minp.x, YARD_MIN.x + 1)
	local sc_xmax = math.min(maxp.x, YARD_MAX.x - 1)
	local sc_zmin = math.max(minp.z, YARD_MIN.z + 1)
	local sc_zmax = math.min(maxp.z, YARD_MAX.z - 1)
	local sc_ymin = math.max(minp.y, 1)
	local has_sky_col = sc_xmin <= sc_xmax and sc_zmin <= sc_zmax and sc_ymin <= maxp.y

	for x = minp.x, maxp.x do
		for y = minp.y, maxp.y do
			for z = minp.z, maxp.z do
				if has_sky_col and y >= sc_ymin and
						x >= sc_xmin and x <= sc_xmax and
						z >= sc_zmin and z <= sc_zmax then
					data[area:index(x, y, z)] = air_id
				else
					data[area:index(x, y, z)] = void_id
				end
			end
		end
	end

	vm:set_data(data)
	if has_sky_col then vm:calc_lighting() end
	vm:write_to_map()
	vm:update_map()
end

if minetest.get_mapgen_setting("mg_name") ~= "singlenode" then
	minetest.log("error", "[mol_world] mineofleaves requires singlenode mapgen; forcing mg_name=singlenode")
	minetest.set_mapgen_setting("mg_name", "singlenode", true)
end

minetest.set_mapgen_setting("static_spawnpoint", "0,3,-8", true)

minetest.register_on_newplayer(function(player)
	player:set_pos(mol.SPAWN_POS)
	player:set_look_horizontal(0)
end)

minetest.register_on_joinplayer(function(player, last_login)
	if last_login == nil then return end
end)

minetest.register_on_placenode(function(pos, newnode, placer, oldnode, itemstack, pointed_thing)
	if newnode.name == "mol:chalk_mark" then
		if mol.is_chalk_allowed_region(pos) then return end
		minetest.remove_node(pos)
		return true
	end
	if mol.is_yard_boundary_region(pos) then
		minetest.remove_node(pos)
		return true
	end
end)

minetest.register_on_generated(function(minp, maxp, seed)
	-- Mapgen-thread safe: this callback only uses VoxelManip/content-id work
	-- and does not call player-facing APIs.
	if intersects(minp, maxp, footprint_min, footprint_max) then
		build_yard_and_house(minp, maxp)
		return
	end

	if range_intersects_built_cell(minp, maxp) then return end
	fill_with_void(minp, maxp)
end)

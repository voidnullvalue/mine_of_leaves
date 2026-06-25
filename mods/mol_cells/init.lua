mol.cells = mol.cells or {}

local CELL_MAX_COORD = mol.CELL_MAX_COORD

local alloc = mol.persist.get("cells", "alloc") or {}
local built = mol.persist.get("cells", "built") or {}

mol.cells.used = {}
mol.cells.alloc = alloc
mol.cells.built = built
mol.cells.built_cells = {}

local function cell_key(cx, cy, cz)
	return cx .. "," .. cy .. "," .. cz
end

local function parse_cell_key(key)
	local cx, cy, cz = string.match(key, "^(-?%d+),(-?%d+),(-?%d+)$")
	if not cx then return nil end
	return {x = tonumber(cx), y = tonumber(cy), z = tonumber(cz)}
end

local function normalize_cell(cell)
	return {x = cell.x, y = cell.y, z = cell.z}
end

local function same_cell(a, b)
	return a and b and a.x == b.x and a.y == b.y and a.z == b.z
end

local function room_id_for_cell(cell_coord)
	for room_id, cell in pairs(alloc) do
		if same_cell(cell, cell_coord) then return room_id end
	end
	return nil
end

local function persist_alloc()
	local stored = {}
	for room_id, cell in pairs(alloc) do
		if type(cell) == "table" then
			stored[room_id] = cell_key(cell.x, cell.y, cell.z)
		else
			stored[room_id] = cell
		end
	end
	mol.persist.set("cells", "alloc", stored)
end

local function persist_built()
	mol.persist.set("cells", "built", built)
end

for room_id, cell in pairs(alloc) do
	if type(cell) == "string" then
		cell = parse_cell_key(cell)
		alloc[room_id] = cell
	end
	if cell then
		mol.cells.used[cell_key(cell.x, cell.y, cell.z)] = true
	end
end

for room_id, cell in pairs(built) do
	if type(cell) == "string" then
		cell = parse_cell_key(cell)
		built[room_id] = cell or true
	end
	if type(cell) == "table" then
		mol.cells.built_cells[room_id] = normalize_cell(cell)
		mol.cells.used[cell_key(cell.x, cell.y, cell.z)] = true
	elseif alloc[room_id] then
		mol.cells.built_cells[room_id] = normalize_cell(alloc[room_id])
		mol.cells.used[cell_key(alloc[room_id].x, alloc[room_id].y, alloc[room_id].z)] = true
	end
end

function mol.cells.allocate(room_id)
	if alloc[room_id] then return normalize_cell(alloc[room_id]) end

	for radius = 0, CELL_MAX_COORD do
		for cx = -radius, radius do
			for cy = -radius, radius do
				for cz = -radius, radius do
					if math.max(math.abs(cx), math.abs(cy), math.abs(cz)) == radius then
						local key = cell_key(cx, cy, cz)
						if not mol.cells.used[key] then
							local cell = {x = cx, y = cy, z = cz}
							mol.cells.used[key] = true
							alloc[room_id] = cell
							persist_alloc()
							return normalize_cell(cell)
						end
					end
				end
			end
		end
	end

	return nil
end

function mol.cells.get_origin(cx, cy, cz)
	if type(cx) == "table" then
		return mol.cell_to_world(cx.x, cx.y, cx.z)
	end
	return mol.cell_to_world(cx, cy, cz)
end

function mol.cells.get_door_pos(cell_coord, slot_index, room_def)
	local origin = mol.cells.get_origin(cell_coord)
	if room_def and room_def.door_slots then
		local index = slot_index or 1
		local slot = room_def.door_slots[index] or room_def.door_slots[index + 1]
		if slot and slot.offset then
			return {
				x = origin.x + slot.offset.x,
				y = origin.y + slot.offset.y + 1,
				z = origin.z + slot.offset.z,
			}
		end
	end
	return {x = origin.x + 2, y = origin.y + 2, z = origin.z + 2}
end

function mol.cells.mark_built(room_id, cell_coord)
	local cell = cell_coord or alloc[room_id]
	if cell then
		built[room_id] = normalize_cell(cell)
		mol.cells.built_cells[room_id] = normalize_cell(cell)
		mol.cells.used[cell_key(cell.x, cell.y, cell.z)] = true
	else
		built[room_id] = true
	end
	persist_built()
end

function mol.cells.is_built(room_id)
	return built[room_id] ~= nil
end

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

local function offset_in_cell(offset)
	return type(offset) == "table" and
		type(offset.x) == "number" and offset.x >= 0 and offset.x < mol.CELL_SIZE and
		type(offset.y) == "number" and offset.y >= 0 and offset.y < mol.CELL_SIZE and
		type(offset.z) == "number" and offset.z >= 0 and offset.z < mol.CELL_SIZE
end

function mol.cells.build(cell_coord, room_def, force_rebuild)
	if type(room_def) ~= "table" then
		minetest.log("error", "[mol_cells] build called without room_def")
		return
	end
	local room_id = room_def.room_id or room_id_for_cell(cell_coord)
	if room_id and mol.cells.is_built(room_id) and not force_rebuild then
		return
	end

	local origin = mol.cells.get_origin(cell_coord)
	local maxp = {
		x = origin.x + mol.CELL_SIZE - 1,
		y = origin.y + mol.CELL_SIZE - 1,
		z = origin.z + mol.CELL_SIZE - 1,
	}
	-- Luanti 5.10 supports core.get_voxel_manip([p1, p2]); using the
	-- no-arg form plus read_from_map(origin, maxp) is the documented fallback.
	local vm = minetest.get_voxel_manip()
	local emin, emax = vm:read_from_map(origin, maxp)
	local area = VoxelArea:new({MinEdge = emin, MaxEdge = emax})
	local data = vm:get_data()
	local param2_data = vm:get_param2_data()
	local ids = {}
	local door_meta = {}
	local void_id = minetest.get_content_id("mol:void")

	for index = 1, #data do
		data[index] = void_id
	end

	for _, spec in ipairs(room_def.nodes or {}) do
		local offset = spec.offset
		if not offset_in_cell(offset) then
			minetest.log("error", "[mol_cells] skipping out-of-bounds room node offset for " .. tostring(room_id or room_def.template or "unknown"))
		else
			local pos = {
				x = origin.x + offset.x,
				y = origin.y + offset.y,
				z = origin.z + offset.z,
			}
			write_node(data, param2_data, area, ids, pos, spec.name, spec.param2)
			if spec.meta then door_meta[#door_meta + 1] = {pos = pos, meta = spec.meta} end
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

	if room_id then
		mol.cells.mark_built(room_id, cell_coord)
	end
end

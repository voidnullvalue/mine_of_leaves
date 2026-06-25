mol = mol or {}

local CELL_SIZE = 64
local MAPBLOCK_SIZE = 16
local CELL_MAPBLOCKS = 4
local CELL_MAX_COORD = 32
local HASH_MOD = 2147483646

mol.CELL_SIZE = CELL_SIZE
mol.MAPBLOCK_SIZE = MAPBLOCK_SIZE
mol.CELL_MAPBLOCKS = CELL_MAPBLOCKS
mol.CELL_MAX_COORD = CELL_MAX_COORD
mol.INTERIOR_ORIGIN = {x = 1024, y = -64, z = 0}
mol.SPAWN_POS = {x = 0, y = 3, z = -8}
mol.HOUSE_POS = {x = -6, y = 0, z = 0}
mol.HOUSE_SIZE = {x = 12, y = 8, z = 10}
mol.YARD_MIN = {x = -12, y = 0, z = -10}
mol.YARD_MAX = {x = 12, y = 0, z = 14}
mol.BOUNDARY_HEIGHT = 5

mol.DOOR_FACEDIR = {n = 0, e = 1, s = 2, w = 3}
mol.DOOR_INWARD = {
	n = {x = 0, y = 0, z = 1},
	e = {x = -1, y = 0, z = 0},
	s = {x = 0, y = 0, z = -1},
	w = {x = 1, y = 0, z = 0},
}
mol.DOOR_INWARD_YAW = {
	n = 0,
	e = math.pi / 2,
	s = math.pi,
	w = math.pi * 1.5,
}

function mol.door_facedir(facing)
	return mol.DOOR_FACEDIR[facing] or 0
end

function mol.door_inward_dir(facing)
	local dir = mol.DOOR_INWARD[facing] or mol.DOOR_INWARD.n
	return {x = dir.x, y = dir.y, z = dir.z}
end

function mol.door_inward_yaw(facing)
	return mol.DOOR_INWARD_YAW[facing] or 0
end

function mol.cell_to_world(cx, cy, cz)
	return {
		x = mol.INTERIOR_ORIGIN.x + cx * mol.CELL_SIZE,
		y = mol.INTERIOR_ORIGIN.y + cy * mol.CELL_SIZE,
		z = mol.INTERIOR_ORIGIN.z + cz * mol.CELL_SIZE,
	}
end

function mol.world_to_cell(pos)
	return {
		x = math.floor((pos.x - mol.INTERIOR_ORIGIN.x) / mol.CELL_SIZE),
		y = math.floor((pos.y - mol.INTERIOR_ORIGIN.y) / mol.CELL_SIZE),
		z = math.floor((pos.z - mol.INTERIOR_ORIGIN.z) / mol.CELL_SIZE),
	}
end

function mol.is_yard_boundary_region(pos)
	if pos.y < 0 or pos.y > mol.BOUNDARY_HEIGHT then return false end
	return pos.x < mol.YARD_MIN.x or pos.x > mol.YARD_MAX.x or
		pos.z < mol.YARD_MIN.z or pos.z > mol.YARD_MAX.z
end

function mol.is_chalk_allowed_region(pos)
	if not (pos and mol.cells and mol.cells.alloc) then return false end
	local cell = mol.world_to_cell(pos)
	local origin = mol.cell_to_world(cell.x, cell.y, cell.z)
	if pos.x < origin.x or pos.x >= origin.x + mol.CELL_SIZE then return false end
	if pos.y < origin.y or pos.y >= origin.y + mol.CELL_SIZE then return false end
	if pos.z < origin.z or pos.z >= origin.z + mol.CELL_SIZE then return false end
	for _, allocated in pairs(mol.cells.alloc) do
		if allocated and allocated.x == cell.x and allocated.y == cell.y and allocated.z == cell.z then
			return true
		end
	end
	return false
end

function mol.derive_seed(seed_str, salt_str)
	local h = 5381
	seed_str = tostring(seed_str or "")
	salt_str = tostring(salt_str or "")

	for i = 1, #seed_str do
		h = (h * 33 + string.byte(seed_str, i)) % HASH_MOD
	end
	for i = 1, #salt_str do
		h = (h * 33 + string.byte(salt_str, i)) % HASH_MOD
	end

	return h
end

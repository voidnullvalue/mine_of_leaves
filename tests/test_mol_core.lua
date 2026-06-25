assert_eq(mol.cell_to_world(0, 0, 0), {x = 1024, y = -64, z = 0}, "cell_to_world origin")
assert_eq(mol.cell_to_world(1, 0, 0).x, 1024 + 64, "cell_to_world positive x")
assert_eq(mol.cell_to_world(-1, 0, 0).x, 1024 - 64, "cell_to_world negative x")
assert_eq(mol.cell_to_world(0, -1, 0).y, -64 - 64, "cell_to_world negative y")
assert_eq(mol.world_to_cell({x = 1024, y = -64, z = 0}), {x = 0, y = 0, z = 0}, "world_to_cell origin")
assert_eq(mol.world_to_cell({x = 1024 - 64, y = -64 - 64, z = -64}), {x = -1, y = -1, z = -1}, "world_to_cell negative")
assert_eq(mol.world_to_cell({x = 1024 + 64, y = -64 + 64, z = 64}), {x = 1, y = 1, z = 1}, "world_to_cell positive")

local round_trip_cell = {x = -2, y = 3, z = -1}
assert_eq(
	mol.world_to_cell(mol.cell_to_world(round_trip_cell.x, round_trip_cell.y, round_trip_cell.z)),
	round_trip_cell,
	"cell/world round trip")

local seed_a = mol.derive_seed("12345", "mol:room:1")
local seed_b = mol.derive_seed("12345", "mol:room:1")
local seed_c = mol.derive_seed("12345", "mol:room:2")
local large_seed = mol.derive_seed("99999999999999999999", "mol:room:0")
local zero_seed = mol.derive_seed("0", "mol:room:0")

assert_eq(seed_a, seed_b, "derive_seed deterministic")
assert_true(seed_a ~= seed_c, "derive_seed salt changes output")
assert_true(large_seed >= 0 and large_seed <= 2147483646, "derive_seed large decimal string in range")
assert_true(zero_seed >= 0 and zero_seed <= 2147483646, "derive_seed zero in range")

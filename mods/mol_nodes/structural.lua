minetest.register_node(":mol:wall", {
	description = "Wall",
	tiles = {"mol_wall.png"},
	paramtype = "light",
	groups = {cracky = 0},
	diggable = false,
})

minetest.register_node(":mol:floor", {
	description = "Floor",
	tiles = {"mol_floor.png"},
	paramtype = "light",
	diggable = false,
})

minetest.register_node(":mol:ceiling", {
	description = "Ceiling",
	tiles = {"mol_ceiling.png"},
	paramtype = "light",
	diggable = false,
})

minetest.register_node(":mol:void", {
	description = "Void",
	drawtype = "airlike",
	paramtype = "light",
	tiles = {"mol_void.png"},
	walkable = false,
	pointable = false,
	diggable = false,
	light_source = 0,
	sunlight_propagates = false,
})

minetest.register_node(":mol:boundary_wall", {
	description = "Boundary Wall",
	tiles = {"mol_boundary_wall.png"},
	paramtype = "light",
	climbable = false,
	diggable = false,
})

minetest.register_node(":mol:hedge", {
	description = "Hedge",
	tiles = {"mol_hedge.png"},
	paramtype = "light",
	climbable = false,
	diggable = false,
})

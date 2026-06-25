local PLACEHOLDER_TEXTURE = "mol_placeholder.png"

minetest.register_node(":mol:wall", {
	description = "Wall",
	tiles = {PLACEHOLDER_TEXTURE},
	groups = {cracky = 0},
	diggable = false,
})

minetest.register_node(":mol:floor", {
	description = "Floor",
	tiles = {PLACEHOLDER_TEXTURE},
	diggable = false,
})

minetest.register_node(":mol:ceiling", {
	description = "Ceiling",
	tiles = {PLACEHOLDER_TEXTURE},
	diggable = false,
})

minetest.register_node(":mol:void", {
	description = "Void",
	drawtype = "airlike",
	tiles = {PLACEHOLDER_TEXTURE},
	walkable = false,
	pointable = false,
	diggable = false,
	light_source = 0,
	sunlight_propagates = false,
})

minetest.register_node(":mol:boundary_wall", {
	description = "Boundary Wall",
	tiles = {PLACEHOLDER_TEXTURE},
	climbable = false,
	diggable = false,
})

minetest.register_node(":mol:hedge", {
	description = "Hedge",
	tiles = {PLACEHOLDER_TEXTURE},
	climbable = false,
	diggable = false,
})

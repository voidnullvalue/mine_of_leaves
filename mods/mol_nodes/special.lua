minetest.register_node(":mol:dark_void", {
	description = "Dark Void",
	tiles = {"mol_dark_void.png"},
	paramtype = "light",
	diggable = false,
	light_source = 0,
	sunlight_propagates = false,
})

minetest.register_node(":mol:light_fixture", {
	description = "Light Fixture",
	tiles = {"mol_light_fixture.png"},
	paramtype = "light",
	walkable = false,
	diggable = false,
	light_source = 12,
})

minetest.register_node(":mol:entry_marker", {
	description = "Entry Marker",
	tiles = {"mol_entry_marker.png"},
	paramtype = "light",
	diggable = false,
	light_source = 4,
})

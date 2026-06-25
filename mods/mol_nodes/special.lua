local PLACEHOLDER_TEXTURE = "mol_placeholder.png"

minetest.register_node("mol:dark_void", {
	description = "Dark Void",
	tiles = {PLACEHOLDER_TEXTURE},
	diggable = false,
	light_source = 0,
	sunlight_propagates = false,
})

minetest.register_node("mol:light_fixture", {
	description = "Light Fixture",
	tiles = {PLACEHOLDER_TEXTURE},
	walkable = false,
	diggable = false,
	light_source = 12,
})

minetest.register_node("mol:entry_marker", {
	description = "Entry Marker",
	tiles = {PLACEHOLDER_TEXTURE},
	diggable = false,
	light_source = 4,
})

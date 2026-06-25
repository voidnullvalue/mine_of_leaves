local PLACEHOLDER_TEXTURE = "mol_placeholder.png"

local function call_door_handler(pos, node, clicker)
	if mol.doors and mol.doors.on_rightclick then
		return mol.doors.on_rightclick(pos, node, clicker)
	end
	return nil
end

minetest.register_node("mol:door_frame", {
	description = "Door Frame",
	tiles = {PLACEHOLDER_TEXTURE},
	diggable = false,
})

minetest.register_node("mol:door_closed", {
	description = "Closed Door",
	tiles = {PLACEHOLDER_TEXTURE},
	groups = {door = 1},
	walkable = false,
	diggable = false,
	on_rightclick = call_door_handler,
})

minetest.register_node("mol:door_open", {
	description = "Open Door",
	tiles = {PLACEHOLDER_TEXTURE},
	groups = {door = 1},
	walkable = false,
	diggable = false,
	on_rightclick = call_door_handler,
})

local function call_door_handler(pos, node, clicker)
	if mol.doors and mol.doors.on_rightclick then
		return mol.doors.on_rightclick(pos, node, clicker)
	end
	return nil
end

minetest.register_node(":mol:door_frame", {
	description = "Door Frame",
	tiles = {"mol_door_frame.png"},
	paramtype = "light",
	diggable = false,
	light_source = 2,
})

minetest.register_node(":mol:door_closed", {
	description = "Closed Door",
	tiles = {"mol_door_closed.png"},
	paramtype = "light",
	groups = {door = 1},
	walkable = false,
	diggable = false,
	on_rightclick = call_door_handler,
})

minetest.register_node(":mol:door_open", {
	description = "Open Door",
	tiles = {"mol_door_open.png"},
	paramtype = "light",
	groups = {door = 1},
	walkable = false,
	diggable = false,
	on_rightclick = call_door_handler,
})

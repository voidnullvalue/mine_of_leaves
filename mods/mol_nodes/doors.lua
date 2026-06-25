local function call_door_handler(pos, node, clicker)
	if mol.doors and mol.doors.on_rightclick then
		return mol.doors.on_rightclick(pos, node, clicker)
	end
	return nil
end

local portal_nodebox = {
	type = "fixed",
	fixed = {
		{-0.5, -0.5, -0.0625, 0.5, 0.5, 0.0625},
	},
}

local function register_portal_segment(name, description, front_tile)
	minetest.register_node(":mol:" .. name, {
		description = description,
		tiles = {
			"mol_dark_void.png^[colorize:#080a10:180",
			"mol_dark_void.png^[colorize:#080a10:180",
			"mol_dark_void.png^[colorize:#080a10:180",
			"mol_dark_void.png^[colorize:#080a10:180",
			"mol_dark_void.png^[colorize:#080a10:180",
			front_tile,
		},
		drawtype = "nodebox",
		node_box = portal_nodebox,
		collision_box = portal_nodebox,
		selection_box = portal_nodebox,
		paramtype = "light",
		paramtype2 = "facedir",
		groups = {door = 1},
		walkable = true,
		diggable = false,
		on_rightclick = call_door_handler,
	})
end

minetest.register_node(":mol:door_frame", {
	description = "Door Frame",
	tiles = {"mol_door_frame.png"},
	paramtype = "light",
	diggable = false,
	light_source = 2,
})

register_portal_segment("door_closed", "Closed Portal", "mol_dark_void.png^[colorize:#182345:110")
register_portal_segment("door_closed_bottom", "Closed Portal Bottom", "mol_dark_void.png^[colorize:#10172d:120")
register_portal_segment("door_closed_middle", "Closed Portal Middle", "mol_dark_void.png^[colorize:#182345:110")
register_portal_segment("door_closed_top", "Closed Portal Top", "mol_dark_void.png^[colorize:#243056:95")
register_portal_segment("door_closed_left_bottom", "Closed Portal Left Bottom", "mol_dark_void.png^[colorize:#10172d:125")
register_portal_segment("door_closed_left_middle", "Closed Portal Left Middle", "mol_dark_void.png^[colorize:#17213f:115")
register_portal_segment("door_closed_left_top", "Closed Portal Left Top", "mol_dark_void.png^[colorize:#222d52:100")
register_portal_segment("door_closed_right_bottom", "Closed Portal Right Bottom", "mol_dark_void.png^[colorize:#121a31:125")
register_portal_segment("door_closed_right_middle", "Closed Portal Right Middle", "mol_dark_void.png^[colorize:#1a2545:115")
register_portal_segment("door_closed_right_top", "Closed Portal Right Top", "mol_dark_void.png^[colorize:#26325a:100")

minetest.register_node(":mol:door_open", {
	description = "Open Door",
	tiles = {"mol_door_open.png"},
	drawtype = "nodebox",
	node_box = portal_nodebox,
	selection_box = portal_nodebox,
	paramtype = "light",
	paramtype2 = "facedir",
	groups = {door = 1},
	walkable = false,
	diggable = false,
	on_rightclick = call_door_handler,
})

if not minetest.get_modpath("mol_narrative") then return end

mol.narrative = mol.narrative or {}

local narrative = mol.narrative
narrative.placed_rooms = narrative.placed_rooms or (mol.persist and mol.persist.get("narrative", "placed_rooms")) or {}

narrative.house = {
	name = "The Aldren Survey House",
	address = "19 Briar Measure Road, Ell Parish",
	organization = "North County Interior Survey",
}

narrative.journals = {
	chamber_shift = {
		title = "Field Journal: East Chamber",
		text = "Nell Ivers wrote that the east chamber measured twenty-one paces on the first pass and thirty-four on the second. The walls held the same nail heads, the same cracked plaster, and the same dead fixture. We laid a string line from the north door to the south door. It touched the floor halfway across, though neither end had slack.",
	},
	column_echo = {
		title = "Field Journal: Pillared Hall",
		text = "Marek Sone counted twelve columns, then drew fourteen. The extra pair appeared only in the echo: footsteps answered from between them, crossing left to right while all of us stood still. Chalk marks on the bases returned in the wrong order after we circled the room.",
	},
	corridor_count = {
		title = "Field Journal: Long Passage",
		text = "Anika Rell kept a distance wheel against the wall. The passage ended after forty meters, but the return roll logged sixty-three. Tape flags set every five meters were still visible behind us, closer together than her notes allowed. Nobody touched the wheel.",
	},
	bent_return = {
		title = "Field Journal: Angled Corridor",
		text = "The bend should have turned us west. The compass agreed until we reached the second door, where the needle settled east without swinging. Jory left a coil of red cord on the corner. We found it later hanging from the first doorframe, dry and clean, with no path between.",
	},
	narrow_listening = {
		title = "Field Journal: Narrow Hall",
		text = "We heard a lantern case slide across boards above us. There is no upper floor on this side of the house. Three knocks followed from below, then from the wall at shoulder height. Our own tapping test came back delayed, as if answered from a longer hall.",
	},
	resource_inventory = {
		title = "Field Journal: Supply Room",
		text = "The supply room contained our old crate before we opened the new one. Same chipped blue paint, same split hinge, same inventory tag in Orla's handwriting. The canteen inside was warm. She insists she filled it outside in winter rain.",
	},
	stair_measure = {
		title = "Field Journal: Stair Segment",
		text = "The stair rises nine steps and lowers us by two meters. Level rods at both landings say the same thing. We placed a brass plumb at the top rail; it pointed through the wall toward the lower landing and rang softly when the door opened behind us.",
	},
}

narrative.documents = {
	property_filing = {
		title = "County Filing 44-B",
		text = "The Aldren Survey House was recorded as a two-story residence in 1896, amended to one story in 1902, and amended again in 1919 with the note: interior footage unavailable. The parcel line has not changed. The assessor refused entry after his chain returned knotted inside its own reel.",
	},
	survey_notice = {
		title = "North County Interior Survey Notice",
		text = "Crew Three was instructed to map only accessible rooms and to mark all closed doors from the approach side. Their final ledger lists eighteen doors, seven rooms, and one corridor longer than the structure's exterior frontage. The ledger was rejected for internal contradiction.",
	},
	private_letter = {
		title = "Letter from E. Vane",
		text = "I left the parlor by the pantry door and came back through the parlor window, though the window was painted shut from outside. Do not sell the house as a residence. Sell the land, burn the papers, and let no buyer measure the walls after sunset.",
	},
	map_note = {
		title = "Plan Room Note",
		text = "Three plans were found in the coal bin. Each shows the breakfast room touching the stair, yet none agrees on which wall carries the door. The paper is ordinary drafting stock. The pencil pressure is heavy enough to tear at each threshold.",
	},
}

narrative.maps = {
	ground = {
		title = "Recovered Floor Plan A",
		ascii = "+-------+---+\n| Hall  |K  |\n|   +---+---+\n|   |Study  |\n+---+   +---+\n|Pantry |Hall|\n+-------+---+\nNote: Hall borders itself on two nonmatching walls.",
	},
	annex = {
		title = "Recovered Floor Plan B",
		ascii = "+----+----+----+\n| A  | B  | C  |\n+----+    +----+\n| D       | A  |\n+----+----+----+\nSouth door of C is annotated as entering north wall of A.",
	},
}

narrative.slots = {
	survey_case = {kind = "journal", pos = {x = 3, y = 1, z = 3}},
	tripod = {kind = "journal", pos = {x = 4, y = 1, z = 4}},
	chalk_bag = {kind = "journal", pos = {x = 2, y = 1, z = 4}},
	tape_reel = {kind = "journal", pos = {x = 2, y = 1, z = 2}},
	field_pack = {kind = "journal", pos = {x = 1, y = 1, z = 3}},
	document_crate = {kind = "document", pos = {x = 3, y = 1, z = 3}},
	broken_level = {kind = "journal", pos = {x = 3, y = 1, z = 4}},
}

narrative.sound_files = {
	mol_ambient_low = "mol_ambient_low.ogg",
	mol_footstep_echo = "mol_footstep_echo.ogg",
	mol_light_flicker = "mol_light_flicker.ogg",
	mol_settling = "mol_settling.ogg",
}

local function escape(value)
	if minetest.formspec_escape then return minetest.formspec_escape(value or "") end
	value = tostring(value or "")
	value = string.gsub(value, "\\", "\\\\")
	value = string.gsub(value, "%]", "\\]")
	value = string.gsub(value, "%[", "\\[")
	value = string.gsub(value, ";", "\\;")
	value = string.gsub(value, ",", "\\,")
	return value
end

function narrative.make_text_formspec(title, text)
	return "formspec_version[6]size[10,8]" ..
		"label[0.5,0.5;" .. escape(title) .. "]" ..
		"textarea[0.5,1.1;9,6.1;body;;" .. escape(text) .. "]" ..
		"button_exit[3.5,7.25;3,0.5;close;Close]"
end

function narrative.make_map_formspec(map_id)
	local map = narrative.maps[map_id] or narrative.maps.ground
	return narrative.make_text_formspec(map.title, map.ascii)
end

local function stack_meta_value(itemstack, key)
	if itemstack and itemstack.get_meta then
		local meta = itemstack:get_meta()
		if meta and meta.get_string then return meta:get_string(key) end
	end
	return ""
end

local function show_text(itemstack, user, prefix, fallback, entries)
	if not (user and user.get_player_name and minetest.show_formspec) then return itemstack end
	local id = stack_meta_value(itemstack, prefix .. "_id")
	local entry = entries[id] or entries[fallback]
	minetest.show_formspec(user:get_player_name(), "mol_narrative:" .. prefix, narrative.make_text_formspec(entry.title, entry.text))
	return itemstack
end

local function show_journal(itemstack, user)
	return show_text(itemstack, user, "journal", "chamber_shift", narrative.journals)
end

local function show_document(itemstack, user)
	return show_text(itemstack, user, "document", "property_filing", narrative.documents)
end

local function show_floor_plan(itemstack, user)
	if user and user.get_player_name and minetest.show_formspec then
		local map_id = stack_meta_value(itemstack, "map_id")
		minetest.show_formspec(user:get_player_name(), "mol_narrative:floor_plan", narrative.make_map_formspec(map_id))
	end
	return itemstack
end

minetest.register_craftitem("mol:expedition_journal", {
	description = "Expedition Journal",
	inventory_image = "mol_placeholder.png",
	on_use = show_journal,
	on_place = show_journal,
	on_secondary_use = show_journal,
})

minetest.register_craftitem("mol:recovered_document", {
	description = "Recovered Document",
	inventory_image = "mol_placeholder.png",
	on_use = show_document,
	on_place = show_document,
	on_secondary_use = show_document,
})

minetest.register_craftitem("mol:floor_plan", {
	description = "Contradictory Floor Plan",
	inventory_image = "mol_placeholder.png",
	on_use = show_floor_plan,
	on_place = show_floor_plan,
	on_secondary_use = show_floor_plan,
})

minetest.register_node("mol:expedition_artifact", {
	description = "Abandoned Survey Equipment",
	tiles = {"mol_placeholder.png"},
	walkable = false,
	diggable = false,
	groups = {not_in_creative_inventory = 1},
})

local function make_stack(name, key, value)
	if not ItemStack then return name end
	local stack = ItemStack(name)
	if stack.get_meta then
		stack:get_meta():set_string(key, value)
	end
	return stack
end

local function choose_document(room_id)
	local order = {"property_filing", "survey_notice", "private_letter", "map_note"}
	local seed = mol.derive_seed(tostring(room_id or ""), "narrative:document")
	return order[(seed % #order) + 1]
end

local function mark_room_placed(room_id)
	if not room_id then return end
	narrative.placed_rooms[room_id] = true
	if mol.persist then
		mol.persist.set("narrative", "placed_rooms", narrative.placed_rooms)
	end
end

local function place_room_content(cell_coord, room_def)
	if not (cell_coord and room_def and room_def.meta and mol.cells and mol.cells.get_origin) then return end
	local room_id = room_def.room_id
	if room_id then
		if narrative.placed_rooms[room_id] then return end
	end
	local slot_id = room_def.meta.narrative_slot
	local slot = narrative.slots[slot_id]
	if not slot then return end
	local origin = mol.cells.get_origin(cell_coord)
	local base = slot.pos or {x = 2, y = 1, z = 2}
	local pos = {x = origin.x + base.x, y = origin.y + base.y, z = origin.z + base.z}

	if minetest.set_node then
		minetest.set_node(pos, {name = "mol:expedition_artifact"})
	end

	local drop_pos = {x = pos.x, y = pos.y + 1, z = pos.z}
	if minetest.add_item then
		if slot.kind == "document" then
			minetest.add_item(drop_pos, make_stack("mol:recovered_document", "document_id", choose_document(room_def.room_id)))
			minetest.add_item({x = drop_pos.x + 0.3, y = drop_pos.y, z = drop_pos.z}, make_stack("mol:floor_plan", "map_id", "ground"))
			if room_def.meta.journal_ref then
				minetest.add_item({x = drop_pos.x - 0.3, y = drop_pos.y, z = drop_pos.z}, make_stack("mol:expedition_journal", "journal_id", room_def.meta.journal_ref))
			end
		elseif room_def.meta.journal_ref then
			minetest.add_item(drop_pos, make_stack("mol:expedition_journal", "journal_id", room_def.meta.journal_ref))
		end
	end
	mark_room_placed(room_id)
end

local function room_def_for(room)
	if not (room and room.template and mol.rooms and mol.rooms.generate) then return nil end
	local room_def = mol.rooms.generate(room.template, room.room_seed, {})
	if not room_def then return nil end
	room_def.room_id = room.room_id
	if mol.graph and mol.graph.prepare_room_def then
		mol.graph.prepare_room_def(room_def, room.room_id)
	end
	return room_def
end

function narrative.place_for_built_rooms()
	if not (mol.cells and mol.cells.built_cells and mol.graph and mol.graph.get_room) then return end
	for room_id, cell_coord in pairs(mol.cells.built_cells) do
		if not narrative.placed_rooms[room_id] then
			local room = mol.graph.get_room(room_id)
			local room_def = room_def_for(room)
			place_room_content(cell_coord, room_def)
		end
	end
end

if minetest.register_on_mods_loaded then
	minetest.register_on_mods_loaded(narrative.place_for_built_rooms)
end

if minetest.register_globalstep then
	local elapsed = 0
	minetest.register_globalstep(function(dtime)
		elapsed = elapsed + dtime
		if elapsed < 1 then return end
		elapsed = 0
		narrative.place_for_built_rooms()
	end)
end

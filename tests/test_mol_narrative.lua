local narrative_present = minetest.get_modpath("mol_narrative") ~= nil

local function word_count(text)
	local count = 0
	for _ in string.gmatch(text or "", "%S+") do
		count = count + 1
	end
	return count
end

local function assert_formspec_valid(formspec, label)
	assert_true(type(formspec) == "string" and string.find(formspec, "formspec_version%[6%]") ~= nil, label .. " has version")
	assert_true(string.find(formspec, "size%[10,8%]") ~= nil, label .. " has size")
	assert_true(string.find(formspec, "button_exit%[") ~= nil, label .. " has close button")
end

local function item_name(item)
	if type(item) == "string" then return item end
	if item and item.get_name then return item:get_name() end
	return ""
end

local function scan_strings(value, callback)
	if type(value) == "string" then
		callback(value)
	elseif type(value) == "table" then
		for _, child in pairs(value) do
			scan_strings(child, callback)
		end
	end
end

if narrative_present then
	assert_true(mol.narrative ~= nil, "narrative namespace loads")
	assert_true(minetest._registered_craftitems["mol:expedition_journal"] ~= nil, "journal item registered")
	assert_true(minetest._registered_craftitems["mol:recovered_document"] ~= nil, "document item registered")
	assert_true(minetest._registered_craftitems["mol:floor_plan"] ~= nil, "floor plan item registered")
	assert_true(minetest._registered_nodes["mol:expedition_artifact"] ~= nil, "artifact node registered")

	scan_strings(mol.narrative, function(text)
		local lowered = string.lower(text)
		assert_true(string.find(lowered, "navidson", 1, true) == nil, "narrative string avoids banned name")
		assert_true(string.find(lowered, "house of leaves", 1, true) == nil, "narrative string avoids banned title")
	end)

	for id, entry in pairs(mol.narrative.journals) do
		assert_true(word_count(entry.text) < 500, "journal " .. id .. " is under 500 words")
		local lowered = string.lower(entry.text .. " " .. entry.title)
		assert_true(string.find(lowered, "navidson", 1, true) == nil, "journal " .. id .. " avoids banned name")
		assert_true(string.find(lowered, "house of leaves", 1, true) == nil, "journal " .. id .. " avoids banned title")
	end

	for id, entry in pairs(mol.narrative.documents) do
		assert_true(word_count(entry.text) < 200, "document " .. id .. " is under 200 words")
		local lowered = string.lower(entry.text .. " " .. entry.title)
		assert_true(string.find(lowered, "navidson", 1, true) == nil, "document " .. id .. " avoids banned name")
		assert_true(string.find(lowered, "house of leaves", 1, true) == nil, "document " .. id .. " avoids banned title")
	end

	for template_name, template_fn in pairs(mol.rooms.templates) do
		local ok, room_def = pcall(template_fn, mol.new_prng(2468), {})
		assert_true(ok, "template " .. template_name .. " generates for narrative scan")
		if ok and room_def and room_def.meta and room_def.meta.narrative_slot then
			assert_true(mol.narrative.slots[room_def.meta.narrative_slot] ~= nil, "template " .. template_name .. " narrative slot exists")
		end
		if ok and room_def and room_def.meta and room_def.meta.journal_ref then
			assert_true(mol.narrative.journals[room_def.meta.journal_ref] ~= nil, "template " .. template_name .. " journal ref exists")
		end
	end

	assert_formspec_valid(mol.narrative.make_text_formspec("Title", "Body"), "journal formspec")
	assert_formspec_valid(mol.narrative.make_map_formspec("ground"), "floor plan formspec")

	local player = {get_player_name = function() return "reader" end}
	local stack = ItemStack("mol:expedition_journal")
	stack:get_meta():set_string("journal_id", "corridor_count")
	minetest._formspecs = {}
	minetest._registered_craftitems["mol:expedition_journal"].on_place(stack, player)
	assert_true(#minetest._formspecs == 1, "journal right-click displays formspec")
	assert_formspec_valid(minetest._formspecs[1].formspec, "shown journal formspec")

	local document_stack = ItemStack("mol:recovered_document")
	document_stack:get_meta():set_string("document_id", "survey_notice")
	minetest._formspecs = {}
	minetest._registered_craftitems["mol:recovered_document"].on_place(document_stack, player)
	assert_true(#minetest._formspecs == 1, "document right-click displays formspec")
	assert_formspec_valid(minetest._formspecs[1].formspec, "shown document formspec")

	local map_stack = ItemStack("mol:floor_plan")
	map_stack:get_meta():set_string("map_id", "annex")
	minetest._formspecs = {}
	minetest._registered_craftitems["mol:floor_plan"].on_place(map_stack, player)
	assert_true(#minetest._formspecs == 1, "floor plan right-click displays formspec")
	assert_formspec_valid(minetest._formspecs[1].formspec, "shown floor plan formspec")

	assert_eq(mol.narrative.sound_files.mol_ambient_low, "mol_ambient_low.ogg", "ambient low sound filename matches")
	assert_eq(mol.narrative.sound_files.mol_footstep_echo, "mol_footstep_echo.ogg", "footstep echo sound filename matches")
	assert_eq(mol.narrative.sound_files.mol_light_flicker, "mol_light_flicker.ogg", "light flicker sound filename matches")
	assert_eq(mol.narrative.sound_files.mol_settling, "mol_settling.ogg", "settling sound filename matches")

	mol.graph.init_world("narrative-placement")
	mol.cells.alloc.room_resource = {x = 0, y = 0, z = 0}
	mol.cells.built_cells.room_resource = {x = 0, y = 0, z = 0}
	mol.narrative.placed_rooms.room_resource = nil
	minetest._set_nodes = {}
	minetest._added_items = {}
	for _, callback in ipairs(minetest._registered_globalsteps) do
		pcall(callback, 1.1)
	end

	local placed_artifact = false
	for _, record in ipairs(minetest._set_nodes) do
		if record.node and record.node.name == "mol:expedition_artifact" then placed_artifact = true end
	end
	assert_true(placed_artifact, "narrative resource room places expedition artifact")

	local added = {}
	for _, record in ipairs(minetest._added_items) do
		added[item_name(record.item)] = true
	end
	assert_true(added["mol:recovered_document"], "narrative resource room drops recovered document")
	assert_true(added["mol:floor_plan"], "narrative resource room drops floor plan")
	assert_true(added["mol:expedition_journal"], "narrative resource room drops journal")
	mol.cells.alloc.room_resource = nil
	mol.cells.built_cells.room_resource = nil
	mol.narrative.placed_rooms.room_resource = nil
else
	mol.graph.init_world("12345")
	local result = mol.graph.validate()
	assert_true(result.ok, "core graph validates with mol_narrative absent")
	assert_true(minetest._registered_craftitems["mol:expedition_journal"] == nil, "journal item absent when narrative mod absent")
end

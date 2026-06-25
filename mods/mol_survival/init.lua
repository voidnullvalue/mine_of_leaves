mol.survival = mol.survival or {}

local survival = mol.survival

survival.players = survival.players or {}
survival.hud_ids = survival.hud_ids or {}
survival.expedition_started = survival.expedition_started or {}
survival.cold_cache = survival.cold_cache or {}

local LIGHT_DEFAULT = 60
local STAMINA_DEFAULT = 100
local LIGHT_INTERVAL = 10
local COLD_INTERVAL = 30
local STAMINA_MOVE_INTERVAL = 60
local STAMINA_REST_SECONDS = 10
local AUDIO_INTERVAL = 1
local FLASHLIGHT_GLOW = 12
local NORMAL_SPEED = 1
local EXHAUSTED_SPEED = 0.5
-- Luanti 5.10 ObjectRef:set_sky accepts set_sky(sky_parameters). For
-- type="plain", base_color controls both fog and sky.
local BLACKOUT_SKY = {type = "plain", base_color = {r = 0, g = 0, b = 0, a = 255}}
local OUTDOOR_SKY = {type = "regular"}
local SURVIVAL_STEP_INTERVAL = 1
local survival_step_elapsed = 0

local function clamp(value, min_value, max_value)
	if value < min_value then return min_value end
	if value > max_value then return max_value end
	return value
end

local function split_door_id(door_id)
	local room_id = string.match(tostring(door_id or ""), "^(.*):slot_%d+$")
	return room_id
end

local function room_neighbors(room_id)
	local list = {}
	if not (mol.graph and mol.graph.edge_order and mol.graph.edges) then return list end
	for _, edge_id in ipairs(mol.graph.edge_order) do
		local edge = mol.graph.edges[edge_id]
		if edge and split_door_id(edge.from_door_id) == room_id then
			list[#list + 1] = edge.to_room_id
		end
	end
	return list
end

local function current_minute()
	if minetest.get_us_time then
		return math.floor(minetest.get_us_time() / 60000000)
	end
	return math.floor(os.time() / 60)
end

local function room_id_for_position(pos)
	if not (pos and mol.cells and mol.cells.alloc) then return nil end
	local cell = mol.world_to_cell(pos)
	for room_id, allocated in pairs(mol.cells.alloc) do
		if allocated and cell.x == allocated.x and cell.y == allocated.y and cell.z == allocated.z then
			return room_id
		end
	end
	return nil
end

function survival.invalidate_cold_cache()
	survival.cold_cache = {}
end

function survival.hop_distance(room_id)
	if room_id == nil then return nil end
	if survival.cold_cache[room_id] ~= nil then return survival.cold_cache[room_id] end
	if not (mol.graph and mol.graph.get_room and mol.graph.get_room("room_entrance")) then return nil end

	local distance = {room_entrance = 0}
	local queue = {"room_entrance"}
	local head = 1
	while head <= #queue do
		local current = queue[head]
		head = head + 1
		for _, next_room in ipairs(room_neighbors(current)) do
			if mol.graph.get_room(next_room) and distance[next_room] == nil then
				distance[next_room] = distance[current] + 1
				queue[#queue + 1] = next_room
			end
		end
	end

	for found_room, hops in pairs(distance) do
		survival.cold_cache[found_room] = hops
	end
	if survival.cold_cache[room_id] == nil then survival.cold_cache[room_id] = false end
	return survival.cold_cache[room_id] or nil
end

function survival.get_cold_level(room_id)
	local hops = survival.hop_distance(room_id)
	if not hops then return 0 end
	return clamp(math.floor(hops / 2), 0, 5)
end

function survival.compass_error(room_id, minute)
	local depth = survival.get_cold_level(room_id)
	if depth <= 2 then return 0 end
	minute = minute or current_minute()
	local seed = mol.derive_seed(tostring(room_id or ""), "compass:" .. tostring(minute))
	local prng = mol.new_prng(seed)
	if depth <= 4 then
		return prng:next(-45, 45)
	end
	local magnitude = prng:next(90, 180)
	if prng:next(0, 1) == 0 then magnitude = -magnitude end
	return magnitude
end

function survival.consume_light_charge(state, seconds, active)
	state.light_charge = tonumber(state.light_charge) or 0
	state.light_timer = (tonumber(state.light_timer) or 0) + (seconds or 0)
	if not active then return state.light_charge end
	while state.light_timer >= LIGHT_INTERVAL and state.light_charge > 0 do
		state.light_timer = state.light_timer - LIGHT_INTERVAL
		state.light_charge = math.max(0, state.light_charge - 1)
	end
	return state.light_charge
end

local function get_state(player)
	local name = player:get_player_name()
	local state = survival.players[name]
	if state then return state end
	state = {
		light_charge = LIGHT_DEFAULT,
		stamina = STAMINA_DEFAULT,
		light_timer = 0,
		cold_timer = 0,
		stamina_timer = 0,
		stationary_timer = 0,
		audio_timer = 0,
		cold_pack_timer = 0,
		silence_timer = 0,
	}
	survival.players[name] = state
	return state
end

local function item_name(stack)
	if not stack then return "" end
	if type(stack) == "string" then return stack end
	if stack.get_name then return stack:get_name() end
	return ""
end

local function wield_name(player)
	if player.get_wielded_item then return item_name(player:get_wielded_item()) end
	return ""
end

local function inventory_contains(player, list_name, item)
	local inv = player.get_inventory and player:get_inventory()
	return inv and inv.contains_item and inv:contains_item(list_name, item)
end

local function add_inventory_item(player, item)
	local inv = player.get_inventory and player:get_inventory()
	if inv and inv.add_item then inv:add_item("main", item) end
end

local function remove_inventory_item(player, item)
	local inv = player.get_inventory and player:get_inventory()
	if inv and inv.remove_item then inv:remove_item("main", item) end
end

local function maybe_add_hud(player)
	local name = player:get_player_name()
	if survival.hud_ids[name] then return end
	if not player.hud_add then return end
	survival.hud_ids[name] = {
		-- Luanti 5.10 HUD definitions accept type/hud_elem_type "text".
		light = player:hud_add({
			hud_elem_type = "text",
			position = {x = 0.02, y = 0.82},
			text = "Light " .. LIGHT_DEFAULT,
			number = 0xffffff,
			alignment = {x = 1, y = 1},
			scale = {x = 100, y = 20},
		}),
		stamina = player:hud_add({
			hud_elem_type = "text",
			position = {x = 0.02, y = 0.86},
			text = "Stamina " .. STAMINA_DEFAULT,
			number = 0xffffff,
			alignment = {x = 1, y = 1},
			scale = {x = 100, y = 20},
		}),
	}
end

local function update_hud(player, state)
	local ids = survival.hud_ids[player:get_player_name()]
	if not (ids and player.hud_change) then return end
	player:hud_change(ids.light, "text", "Light " .. tostring(math.floor(state.light_charge or 0)))
	player:hud_change(ids.stamina, "text", "Stamina " .. tostring(math.floor(state.stamina or 0)))
end

local function set_glow(player, glow)
	if player.set_properties then player:set_properties({glow = glow}) end
end

local function is_moving(player)
	local velocity = player.get_velocity and player:get_velocity() or {x = 0, y = 0, z = 0}
	local speed = math.sqrt((velocity.x or 0) ^ 2 + (velocity.y or 0) ^ 2 + (velocity.z or 0) ^ 2)
	return speed > 0.5
end

local function set_speed(player, state)
	if not player.set_physics_override then return end
	local exhausted = (state.stamina or 0) <= 0
	if exhausted and state.speed ~= EXHAUSTED_SPEED then
		-- Luanti 5.10 set_physics_override({speed=...}) scales player speed.
		player:set_physics_override({speed = EXHAUSTED_SPEED})
		state.speed = EXHAUSTED_SPEED
	elseif not exhausted and (state.stamina or 0) >= 20 and state.speed ~= NORMAL_SPEED then
		player:set_physics_override({speed = NORMAL_SPEED})
		state.speed = NORMAL_SPEED
	end
end

local function player_room_id(player)
	local name = player:get_player_name()
	local tracked = mol.players and mol.players[name] and mol.players[name].current_room_id
	return tracked or room_id_for_position(player:get_pos())
end

local function effective_cold_level(player, state)
	local level = survival.get_cold_level(player_room_id(player))
	if wield_name(player) == "mol:cold_pack" and (state.cold_pack_timer or 0) < 120 then
		level = math.max(0, level - 1)
	end
	return level
end

local function safe_sound(name, spec)
	if not minetest.sound_play then return nil end
	local ok, handle = pcall(minetest.sound_play, name, spec or {})
	if ok then return handle end
	return nil
end

function survival.recover_player(player, message)
	local name = player:get_player_name()
	local state = get_state(player)
	state.light_charge = 0
	state.stamina = 20
	state.light_timer = 0
	set_glow(player, 0)
	set_speed(player, state)
	if player.set_sky then player:set_sky(BLACKOUT_SKY) end
	if player.hud_set_flags then player:hud_set_flags({wielditem = false}) end
	if minetest.chat_send_player then
		minetest.chat_send_player(name, message or "The house released you. You remember being outside.")
	end
	minetest.after(0.5, function()
		local current = minetest.get_player_by_name(name)
		if not current then return end
		current:set_pos(mol.SPAWN_POS)
		if current.set_hp then current:set_hp(10) end
		if current.set_sky then current:set_sky(OUTDOOR_SKY) end
		mol.players[name] = mol.players[name] or {}
		mol.players[name].current_room_id = "room_yard"
	end)
	return true
end

function survival.handle_hpchange(player, hp_change, reason)
	if hp_change >= 0 then return hp_change end
	local hp = player.get_hp and player:get_hp() or 20
	if hp + hp_change > 0 then return hp_change end
	survival.recover_player(player)
	return 0
end

local function update_stamina(player, state, dtime)
	if is_moving(player) then
		state.stationary_timer = 0
		state.stamina_timer = (state.stamina_timer or 0) + dtime
		while state.stamina_timer >= STAMINA_MOVE_INTERVAL and state.stamina > 0 do
			state.stamina_timer = state.stamina_timer - STAMINA_MOVE_INTERVAL
			state.stamina = math.max(0, state.stamina - 1)
		end
	else
		state.stamina_timer = 0
		state.stationary_timer = (state.stationary_timer or 0) + dtime
		while state.stationary_timer >= STAMINA_REST_SECONDS and state.stamina < 100 do
			state.stationary_timer = state.stationary_timer - STAMINA_REST_SECONDS
			state.stamina = math.min(100, state.stamina + 5)
		end
	end
	set_speed(player, state)
end

local function update_cold(player, state, dtime)
	state.cold_timer = (state.cold_timer or 0) + dtime
	if state.cold_timer < COLD_INTERVAL then return end
	state.cold_timer = state.cold_timer - COLD_INTERVAL
	local level = effective_cold_level(player, state)
	if level <= 2 then return end
	local damage = level - 2
	if player.set_hp and player.get_hp then
		local hp = player:get_hp()
		if hp - damage <= 0 then
			survival.recover_player(player)
		else
			player:set_hp(hp - damage)
		end
	end
end

local function update_light(player, state, dtime)
	local active = wield_name(player) == "mol:flashlight" and (state.light_charge or 0) > 0
	survival.consume_light_charge(state, dtime, active)
	set_glow(player, active and FLASHLIGHT_GLOW or 0)
	if active and state.light_charge < 20 then
		state.flicker_timer = (state.flicker_timer or 0) + dtime
		if state.flicker_timer >= 10 then
			state.flicker_timer = 0
			safe_sound("mol_light_flicker", {to_player = player:get_player_name(), gain = 0.25})
		end
	end
end

local function update_audio(player, state, dtime)
	state.audio_timer = (state.audio_timer or 0) + dtime
	if state.audio_timer < AUDIO_INTERVAL then return end
	state.audio_timer = state.audio_timer - AUDIO_INTERVAL

	local room_id = player_room_id(player)
	local depth = survival.get_cold_level(room_id)
	local name = player:get_player_name()
	if (state.silence_timer or 0) > 0 then
		state.silence_timer = math.max(0, state.silence_timer - 1)
		return
	end
	if depth >= 4 and math.random(1, 240) == 1 then
		state.silence_timer = math.random(3, 5)
		minetest.log("action", "[mol_survival] silence event for " .. name .. " in " .. tostring(room_id))
		return
	end
	if depth >= 2 then
		safe_sound("mol_ambient_low", {to_player = name, gain = 0.08})
	end
	if depth >= 3 and math.random(1, 300) == 1 then
		local pos = player:get_pos()
		safe_sound("mol_footstep_echo", {pos = {x = pos.x + 2, y = pos.y, z = pos.z - 2}, gain = 0.25, max_hear_distance = 12})
	end
	if depth >= 4 and math.random(1, 90) == 1 then
		safe_sound("mol_settling", {to_player = name, gain = 0.2})
	end
end

local function has_notebook(player)
	return inventory_contains(player, "main", "mol:expedition_notebook")
end

local function update_objective(player)
	local room_id = player_room_id(player)
	if room_id ~= "room_escape" or not has_notebook(player) then return end
	if mol.persist then mol.persist.set("events", "expedition_completed", true) end
	if mol.expedition and mol.expedition.mark_objective then
		mol.expedition.mark_objective(player:get_player_name(), "escaped", true)
	end
	survival.recover_player(player, "You found your way out with the notebook.")
end

local function give_loadout(player)
	local name = player:get_player_name()
	if survival.expedition_started[name] then return end
	local attr_started = player.get_attribute and player:get_attribute("mol_survival_started")
	if attr_started == "true" then
		survival.expedition_started[name] = true
		return
	end
	local inv = player.get_inventory and player:get_inventory()
	if inv and inv.is_empty and not inv:is_empty("main") then
		survival.expedition_started[name] = true
		if player.set_attribute then player:set_attribute("mol_survival_started", "true") end
		return
	end
	add_inventory_item(player, "mol:flashlight 1")
	add_inventory_item(player, "mol:battery 1")
	add_inventory_item(player, "mol:cold_pack 2")
	add_inventory_item(player, "mol:ration 3")
	add_inventory_item(player, "mol:chalk 20")
	if player.set_wielded_item then player:set_wielded_item("mol:flashlight") end
	if player.set_attribute then player:set_attribute("mol_survival_started", "true") end
	survival.expedition_started[name] = true
end

minetest.register_craftitem(":mol:flashlight", {
	description = "Flashlight",
	inventory_image = "mol_placeholder.png",
})

minetest.register_craftitem(":mol:battery", {
	description = "Battery",
	inventory_image = "mol_placeholder.png",
	on_use = function(itemstack, user)
		if not user then return itemstack end
		local state = get_state(user)
		state.light_charge = math.min(100, (state.light_charge or 0) + 20)
		if itemstack.take_item then itemstack:take_item(1) end
		return itemstack
	end,
})

minetest.register_craftitem(":mol:cold_pack", {
	description = "Handwarmer",
	inventory_image = "mol_placeholder.png",
})

minetest.register_craftitem(":mol:ration", {
	description = "Ration",
	inventory_image = "mol_placeholder.png",
	on_use = function(itemstack, user)
		if not user then return itemstack end
		local state = get_state(user)
		state.stamina = math.min(100, (state.stamina or 0) + 30)
		if itemstack.take_item then itemstack:take_item(1) end
		return itemstack
	end,
})

minetest.register_craftitem(":mol:compass", {
	description = "Compass",
	inventory_image = "mol_placeholder.png",
	on_use = function(itemstack, user)
		if not user then return itemstack end
		local room_id = player_room_id(user)
		local error = survival.compass_error(room_id)
		local direction = (math.floor(((user:get_look_horizontal() or 0) * 180 / math.pi) + error) % 360)
		minetest.chat_send_player(user:get_player_name(), "Compass: " .. direction .. " degrees")
		return itemstack
	end,
})

minetest.register_node(":mol:chalk_mark", {
	description = "Chalk Mark",
	drawtype = "signlike",
	tiles = {"mol_placeholder.png^[colorize:#e6f2ff:120"},
	inventory_image = "mol_placeholder.png^[colorize:#e6f2ff:120",
	wield_image = "mol_placeholder.png^[colorize:#e6f2ff:120",
	paramtype = "light",
	paramtype2 = "wallmounted",
	walkable = false,
	groups = {attached_node = 1, oddly_breakable_by_hand = 1},
	after_place_node = function(pos, placer)
		if placer then
			minetest.get_meta(pos):set_string("owner", placer:get_player_name())
		end
	end,
	can_dig = function(pos, player)
		return player and inventory_contains(player, "main", "mol:chalk")
	end,
})

minetest.register_node(":mol:expedition_notebook", {
	description = "Expedition Notebook",
	tiles = {"mol_placeholder.png^[colorize:#ffffaa:90"},
	walkable = false,
	groups = {oddly_breakable_by_hand = 1},
	on_rightclick = function(pos, node, clicker)
		if not clicker then return end
		add_inventory_item(clicker, "mol:expedition_notebook 1")
		if mol.expedition and mol.expedition.mark_objective then
			mol.expedition.mark_objective(clicker:get_player_name(), "notebook_found", true)
		end
		minetest.remove_node(pos)
	end,
})

minetest.register_craftitem(":mol:chalk", {
	description = "Chalk",
	inventory_image = "mol_placeholder.png^[colorize:#e6f2ff:120",
	on_place = function(itemstack, placer, pointed_thing)
		if not (pointed_thing and pointed_thing.above and placer) then return itemstack end
		local pos = pointed_thing.above
		if not mol.is_chalk_allowed_region(pos) then return itemstack end
		minetest.set_node(pos, {name = "mol:chalk_mark"})
		minetest.get_meta(pos):set_string("owner", placer:get_player_name())
		if itemstack.take_item then itemstack:take_item(1) end
		return itemstack
	end,
})

minetest.register_craftitem(":mol:map_fragment", {
	description = "Map Fragment",
	inventory_image = "mol_placeholder.png",
	on_use = function(itemstack, user)
		if not user then return itemstack end
		local room_id = player_room_id(user)
		local hops = survival.hop_distance(room_id) or 0
		local entrance = mol.graph.get_room("room_entrance")
		local physical = 0
		if entrance and entrance.cell_coord then
			local origin = mol.cells.get_origin(entrance.cell_coord)
			physical = math.floor(vector.distance(user:get_pos(), origin))
		end
		minetest.chat_send_player(user:get_player_name(), "Entrance: " .. hops .. " doors, " .. physical .. " nodes")
		return itemstack
	end,
})

minetest.register_on_joinplayer(function(player)
	get_state(player)
	give_loadout(player)
	maybe_add_hud(player)
	update_hud(player, get_state(player))
end)

minetest.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	local ids = survival.hud_ids[name]
	if ids and player.hud_remove then
		for _, id in pairs(ids) do player:hud_remove(id) end
	end
	survival.hud_ids[name] = nil
end)

if minetest.register_on_player_hpchange then
	minetest.register_on_player_hpchange(function(player, hp_change, reason)
		return survival.handle_hpchange(player, hp_change, reason)
	end, true)
end

minetest.register_globalstep(function(dtime)
	survival_step_elapsed = survival_step_elapsed + dtime
	if survival_step_elapsed < SURVIVAL_STEP_INTERVAL then return end
	dtime = survival_step_elapsed
	survival_step_elapsed = 0
	for _, player in ipairs(minetest.get_connected_players()) do
		local state = get_state(player)
		if wield_name(player) == "mol:cold_pack" and (state.cold_pack_timer or 0) < 120 then
			state.cold_pack_timer = state.cold_pack_timer + dtime
			if state.cold_pack_timer >= 120 then
				remove_inventory_item(player, "mol:cold_pack 1")
				state.cold_pack_timer = 0
			end
		end
		update_light(player, state, dtime)
		update_stamina(player, state, dtime)
		update_cold(player, state, dtime)
		update_audio(player, state, dtime)
		update_objective(player)
		update_hud(player, state)
	end
end)

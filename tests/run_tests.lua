local PROJECT_ROOT = "."
if arg and arg[0] then
	local script_dir = string.match(arg[0], "^(.*)/[^/]+$")
	if script_dir then
		if script_dir == "tests" then
			PROJECT_ROOT = "."
		else
			PROJECT_ROOT = string.gsub(script_dir, "/tests$", "")
		end
	end
end
_G.PROJECT_ROOT = PROJECT_ROOT
local failure_count = 0
test_logs = {}

minetest = {
	_registered_globalsteps = {},
	_registered_on_leaveplayers = {},
	_registered_on_joinplayers = {},
	_registered_on_player_hpchanges = {},
	_registered_on_mods_loaded = {},
	_registered_chatcommands = {},
	_registered_nodes = {},
	_registered_craftitems = {},
	_players = {},
	_meta = {},
	_chat_messages = {},
	_after_calls = {},
	_emerge_calls = {},
	log = function(level, message)
		test_logs[#test_logs + 1] = {level = level, message = message}
	end,
	get_us_time = function()
		return minetest._us_time or 0
	end,
	get_mapgen_setting = function(name)
		if name == "seed" then return "12345" end
		return "singlenode"
	end,
	serialize = function(value)
		local function encode(v)
			if type(v) == "number" or type(v) == "boolean" then return tostring(v) end
			if type(v) == "string" then return string.format("%q", v) end
			if type(v) ~= "table" then return "nil" end
			local parts = {}
			for key, child in pairs(v) do
				parts[#parts + 1] = "[" .. encode(key) .. "]=" .. encode(child)
			end
			table.sort(parts)
			return "{" .. table.concat(parts, ",") .. "}"
		end
		return encode(value)
	end,
	deserialize = function(raw)
		if raw == nil or raw == "" then return nil end
		local fn, err = loadstring("return " .. raw)
		if not fn then return nil end
		local ok, value = pcall(fn)
		if not ok then return nil end
		return value
	end,
	set_mapgen_setting = function() end,
	get_modpath = function(n)
		local relative = "mods/" .. n
		local handle = io.open(PROJECT_ROOT .. "/" .. relative .. "/init.lua", "r")
		if handle then
			handle:close()
			return relative
		end
		return nil
	end,
	get_content_id = function(name)
		minetest._content_ids = minetest._content_ids or {}
		minetest._content_id_count = minetest._content_id_count or 0
		if not minetest._content_ids[name] then
			minetest._content_id_count = minetest._content_id_count + 1
			minetest._content_ids[name] = minetest._content_id_count
		end
		return minetest._content_ids[name]
	end,
	get_voxel_manip = function()
		return minetest._voxel_manip
	end,
	get_meta = function(pos)
		local key = pos.x .. "," .. pos.y .. "," .. pos.z
		minetest._meta[key] = minetest._meta[key] or {}
		return {
			set_string = function(_, name, value)
				minetest._meta[key][name] = value
			end,
			get_string = function(_, name)
				return minetest._meta[key][name] or ""
			end,
		}
	end,
	chat_send_player = function(name, message)
		minetest._chat_messages[#minetest._chat_messages + 1] = {name = name, message = message}
	end,
	emerge_area = function(minp, maxp, callback, param)
		minetest._emerge_calls[#minetest._emerge_calls + 1] = {minp = minp, maxp = maxp, param = param}
		if minetest._emerge_mode ~= "hold" then
			callback(minp, "from_memory", 0, param)
		end
	end,
	after = function(delay, callback)
		minetest._after_calls[#minetest._after_calls + 1] = {delay = delay, callback = callback}
		if not minetest._hold_after then callback() end
	end,
	get_player_by_name = function(name)
		return minetest._players[name]
	end,
	get_connected_players = function()
		local players = {}
		for _, player in pairs(minetest._players) do
			players[#players + 1] = player
		end
		return players
	end,
	get_node_or_nil = function()
		return {name = "mol:door_closed"}
	end,
	register_globalstep = function(callback)
		minetest._registered_globalsteps[#minetest._registered_globalsteps + 1] = callback
	end,
	register_on_leaveplayer = function(callback)
		minetest._registered_on_leaveplayers[#minetest._registered_on_leaveplayers + 1] = callback
	end,
	register_on_joinplayer = function(callback)
		minetest._registered_on_joinplayers[#minetest._registered_on_joinplayers + 1] = callback
	end,
	register_on_player_hpchange = function(callback)
		minetest._registered_on_player_hpchanges[#minetest._registered_on_player_hpchanges + 1] = callback
	end,
	register_on_mods_loaded = function(callback)
		minetest._registered_on_mods_loaded[#minetest._registered_on_mods_loaded + 1] = callback
	end,
	register_node = function(name, def)
		minetest._registered_nodes[name] = def
	end,
	register_craftitem = function(name, def)
		minetest._registered_craftitems[name] = def
	end,
	register_chatcommand = function(name, def)
		minetest._registered_chatcommands[name] = def
	end,
	register_on_newplayer = function(callback)
		minetest._registered_on_newplayers = minetest._registered_on_newplayers or {}
		minetest._registered_on_newplayers[#minetest._registered_on_newplayers + 1] = callback
	end,
	register_on_placenode = function(callback)
		minetest._registered_on_placenodes = minetest._registered_on_placenodes or {}
		minetest._registered_on_placenodes[#minetest._registered_on_placenodes + 1] = callback
	end,
	register_on_generated = function(callback)
		minetest._registered_on_generated = minetest._registered_on_generated or {}
		minetest._registered_on_generated[#minetest._registered_on_generated + 1] = callback
	end,
	set_node = function(pos, node)
		minetest._set_nodes = minetest._set_nodes or {}
		minetest._set_nodes[#minetest._set_nodes + 1] = {pos = pos, node = node}
	end,
	add_item = function(pos, item)
		minetest._added_items = minetest._added_items or {}
		minetest._added_items[#minetest._added_items + 1] = {pos = pos, item = item}
		return item
	end,
	remove_node = function(pos)
		minetest._removed_nodes = minetest._removed_nodes or {}
		minetest._removed_nodes[#minetest._removed_nodes + 1] = pos
	end,
	sound_play = function(name, spec)
		minetest._sounds = minetest._sounds or {}
		minetest._sounds[#minetest._sounds + 1] = {name = name, spec = spec}
		return #minetest._sounds
	end,
	show_formspec = function(player_name, formname, formspec)
		minetest._formspecs = minetest._formspecs or {}
		minetest._formspecs[#minetest._formspecs + 1] = {player_name = player_name, formname = formname, formspec = formspec}
	end,
	formspec_escape = function(value)
		value = tostring(value or "")
		value = string.gsub(value, "\\", "\\\\")
		value = string.gsub(value, "%]", "\\]")
		value = string.gsub(value, "%[", "\\[")
		value = string.gsub(value, ";", "\\;")
		value = string.gsub(value, ",", "\\,")
		return value
	end,
}

vector = {
	add = function(pos, value)
		return {x = pos.x + value, y = pos.y + value, z = pos.z + value}
	end,
	subtract = function(pos, value)
		return {x = pos.x - value, y = pos.y - value, z = pos.z - value}
	end,
	distance = function(a, b)
		local dx = a.x - b.x
		local dy = a.y - b.y
		local dz = a.z - b.z
		return math.sqrt(dx * dx + dy * dy + dz * dz)
	end,
}

PseudoRandom = {}
PseudoRandom.__index = PseudoRandom
setmetatable(PseudoRandom, {
	__call = function(_, seed)
		return setmetatable({state = tonumber(seed) or 0}, PseudoRandom)
	end,
})

function PseudoRandom:next(min_value, max_value)
	self.state = (1103515245 * self.state + 12345) % 2147483648
	local span = max_value - min_value + 1
	return min_value + (self.state % span)
end

ItemStack = {}
ItemStack.__index = ItemStack
setmetatable(ItemStack, {
	__call = function(_, name)
		return setmetatable({name = name, meta = {}}, ItemStack)
	end,
})

function ItemStack:get_name()
	return self.name
end

function ItemStack:get_meta()
	local meta = self.meta
	return {
		set_string = function(_, key, value) meta[key] = value end,
		get_string = function(_, key) return meta[key] or "" end,
	}
end

VoxelArea = {}
function VoxelArea:new(def)
	local area = {
		MinEdge = def.MinEdge,
		MaxEdge = def.MaxEdge,
		ysize = def.MaxEdge.y - def.MinEdge.y + 1,
		zsize = def.MaxEdge.z - def.MinEdge.z + 1,
	}
	function area:index(x, y, z)
		local dx = x - self.MinEdge.x
		local dy = y - self.MinEdge.y
		local dz = z - self.MinEdge.z
		return 1 + dx * self.ysize * self.zsize + dy * self.zsize + dz
	end
	return area
end

local real_dofile = dofile
dofile = function(path)
	if string.sub(path, 1, 1) == "/" then
		return real_dofile(path)
	end
	return real_dofile(PROJECT_ROOT .. "/" .. path)
end

local function same_value(a, b)
	if type(a) ~= type(b) then return false end
	if type(a) ~= "table" then return a == b end

	for key, value in pairs(a) do
		if not same_value(value, b[key]) then return false end
	end
	for key in pairs(b) do
		if a[key] == nil then return false end
	end
	return true
end

test_same_value = same_value

local function value_to_string(value)
	if type(value) ~= "table" then return tostring(value) end
	local parts = {}
	for key, child in pairs(value) do
		table.insert(parts, tostring(key) .. "=" .. value_to_string(child))
	end
	table.sort(parts)
	return "{" .. table.concat(parts, ",") .. "}"
end

function assert_eq(a, b, label)
	if same_value(a, b) then
		print("PASS " .. label)
	else
		failure_count = failure_count + 1
		print("FAIL " .. label .. ": expected " .. value_to_string(b) .. ", got " .. value_to_string(a))
	end
end

function assert_true(value, label)
	assert_eq(value and true or false, true, label)
end

dofile("mods/mol_core/util.lua")
dofile("mods/mol_core/init.lua")
mol.persist = {
	get = function() return nil end,
	set = function() end,
	delete = function() end,
}
dofile("tests/test_mol_core.lua")
dofile("tests/test_stage2_core.lua")
dofile("mods/mol_rooms/init.lua")
dofile("mods/mol_cells/init.lua")
dofile("mods/mol_graph/init.lua")
dofile("tests/test_mol_rooms.lua")
dofile("tests/test_mol_graph.lua")
dofile("tests/test_mol_determinism_large.lua")
dofile("tests/test_mol_mutations.lua")
dofile("mods/mol_survival/init.lua")
dofile("tests/test_mol_survival.lua")
if minetest.get_modpath("mol_narrative") then
	dofile("mods/mol_narrative/init.lua")
	for _, callback in ipairs(minetest._registered_on_mods_loaded) do
		callback()
	end
end
dofile("tests/test_mol_narrative.lua")
dofile("mods/mol_expedition/init.lua")
dofile("tests/test_mol_expedition.lua")
dofile("tests/test_mol_hardening.lua")
dofile("mods/mol_doors/init.lua")
dofile("tests/test_mol_doors.lua")
dofile("mods/mol_nodes/init.lua")
dofile("tests/test_mol_world.lua")

if failure_count > 0 then
	print("FAILURES " .. failure_count)
	os.exit(1)
end

print("All tests passed")

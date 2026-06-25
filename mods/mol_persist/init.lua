mol = mol or {}
mol.persist = mol.persist or {}

local SCHEMA_VERSION = "1"
local storage = minetest.get_mod_storage()
local ignore_existing_storage = false
local session_written = {}

local function storage_key(ns, key)
	return ns .. ":" .. key
end

function mol.persist.get(ns, key)
	local key_name = storage_key(ns, key)
	if ignore_existing_storage and not session_written[key_name] and ns ~= "meta" then
		return nil
	end
	local raw = storage:get_string(key_name)
	if raw == "" then return nil end
	return minetest.deserialize(raw)
end

function mol.persist.set(ns, key, value)
	local key_name = storage_key(ns, key)
	session_written[key_name] = true
	storage:set_string(key_name, minetest.serialize(value))
end

function mol.persist.delete(ns, key)
	local key_name = storage_key(ns, key)
	session_written[key_name] = true
	storage:set_string(key_name, "")
end

function mol.persist.init()
	local version = mol.persist.get("meta", "version")
	if version == nil then
		minetest.log("warning", "[mol_persist] missing schema version; initializing version " .. SCHEMA_VERSION)
		mol.persist.set("meta", "version", SCHEMA_VERSION)
	elseif version ~= SCHEMA_VERSION then
		minetest.log("error", "[mol_persist] unsupported schema version " .. tostring(version) .. "; treating storage as fresh")
		ignore_existing_storage = true
		mol.persist.set("meta", "version", SCHEMA_VERSION)
	end
end

mol.persist.init()

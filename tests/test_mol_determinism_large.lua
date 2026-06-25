local function graph_signature()
	local rooms = {}
	for _, room_id in ipairs(mol.graph.room_order) do
		local room = mol.graph.get_room(room_id)
		rooms[#rooms + 1] = room.room_id .. ":" .. tostring(room.template) .. ":" .. tostring(room.room_seed)
	end
	local edges = {}
	for _, edge_id in ipairs(mol.graph.edge_order) do
		local edge = mol.graph.edges[edge_id]
		edges[#edges + 1] = edge.edge_id .. ":" .. edge.from_door_id .. ":" .. edge.to_room_id .. ":" .. edge.to_slot
	end
	return table.concat(rooms, "|") .. "\n" .. table.concat(edges, "|")
end

local started = os.clock()
local pass_count = 0
local failures = {}
local first_signatures = {}

for seed = 0, 999 do
	local seed_str = tostring(seed)
	local ok, init_errors = mol.graph.init_world(seed_str)
	local result = ok and mol.graph.validate() or {ok = false, errors = init_errors or {"init_world returned false"}}
	if result.ok then
		pass_count = pass_count + 1
	else
		failures[#failures + 1] = seed_str .. ": " .. table.concat(result.errors or {}, "; ")
	end
	if seed < 500 then
		first_signatures[seed_str] = graph_signature()
	end
end

local deterministic = true
local mismatch_seed
for seed = 0, 499 do
	local seed_str = tostring(seed)
	mol.graph.init_world(seed_str)
	if graph_signature() ~= first_signatures[seed_str] then
		deterministic = false
		mismatch_seed = seed_str
		break
	end
end

local elapsed = os.clock() - started
for _, failure in ipairs(failures) do
	print("1,000-seed graph validation failure " .. failure)
end
print(string.format("mol_graph deterministic validation: %d/1000 seeds passed in %.3fs", pass_count, elapsed))

assert_eq(pass_count, 1000, "1,000-seed graph validation passed 1000/1000")
assert_true(deterministic, "first 500 seeds produce identical graph on second run" .. (mismatch_seed and ("; first mismatch " .. mismatch_seed) or ""))
assert_true(elapsed < 120, "1,000-seed graph validation completes under 120 seconds")

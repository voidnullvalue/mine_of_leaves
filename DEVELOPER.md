# Developer Guide

## Start A Dev Server

Run Luanti with this game directory selected, or from a Luanti checkout/profile that can see this repo:

```sh
luanti --gameid mineofleaves --worldname mineofleaves-dev
```

Use singlenode mapgen. The game also forces `mg_name=singlenode` at startup.

## Run Unit Tests

The unit test suite runs under plain Lua 5.1 or LuaJIT; it does not require Luanti, but it does require a standalone `lua` or `luajit` executable on `PATH`.

```sh
lua tests/run_tests.lua
```

The Stage 9 suite includes the 1,000-seed deterministic graph validation and should finish well under 120 seconds.

## Smoke-Test Yard Containment

1. Start a local world with this game and join as a normal player.
2. Walk into the north, south, east, and west yard boundaries; each side should block movement with `mol:boundary_wall`.
3. Try jumping at each wall; `BOUNDARY_HEIGHT = 5` should prevent jumping over.
4. Try placing nodes just outside or inside the boundary region; placement should be removed unless you are placing allowed chalk inside an allocated interior cell.
5. Confirm a normal player has no `build` privilege unless explicitly granted by an admin.

## Debug Commands

All debug commands require `server` privilege.

`/mol_build <room_id>` builds a graph room on demand.

`/mol_regen <room_id>` rebuilds an already allocated room in place.

`/mol_graph` prints current rooms and graph edges.

`/mol_door <from_door_id> <to_room_id> <to_slot>` reroutes one graph door.

`/mol_where` prints the player's logical room, cell, and position.

`/mol_mutations` prints recent graph mutation records.

`/mol_expeditions` lists expedition records and lifecycle state.

## Reproduce A Seed

Set the Luanti world seed before first world creation, then start the world. The graph uses the exact string from `minetest.get_mapgen_setting("seed")` and derives numeric PRNG seeds through `mol.derive_seed`, so large decimal seed strings are safe.

For pure graph reproduction in tests, call:

```lua
mol.graph.init_world("500")
local result = mol.graph.validate()
```

## Known Limitations

The game uses placeholder textures and minimal node art. Room cells are built on demand during traversal, so the first visit to a room can pay the VoxelManip and lighting cost. Stage 9 found no permanent forceload use; if future work adds forceloading, it must include cleanup after players leave cells.

This repository-level hardening pass can run unit tests without Luanti, but full yard containment and traversal smoke tests still require an interactive Luanti 5.10 server/client session.

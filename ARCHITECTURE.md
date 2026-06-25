# mineofleaves — Architecture

Luanti 5.10 standalone game. A procedurally generated impossible house.

---

## Findings: repository state

The repository is a completely empty directory. There are no existing files, mapgen configuration, node definitions, persistence patterns, test infrastructure, or conflicting code. The only reference implementation available is `giant_jungle_creeper`, a standalone Luanti mod in the home directory, which establishes coding conventions (documented in section 2). The Luanti engine binary is not on `$PATH` in the build environment.

---

## 1. Directory and module structure

```
mineofleaves/
├── game.conf                        # name, description, allowed_mapgens = singlenode
├── settingtypes.txt                 # exposes mol_ settings to the Luanti settings UI
├── menu/
│   └── header.png                   # placeholder; required by the game list UI
└── mods/
    ├── mol_core/
    │   ├── mod.conf                 # no depends
    │   └── init.lua                 # global mol table, constants, math, seed, PRNG
    ├── mol_nodes/
    │   ├── mod.conf                 # depends = mol_core
    │   ├── init.lua
    │   ├── structural.lua           # walls, floors, ceilings, void fill
    │   ├── doors.lua                # door frame, door leaf (open/closed/locked states)
    │   └── special.lua              # dark-void, light fixture, entry marker
    ├── mol_world/
    │   ├── mod.conf                 # depends = mol_core, mol_nodes
    │   └── init.lua                 # on_generated hook, exterior house, mapgen guard
    ├── mol_cells/
    │   ├── mod.conf                 # depends = mol_core, mol_persist
    │   └── init.lua                 # cell allocation, coord math, VoxelManip builder
    ├── mol_rooms/
    │   ├── mod.conf                 # depends = mol_core, mol_cells, mol_nodes
    │   ├── init.lua                 # template registry, generate() dispatcher
    │   └── templates/
    │       ├── corridor.lua
    │       ├── chamber.lua
    │       └── vestibule.lua
    ├── mol_graph/
    │   ├── mod.conf                 # depends = mol_core, mol_persist
    │   └── init.lua                 # room graph, edge table, mutate(), load/save
    ├── mol_doors/
    │   ├── mod.conf                 # depends = mol_core, mol_graph, mol_cells, mol_rooms
    │   └── init.lua                 # globalstep trigger, concealment, teleport, reveal
    ├── mol_persist/
    │   ├── mod.conf                 # depends = mol_core
    │   └── init.lua                 # mod_storage wrapper, versioned namespaced keys
    └── mol_debug/
        ├── mod.conf                 # depends = mol_core, mol_cells, mol_graph, mol_doors
        └── init.lua                 # chat commands, cell visualizer, graph dump
```

`game.conf` must contain `allowed_mapgens = singlenode` so the world-creation dialog offers no other choice.

---

## 2. Module responsibilities

### mol_core

The global `mol` table that every other module extends. Contains:

- `CELL_SIZE = 64`, `MAPBLOCK_SIZE = 16`, `CELL_MAPBLOCKS = 4`
- `INTERIOR_ORIGIN = {x=1024, y=-64, z=0}` — interior cells start here, well away from spawn MapBlocks
- `mol.cell_to_world(cx, cy, cz)` → world-space origin of that cell
- `mol.world_to_cell(pos)` → cell coordinate
- `mol.room_seed(world_seed, room_id)` → deterministic integer via `PseudoRandom`
- `mol.new_prng(seed)` → a fresh `PseudoRandom` instance
- No side effects at load time beyond populating `mol`.

### mol_nodes

Registers every node the game uses. No logic — only registrations and texture definitions. Three files keep groups small:

- **structural.lua**: `mol:wall`, `mol:floor`, `mol:ceiling`, `mol:void` (unwalkable darkness fill outside rooms)
- **doors.lua**: `mol:door_frame`, `mol:door_closed`, `mol:door_open` — each door node carries metadata (`door_id`) linking it to the graph
- **special.lua**: `mol:dark_void` (light_source=0, opaque, stops player view), `mol:light_fixture`, `mol:entry_marker` (decorative node in the exterior house door)

### mol_world

- Registers the `on_generated` callback.
- On every `on_generated` call, checks whether the generated MapBlock range overlaps the exterior house footprint. If so, rebuilds the house in that region (idempotent — reads before writing to avoid unnecessary writes).
- On first generation of the spawn MapBlock, places the full exterior house via VoxelManip.
- Guards against wrong mapgen: `minetest.get_mapgen_setting("mg_name")` checked at load time; logs a hard error and calls `minetest.set_mapgen_setting("mg_name", "singlenode", true)` to correct it.
- The exterior house is a hardcoded schematic-style build (a table of `{pos_offset, node_name}` entries), not procedural. This keeps the entry point stable and memorable.

### mol_cells

- Maintains an in-memory allocation table `mol.cells.used` (set of `"cx,cy,cz"` strings), loaded from `mol_persist` on startup.
- `mol.cells.allocate(room_id)` → finds the next free cell coordinate, records it, persists it, returns the cell coord. Room ID is the canonical key; each room ID maps to exactly one cell coordinate, one-to-one.
- `mol.cells.get_origin(cx, cy, cz)` → `vector.add(INTERIOR_ORIGIN, {x=cx*64, y=cy*64, z=cz*64})`
- `mol.cells.build(cell_coord, room_def)` → uses `minetest.get_voxel_manip()` to read the cell's 64³ volume, fills it from `room_def.nodes` (a flat array of `{offset, node_name, param2}`), writes back, calls `vm:calc_lighting()`, `vm:write_to_map()`. Lighting recalculation is mandatory because rooms have light fixtures.
- Does not call `emerge_area`. VoxelManip's `read_from_map()` forces singlenode generation of unloaded MapBlocks synchronously before reading — this is sufficient.

### mol_rooms

- Template registry: `mol.rooms.templates["corridor"]`, `mol.rooms.templates["chamber"]`, etc.
- Each template is a function `(prng, options) → room_def`.
- `room_def` = `{nodes = {...}, door_slots = { {offset, facing, slot_id}, ... }}`. Door slots describe where doors can appear in this room; the graph layer decides which slots are actually connected.
- `mol.rooms.generate(template_name, room_seed, options)` → instantiates a template deterministically.
- Templates are pure functions: same `prng` state = same output. No global side effects.
- **corridor.lua**: 4-node-wide, 64-node-long passage; 2 door slots (each end)
- **chamber.lua**: roughly cubic interior (16–48 nodes on a side), up to 4 door slots on walls
- **vestibule.lua**: 4×4×4 antechamber used as the immediate "dark zone" inside every door to conceal teleport. Always placed as the first room in a chain.

### mol_graph

- In-memory directed graph loaded at startup from `mol_persist`.
- Node record: `{room_id, template, room_seed, cell_coord, door_slots[]}`
- Edge record: `{from_door_id, to_room_id, to_door_slot}`
- `mol.graph.add_room(room_id, template, room_seed)` — registers a room without placing it physically
- `mol.graph.connect(from_door_id, to_room_id, to_slot)` — creates a traversal edge (and reverse edge by default)
- `mol.graph.mutate(from_door_id, new_to_room_id, new_to_slot)` — replaces an edge; does not rebuild any room; persists immediately
- `mol.graph.get_destination(door_id)` → `{room_id, entry_slot}` or `nil`
- `mol.graph.ensure_placed(room_id)` → if the room has no cell_coord yet, calls `mol.cells.allocate()` then `mol.rooms.generate()` then `mol.cells.build()`. This is the only place physical room construction is triggered.
- The graph for a fresh world is generated deterministically from the world seed: `mol.graph.init_world(world_seed)` produces the initial graph topology at startup if no persisted graph exists.

### mol_doors

- Registers `on_rightclick` for `mol:door_closed` and `mol:door_open`.
- Also registers a globalstep that checks players within 0.8 nodes of any open door (for automatic traversal without right-click). Checks are throttled per-player at 4 Hz.
- Traversal sequence: concealment → ensure destination placed → teleport → reveal (see lifecycle section).
- Concealment uses `player:set_sky({type="plain", base_color={r=0,g=0,b=0}})`.
- Reveal uses a dark ambient sky appropriate to interior rooms.
- Tracks in-flight traversals in a `mol.doors.traversing` table keyed by player name to prevent double-trigger.

### mol_persist

- Single API: `mol.persist.get(ns, key)`, `mol.persist.set(ns, key, value)`, `mol.persist.delete(ns, key)`.
- Backed by `minetest.get_mod_storage()` on the `mol_persist` mod.
- Keys are formatted as `"ns:key"`.
- Values are `minetest.serialize` / `minetest.deserialize` (consistent with the codebase style).
- On startup, `mol.persist.load_all()` reads the handful of top-level keys (graph, cells, door_state) into memory. Writes happen immediately on change.
- Schema version is stored under `"meta:version"`. A version mismatch at startup prints a warning and falls back to a fresh state.

### mol_debug

All commands require `server` privilege.

| Command | Effect |
|---------|--------|
| `/mol_cell <cx> <cy> <cz>` | Teleport caller to that cell's origin |
| `/mol_build <room_id>` | Force `mol.graph.ensure_placed(room_id)` |
| `/mol_graph` | Print the room graph to caller's chat |
| `/mol_door <door_id> <dest_room_id> <dest_slot>` | Call `mol.graph.mutate()` |
| `/mol_regen <room_id>` | Re-run `mol.cells.build()` for the room's existing cell |
| `/mol_where` | Print caller's current room_id |
| `/mol_particles` | Toggle cell-boundary particle visualizer |

---

## 3. Generation lifecycle: MapBlock request → completed room

```
1. Engine requests MapBlocks (player approaches, or emerge_area called)
   └── singlenode fills them with mol_world's registered singlenode node ("mol:void")

2. on_generated fires for the MapBlock range
   ├── mol_world checks: does this range intersect HOUSE_FOOTPRINT?
   │   └── YES → rebuild house section in this range (VoxelManip, idempotent)
   └── mol_world checks: does this range intersect any ALLOCATED CELL?
       └── YES and cell is marked "built" → do nothing (map DB already correct)
           NO  → do nothing (rooms are demand-built, not terrain-built)

3. Player approaches a door to an unvisited room (or /mol_build called):
   mol.graph.ensure_placed(room_id)
   │
   ├── a. mol.cells.allocate(room_id)
   │       → scan mol.cells.used for next free (cx,cy,cz) in a spiral
   │       → record "room_id → (cx,cy,cz)" in persist
   │       → add to mol.cells.used
   │
   ├── b. mol.rooms.generate(template, room_seed, options)
   │       → instantiate template function with PseudoRandom(room_seed)
   │       → returns room_def {nodes[], door_slots[]}
   │
   ├── c. mol.cells.build(cell_coord, room_def)
   │       → vm = minetest.get_voxel_manip()
   │       → emin, emax = vm:read_from_map(cell_origin, cell_origin+63)
   │           (forces singlenode generation of any unloaded MapBlocks)
   │       → fill 64³ data array: all nodes default to mol:void
   │       → write room interior nodes and door frames from room_def.nodes
   │       → write door leaf nodes with metadata {door_id = generated_id}
   │       → vm:set_data(data)
   │       → vm:set_light_data(light_data)  -- zero out stale lighting
   │       → vm:calc_lighting()
   │       → vm:write_to_map()
   │       → vm:update_map()
   │
   └── d. mark room as "placed" in graph node record; persist graph
```

Room generation is synchronous. The VoxelManip `read_from_map` is the only blocking call that could be slow for cold MapBlocks. For a 64³ region on singlenode, this is fast — it is generating trivial fill content.

---

## 4. Doorway traversal lifecycle

```
Player right-clicks mol:door_closed (or globalstep detects proximity):

 1. GUARD
    ├── if mol.doors.traversing[player_name] → ignore (already traversing)
    └── mol.doors.traversing[player_name] = true

 2. READ DOOR METADATA
    └── door_id = minetest.get_meta(door_pos):get_string("door_id")

 3. LOOK UP DESTINATION
    └── dest = mol.graph.get_destination(door_id)
        └── if nil → show_message "Door leads nowhere." → clear flag → return

 4. CONCEAL
    └── player:set_sky({type="plain", base_color={r=0,g=0,b=0,a=255}})

 5. ENSURE DESTINATION EXISTS
    └── mol.graph.ensure_placed(dest.room_id)
        (synchronous; typically instant if room was pre-built)

 6. COMPUTE ENTRY POSITION
    └── entry_pos = mol.cells.get_door_pos(dest.cell_coord, dest.entry_slot)

 7. TELEPORT
    └── player:set_pos(entry_pos)

 8. BRIEF PAUSE  (allows client chunk to arrive)
    └── minetest.after(0.3, function()

 9.     REVEAL
        └── player:set_sky({type="plain", base_color={r=5,g=5,b=8,a=255}})
            (dark interior ambient, not pure black)

10.     CLEAR FLAG
        └── mol.doors.traversing[player_name] = nil

    end)
```

The 0.3-second pause gives the client time to receive the destination chunk before the sky is restored. If pre-generation of the next room is desired (to eliminate any pause), `mol.graph.ensure_placed` can be called speculatively when the player enters the preceding room.

---

## 5. Persistence design

### Storage backend

`minetest.get_mod_storage()` on `mol_persist`. Per-world SQLite blob store. No external dependencies, no migration friction.

### Key schema (version 1)

| Key | Value | Updated |
|-----|-------|---------|
| `meta:version` | `"1"` | once |
| `graph:rooms` | serialized array of room records | on add |
| `graph:edges` | serialized array of edge records | on add or mutate |
| `cells:alloc` | serialized `{[room_id] = "cx,cy,cz"}` map | on allocate |
| `cells:built` | serialized set of room_ids physically placed | on build |
| `doors:overrides` | serialized `{[door_id] = {to_room, to_slot}}` map | on mutate |
| `world:initialized` | `"true"` | once |

### Strategy

- The entire graph and allocation map fit in memory. Load all keys at startup.
- Write on every mutation, not batched. At the expected scale (hundreds of rooms), write latency is negligible.
- `doors:overrides` is the delta above the deterministic initial graph. On load: reconstruct the initial graph from world seed, then apply all overrides. The base graph never needs to be stored — only mutations do.
- Room geometry is never persisted. It is always regenerated from `(world_seed, room_id)`.

### Reproducibility guarantee

Given the same `world.mt` seed:

1. `mol.graph.init_world(world_seed)` produces the same initial graph
2. `mol.cells.allocate()` allocates cells in a deterministic order (spiral, seeded)
3. `mol.rooms.generate(template, mol.room_seed(world_seed, room_id))` produces identical geometry
4. Mutations stored in `doors:overrides` are the only non-deterministic state

A debug server started from a world backup will produce identical room contents.

---

## 6. Multiplayer design

### Shared physical world

All players occupy the same physical map. Cells are fixed world positions. Two players in the same abstract room are in the same physical MapBlocks and can see and interact with each other normally. No instancing is required.

### Player state tracking

`mol.players[player_name]` holds `{current_room_id}`, updated on every traversal. In-memory only — reconnect recovery uses physical position to infer the current room (check which cell the player is in on `on_joinplayer`).

### Concurrent traversal

- Two players going through the same door simultaneously both reach the same destination — correct behavior.
- The traversal flag `mol.doors.traversing` is per-player; concurrent traversals do not block each other.
- `mol.graph.ensure_placed` is guarded by the `cells:built` set to prevent double-build from concurrent calls.

### Door mutation visibility

If player A mutates a door while player B is mid-traversal through it, player B completes to the old destination (the destination is resolved at step 3, before the mutation applies). This is acceptable.

### Expedition support

For coordinated group navigation, a chat command or sign mechanic can announce the current room to party members. No architectural change is needed — the shared physical world handles co-presence naturally.

### Server restart

On `on_joinplayer`, if the player's physical position is inside a known cell, restore `mol.players[name].current_room` from the allocation map. If the player is outside all cells (fresh spawn), place them at the house entry.

---

## 7. Major Luanti API risks

### R1: VoxelManip lighting recalculation is mandatory and expensive

`vm:calc_lighting()` must be called after every room build that includes light sources. Omitting it leaves the room dark or flickering. For a 64³ region with multiple light fixtures this takes measurable time (tens of milliseconds). **Mitigation**: build rooms off the hot path — demand-build triggered by door approach, not during active gameplay.

### R2: `player:set_pos()` to an unloaded region

If destination cell MapBlocks have been evicted from the active block list, teleporting a player there before re-emergence causes a brief client fall-through. **Mitigation**: call `minetest.emerge_area()` before `set_pos()` during traversal. The emerge callback round-trip (~1 frame) is already covered by the 0.3-second pause. Alternatively, keep cells force-loaded (`minetest.forceload_block`) while any player is in an adjacent graph room.

### R3: mod_storage key size limits

No documented per-key size limit, but practical concern at scale. **Mitigation**: the initial graph is regenerated from seed (only overrides stored), keeping `doors:overrides` small. `cells:alloc` scales linearly with visited rooms — fine at expected scale.

### R4: globalstep performance for door proximity detection

O(players × doors) per step. **Mitigation**: maintain a spatial index — a table keyed by MapBlock coordinate listing door positions in that MapBlock. Each globalstep, determine which MapBlock each player is in and only check doors in that MapBlock and its neighbors.

### R5: `on_generated` re-entrancy during room construction

If `vm:write_to_map()` causes block changes that trigger further `on_generated` calls, re-entrant room building could occur. **Mitigation**: the `cells:built` set acts as a re-entrancy guard — the second call sees the room as already built and does nothing.

### R6: `PseudoRandom` value range

`PseudoRandom:next(min, max)` must stay within the engine's 0..32767 output range, so keep `max - min ≤ 32767`. Current template call sites use much smaller ranges. For seeding child PRNGs, use `PseudoRandom(seed)` directly rather than deriving large values from `next()`.

### R7: `allowed_mapgens` is advisory, not enforced

A player can still override `mg_name` in `minetest.conf`. **Mitigation**: the `mol_world` startup guard calls `minetest.set_mapgen_setting("mg_name", "singlenode", true)` (the third argument forces override) to correct it at runtime, and logs a visible warning.

### R8: entity `static_save` for door triggers

If door triggers used entities, `static_save = true` would cause fragile respawn behavior at cell edges. **Mitigation**: use node metadata + globalstep proximity check exclusively for door triggers. No trigger entities.

---

## 9. Staged implementation plan

### Stage 0 — Scaffolding

- `game.conf`, `settingtypes.txt`, `menu/header.png`
- `mol_core`: constants, cell math, seed, PRNG wrappers
- `mol_persist`: storage wrapper, load/save
- `mol_nodes`: register `mol:void`, `mol:wall`, `mol:floor`, `mol:ceiling`, `mol:door_frame`, `mol:door_closed`, `mol:light_fixture` with placeholder textures
- `mol_world`: mapgen guard, `on_generated` stub, flat singlenode ground plane at spawn
- `mol_debug`: `/mol_cell` teleport command

**Deliverable**: can start the game in Luanti, see a flat world, no errors.

### Stage 1 — Single physical room

- `mol_cells`: allocate, get_origin, build (VoxelManip path)
- `mol_rooms`: `chamber` template — hardcoded 32×32×32 hollow box with light fixtures and four door frame positions
- `mol_debug`: `/mol_build 1` triggers `ensure_placed(1)` with a hardcoded room definition

**Deliverable**: `/mol_build 1` places a room at cell (0,0,0) relative to INTERIOR_ORIGIN. Can teleport there and walk around.

### Stage 2 — Room graph and persistence

- `mol_graph`: full graph data structure, `add_room`, `connect`, `get_destination`, `ensure_placed`, `init_world`
- `mol_persist`: fully wired to graph and cells
- `mol_rooms`: `corridor` template
- World seed initializes a small hardcoded graph (5 rooms, 6 connections)
- `mol_debug`: `/mol_graph` dump

**Deliverable**: graph with 5 rooms persists across server restarts. Restarting with the same seed produces identical room positions — verified by comparing node positions before and after.

### Stage 3 — Exterior house and entry

- `mol_world`: full exterior house VoxelManip build at spawn
- House has four walls, a roof, floor, windows, and a single `mol:door_closed` node with `door_id = "entry"`
- Graph: `"entry"` door connects to room_id 1
- `mol_doors`: `on_rightclick` handler — resolves destination, ensures placed, teleports; no concealment yet

**Deliverable**: player spawns outside the house, right-clicks the door, is teleported inside room 1.

### Stage 4 — Traversal concealment

- `mol_doors`: full lifecycle with `set_sky` blackout, 0.3-second pause, sky restore
- `mol_rooms`: `vestibule` template — tiny antechamber placed as the first nodes inside every door; the main room is behind a corner so the far side is never visible through an open door

**Deliverable**: traversal looks polished. No pop-in visible. 10 door transitions produce no Lua errors.

### Stage 5 — Procedural generation

- `mol_rooms`: all three templates use PRNG for room size, light placement, door slot selection, wall variation
- `mol.graph.init_world` generates a larger initial graph (20+ rooms) deterministically from world seed
- `mol_debug`: `/mol_regen` verifies regenerating a room with the same seed overwrites identically

**Deliverable**: 20 rooms all visually distinct; same seed always produces same layout.

### Stage 6 — Runtime mutation

- `mol_graph.mutate()` fully implemented and persisted
- `mol_debug`: `/mol_door <door_id> <dest_room_id> <dest_slot>` rewires a door live
- One scripted mutation: after visiting room 5, room 3's back door rewires to a new room 21 (a secret room)

**Deliverable**: door rewiring takes effect on next traversal. Restart preserves the mutation.

### Stage 7 — Multiplayer hardening

- Concurrent traversal safety verified (two players on same door simultaneously)
- `on_joinplayer` position inference for reconnect
- Adjacent-cell forceloading was evaluated but not implemented; the release build avoids permanent forceload risk by not using forceloads.
- Stress test: 2 clients, 10 minutes, alternating fast traversal

**Deliverable**: 2 players explore simultaneously without corruption or crashes.

---

## 8. Implementation status and known limitations

Stage 9 confirmed the implementation is a deterministic, testable hardening pass over the completed game systems, not a gameplay expansion.

- Graph generation now has a dedicated 1,000-seed deterministic validation test. Seeds `"0"` through `"999"` run through `mol.graph.init_world(seed)` and `mol.graph.validate()`, and the first 500 seeds are generated twice in the same Lua session to confirm identical graph signatures.
- Seed handling keeps the full Luanti world seed as a string. Production code derives numeric PRNG seeds through `mol.derive_seed`; a hardening test scans production Lua files for `tonumber(minetest.get_mapgen_setting(...))`.
- Luanti 5.10 API audit findings are reflected in code comments at the verified call sites: VoxelManip, `emerge_area`, `ObjectRef:set_sky`, `ObjectRef:set_physics_override`, and HUD text definitions.
- `INTERIOR_ORIGIN` is MapBlock-aligned: `1024 % 16 == 0`, `-64 % 16 == 0`, and `0 % 16 == 0` under Lua 5.1 modulo semantics. Unit tests assert this alignment.
- Cell builds are bounded to each 64³ cell. Template validation and `mol.cells.build` reject or skip out-of-bounds offsets.
- `on_generated` edits only the provided `minp..maxp` range and uses no player-facing APIs in the mapgen callback.
- Yard containment is documented in `CONTAINMENT_AUDIT.md`. Boundary walls are non-climbable and non-diggable; default privileges exclude `build`; chalk placement is restricted to allocated interior cells.
- Door traversal is guarded per player before emerge or delayed callbacks. The emerge callback handles disconnected players by clearing traversal state.
- Survival globalstep is bounded to 1 Hz. Door proximity uses the MapBlock spatial index from R4 rather than scanning every door globally.
- No permanent forceloading is currently implemented. This avoids leaked forceloads; future forceload support must include explicit leave/cleanup paths.
- Persistence treats unsupported schema versions as a fresh session and handles `minetest.deserialize()` returning nil for corrupt keys by falling back to empty state.

Known limitations:

- Art remains placeholder-level.
- First traversal into an unbuilt room can pay VoxelManip and lighting cost.
- The Stage 7 design note mentioned adjacent-cell forceloading, but the current implementation does not forceload cells. This is safer for release hardening until a cleanup policy is implemented.

## 10. Acceptance criteria for the first playable vertical slice

The vertical slice is the exit condition for Stage 4.

**AC1 — Engine launch**: `mineofleaves` appears in the Luanti game list. Creating a new world with it and the `singlenode` mapgen succeeds. No Lua errors in `debug.txt` during startup.

**AC2 — Mapgen guard**: Creating a world with `mg_name = v7` causes a visible error message and falls back to singlenode behavior. No crash.

**AC3 — Spawn exterior**: The player spawns on flat ground outside a recognizable house. The house has at least four walls, a roof, a door, and is fully enclosed. No floating nodes, no holes.

**AC4 — Entry traversal**: Right-clicking the exterior door initiates a traversal. The screen goes black. After ≤1 second the player is inside room 1. The screen returns to the room's ambient lighting. No Lua error in log.

**AC5 — Interior navigation**: Room 1 has at least two exit doors. Each leads to a distinct room. Both destination rooms are enclosed and navigable without falling into void.

**AC6 — Impossibility is physical**: At least one pair of connected rooms is separated by more than 128 nodes in world coordinates, yet traversal between them takes one door step. Verifiable with `/mol_where` and `/mol_cell`.

**AC7 — Reproducibility**: Two identical playthroughs from the same world seed (same door sequence) always reach the same rooms. Verified by: start world, take 5 door steps, note room IDs via `/mol_where`; restore world backup; repeat — room IDs must match.

**AC8 — Persistence across restart**: Stopping and restarting the server preserves all placed room geometry and all graph edges. A room visited before the restart is at the same physical position after.

**AC9 — No mobs_redo**: `grep -r "mobs_redo\|mobs_api\|mobs:" mods/` returns nothing. No dependency on any mob framework.

**AC10 — No singlenode bleed**: The map outside the house exterior and cell region is either `mol:void` or the singlenode default. No biome terrain, trees, or ores anywhere.

**AC11 — Clean 10-minute session**: A single-player session of at least 10 minutes traversing rooms produces zero Lua errors in `debug.txt`.

**AC12 — Formspec hygiene**: No leftover open formspecs after traversal completes. Verified by pressing Escape after each door step — no stale formspec dialog appears.

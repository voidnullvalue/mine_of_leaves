# Containment Audit

Stage 9 audit results:

1. Boundary walls are generated on all four sides of the yard with `mol:boundary_wall`.
2. `BOUNDARY_HEIGHT = 5`; Luanti's normal jump height is about 1.25 nodes and the player collision height is about 1.8 nodes, so 5 nodes exceeds the 3.05-node jump-over threshold.
3. `mol:boundary_wall` sets `climbable = false`.
4. Boundary, house wall, and ceiling nodes set `diggable = false`.
5. `mods/mol_world/init.lua` removes placements in `mol.is_yard_boundary_region(pos)`.
6. `game.conf` sets `default_privs = interact, shout`, excluding `build`.
7. Chalk placement is restricted by `mol.is_chalk_allowed_region(pos)` to allocated interior cells.
8. Non-footprint mapgen fills generated chunks with `mol:void`; no traversable exterior space is exposed outside the yard.
9. The house roof/ceiling is `mol:ceiling`, which is non-climbable by default and `diggable = false`.
10. House exterior walls are `mol:wall` and `diggable = false`.

No containment bypass was found in code review or unit-level checks. Runtime collision and jump testing still requires an interactive Luanti 5.10 server/client session.

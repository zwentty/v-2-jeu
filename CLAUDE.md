# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**V2jeu** — top-down tactical dungeon crawler in Godot 4.6 (Forward Plus, D3D12 on Windows).  
Language: GDScript. Comments and variable names are in French.  
Controls use AZERTY layout: ZQSD for movement.

## Running the game

Open the project in the Godot 4.6 editor and press **F5** (or the play button). There is no build step or CLI runner — Godot manages compilation automatically.

## Architecture

### Autoloads (singletons)

| Singleton | File | Role |
|-----------|------|------|
| `Settings` | `scripts/settings.gd` | Loads/saves keybindings to `user://settings.cfg` |
| `EnemyManager` | `scripts/enemy_manager.gd` | Coordinates all enemies tactically each frame |
| `GameState` | `scripts/game_state.gd` | Persists player health + inventory across room scenes |

### Key systems

**`scripts/enemy_manager.gd`** — the most complex file. Every 0.2 s it assigns a tactical role (INTERCEPT, FLANK_LEFT, FLANK_RIGHT, CHASE, SURROUND_*) to each engaged enemy based on group size. With 3+ enemies it forms triangle/encirclement formations, and uses physics raycasts to detect when the player is surrounded and trigger a "rush" mode. All enemies register/deregister themselves here.

**`scripts/steering.gd`** — static utility class. Provides `seek`, `flee`, `orbit`, `wander`, `separate`, `arrive` functions used by enemy scripts. Reuse these instead of writing new movement math.

**`scenes/enemy/enemy.gd`** — melee enemy. State machine: IDLE → PATROL → ENGAGE → ATTACK → DEAD. Uses `NavigationAgent2D` for obstacle avoidance + separation steering from `steering.gd`. On death becomes a traversable corpse item.

**`scenes/enemy/ranged_enemy.gd`** — ranged enemy. Same state machine structure. Maintains optimal distance from player (200–400 px), retreats if too close, fires projectiles via `scenes/projectile/projectile.tscn`.

**`scenes/player/player.gd`** — CharacterBody2D. Click-to-attack at cursor (50 px range), dash with i-frames (600 px/s, 0.3 s), 1 s invincibility after hit.

**`scenes/world/room.gd`** — generic room script attached to each room scene's root. Builds a single `NavigationRegion2D` at runtime: the `play_area` (Rect2) is the walkable bound, and the static colliders under the room (tiles with a hitbox, walls, door barriers) are **baked out automatically** via `NavigationServer2D.parse_source_geometry_data` + `bake_from_source_geometry_data` (so adding/editing collidable tiles updates enemy pathing with no code). `nav_agent_radius` sets the margin, `nav_collision_mask` selects which physics layers to carve; `obstacle_rects` (Array[Rect2]) adds optional manual holes. On clear it opens every door (group `door`) and records the room in `GameState.cleared_rooms`. When the player re-enters a cleared room, its enemies are freed immediately (it stays empty, doors already open). If `is_final_room` is set, clearing it triggers victory. On load, the player is placed on the `Marker2D` whose name matches `GameState.next_spawn_point` (set by the door that was used).

**`scenes/world/door.gd` / `door.tscn`** — a door is an `Area2D` placed anywhere on a room's edge (any direction). Exports `target_scene` (room it leads to) + `target_spawn` (name of the arrival `Marker2D` in that room). It has a child `Barriere` (StaticBody) that physically blocks until the room is cleared; `room.gd` then calls `open()`. On contact with the player (when open) it saves state to `GameState` and loads `target_scene`. A door with empty `target_scene` never opens (acts as a wall / dead end). Doors are fully directional-agnostic: a bottom door can lead to a top spawn, branches are possible, etc.

### Level structure

Every room is its own scene under `scenes/world/`, all built on the **same local origin** (a 2560×1440 box). Because they share coordinates, the player's `Camera2D` limits are set once (`0/0/2560/1440`) and work in every room.

Rooms are linked by **doors**, not hardcoded directions. Current layout: `salle_1` ⇄ `salle_2` ⇄ `salle_3` ⇄ `salle_4`, where `salle_4` is the final room (`is_final_room = true` → victory on clear). Each room has named arrival markers (`SpawnGauche`, `SpawnDroite`, …); a door's `target_spawn` names the marker the player lands on.

To add a room: duplicate an existing room scene in Godot, place a door (instance of `door.tscn`) wherever you want and set its `target_scene` + `target_spawn`, add a matching arrival `Marker2D` (name it, e.g. `SpawnGauche`), point a door in the previous room at it, and adjust `obstacle_rects` / enemy placement. Set `is_final_room` on the last room. No hardcoded room boundaries remain — enemies read their bounds from the room's `play_area` (via the `room` group).

### Inventory

`scenes/ui/inventory.gd` manages a 24-slot grid. Items are collected but currently have no gameplay effect — the system is a stub awaiting implementation.

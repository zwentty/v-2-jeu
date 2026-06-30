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

**`scripts/base_enemy.gd`** — base class all enemies extend. Holds the shared state machine, navigation, patrol, room bounds, health, and the **death drop**. `die()` spawns `scenes/items/item.tscn` and fills `item_name`/`item_color`/`item_polygon` **and `carried_form`** (the exported `drop_form` PlayableForm, if set) so the dropped soul carries a transformable form.

**`scenes/enemy/enemy.gd`** — melee enemy (extends `base_enemy.gd`). State machine: IDLE → PATROL → ENGAGE → ATTACK → DEAD. Uses `NavigationAgent2D` for obstacle avoidance + separation steering from `steering.gd`. On death becomes a traversable corpse item. Its `drop_form` (set in `enemy.tscn` → `resources/forms/soldat_form.tres`) is the form the player gains by eating its soul.

**`scenes/enemy/ranged_enemy.gd`** — ranged enemy (extends `base_enemy.gd`). Same state machine structure. Maintains optimal distance from player (200–400 px), retreats if too close, fires projectiles via `scenes/projectile/projectile.tscn`. **No `drop_form` assigned yet** (transformation content for this enemy is not built — see Transformation system).

**`scenes/player/player.gd`** — CharacterBody2D (the *slime*). Dash-attack at cursor with i-frames + 1 s invincibility after hit. Hosts the `TransformHandler` + `TransformInventory` children. Movement uses a `move_speed` variable (overwritten by the active form's stats, not the `SPEED` const). Attack input is routed: **if transformed → `transform_inventory.use_attack()`, else the base dash-attack**. The *compétence* input (eat souls / pickup) works **only in base form** — once transformed into an enemy you can't eat souls (enemy forms have no ability).

**`scenes/world/room.gd`** — generic room script attached to each room scene's root. Builds a single `NavigationRegion2D` at runtime: the `play_area` (Rect2) is the walkable bound, and the static colliders under the room (tiles with a hitbox, walls, door barriers) are **baked out automatically** via `NavigationServer2D.parse_source_geometry_data` + `bake_from_source_geometry_data` (so adding/editing collidable tiles updates enemy pathing with no code). `nav_agent_radius` sets the margin, `nav_collision_mask` selects which physics layers to carve; `obstacle_rects` (Array[Rect2]) adds optional manual holes. On clear it opens every door (group `door`) and records the room in `GameState.cleared_rooms`. When the player re-enters a cleared room, its enemies are freed immediately (it stays empty, doors already open). If `is_final_room` is set, clearing it triggers victory. On load, the player is placed on the `Marker2D` whose name matches `GameState.next_spawn_point` (set by the door that was used).

**`scenes/world/door.gd` / `door.tscn`** — a door is an `Area2D` placed anywhere on a room's edge (any direction). Exports `target_scene` (room it leads to) + `target_spawn` (name of the arrival `Marker2D` in that room). It has a child `Barriere` (StaticBody) that physically blocks until the room is cleared; `room.gd` then calls `open()`. On contact with the player (when open) it saves state to `GameState` and loads `target_scene`. A door with empty `target_scene` never opens (acts as a wall / dead end). Doors are fully directional-agnostic: a bottom door can lead to a top spawn, branches are possible, etc.

### Transformation system (slime forms)

The slime can **eat enemy souls and transform** into them. A run uses **3 fixed transformation slots**, never empty (each defaults to the base slime).

**Data resources** (authored as `.tres` under `resources/forms/`):
- **`scripts/stat_block.gd`** (`StatBlock`) — `max_health`, `move_speed`, `damage`, `weight` (floats). Player-side stats of a form.
- **`scripts/playable_form.gd`** (`PlayableForm`) — `id` (StringName), `display_name`, `sprite_frames`, `attack_scene`, `ability_scene`, `stats` (StatBlock), `icon`.
- Existing forms: `base_form.tres` (slime nu, green `Monster_Slime` sprite) and `soldat_form.tres` (melee enemy, `Human_Soldier` sprite). Each has its own `*_stats.tres` + `*_frames.tres`. **The ranged enemy form does not exist yet.**

**`scenes/player/transform_handler.gd`** (`TransformHandler`, a **Node2D** child of the player) — `apply(form)` does, in order: free the previous attack/ability instances → set the AnimatedSprite2D's `sprite_frames` + play `idle` → instantiate the form's `attack_scene`/`ability_scene` as children → apply stats. **HP % is preserved across a switch** (ratio = health/old max, then health = ratio × new max; first apply starts full). It refreshes the stats node's health bar afterwards and emits `transformed(form)`. `use_attack()` / `use_ability()` call a **common `trigger()` method** on the mounted instance — the handler never knows the concrete attack type. Must be a Node2D so the mounted `Area2D` attacks follow the player.

**`scenes/player/transform_inventory.gd`** (`TransformInventory`, child of the player) — owns the 3 slots (`SLOT_COUNT`), starts on slot 1, all base. `devour(form)` stores a **deep copy** (`form.duplicate(true)`) into the **active slot** and transforms into it. `switch_to/next/prev` change the active slot (with `switch_cooldown`). `clear_active_slot()` (**G**) resets the active slot to base. `reset_for_new_run()` (called on player death) resets all slots to base, slot 1. Emits `inventory_changed(slots, active_index)`. **Creates its input actions at runtime** if missing (`_ensure_input_actions`): `transform_slot_1..3` (physical number row, AZERTY-safe), `transform_prev`=A, `transform_next`=R, `transform_base`=G. Connects to each item's `forme_ramassee` signal (via `node_added`) so eating a soul calls `devour`.

**`scenes/attacks/`** — *slime* attack scenes, deliberately separate from the enemy attacks (duplication is intentional) and aimed at **enemies** (group `enemy`). All expose the common `trigger()` interface. `melee_attack_player.tscn/.gd` is the mounted melee hitbox (used by `soldat_form`). `projectile_player.tscn/.gd` is a flying projectile — **not** directly mountable (it moves on `_ready`); a ranged form needs a small launcher scene (not built yet).

**`scenes/items/item.gd`** — the ground drop. Exports `carried_form: PlayableForm`; on `pickup()` it emits **`forme_ramassee(carried_form)`** (consumed by the inventory) in addition to its existing soul behavior. Pickup mechanism itself is unchanged.

**`scenes/ui/transform_ui.gd` / `.tscn`** (`TransformUI`) — bottom-of-screen HUD row, instanced under each room's `UILayer`. Subscribes to `inventory_changed` and rebuilds a row of icons (96×96) from the signal payload only, the active slot highlighted by opacity. Display-only; it auto-resolves the inventory via the `player` group. Add it to a room's `UILayer` to show it.

> **Status:** only enemy 1 (melee → `soldat_form`) is wired end-to-end. Enemy 2 (ranged) still needs: a launcher attack scene exposing `trigger()`, a blue-slime `SpriteFrames`, a `StatBlock`, a `PlayableForm`, and `drop_form` on `ranged_enemy.tscn`. `StatBlock.damage` is not consumed yet (per-form damage comes from the attack scene); `move_speed` and `max_health` are.

### Level structure

Every room is its own scene under `scenes/world/`, all built on the **same local origin** (a 2560×1440 box). Because they share coordinates, the player's `Camera2D` limits are set once (`0/0/2560/1440`) and work in every room.

Rooms are linked by **doors**, not hardcoded directions. Current layout: `salle_1` ⇄ `salle_2` ⇄ `salle_3` ⇄ `salle_4`, where `salle_4` is the final room (`is_final_room = true` → victory on clear). Each room has named arrival markers (`SpawnGauche`, `SpawnDroite`, …); a door's `target_spawn` names the marker the player lands on.

To add a room: duplicate an existing room scene in Godot, place a door (instance of `door.tscn`) wherever you want and set its `target_scene` + `target_spawn`, add a matching arrival `Marker2D` (name it, e.g. `SpawnGauche`), point a door in the previous room at it, and adjust `obstacle_rects` / enemy placement. Set `is_final_room` on the last room. No hardcoded room boundaries remain — enemies read their bounds from the room's `play_area` (via the `room` group).

### Inventory

`scenes/ui/inventory.gd` manages a 24-slot grid (the **soul/item inventory**, distinct from the transformation slots). Items are collected but currently have no gameplay effect — the system is a stub awaiting implementation. The gameplay-relevant inventory is the **3-slot transformation inventory** (see Transformation system).

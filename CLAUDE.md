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

### Key systems

**`scripts/enemy_manager.gd`** — the most complex file. Every 0.2 s it assigns a tactical role (INTERCEPT, FLANK_LEFT, FLANK_RIGHT, CHASE, SURROUND_*) to each engaged enemy based on group size. With 3+ enemies it forms triangle/encirclement formations, and uses physics raycasts to detect when the player is surrounded and trigger a "rush" mode. All enemies register/deregister themselves here.

**`scripts/steering.gd`** — static utility class. Provides `seek`, `flee`, `orbit`, `wander`, `separate`, `arrive` functions used by enemy scripts. Reuse these instead of writing new movement math.

**`scenes/enemy/enemy.gd`** — melee enemy. State machine: IDLE → PATROL → ENGAGE → ATTACK → DEAD. Uses `NavigationAgent2D` for obstacle avoidance + separation steering from `steering.gd`. On death becomes a traversable corpse item.

**`scenes/enemy/ranged_enemy.gd`** — ranged enemy. Same state machine structure. Maintains optimal distance from player (200–400 px), retreats if too close, fires projectiles via `scenes/projectile/projectile.tscn`.

**`scenes/player/player.gd`** — CharacterBody2D. Click-to-attack at cursor (50 px range), dash with i-frames (600 px/s, 0.3 s), 1 s invincibility after hit.

**`scenes/world/world.gd`** — master coordinator. Builds the `NavigationRegion2D` polygon at runtime (2 rooms + 5 rock obstacles each). Detects room clear → opens door. Room 2 enemies are kept inactive until the player crosses x = 2560.

### Level structure

Two rooms laid out horizontally:
- Room 1: x 0–2560
- Room 2: x 2560–5088

Room boundaries are checked by hardcoded x-coordinates in `world.gd` and `enemy_manager.gd`. Any new room must update these constants in both files.

### Inventory

`scenes/ui/inventory.gd` manages a 24-slot grid. Items are collected but currently have no gameplay effect — the system is a stub awaiting implementation.

## EventBus.gd
## Global signal bus. All systems communicate through here — never hold direct
## references to other autoloads just to emit an event. Add new signals here as
## systems are built; group them by domain for readability.
extends Node


# ─────────────────────────────────────────────
#  TIME
# ─────────────────────────────────────────────
signal day_changed(new_day: int)
signal week_changed(new_week: int, week_name: String)
signal month_changed(new_month: int)
signal turn_ended()                          # local player pressed End Turn


# ─────────────────────────────────────────────
#  ECONOMY
# ─────────────────────────────────────────────
signal resource_changed(type: String, new_amount: int, delta: int)
signal mine_captured(mine_id: String, new_owner: String)
signal daily_income_collected(income: Dictionary)


# ─────────────────────────────────────────────
#  ADVENTURE MAP
# ─────────────────────────────────────────────
signal hero_moved(hero_id: String, new_tile: Vector2i)
signal hero_entered_town(hero_id: String, town_id: String)
signal hero_entered_combat(hero_id: String, enemy_id: String)
signal map_object_interacted(object_id: String, hero_id: String)
signal town_captured(town_id: String, new_owner: String)
signal fog_updated(visible_tiles: Array)


# ─────────────────────────────────────────────
#  COMBAT
# ─────────────────────────────────────────────
signal combat_started(attacker_data: Dictionary, defender_data: Dictionary)
signal combat_ended(result: String, surviving_units: Array)
signal combat_round_started(round_number: int)
signal combat_round_ended(round_number: int)

signal unit_turn_started(unit_id: String)
signal unit_turn_ended(unit_id: String)
signal unit_moved(unit_id: String, from_hex: Vector3i, to_hex: Vector3i)
signal unit_attacked(attacker_id: String, defender_id: String, damage: int, killed: int)
signal unit_damaged(unit_id: String, damage: int, killed_count: int)
signal unit_died(unit_id: String, faction: String, unit_data: Resource)
signal unit_status_applied(unit_id: String, effect_name: String, duration: int)
signal unit_status_expired(unit_id: String, effect_name: String)

signal spell_cast(hero_id: String, spell_name: String, targets: Array)
signal morale_triggered(unit_id: String, positive: bool)
signal luck_triggered(unit_id: String)

signal siege_wall_damaged(wall_id: String, remaining_hp: int)
signal siege_wall_destroyed(wall_id: String)
signal siege_gate_opened()
signal siege_gate_destroyed()


# ─────────────────────────────────────────────
#  HERO
# ─────────────────────────────────────────────
signal hero_gained_xp(hero_id: String, amount: int, new_total: int)
signal hero_leveled_up(hero_id: String, new_level: int)
signal hero_skill_learned(hero_id: String, skill_name: String, new_level: int)
signal hero_spell_learned(hero_id: String, spell_name: String)
signal artifact_equipped(hero_id: String, artifact_name: String, slot: String)
signal artifact_unequipped(hero_id: String, artifact_name: String, slot: String)
signal hero_died(hero_id: String)
signal hero_captured(hero_id: String, captor_id: String)


# ─────────────────────────────────────────────
#  TOWN / BUILDINGS
# ─────────────────────────────────────────────
signal building_constructed(town_id: String, building_id: String)
signal creatures_recruited(town_id: String, unit_name: String, count: int)
signal mage_guild_visited(hero_id: String, town_id: String, spells_learned: Array)
signal hero_hired(hero_id: String, town_id: String)


# ─────────────────────────────────────────────
#  ROGUELIKE / RUN
# ─────────────────────────────────────────────
signal run_started(faction: String, difficulty: String, seed: int)
signal run_won(stats: Dictionary)
signal run_lost(cause: String, stats: Dictionary)
signal meta_renown_gained(amount: int, new_total: int)
signal weekly_event_triggered(event_name: String, event_data: Dictionary)
signal map_encounter_triggered(encounter_type: String, data: Dictionary)


# ─────────────────────────────────────────────
#  UI / SCENE
# ─────────────────────────────────────────────
signal scene_transition_requested(scene_path: String, data: Dictionary)
signal tooltip_requested(content: Dictionary, screen_position: Vector2)
signal tooltip_dismissed()
signal notification_requested(message: String, color: Color, duration: float)

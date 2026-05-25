## DamageCalculator.gd
## Pure stateless damage formula — no node, no state.
## All functions are static; instantiate only if you need a named reference.
##
## HoMM3 formula:
##   base   = rand(min_dmg, max_dmg) * stack_count
##   if atk > def:  modifier = 1 + 0.05 * min(atk-def, 60)   → max +300 %
##   if def > atk:  modifier = 1 - 0.025 * min(def-atk, 28)  → min -70 %
##   final  = base * hero_atk_modifier * hero_def_modifier * luck_modifier
class_name DamageCalculator
extends RefCounted


## Main entry point used by CombatScene.
## attacker_hero_attack and defender_hero_defense are the hero's effective
## primary stats (0 if no hero on that side).
static func calculate(
		attacker:             UnitStack,
		defender:             UnitStack,
		attacker_hero_attack: int = 0,
		defender_hero_defense: int = 0,
		is_lucky:             bool = false,
		is_ranged_penalty:    bool = false) -> int:

	# 1. Base damage
	var base: float = float(
		randi_range(attacker.unit_data.min_damage, attacker.unit_data.max_damage)
	) * float(attacker.count)

	# 2. Attack vs Defense
	var atk: int = attacker.effective_attack() + attacker_hero_attack
	var def: int = defender.effective_defense() + defender_hero_defense
	var combat_modifier: float = _combat_modifier(atk, def)

	# 3. Luck doubles base damage (applied before modifiers, matching HoMM3)
	if is_lucky:
		base *= 2.0

	# 4. Ranged penalty (half damage if shooter is adjacent OR blocked LoS)
	if is_ranged_penalty:
		base *= 0.5

	# 5. Final
	var final_damage: int = int(base * combat_modifier)
	return maxi(final_damage, 1)   # minimum 1 damage always


## Returns the fractional combat modifier from attack vs defense.
static func _combat_modifier(atk: int, def: int) -> float:
	if atk >= def:
		var diff: int = mini(atk - def, 60)
		return 1.0 + 0.05 * float(diff)
	else:
		var diff: int = mini(def - atk, 28)
		return 1.0 - 0.025 * float(diff)


## Returns true if a luck proc triggers given a luck value (0–3).
## Probability: 6.25% per luck point.
static func roll_luck(luck: int, rng: RandomNumberGenerator = null) -> bool:
	if luck <= 0:
		return false
	var chance: float = float(luck) * 0.0625
	var roll: float   = randf() if rng == null else rng.randf()
	return roll < chance


## Returns true if a morale proc triggers.
## Positive morale: 8.33%/16.67%/25% per level.
## Negative morale: same chance but of LOSING a turn.
static func roll_morale(morale: int, rng: RandomNumberGenerator = null) -> bool:
	if morale == 0:
		return false
	var chance: float = absf(float(morale)) * 0.0833
	var roll: float   = randf() if rng == null else rng.randf()
	return roll < chance


## Quick helper: returns how many of `defender`'s creatures die from `damage`.
static func creatures_killed(damage: int, defender: UnitStack) -> int:
	if defender.unit_data.hp <= 0:
		return 0
	# First hit drains hp_top, rest kill full-HP creatures
	var overflow: int = damage - defender.hp_top
	if overflow <= 0:
		return 0
	return 1 + overflow / defender.unit_data.hp

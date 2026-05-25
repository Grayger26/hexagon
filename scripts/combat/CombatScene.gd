## CombatScene.gd
## Master controller for one combat encounter.
## Receives setup data via _on_scene_entered(data) from SceneManager.
##
## data dictionary keys:
##   "attacker_army"  : Array[Dictionary]  [{unit_id, count}, ...]  up to 7 entries
##   "defender_army"  : Array[Dictionary]
##   "attacker_hero"  : HeroState or null
##   "defender_hero"  : HeroState or null
##   "is_siege"       : bool (false for now — Milestone 2)
##   "return_scene"   : SceneManager.Scene  (where to go after combat ends)
##
## If called with no data (e.g. launched directly from editor for testing)
## a default hardcoded test battle is used instead.
extends Node2D


# ─────────────────────────────────────────────
#  CHILD NODE PATHS  (set in the .tscn)
# ─────────────────────────────────────────────
@onready var tilemap:       CombatTileMap  = $CombatTileMap
@onready var unit_layer:    Node2D         = $UnitLayer
@onready var ui_layer:      CanvasLayer    = $UILayer
@onready var turn_bar:      HBoxContainer  = $UILayer/TurnOrderBar
@onready var combat_log:    RichTextLabel  = $UILayer/CombatLog
@onready var end_turn_btn:  Button         = $UILayer/BtnEndTurn
@onready var action_hint:   Label          = $UILayer/ActionHint
@onready var result_panel:  PanelContainer = $UILayer/ResultPanel
@onready var result_label:  Label          = $UILayer/ResultPanel/VBox/Label
@onready var result_btn:    Button         = $UILayer/ResultPanel/VBox/BtnContinue


# ─────────────────────────────────────────────
#  COMBAT STATE MACHINE STATES
# ─────────────────────────────────────────────
enum CombatPhase {
	SETUP,          ## populating stacks, not interactive yet
	PLAYER_SELECT,  ## waiting for player to select their active unit
	PLAYER_MOVE,    ## unit selected; showing movement range
	PLAYER_ATTACK,  ## player clicked a reachable hex; showing attack targets
	ENEMY_TURN,     ## AI is acting
	RESOLVE_DAMAGE, ## animation playing, inputs blocked
	COMBAT_OVER,    ## winner determined
}

var phase: CombatPhase = CombatPhase.SETUP


# ─────────────────────────────────────────────
#  RUNTIME DATA
# ─────────────────────────────────────────────
var attacker_hero: Resource = null   ## HeroState or null
var defender_hero: Resource = null
var return_scene: int = SceneManager.Scene.ADVENTURE_MAP

var all_stacks:      Array[UnitStack] = []
var attacker_stacks: Array[UnitStack] = []
var defender_stacks: Array[UnitStack] = []

var turn_manager: CombatTurnManager = CombatTurnManager.new()
var rng: RandomNumberGenerator      = RandomNumberGenerator.new()

## Currently selected/active stack
var active_stack: UnitStack = null

## Hexes highlighted for the current action
var _reachable_hexes: Array[Vector3i] = []
var _attackable_stacks: Array[UnitStack] = []

## Maps hex (Vector3i) → UnitStack for fast lookup
var _hex_to_stack: Dictionary = {}

## Combat log history
var _log_lines: Array[String] = []


# ─────────────────────────────────────────────
#  ENTRY POINT  (called by SceneManager)
# ─────────────────────────────────────────────

func _on_scene_entered(data: Dictionary) -> void:
	rng.randomize()
	if data.is_empty():
		_load_test_battle()
	else:
		attacker_hero = data.get("attacker_hero", null)
		defender_hero = data.get("defender_hero", null)
		return_scene  = data.get("return_scene",
				SceneManager.Scene.ADVENTURE_MAP) as int
		_spawn_armies(
			data.get("attacker_army", []) as Array,
			data.get("defender_army", []) as Array
		)

	_setup_signals()
	tilemap.build_grid(6, rng)
	_build_hex_map()
	turn_manager.build_queue(all_stacks)
	_start_next_turn()


func _ready() -> void:
	# Wire static UI buttons
	end_turn_btn.pressed.connect(_on_end_turn_pressed)
	result_btn.pressed.connect(_on_result_continue)
	result_panel.hide()

	# If opened directly from the editor (no _on_scene_entered call yet)
	if phase == CombatPhase.SETUP and all_stacks.is_empty():
		_on_scene_entered({})


# ─────────────────────────────────────────────
#  ARMY SPAWNING
# ─────────────────────────────────────────────

func _spawn_armies(att_army: Array, def_army: Array) -> void:
	# Attacker deploys in columns 0-1, defender in columns 15-16
	var att_deploy: Array[Vector2i] = [
		Vector2i(0,1), Vector2i(0,3), Vector2i(0,5), Vector2i(0,7), Vector2i(0,9),
		Vector2i(1,2), Vector2i(1,6),
	]
	var def_deploy: Array[Vector2i] = [
		Vector2i(16,1), Vector2i(16,3), Vector2i(16,5), Vector2i(16,7), Vector2i(16,9),
		Vector2i(15,2), Vector2i(15,6),
	]

	for i: int in range(mini(att_army.size(), 7)):
		var entry: Dictionary = att_army[i] as Dictionary
		var unit_id: String   = entry.get("unit_id", "") as String
		var count: int        = entry.get("count",   1)  as int
		var data: UnitData    = DataManager.get_unit(unit_id) as UnitData
		if data == null:
			continue
		var stack := _make_stack(data, count, 0, i, att_deploy[i])
		attacker_stacks.append(stack)
		all_stacks.append(stack)

	for i: int in range(mini(def_army.size(), 7)):
		var entry: Dictionary = def_army[i] as Dictionary
		var unit_id: String   = entry.get("unit_id", "") as String
		var count: int        = entry.get("count",   1)  as int
		var data: UnitData    = DataManager.get_unit(unit_id) as UnitData
		if data == null:
			continue
		var stack := _make_stack(data, count, 1, i, def_deploy[i])
		defender_stacks.append(stack)
		all_stacks.append(stack)


func _make_stack(data: UnitData, count: int, side: int,
		slot: int, offset: Vector2i) -> UnitStack:
	var stack := UnitStack.new()
	stack.init(data, count, side, slot)
	stack.hex = HexGrid.offset_to_cube(offset.x, offset.y)
	stack.position = tilemap.hex_to_local(stack.hex)
	unit_layer.add_child(stack)
	# Flip defender sprites to face left
	if side == 1:
		stack.scale.x = -1.0
	return stack


func _build_hex_map() -> void:
	_hex_to_stack.clear()
	for s: UnitStack in all_stacks:
		if not s.is_dead():
			_hex_to_stack[s.hex] = s


func _update_hex_map_for(stack: UnitStack, old_hex: Vector3i) -> void:
	_hex_to_stack.erase(old_hex)
	if not stack.is_dead():
		_hex_to_stack[stack.hex] = stack


# ─────────────────────────────────────────────
#  TURN FLOW
# ─────────────────────────────────────────────

func _start_next_turn() -> void:
	active_stack = turn_manager.current_stack()
	if active_stack == null:
		return

	active_stack.tick_effects()
	EventBus.unit_turn_started.emit(active_stack.stack_id)
	_refresh_turn_bar()
	_log("── Round %d — %s's turn" % [turn_manager.round_number(),
		active_stack.unit_data.unit_name])

	# Roll morale at turn start
	if not active_stack.unit_data.has_ability("morale_immune"):
		var morale: int = _get_side_morale(active_stack.side)
		if DamageCalculator.roll_morale(morale, rng):
			if morale > 0:
				_log("✦ %s surges with high morale — acts again!" \
					% active_stack.unit_data.unit_name)
				EventBus.morale_triggered.emit(active_stack.stack_id, true)
				# High morale: advance then give another turn (simple impl)
				# Full double-turn handled in Milestone 2; here we just note it
			else:
				_log("✦ %s is paralysed by low morale — loses turn!" \
					% active_stack.unit_data.unit_name)
				EventBus.morale_triggered.emit(active_stack.stack_id, false)
				turn_manager.advance()
				_start_next_turn()
				return

	# Player controls side 0; AI controls side 1
	if active_stack.side == 0:
		_enter_player_select()
	else:
		_run_ai_turn()


func _enter_player_select() -> void:
	phase = CombatPhase.PLAYER_SELECT
	_deselect_all()
	active_stack.set_selected(true)
	_show_reachable(active_stack)
	_set_hint("Click a blue hex to move  |  Click a red enemy to attack  |  W = Wait  |  D = Defend")


func _on_end_turn_pressed() -> void:
	# "End Turn" in combat = pass / defend for now
	if phase in [CombatPhase.PLAYER_SELECT, CombatPhase.PLAYER_MOVE, CombatPhase.PLAYER_ATTACK]:
		_finish_player_turn()


func _finish_player_turn() -> void:
	_deselect_all()
	tilemap.clear_highlights()
	tilemap.clear_cursor()
	EventBus.unit_turn_ended.emit(active_stack.stack_id)
	turn_manager.advance()
	_start_next_turn()


# ─────────────────────────────────────────────
#  INPUT
# ─────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if phase == CombatPhase.COMBAT_OVER:
		return

	# Keyboard shortcuts
	if event is InputEventKey and event.pressed:
		var key := event as InputEventKey
		if key.keycode == KEY_W:
			_action_wait()
			return
		if key.keycode == KEY_D:
			_action_defend()
			return

	# Mouse
	if not (event is InputEventMouse):
		return

	var mouse_local: Vector2 = tilemap.get_local_mouse_position()
	var hovered_hex: Vector3i = tilemap.local_pos_to_hex(mouse_local)

	if not HexGrid.is_in_bounds(hovered_hex):
		tilemap.clear_cursor()
		return

	tilemap.set_cursor(hovered_hex)

	if event is InputEventMouseMotion:
		_on_hover(hovered_hex)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_on_click(hovered_hex)


func _on_hover(_hex: Vector3i) -> void:
	## Path preview removed — movement overlay is sufficient.
	## Cursor glow is handled by set_cursor() in _unhandled_input.
	pass


func _on_click(hex: Vector3i) -> void:
	match phase:
		CombatPhase.PLAYER_SELECT, CombatPhase.PLAYER_MOVE:
			var stack_at_hex: UnitStack = _hex_to_stack.get(hex, null) as UnitStack

			# Clicked an enemy → attack if adjacent or is ranged
			if stack_at_hex != null and stack_at_hex.side != active_stack.side:
				_try_attack(stack_at_hex)
				return

			# Clicked a friendly → select that stack instead
			if stack_at_hex != null and stack_at_hex.side == active_stack.side:
				if stack_at_hex != active_stack and not stack_at_hex.has_acted:
					_deselect_all()
					active_stack = stack_at_hex
					active_stack.set_selected(true)
					_show_reachable(active_stack)
				return

			# Clicked empty reachable hex → move
			if hex in _reachable_hexes:
				_action_move(hex)


## Internal helper: moves `stack` to `target_hex` silently (no phase change,
## no highlight update). Used by _try_attack for auto-move-then-attack.
func _move_stack_to(stack: UnitStack, target_hex: Vector3i) -> void:
	var old_hex: Vector3i = stack.hex
	stack.hex      = target_hex
	stack.position = tilemap.hex_to_local(target_hex)
	_update_hex_map_for(stack, old_hex)
	EventBus.unit_moved.emit(stack.stack_id, old_hex, target_hex)
	_log("%s moves to attack." % stack.unit_data.unit_name)


## Player explicitly clicked an empty hex — move there and show attack options.
func _action_move(target_hex: Vector3i) -> void:
	phase = CombatPhase.PLAYER_MOVE
	var old_hex: Vector3i = active_stack.hex

	active_stack.hex      = target_hex
	active_stack.position = tilemap.hex_to_local(target_hex)
	_update_hex_map_for(active_stack, old_hex)

	EventBus.unit_moved.emit(active_stack.stack_id, old_hex, target_hex)
	_log("%s moves." % active_stack.unit_data.unit_name)

	tilemap.clear_highlights()
	tilemap.clear_cursor()
	_show_attackable(active_stack)
	phase = CombatPhase.PLAYER_ATTACK


func _try_attack(target: UnitStack) -> void:
	## HoMM3 attack flow:
	## 1. Ranged unit: shoot from current hex (full damage).
	##    Exception: if an enemy is adjacent to the shooter, it must melee-attack
	##    that enemy instead (half damage = ranged_penalty applied).
	## 2. Melee unit: auto-move to the nearest free hex adjacent to the target,
	##    then attack. Move is only possible if that hex is within movement range.

	var is_ranged: bool = active_stack.unit_data.is_ranged \
		and active_stack.ammo_remaining > 0

	## Check whether any enemy is already adjacent to this stack (blocks ranged).
	var enemy_adjacent: bool = false
	for s: UnitStack in (defender_stacks if active_stack.side == 0 else attacker_stacks):
		if not s.is_dead() and _is_adjacent(active_stack.hex, s.hex):
			enemy_adjacent = true
			break

	if is_ranged and not enemy_adjacent:
		## Pure ranged shot — no movement needed.
		_perform_attack(active_stack, target)
		_finish_player_turn()
		return

	if is_ranged and enemy_adjacent:
		## Forced melee: ranged unit attacked while enemy is adjacent.
		## Only legal if the target IS the adjacent enemy.
		if _is_adjacent(active_stack.hex, target.hex):
			_perform_attack(active_stack, target)   ## ranged_penalty detected in _perform_attack
			_finish_player_turn()
		return

	## Melee path: auto-move to an adjacent hex, then strike.
	if _is_adjacent(active_stack.hex, target.hex):
		## Already adjacent — attack immediately.
		_perform_attack(active_stack, target)
		_finish_player_turn()
		return

	## Find the best free adjacent hex reachable this turn.
	var adj_free: Vector3i = _nearest_free_adjacent_in_range(active_stack, target)
	if adj_free == Vector3i.ZERO:
		## Target unreachable this turn — do nothing (player must move manually first).
		_log("%s can't reach %s this turn." % [
			active_stack.unit_data.unit_name, target.unit_data.unit_name])
		return

	## Silently move to the adjacent hex then attack.
	_move_stack_to(active_stack, adj_free)
	_perform_attack(active_stack, target)
	_finish_player_turn()


func _action_wait() -> void:
	if phase not in [CombatPhase.PLAYER_SELECT, CombatPhase.PLAYER_MOVE]:
		return
	_log("%s waits." % active_stack.unit_data.unit_name)
	_deselect_all()
	tilemap.clear_highlights()
	turn_manager.wait_current()
	# Don't call advance — wait_current already removed it from front
	_start_next_turn()


func _action_defend() -> void:
	if phase not in [CombatPhase.PLAYER_SELECT, CombatPhase.PLAYER_MOVE]:
		return
	# Apply defend buff (+defense modifier lasting 1 turn)
	active_stack.add_effect("defend", 0.3, 1, "defense")
	_log("%s defends." % active_stack.unit_data.unit_name)
	turn_manager.defend_current()
	_deselect_all()
	tilemap.clear_highlights()
	_start_next_turn()


# ─────────────────────────────────────────────
#  ATTACK RESOLUTION
# ─────────────────────────────────────────────

func _perform_attack(attacker: UnitStack, defender: UnitStack) -> void:
	phase = CombatPhase.RESOLVE_DAMAGE

	var att_hero_atk: int = 0
	var def_hero_def: int = 0
	if attacker_hero != null and attacker.side == 0:
		att_hero_atk = (attacker_hero as HeroState).effective_attack()
	if defender_hero != null and defender.side == 1:
		def_hero_def = (defender_hero as HeroState).effective_defense()

	# Luck roll
	var luck: int   = _get_side_luck(attacker.side)
	var is_lucky: bool = DamageCalculator.roll_luck(luck, rng)
	if is_lucky:
		_log("★ Lucky hit!")
		EventBus.luck_triggered.emit(attacker.stack_id)

	# Ranged penalty: shooter adjacent to ANY enemy OR no line of sight
	var ranged_penalty: bool = false
	if attacker.unit_data.is_ranged:
		attacker.ammo_remaining -= 1
		var blocked: Array[Vector3i] = _get_blocked_hexes(null)
		if not HexGrid.has_line_of_sight(attacker.hex, defender.hex, blocked):
			ranged_penalty = true
		else:
			for s: UnitStack in all_stacks:
				if s.side != attacker.side and not s.is_dead() \
						and _is_adjacent(attacker.hex, s.hex):
					ranged_penalty = true
					break

	# Damage
	var damage: int = DamageCalculator.calculate(
		attacker, defender, att_hero_atk, def_hero_def, is_lucky, ranged_penalty)
	var killed: int = defender.apply_damage(damage)

	EventBus.unit_attacked.emit(attacker.stack_id, defender.stack_id, damage, killed)
	EventBus.unit_damaged.emit(defender.stack_id, damage, killed)

	_log("%s attacks %s: %d damage, %d killed." % [
		attacker.unit_data.unit_name,
		defender.unit_data.unit_name,
		damage, killed
	])

	if defender.is_dead():
		_on_stack_died(defender)
	else:
		# Retaliation (once per round, if not no_retaliation ability, melee only)
		if not attacker.unit_data.has_ability("no_retaliation") \
				and not defender.unit_data.is_ranged \
				and not defender.has_retaliated:
			defender.has_retaliated = true
			_perform_retaliation(defender, attacker)

	_check_combat_over()
	phase = CombatPhase.PLAYER_SELECT


func _perform_retaliation(retaliator: UnitStack, target: UnitStack) -> void:
	if retaliator.is_dead():
		return
	var damage: int = DamageCalculator.calculate(retaliator, target)
	var killed: int = target.apply_damage(damage)
	_log("  ↩ %s retaliates: %d damage, %d killed." % [
		retaliator.unit_data.unit_name, damage, killed
	])
	EventBus.unit_attacked.emit(retaliator.stack_id, target.stack_id, damage, killed)
	if target.is_dead():
		_on_stack_died(target)


func _on_stack_died(stack: UnitStack) -> void:
	_log("☠ %s eliminated!" % stack.unit_data.unit_name)
	EventBus.unit_died.emit(stack.stack_id, stack.unit_data.faction, stack.unit_data)
	_hex_to_stack.erase(stack.hex)
	turn_manager.remove_stack(stack)
	if stack in attacker_stacks:
		attacker_stacks.erase(stack)
	if stack in defender_stacks:
		defender_stacks.erase(stack)


# ─────────────────────────────────────────────
#  AI TURN  (simple: move toward nearest enemy, attack if possible)
# ─────────────────────────────────────────────

func _run_ai_turn() -> void:
	phase = CombatPhase.ENEMY_TURN
	await get_tree().create_timer(0.55).timeout   ## brief pause so player can see

	var ai_stack: UnitStack = active_stack
	if ai_stack == null or ai_stack.is_dead():
		turn_manager.advance()
		_start_next_turn()
		return

	# Find nearest enemy
	var target: UnitStack = _find_nearest_enemy(ai_stack)
	if target == null:
		_log("%s has no targets — skipping." % ai_stack.unit_data.unit_name)
		turn_manager.advance()
		_start_next_turn()
		return

	# Ranged AI: stay put and shoot
	if ai_stack.unit_data.is_ranged and ai_stack.ammo_remaining > 0:
		_perform_attack(ai_stack, target)
		turn_manager.advance()
		_start_next_turn()
		return

	# Flying: go straight to adjacent hex of target
	if ai_stack.unit_data.is_flying:
		var dest: Vector3i = _nearest_free_adjacent(ai_stack.hex, target)
		if dest != Vector3i.ZERO:
			var old_hex: Vector3i = ai_stack.hex
			ai_stack.hex      = dest
			ai_stack.position = tilemap.hex_to_local(dest)
			_update_hex_map_for(ai_stack, old_hex)

	# Melee: move toward target
	else:
		var blocked: Array[Vector3i]   = _get_blocked_hexes(ai_stack)
		var reachable: Array[Vector3i] = HexGrid.get_reachable(
			ai_stack.hex, ai_stack.movement_left, blocked)

		# Pick closest reachable hex to target
		var best_hex: Vector3i = ai_stack.hex
		var best_dist: int     = HexGrid.hex_distance(ai_stack.hex, target.hex)
		for h: Vector3i in reachable:
			var d: int = HexGrid.hex_distance(h, target.hex)
			if d < best_dist:
				best_dist = d
				best_hex  = h

		if best_hex != ai_stack.hex:
			var old_hex: Vector3i = ai_stack.hex
			ai_stack.hex      = best_hex
			ai_stack.position = tilemap.hex_to_local(best_hex)
			_update_hex_map_for(ai_stack, old_hex)
			EventBus.unit_moved.emit(ai_stack.stack_id, old_hex, best_hex)

	# Attack if now adjacent
	if _is_adjacent(ai_stack.hex, target.hex):
		_perform_attack(ai_stack, target)

	if not _check_combat_over():
		turn_manager.advance()
		_start_next_turn()


# ─────────────────────────────────────────────
#  COMBAT OVER
# ─────────────────────────────────────────────

func _check_combat_over() -> bool:
	var att_alive: bool = attacker_stacks.any(func(s: UnitStack) -> bool: return not s.is_dead())
	var def_alive: bool = defender_stacks.any(func(s: UnitStack) -> bool: return not s.is_dead())

	if att_alive and def_alive:
		return false

	phase = CombatPhase.COMBAT_OVER
	tilemap.clear_highlights()
	tilemap.clear_cursor()

	var result: String
	if att_alive:
		result = "victory"
		_show_result("VICTORY!")
		_log("═══ Attacker wins! ═══")
	elif def_alive:
		result = "defeat"
		_show_result("DEFEAT")
		_log("═══ Defender wins! ═══")
	else:
		result = "draw"
		_show_result("DRAW")
		_log("═══ Both sides wiped out! ═══")

	var survivors: Array[UnitStack] = all_stacks.filter(
		func(s: UnitStack) -> bool: return not s.is_dead())
	EventBus.combat_ended.emit(result, survivors)
	GameState.increment_stat("battles_won" if result == "victory" else "battles_lost")
	return true


func _on_result_continue() -> void:
	SceneManager.go_to(return_scene as SceneManager.Scene)


# ─────────────────────────────────────────────
#  HIGHLIGHT HELPERS
# ─────────────────────────────────────────────

func _show_reachable(stack: UnitStack) -> void:
	tilemap.clear_highlights()
	var blocked: Array[Vector3i]   = _get_blocked_hexes(stack)
	_reachable_hexes               = HexGrid.get_reachable(
		stack.hex, stack.movement_left, blocked)
	tilemap.highlight_movement(_reachable_hexes)
	_show_attackable(stack)


func _show_attackable(stack: UnitStack) -> void:
	_attackable_stacks.clear()
	var attackable_hexes: Array[Vector3i] = []

	if stack.unit_data.is_ranged and stack.ammo_remaining > 0:
		# Ranged: all enemies are targets
		for s: UnitStack in (defender_stacks if stack.side == 0 else attacker_stacks):
			if not s.is_dead():
				_attackable_stacks.append(s)
				attackable_hexes.append(s.hex)
	else:
		# Melee: enemies adjacent to current position OR reachable position
		var enemies: Array[UnitStack] = (
			defender_stacks if stack.side == 0 else attacker_stacks)
		for enemy: UnitStack in enemies:
			if enemy.is_dead():
				continue
			if _is_adjacent(stack.hex, enemy.hex):
				_attackable_stacks.append(enemy)
				attackable_hexes.append(enemy.hex)
			else:
				# Can we reach a hex adjacent to this enemy?
				if _nearest_free_adjacent(stack.hex, enemy) != Vector3i.ZERO:
					_attackable_stacks.append(enemy)
					attackable_hexes.append(enemy.hex)

	tilemap.highlight_attack(attackable_hexes)


# ─────────────────────────────────────────────
#  UTILITY
# ─────────────────────────────────────────────

func _get_blocked_hexes(exclude: UnitStack) -> Array[Vector3i]:
	var blocked: Array[Vector3i] = []
	blocked.append_array(tilemap.obstacle_hexes)
	for s: UnitStack in all_stacks:
		if s == exclude or s.is_dead():
			continue
		blocked.append(s.hex)
	return blocked


func _is_adjacent(a: Vector3i, b: Vector3i) -> bool:
	return HexGrid.hex_distance(a, b) == 1


## Returns the nearest hex adjacent to `target` that is free AND within
## `stack`'s current movement range. Returns Vector3i.ZERO if none found.
func _nearest_free_adjacent_in_range(stack: UnitStack, target: UnitStack) -> Vector3i:
	var blocked: Array[Vector3i] = _get_blocked_hexes(stack)
	var reachable: Array[Vector3i] = HexGrid.get_reachable(
		stack.hex, stack.movement_left, blocked)
	var best: Vector3i = Vector3i.ZERO
	var best_dist: int = 9999
	for nb: Vector3i in HexGrid.get_neighbours(target.hex):
		if not HexGrid.is_in_bounds(nb): continue
		if nb in blocked: continue
		if nb not in reachable: continue
		var d: int = HexGrid.hex_distance(stack.hex, nb)
		if d < best_dist:
			best_dist = d
			best = nb
	return best


func _nearest_free_adjacent(from_hex: Vector3i, target: UnitStack) -> Vector3i:
	var blocked: Array[Vector3i] = _get_blocked_hexes(null)
	var best: Vector3i   = Vector3i.ZERO
	var best_dist: int   = 9999
	for nb: Vector3i in HexGrid.get_neighbours(target.hex):
		if not HexGrid.is_in_bounds(nb):
			continue
		if nb in blocked:
			continue
		var d: int = HexGrid.hex_distance(from_hex, nb)
		if d < best_dist:
			best_dist = d
			best       = nb
	return best


func _find_nearest_enemy(stack: UnitStack) -> UnitStack:
	var enemies: Array[UnitStack] = (
		attacker_stacks if stack.side == 1 else defender_stacks)
	var nearest: UnitStack = null
	var min_dist: int      = 9999
	for e: UnitStack in enemies:
		if e.is_dead():
			continue
		var d: int = HexGrid.hex_distance(stack.hex, e.hex)
		if d < min_dist:
			min_dist = d
			nearest  = e
	return nearest


func _get_side_morale(side: int) -> int:
	var hero: Resource = attacker_hero if side == 0 else defender_hero
	if hero == null:
		return 0
	return (hero as HeroState).effective_morale()


func _get_side_luck(side: int) -> int:
	var hero: Resource = attacker_hero if side == 0 else defender_hero
	if hero == null:
		return 0
	return (hero as HeroState).effective_luck()


func _deselect_all() -> void:
	for s: UnitStack in all_stacks:
		s.set_selected(false)


# ─────────────────────────────────────────────
#  UI HELPERS
# ─────────────────────────────────────────────

func _set_hint(text: String) -> void:
	if action_hint:
		action_hint.text = text


func _show_result(text: String) -> void:
	result_label.text = text
	result_panel.show()


func _log(text: String) -> void:
	_log_lines.append(text)
	if _log_lines.size() > 80:
		_log_lines.pop_front()
	if combat_log:
		combat_log.text = "\n".join(_log_lines)
		# Scroll to bottom
		await get_tree().process_frame
		combat_log.scroll_to_line(combat_log.get_line_count() - 1)


func _refresh_turn_bar() -> void:
	if turn_bar == null:
		return
	for child: Node in turn_bar.get_children():
		child.queue_free()
	var queue: Array[UnitStack] = turn_manager.queue_snapshot()
	for i: int in range(mini(queue.size(), 12)):
		var s: UnitStack = queue[i]
		var icon := ColorRect.new()
		icon.custom_minimum_size = Vector2(36, 36)
		icon.color = Color(0.6, 0.1, 0.1) if s.side == 1 else Color(0.1, 0.35, 0.6)
		if s == active_stack:
			icon.color = icon.color.lightened(0.3)
		var lbl := Label.new()
		lbl.text = s.unit_data.unit_name.left(4)
		lbl.add_theme_font_size_override("font_size", 9)
		icon.add_child(lbl)
		turn_bar.add_child(icon)


# ─────────────────────────────────────────────
#  SIGNALS
# ─────────────────────────────────────────────

func _setup_signals() -> void:
	EventBus.unit_died.connect(_on_unit_died_signal)


func _on_unit_died_signal(_unit_id: String, _faction: String, _data: Resource) -> void:
	GameState.increment_stat("creatures_killed")


# ─────────────────────────────────────────────
#  TEST / FALLBACK BATTLE
# ─────────────────────────────────────────────

func _load_test_battle() -> void:
	# Hardcoded test armies so the scene works without any .tres files.
	# Two manually created UnitData instances — replace with real .tres once available.
	var swordsman := _make_test_unit("swordsman",  "Swordsman",  "castle",
		7, 7, 3, 7, 25, 4, 5,  false, "res://assets/sprites/swordman.png")
	var archer    := _make_test_unit("archer",     "Archer",     "castle",
		6, 3, 2, 4, 10, 4, 4,  true,  "res://assets/sprites/archer.png")
	var goblin    := _make_test_unit("goblin",     "Goblin",     "stronghold",
		4, 2, 1, 2,  5, 5, 3,  false, "res://assets/sprites/enemy_swordman.png")
	var wolf      := _make_test_unit("wolf_rider", "Wolf Rider", "stronghold",
		5, 4, 2, 5, 20, 6, 5,  false, "res://assets/sprites/enemy_archer.png")

	var att_army: Array = [
		{"unit_id": "swordsman", "count": 20},
		{"unit_id": "archer",    "count": 15},
	]
	var def_army: Array = [
		{"unit_id": "goblin",     "count": 30},
		{"unit_id": "wolf_rider", "count": 12},
	]

	# Register in DataManager's cache directly for this session
	DataManager.units["swordsman"]  = swordsman
	DataManager.units["archer"]     = archer
	DataManager.units["goblin"]     = goblin
	DataManager.units["wolf_rider"] = wolf

	_spawn_armies(att_army, def_army)


func _make_test_unit(id: String, name: String, faction: String,
		atk: int, def: int, min_d: int, max_d: int, hp: int,
		spd: int, mov: int,
		ranged: bool = false,
		sprite_path: String = "") -> UnitData:
	var d := UnitData.new()
	d.id        = id
	d.unit_name = name
	d.faction   = faction
	d.attack    = atk
	d.defense   = def
	d.min_damage = min_d
	d.max_damage = max_d
	d.hp        = hp
	d.speed     = spd
	d.movement  = mov
	d.is_ranged = ranged
	d.ammo      = 12 if ranged else 0
	if sprite_path != "" and ResourceLoader.exists(sprite_path):
		d.sprite_idle = load(sprite_path) as Texture2D
	return d

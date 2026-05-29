## UnitStack.gd
## Runtime entity for one stack of creatures on the combat grid.
## Holds mutable combat state — HP, position, effects, ammo, etc.
## The immutable blueprint lives in UnitData.gd.
##
## Signals upward to CombatScene via EventBus (never direct references).
class_name UnitStack
extends Node2D


# ─────────────────────────────────────────────
#  DATA
# ─────────────────────────────────────────────
var unit_data: UnitData = null   ## immutable blueprint

var stack_id:  String  = ""     ## unique id for this stack in this combat
var side:      int     = 0      ## 0 = attacker (left), 1 = defender (right)
var slot_index: int    = 0      ## 0–6 slot in the hero's army

# ─────────────────────────────────────────────
#  MUTABLE COMBAT STATE
# ─────────────────────────────────────────────
var count:          int = 0     ## living creatures in the stack
var hp_top:         int = 0     ## HP of the "top" creature (takes damage first)
								## remaining creatures all have full HP

var has_acted:      bool = false   ## used this turn
var has_retaliated: bool = false   ## has used its one free retaliation this round
var has_waited:     bool = false   ## used Wait action (goes at end of round)

var ammo_remaining: int = 0     ## shots left (only meaningful if is_ranged)
var movement_left:  int = 0     ## hex steps remaining this turn

## Active effects: Array of { name, value, duration, stat_affected }
var active_effects: Array[Dictionary] = []


# ─────────────────────────────────────────────
#  HEX POSITION
# ─────────────────────────────────────────────
var hex: Vector3i = Vector3i.ZERO   ## current cube position on the grid


# ─────────────────────────────────────────────
#  VISUAL NODES  (set up in _ready)
# ─────────────────────────────────────────────
var _sprite:     Sprite2D
var _count_label: Label
var _selected_ring: Node2D   ## highlight drawn around this unit when selected


# ─────────────────────────────────────────────
#  SETUP
# ─────────────────────────────────────────────

func _ready() -> void:
	_build_visuals()
	_refresh_visuals()


## Initialise from a UnitData blueprint + starting count.
func init(data: UnitData, starting_count: int, p_side: int, p_slot: int) -> void:
	unit_data   = data
	count       = starting_count
	side        = p_side
	slot_index  = p_slot
	stack_id    = "%s_%d_%d" % [data.id, p_side, p_slot]

	hp_top         = data.hp
	ammo_remaining = data.ammo
	movement_left  = data.movement
	has_acted      = false
	has_retaliated = false
	has_waited     = false
	active_effects = []

	_refresh_visuals()


# ─────────────────────────────────────────────
#  HP & DAMAGE
# ─────────────────────────────────────────────

## Total effective HP of the whole stack.
func total_hp() -> int:
	return (count - 1) * unit_data.hp + hp_top


## Max possible HP (all creatures full).
func max_total_hp() -> int:
	return count * unit_data.hp


## Apply raw damage. Returns the number of creatures killed.
func apply_damage(damage: int) -> int:
	var killed: int = 0
	var remaining_damage: int = damage

	# Drain hp_top first
	if remaining_damage >= hp_top:
		remaining_damage -= hp_top
		killed += 1
		count  -= 1
		hp_top  = unit_data.hp   # reset for next creature

	# Kill full-HP creatures
	if count > 0 and remaining_damage > 0:
		var full_kills: int = remaining_damage / unit_data.hp
		full_kills = mini(full_kills, count - 1)   # always leave top creature
		killed          += full_kills
		count           -= full_kills
		remaining_damage = remaining_damage - full_kills * unit_data.hp

	# Apply leftover to the new top creature
	if count > 0 and remaining_damage > 0:
		hp_top -= remaining_damage
		if hp_top <= 0:
			hp_top  = unit_data.hp
			count  -= 1
			killed += 1

	count = maxi(count, 0)
	if count == 0:
		hp_top = 0

	_refresh_visuals()
	return killed


## Heal the stack (cannot exceed original count passed on init — simple version).
func apply_heal(amount: int) -> void:
	hp_top = mini(hp_top + amount, unit_data.hp)
	_refresh_visuals()


func is_dead() -> bool:
	return count <= 0


# ─────────────────────────────────────────────
#  STATUS EFFECTS
# ─────────────────────────────────────────────

func add_effect(effect_name: String, value: float, duration: int,
		stat_affected: String = "") -> void:
	# Replace existing effect of same name
	for i: int in range(active_effects.size()):
		if (active_effects[i] as Dictionary)["name"] as String == effect_name:
			active_effects[i] = {
				"name": effect_name, "value": value,
				"duration": duration, "stat_affected": stat_affected
			}
			EventBus.unit_status_applied.emit(stack_id, effect_name, duration)
			return
	active_effects.append({
		"name": effect_name, "value": value,
		"duration": duration, "stat_affected": stat_affected
	})
	EventBus.unit_status_applied.emit(stack_id, effect_name, duration)


## Decrement all effect durations; remove expired ones.
## Call at the start of this stack's turn.
func tick_effects() -> void:
	var still_active: Array[Dictionary] = []
	for effect: Variant in active_effects:
		var e: Dictionary = effect as Dictionary
		var new_dur: int  = (e["duration"] as int) - 1
		if new_dur > 0:
			e["duration"] = new_dur
			still_active.append(e)
		else:
			EventBus.unit_status_expired.emit(stack_id, e["name"] as String)
	active_effects = still_active


func has_effect(effect_name: String) -> bool:
	for effect: Variant in active_effects:
		if (effect as Dictionary)["name"] as String == effect_name:
			return true
	return false


func get_effect_value(effect_name: String) -> float:
	for effect: Variant in active_effects:
		var e: Dictionary = effect as Dictionary
		if e["name"] as String == effect_name:
			return e["value"] as float
	return 0.0


# ─────────────────────────────────────────────
#  EFFECTIVE STAT HELPERS
## These return the stat value after applying active buffs/debuffs.
# ─────────────────────────────────────────────

func effective_attack() -> int:
	return unit_data.attack + _effect_bonus("attack")

func effective_defense() -> int:
	return maxi(0, unit_data.defense + _effect_bonus("defense"))

func effective_speed() -> int:
	return maxi(1, unit_data.speed + _effect_bonus("speed"))

func _effect_bonus(stat: String) -> int:
	var total: int = 0
	for effect: Variant in active_effects:
		var e: Dictionary = effect as Dictionary
		if e["stat_affected"] as String == stat:
			total += int(e["value"] as float)
	return total


# ─────────────────────────────────────────────
#  TURN RESET
# ─────────────────────────────────────────────

func reset_for_new_round() -> void:
	has_acted      = false
	has_retaliated = false
	movement_left  = effective_speed()   ## speed also acts as movement in HoMM3
	## Note: has_waited intentionally NOT reset here — handled by TurnManager


# ─────────────────────────────────────────────
#  SELECTION VISUAL
# ─────────────────────────────────────────────

func set_selected(selected: bool) -> void:
	if _selected_ring:
		_selected_ring.visible = selected


# ─────────────────────────────────────────────
#  VISUALS
# ─────────────────────────────────────────────

func _build_visuals() -> void:
	# Sprite — fills the 32×32 tile exactly, no background box.
	# Centred on the node origin (Sprite2D default is centred).
	_sprite = Sprite2D.new()
	_sprite.scale = Vector2(1.0, 1.0)
	add_child(_sprite)

	# Small count badge — dark pill at bottom-right, showing stack size.
	# Sized in tile-local coords (tile = 32px), small enough not to obscure the sprite.
	var badge_bg := ColorRect.new()
	badge_bg.size     = Vector2(14, 10)
	badge_bg.position = Vector2(4, 7)
	badge_bg.color    = Color(0.0, 0.0, 0.0, 0.72)
	add_child(badge_bg)

	_count_label = Label.new()
	_count_label.position = Vector2(4, 5)
	_count_label.size     = Vector2(14, 10)
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_count_label.add_theme_font_size_override("font_size", 8)
	_count_label.add_theme_color_override("font_color", Color.WHITE)
	add_child(_count_label)

	# Selection ring
	_selected_ring = _make_selection_ring()
	_selected_ring.visible = false
	add_child(_selected_ring)


func _make_selection_ring() -> Node2D:
	var ring := Node2D.new()
	# Drawn as a simple script-drawn polygon outline in _draw
	# We use a child Node2D with a script so it can override _draw
	var drawer := _RingDrawer.new()
	ring.add_child(drawer)
	return ring


func _refresh_visuals() -> void:
	if not is_inside_tree():
		return
	if _sprite and unit_data:
		_sprite.texture = unit_data.sprite_idle
	if is_dead():
		modulate = Color(0.4, 0.4, 0.4, 0.5)
		return
	modulate = Color.WHITE
	if _count_label:
		_count_label.text = str(count)


func _hp_color(ratio: float) -> Color:
	if ratio > 0.6:
		return Color(0.1, 0.85, 0.1)   # green
	elif ratio > 0.3:
		return Color(0.95, 0.75, 0.1)  # yellow
	else:
		return Color(0.9, 0.15, 0.1)   # red


## Inner helper class for drawing the selection ring outline.
## Defined here to keep everything in one file.
class _RingDrawer extends Node2D:
	func _draw() -> void:
		draw_arc(Vector2.ZERO, 22.0, 0.0, TAU, 32, Color(1.0, 0.85, 0.1), 2.5)

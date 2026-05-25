## HeroState.gd
## Mutable runtime state for one hero during an active run.
## Created from a HeroData archetype by HeroFactory (Milestone 4).
## GameState.player_hero points to an instance of this.
class_name HeroState
extends Resource

var hero_data: HeroData = null
var hero_id:   String   = ""

# ── PRIMARY STATS ─────────────────────────────────────────────────────────────
var attack:      int = 1
var defense:     int = 1
var spell_power: int = 1
var knowledge:   int = 1

# ── PROGRESSION ───────────────────────────────────────────────────────────────
var level:      int = 1
var current_xp: int = 0

func xp_for_next_level() -> int:
	return 1000 * level * level

func xp_progress_ratio() -> float:
	var prev := 1000 * (level - 1) * (level - 1)
	var span := xp_for_next_level() - prev
	return 0.0 if span <= 0 else float(current_xp - prev) / float(span)

# ── SECONDARY SKILLS ──────────────────────────────────────────────────────────
## skill_id -> level (1=Basic 2=Advanced 3=Expert)
var secondary_skills: Dictionary = {}

const MAX_SECONDARY_SKILLS := 8
const MAX_SKILL_LEVEL       := 3

func has_skill(skill_id: String) -> bool:
	return secondary_skills.has(skill_id)

func get_skill_level(skill_id: String) -> int:
	return secondary_skills.get(skill_id, 0)

func can_learn_skill(skill_id: String) -> bool:
	if has_skill(skill_id):
		return secondary_skills[skill_id] < MAX_SKILL_LEVEL
	return secondary_skills.size() < MAX_SECONDARY_SKILLS

func learn_skill(skill_id: String) -> void:
	if has_skill(skill_id):
		secondary_skills[skill_id] = mini(secondary_skills[skill_id] + 1, MAX_SKILL_LEVEL)
	else:
		secondary_skills[skill_id] = 1

func skills_full() -> bool:
	if secondary_skills.size() < MAX_SECONDARY_SKILLS:
		return false
	for lvl in secondary_skills.values():
		if lvl < MAX_SKILL_LEVEL:
			return false
	return true

# ── SPELLBOOK ─────────────────────────────────────────────────────────────────
var known_spells: Array[String] = []
var current_mana: int = 0

func max_mana() -> int:
	return knowledge * 10

func has_spell(spell_id: String) -> bool:
	return spell_id in known_spells

func learn_spell(spell_id: String) -> void:
	if not has_spell(spell_id):
		known_spells.append(spell_id)

func restore_mana(amount: int = -1) -> void:
	current_mana = max_mana() if amount < 0 else mini(current_mana + amount, max_mana())

func spend_mana(amount: int) -> bool:
	if current_mana < amount:
		return false
	current_mana -= amount
	return true

# ── ARTIFACTS ─────────────────────────────────────────────────────────────────
const ARTIFACT_SLOTS: Array[String] = [
	"head","neck","torso","hand_left","hand_right",
	"ring_left","ring_right","feet","misc",
]

var equipped_artifacts: Dictionary = {}   ## slot -> ArtifactData or null
var backpack: Array[Resource] = []

func equip_artifact(artifact: Resource, slot: String) -> bool:
	if slot not in ARTIFACT_SLOTS:
		push_error("[HeroState] Invalid slot: %s" % slot)
		return false
	if equipped_artifacts.get(slot) != null:
		backpack.append(equipped_artifacts[slot])
	equipped_artifacts[slot] = artifact
	EventBus.artifact_equipped.emit(hero_id, artifact.id, slot)
	return true

func get_artifact_in_slot(slot: String) -> Resource:
	return equipped_artifacts.get(slot, null)

# ── ARMY (7 slots) ────────────────────────────────────────────────────────────
const ARMY_SLOTS := 7
var army: Array = []   ## Array[Dictionary|null], size 7

func init_army() -> void:
	army.resize(ARMY_SLOTS)
	army.fill(null)

func add_unit(unit_id: String, count: int) -> bool:
	for i in range(ARMY_SLOTS):
		if army[i] != null and army[i]["unit_id"] == unit_id:
			army[i]["count"] += count
			return true
	for i in range(ARMY_SLOTS):
		if army[i] == null:
			army[i] = {"unit_id": unit_id, "count": count}
			return true
	push_warning("[HeroState] Army full — cannot add %s x%d" % [unit_id, count])
	return false

func remove_unit_stack(slot_index: int) -> void:
	if slot_index >= 0 and slot_index < ARMY_SLOTS:
		army[slot_index] = null

func army_is_empty() -> bool:
	for slot in army:
		if slot != null:
			return false
	return true

# ── MAP ───────────────────────────────────────────────────────────────────────
var map_position:        Vector2i = Vector2i.ZERO
var movement_points:     int      = 0
var movement_points_max: int      = 1500

# ── WAR MACHINES ──────────────────────────────────────────────────────────────
var has_ballista:  bool = false
var has_ammo_cart: bool = false
var has_first_aid: bool = false

# ── COMPUTED STATS (include artifact bonuses) ─────────────────────────────────
func effective_attack()      -> int: return attack      + _artifact_bonus("attack")
func effective_defense()     -> int: return defense     + _artifact_bonus("defense")
func effective_spell_power() -> int: return spell_power + _artifact_bonus("spell_power")
func effective_knowledge()   -> int: return knowledge   + _artifact_bonus("knowledge")

func effective_morale() -> int:
	var b := get_skill_level("leadership") + _artifact_bonus("morale")
	return clampi(b, -3, 3)

func effective_luck() -> int:
	var b := get_skill_level("luck") + _artifact_bonus("luck")
	return clampi(b, 0, 3)

func _artifact_bonus(stat: String) -> int:
	var total := 0
	for slot in equipped_artifacts:
		var a = equipped_artifacts[slot]
		if a != null and a.stat_bonuses.has(stat):
			total += a.stat_bonuses[stat]
	return total

# ── SERIALISATION ─────────────────────────────────────────────────────────────
func to_dict() -> Dictionary:
	return {
		"hero_id":      hero_id,
		"level":        level,
		"current_xp":   current_xp,
		"attack":       attack,
		"defense":      defense,
		"spell_power":  spell_power,
		"knowledge":    knowledge,
		"current_mana": current_mana,
		"secondary_skills": secondary_skills.duplicate(),
		"known_spells":     known_spells.duplicate(),
		"army":             army.duplicate(true),
		"map_position":     [map_position.x, map_position.y],
		"movement_points":  movement_points,
		"has_ballista":     has_ballista,
		"has_ammo_cart":    has_ammo_cart,
		"has_first_aid":    has_first_aid,
	}

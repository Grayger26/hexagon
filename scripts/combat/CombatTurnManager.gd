## CombatTurnManager.gd
## Owns turn order for a combat encounter.
## Sorted by effective Speed descending; attacker side breaks ties.
##
## Usage:
##   turn_manager.build_queue(all_stacks)
##   var acting = turn_manager.current_stack()
##   turn_manager.advance()   # after the stack has acted
class_name CombatTurnManager
extends RefCounted


# ─────────────────────────────────────────────
#  STATE
# ─────────────────────────────────────────────
var _queue:        Array[UnitStack] = []   ## ordered for this round
var _wait_queue:   Array[UnitStack] = []   ## stacks that used Wait
var _round_number: int = 0
var _all_stacks:   Array[UnitStack] = []   ## full roster (living + dead tracked here)


# ─────────────────────────────────────────────
#  PUBLIC API
# ─────────────────────────────────────────────

## Call once at combat start (and after every new round) with ALL living stacks.
func build_queue(stacks: Array[UnitStack]) -> void:
	_all_stacks = stacks.duplicate()
	_rebuild_round_queue()
	_round_number += 1
	EventBus.combat_round_started.emit(_round_number)


## The stack that should act right now.
func current_stack() -> UnitStack:
	if _queue.is_empty():
		return null
	return _queue[0]


## Call after the active stack has finished its action.
## Handles Wait stacks being appended to the end.
func advance() -> void:
	if _queue.is_empty():
		return

	var acted: UnitStack = _queue.pop_front()
	acted.has_acted = true

	# If this was a waited stack now acting, clear its wait flag
	if acted.has_waited:
		acted.has_waited = false

	_clean_dead()

	# If main queue is empty, flush wait_queue then start new round
	if _queue.is_empty():
		if not _wait_queue.is_empty():
			# Waited stacks act in their original speed order at end of round
			_queue = _wait_queue.duplicate()
			_wait_queue.clear()
		else:
			_end_round()


## Move the current stack to the end of this round (Wait action).
func wait_current() -> void:
	if _queue.is_empty():
		return
	var stack: UnitStack = _queue.pop_front()
	stack.has_waited = true
	_wait_queue.append(stack)


## Defend: stack skips its turn this round (acts immediately but gains defense buff).
## The buff is applied by CombatScene — TurnManager just advances.
func defend_current() -> void:
	advance()


## Remove a dead stack from both queues mid-round.
func remove_stack(stack: UnitStack) -> void:
	_queue.erase(stack)
	_wait_queue.erase(stack)
	_all_stacks.erase(stack)


func round_number() -> int:
	return _round_number


func queue_snapshot() -> Array[UnitStack]:
	var snap: Array[UnitStack] = _queue.duplicate()
	snap.append_array(_wait_queue)
	return snap


# ─────────────────────────────────────────────
#  INTERNAL
# ─────────────────────────────────────────────

func _rebuild_round_queue() -> void:
	_queue.clear()
	_wait_queue.clear()

	var living: Array[UnitStack] = []
	for s: UnitStack in _all_stacks:
		if not s.is_dead():
			s.reset_for_new_round()
			living.append(s)

	# Sort: highest effective_speed first; attacker (side==0) breaks ties
	living.sort_custom(func(a: UnitStack, b: UnitStack) -> bool:
		var sa: int = a.effective_speed()
		var sb: int = b.effective_speed()
		if sa != sb:
			return sa > sb
		return a.side < b.side   # attacker goes first on equal speed
	)
	_queue = living


func _clean_dead() -> void:
	var i: int = _queue.size() - 1
	while i >= 0:
		if _queue[i].is_dead():
			_queue.remove_at(i)
		i -= 1
	i = _wait_queue.size() - 1
	while i >= 0:
		if _wait_queue[i].is_dead():
			_wait_queue.remove_at(i)
		i -= 1


func _end_round() -> void:
	EventBus.combat_round_ended.emit(_round_number)
	# Rebuild for next round with all surviving stacks
	var surviving: Array[UnitStack] = []
	for s: UnitStack in _all_stacks:
		if not s.is_dead():
			surviving.append(s)
	_all_stacks = surviving
	_rebuild_round_queue()
	_round_number += 1
	EventBus.combat_round_started.emit(_round_number)

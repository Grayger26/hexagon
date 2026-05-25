## StateMachine.gd
## Reusable base class for all state machines in the project.
## Usage:
##   1. Extend StateMachine in your manager script.
##   2. Create inner classes (or separate scripts) that extend State.
##   3. Call transition_to(MyState.new()) to switch states.
class_name StateMachine
extends Node


class State:
	var machine: StateMachine = null

	func enter(_data: Dictionary = {}) -> void:
		pass

	func exit() -> void:
		pass

	## Called every _process frame while this state is active.
	func update(_delta: float) -> void:
		pass

	## Called every _physics_process frame.
	func physics_update(_delta: float) -> void:
		pass

	## Called on unhandled input. Return true to consume the event.
	func handle_input(_event: InputEvent) -> bool:
		return false

	## Convenience shortcut — ask the machine to transition.
	func transition_to(new_state: State, data: Dictionary = {}) -> void:
		machine.transition_to(new_state, data)

	func state_name() -> String:
		return "State"


# ─────────────────────────────────────────────

var current_state:  State = null
var previous_state: State = null

@export var debug_transitions: bool = false


func _process(delta: float) -> void:
	if current_state:
		current_state.update(delta)


func _physics_process(delta: float) -> void:
	if current_state:
		current_state.physics_update(delta)


func _unhandled_input(event: InputEvent) -> void:
	if current_state:
		current_state.handle_input(event)


func transition_to(new_state: State, data: Dictionary = {}) -> void:
	if new_state == null:
		push_error("[StateMachine] transition_to called with null state.")
		return
	if debug_transitions:
		var from := current_state.state_name() if current_state else "null"
		print("[StateMachine] %s → %s" % [from, new_state.state_name()])
	if current_state:
		current_state.exit()
		previous_state = current_state
	new_state.machine = self
	current_state = new_state
	current_state.enter(data)


func transition_to_previous(data: Dictionary = {}) -> void:
	if previous_state == null:
		push_warning("[StateMachine] No previous state to return to.")
		return
	transition_to(previous_state, data)


func current_state_name() -> String:
	return current_state.state_name() if current_state else "none"

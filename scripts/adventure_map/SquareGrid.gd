## SquareGrid.gd
## Cartesian-coordinate grid utilities for the adventure map.
## 8-directional movement (cardinal + diagonal) matching HoMM3's adventure map.
class_name SquareGrid
extends RefCounted


## Tile size in pixels (matches the atlas tile size).
const TILE_SIZE: int = 32

## All 8 movement directions: cardinal + diagonal.
## Cardinal directions listed first so straight-line paths are preferred
## over zigzag paths when A* f-values are tied (common with Chebyshev heuristic
## on a uniform-cost 8-dir grid).
const DIRECTIONS_MOVE: Array[Vector2i] = [
	Vector2i( 0, -1),  ## N
	Vector2i( 1,  0),  ## E
	Vector2i( 0,  1),  ## S
	Vector2i(-1,  0),  ## W
	Vector2i( 1, -1),  ## NE
	Vector2i( 1,  1),  ## SE
	Vector2i(-1,  1),  ## SW
	Vector2i(-1, -1),  ## NW
]

## 8-directional direction vectors (used for path-arrow texture lookup).
## Indexed so that any Vector2i difference maps to its position in this array.
const DIRECTIONS_8: Array[Vector2i] = [
	Vector2i(-1, -1),  ## NW
	Vector2i( 0, -1),  ## N
	Vector2i( 1, -1),  ## NE
	Vector2i(-1,  0),  ## W
	Vector2i( 0,  0),  ## self / target
	Vector2i( 1,  0),  ## E
	Vector2i(-1,  1),  ## SW
	Vector2i( 0,  1),  ## S
	Vector2i( 1,  1),  ## SE
]

## Atlas coordinates for each 8-direction vector in path_arrows.png (3x3 grid).
## Layout: row 0 = NW / N / NE, row 1 = W / + / E, row 2 = SW / S / SE.
## Each arrow's arrowhead is at the corner matching its atlas position;
## the shaft extends toward the opposite corner.
const DIRECTION_ARROW_ATLAS: Dictionary = {
	Vector2i(-1, -1): Vector2i(0, 0),  ## NW
	Vector2i( 0, -1): Vector2i(1, 0),  ## N
	Vector2i( 1, -1): Vector2i(2, 0),  ## NE
	Vector2i(-1,  0): Vector2i(0, 1),  ## W
	Vector2i( 0,  0): Vector2i(1, 1),  ## target marker
	Vector2i( 1,  0): Vector2i(2, 1),  ## E
	Vector2i(-1,  1): Vector2i(0, 2),  ## SW
	Vector2i( 0,  1): Vector2i(1, 2),  ## S
	Vector2i( 1,  1): Vector2i(2, 2),  ## SE
}

## Movement cost per standard tile.
const BASE_MOVE_COST: int = 100


## Return the 8 neighbours of a tile (cardinal + diagonal).
static func get_neighbours(tile: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for d: Vector2i in DIRECTIONS_MOVE:
		result.append(tile + d)
	return result


## Chebyshev distance for 8-directional movement.
## Since diagonal moves have the same cost as cardinal, this is the
## admissible heuristic: max(|dx|, |dy|).
static func chebyshev_distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


## A* pathfinding on a square grid.
## Returns an ordered Array[Vector2i] of steps from `start` to `goal`
## (excluding start, including goal). Returns an empty Array if no path exists.
## `blocked`  — tiles the path cannot enter.
## `max_cost` — if > 0, stop searching once the accumulated path cost exceeds this.
##              Used to cap pathfinding to the player's remaining movement points.
static func find_path(
		start:   Vector2i,
		goal:    Vector2i,
		blocked: Array[Vector2i] = [],
		max_cost: int = -1) -> Array[Vector2i]:
	if start == goal:
		return []
	if goal in blocked:
		return []

	var blocked_set: Dictionary = {}
	for b: Vector2i in blocked:
		blocked_set[b] = true

	var open:   Array[Dictionary] = []
	var closed: Dictionary = {}

	open.append({
		"tile": start,
		"g": 0,
		"f": chebyshev_distance(start, goal),
		"parent": null,
	})

	while not open.is_empty():
		# Find lowest-f in open (simple linear scan — fine for small grids)
		var best_idx: int = 0
		for i: int in range(1, open.size()):
			if (open[i]["f"] as int) < (open[best_idx]["f"] as int):
				best_idx = i
		var cur: Dictionary = open[best_idx]
		open.remove_at(best_idx)

		var tile: Vector2i = cur["tile"] as Vector2i
		if tile == goal:
			return _reconstruct_path(cur)

		closed[tile] = true

		for nb: Vector2i in get_neighbours(tile):
			if nb in blocked_set:
				continue
			if closed.has(nb):
				continue

			var g: int = (cur["g"] as int) + BASE_MOVE_COST
			if max_cost > 0 and g > max_cost:
				continue  # beyond movement budget

			var f: int = g + chebyshev_distance(nb, goal)

			# Skip if a better path to this tile already exists
			var skip: bool = false
			for entry: Variant in open:
				var e: Dictionary = entry as Dictionary
				if e["tile"] as Vector2i == nb and (e["g"] as int) <= g:
					skip = true
					break
			if not skip:
				open.append({
					"tile": nb,
					"g": g,
					"f": f,
					"parent": cur,
				})

	return []  # no path found


## Reconstruct the path from A* metadata.
static func _reconstruct_path(node: Dictionary) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var cur: Variant = node
	while cur != null:
		var d: Dictionary = cur as Dictionary
		if d["parent"] != null:
			path.push_front(d["tile"] as Vector2i)
		cur = d["parent"]
	return path

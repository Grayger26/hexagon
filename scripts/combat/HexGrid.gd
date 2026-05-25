## HexGrid.gd
## Pure math library for a flat-top hex grid using cube coordinates (q, r, s).
## q + r + s == 0 always.
##
## Flat-top = flat edge at top and bottom, pointy corners left and right.
##
## Tile pixel dimensions match the 32×32 PNG atlas tiles.
## IMPORTANT: pixel↔hex conversion here is only used for mouse input.
## All unit/tile positioning uses TileMapLayer.map_to_local() instead,
## which guarantees it always matches Godot's internal tile spacing.
##
## Grid: 17 columns × 11 rows. Attacker left (low q), defender right (high q).
class_name HexGrid
extends RefCounted


# ── GRID DIMENSIONS ───────────────────────────────────────────────────────────
const COLS: int = 17
const ROWS: int = 11

## Pixel dimensions of one tile in the atlas PNG.
const TILE_W: int = 32
const TILE_H: int = 32

## Flat-top hex spacing used by Godot's TileMapLayer (TILE_LAYOUT_STAIRS_RIGHT):
##   horizontal step = TILE_W * 0.75  (columns overlap by 25%)
##   vertical step   = TILE_H         (rows don't overlap)
##   odd-column offset = TILE_H / 2   (every other column is staggered down)
const HEX_COL_STEP:    float = TILE_W * 0.75          # = 24
const HEX_ROW_STEP:    float = float(TILE_H)           # = 32
const HEX_STAGGER:     float = float(TILE_H) * 0.5    # = 16

## Legacy aliases kept so other scripts that reference HEX_W / HEX_H still compile.
const HEX_W: float = float(TILE_W)
const HEX_H: float = float(TILE_H)
const HEX_SIZE: float = float(TILE_W) * 0.5   # half-width = "radius" in Godot terms


# ── COORDINATE CONVERSION ─────────────────────────────────────────────────────

## Offset (col, row) — "even-q" / STAIRS_RIGHT layout — → cube coords.
static func offset_to_cube(col: int, row: int) -> Vector3i:
	var q: int = col
	var r: int = row - (col - (col & 1)) / 2
	return Vector3i(q, r, -q - r)


## Cube coords → offset (col, row) for TileMapLayer cell addressing.
static func cube_to_offset(cube: Vector3i) -> Vector2i:
	var col: int = cube.x
	var row: int = cube.y + (cube.x - (cube.x & 1)) / 2
	return Vector2i(col, row)


## Pixel position (local to TileMapLayer) → nearest cube hex.
## Matches Godot's STAIRS_RIGHT / flat-top spacing exactly.
static func pixel_to_hex(pos: Vector2) -> Vector3i:
	# Reverse of Godot's map_to_local for STAIRS_RIGHT flat-top:
	# col ≈ pos.x / HEX_COL_STEP  (then snap to nearest)
	# row depends on whether col is even or odd
	var col_f: float = pos.x / HEX_COL_STEP
	var col: int     = roundi(col_f)
	var stagger: float = HEX_STAGGER if (col & 1) == 1 else 0.0
	var row: int = roundi((pos.y - stagger) / HEX_ROW_STEP)
	# Clamp to grid bounds before converting
	col = clampi(col, 0, COLS - 1)
	row = clampi(row, 0, ROWS - 1)
	return offset_to_cube(col, row)


# ── DISTANCE & NEIGHBOURS ─────────────────────────────────────────────────────

static func hex_distance(a: Vector3i, b: Vector3i) -> int:
	return (abs(a.x - b.x) + abs(a.y - b.y) + abs(a.z - b.z)) / 2


const DIRECTIONS: Array[Vector3i] = [
	Vector3i( 1, -1,  0),   # E
	Vector3i( 1,  0, -1),   # NE
	Vector3i( 0,  1, -1),   # NW
	Vector3i(-1,  1,  0),   # W
	Vector3i(-1,  0,  1),   # SW
	Vector3i( 0, -1,  1),   # SE
]

static func get_neighbours(hex: Vector3i) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for d: Vector3i in DIRECTIONS:
		result.append(hex + d)
	return result


static func get_hexes_in_range(origin: Vector3i, radius: int) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for dq: int in range(-radius, radius + 1):
		for dr: int in range(max(-radius, -dq - radius), min(radius, -dq + radius) + 1):
			var ds: int = -dq - dr
			var hex := Vector3i(origin.x + dq, origin.y + dr, origin.z + ds)
			if hex != origin:
				result.append(hex)
	return result


static func is_in_bounds(hex: Vector3i) -> bool:
	var off: Vector2i = cube_to_offset(hex)
	return off.x >= 0 and off.x < COLS and off.y >= 0 and off.y < ROWS


# ── PATHFINDING ───────────────────────────────────────────────────────────────

static func get_reachable(
		start:      Vector3i,
		move_range: int,
		blocked:    Array[Vector3i]) -> Array[Vector3i]:
	var visited: Dictionary      = {}
	var frontier: Array          = [{"hex": start, "cost": 0}]
	visited[start]               = 0
	var reachable: Array[Vector3i] = []
	while not frontier.is_empty():
		var current: Dictionary = frontier.pop_front()
		var hex:  Vector3i      = current["hex"]  as Vector3i
		var cost: int           = current["cost"] as int
		for nb: Vector3i in get_neighbours(hex):
			if not is_in_bounds(nb): continue
			if nb in blocked:        continue
			if visited.has(nb):      continue
			var new_cost: int = cost + 1
			if new_cost <= move_range:
				visited[nb] = new_cost
				reachable.append(nb)
				frontier.append({"hex": nb, "cost": new_cost})
	return reachable


static func find_path(
		start:   Vector3i,
		goal:    Vector3i,
		blocked: Array[Vector3i]) -> Array[Vector3i]:
	if start == goal:
		return []
	var open:   Array      = []
	var closed: Dictionary = {}
	open.append({"hex": start, "g": 0, "f": hex_distance(start, goal), "parent": null})
	while not open.is_empty():
		var best_idx: int = 0
		for i: int in range(1, open.size()):
			if (open[i] as Dictionary)["f"] as int < (open[best_idx] as Dictionary)["f"] as int:
				best_idx = i
		var current: Dictionary = open[best_idx] as Dictionary
		open.remove_at(best_idx)
		var hex: Vector3i = current["hex"] as Vector3i
		if hex == goal:
			return _reconstruct_path(current)
		closed[hex] = current
		for nb: Vector3i in get_neighbours(hex):
			if not is_in_bounds(nb): continue
			if nb in blocked:        continue
			if closed.has(nb):       continue
			var g: int = (current["g"] as int) + 1
			var f: int = g + hex_distance(nb, goal)
			var skip: bool = false
			for ex: Variant in open:
				var ed: Dictionary = ex as Dictionary
				if ed["hex"] as Vector3i == nb and (ed["g"] as int) <= g:
					skip = true; break
			if not skip:
				open.append({"hex": nb, "g": g, "f": f, "parent": current})
	return []


static func has_line_of_sight(
		from_hex: Vector3i,
		to_hex:   Vector3i,
		blocked:  Array[Vector3i]) -> bool:
	var n: int = hex_distance(from_hex, to_hex)
	if n == 0: return true
	for i: int in range(1, n):
		var t: float      = float(i) / float(n)
		var sampled: Vector3i = _cube_round(
			lerp(float(from_hex.x), float(to_hex.x), t),
			lerp(float(from_hex.y), float(to_hex.y), t))
		if sampled in blocked: return false
	return true


static func _cube_round(q_f: float, r_f: float) -> Vector3i:
	var s_f: float  = -q_f - r_f
	var q: int      = roundi(q_f)
	var r: int      = roundi(r_f)
	var s: int      = roundi(s_f)
	if absf(float(q) - q_f) > absf(float(r) - r_f) and absf(float(q) - q_f) > absf(float(s) - s_f):
		q = -r - s
	elif absf(float(r) - r_f) > absf(float(s) - s_f):
		r = -q - s
	else:
		s = -q - r
	return Vector3i(q, r, s)


static func _reconstruct_path(node: Dictionary) -> Array[Vector3i]:
	var path: Array[Vector3i] = []
	var current: Variant = node
	while current != null:
		var d: Dictionary = current as Dictionary
		if d["parent"] != null:
			path.push_front(d["hex"] as Vector3i)
		current = d["parent"]
	return path

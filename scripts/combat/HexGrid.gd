## HexGrid.gd
## Cube coordinate hex grid — POINTY-TOP orientation.
##
## Pointy-top = pointy corners at top and bottom, flat edges on left/right sides.
## This matches the 32×32 PNG tiles in assets/tilemaps/hex_tiles.png.
##
## Offset layout used: ODD-R (odd rows shift right by half a tile).
## Matches Godot TileSet: TILE_LAYOUT_STAIRS_RIGHT + TILE_OFFSET_AXIS_VERTICAL.
##
## Cube coords: q + r + s = 0 always.
## q increases right, r increases down, s = -q-r.
##
## Grid: 17 columns × 11 rows.
## Attacker deploys left (low q), defender deploys right (high q).
class_name HexGrid
extends RefCounted


# ── GRID DIMENSIONS ───────────────────────────────────────────────────────────
const COLS: int = 17
const ROWS: int = 11

## Pixel size of one tile in the atlas PNG.
const TILE_W: int = 32
const TILE_H: int = 32

## Pointy-top hex spacing for Godot STAIRS_RIGHT + VERTICAL axis:
##   columns advance by full tile width (no horizontal overlap)
##   rows    advance by tile_height × 0.75 (rows overlap by 25%)
##   odd rows shift right by tile_width / 2
const HEX_COL_STEP: float = float(TILE_W)          ## 32  — horizontal step per column
const HEX_ROW_STEP: float = float(TILE_H) * 0.75   ## 24  — vertical step per row
const HEX_STAGGER:  float = float(TILE_W) * 0.5    ## 16  — odd-row rightward offset

## Legacy aliases kept so callers compile without changes.
const HEX_W:    float = float(TILE_W)
const HEX_H:    float = float(TILE_H)
const HEX_SIZE: float = float(TILE_W) * 0.5


# ── COORDINATE CONVERSION  (odd-r offset) ────────────────────────────────────

## Offset (col, row) → cube. Odd-r: odd rows shift right.
static func offset_to_cube(col: int, row: int) -> Vector3i:
	var q: int = col - (row - (row & 1)) / 2
	var r: int = row
	return Vector3i(q, r, -q - r)


## Cube → offset (col, row).
static func cube_to_offset(cube: Vector3i) -> Vector2i:
	var col: int = cube.x + (cube.y - (cube.y & 1)) / 2
	var row: int = cube.y
	return Vector2i(col, row)


## Local pixel position → nearest cube hex.
## Reverses Godot's map_to_local for STAIRS_RIGHT + VERTICAL pointy-top.
static func pixel_to_hex(pos: Vector2) -> Vector3i:
	## Estimate row first (rows advance by HEX_ROW_STEP = 24px).
	var row_f: float = pos.y / HEX_ROW_STEP
	var row: int     = roundi(row_f)
	## Odd rows are offset right by HEX_STAGGER = 16px.
	var stagger: float = HEX_STAGGER if (row & 1) == 1 else 0.0
	var col: int = roundi((pos.x - stagger) / HEX_COL_STEP)
	col = clampi(col, 0, COLS - 1)
	row = clampi(row, 0, ROWS - 1)
	return offset_to_cube(col, row)


# ── DISTANCE & NEIGHBOURS ─────────────────────────────────────────────────────

static func hex_distance(a: Vector3i, b: Vector3i) -> int:
	return (abs(a.x - b.x) + abs(a.y - b.y) + abs(a.z - b.z)) / 2


## The 6 cube-coordinate directions (same for all hex orientations).
const DIRECTIONS: Array[Vector3i] = [
	Vector3i( 1,  0, -1),   ## E
	Vector3i( 1, -1,  0),   ## NE
	Vector3i( 0, -1,  1),   ## NW
	Vector3i(-1,  0,  1),   ## W
	Vector3i(-1,  1,  0),   ## SW
	Vector3i( 0,  1, -1),   ## SE
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
			var hex := Vector3i(origin.x + dq, origin.y + dr, -origin.x - dq - origin.y - dr)
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
	var visited: Dictionary       = {}
	var frontier: Array           = [{"hex": start, "cost": 0}]
	visited[start]                = 0
	var reachable: Array[Vector3i] = []
	while not frontier.is_empty():
		var current: Dictionary = frontier.pop_front()
		var hex:  Vector3i     = current["hex"]  as Vector3i
		var cost: int          = current["cost"] as int
		for nb: Vector3i in get_neighbours(hex):
			if not is_in_bounds(nb): continue
			if nb in blocked:        continue
			if visited.has(nb):      continue
			var nc: int = cost + 1
			if nc <= move_range:
				visited[nb] = nc
				reachable.append(nb)
				frontier.append({"hex": nb, "cost": nc})
	return reachable


static func find_path(
		start:   Vector3i,
		goal:    Vector3i,
		blocked: Array[Vector3i]) -> Array[Vector3i]:
	if start == goal:
		return []
	var open:   Array      = [{"hex": start, "g": 0,
		"f": hex_distance(start, goal), "parent": null}]
	var closed: Dictionary = {}
	while not open.is_empty():
		var bi: int = 0
		for i: int in range(1, open.size()):
			if (open[i] as Dictionary)["f"] as int < (open[bi] as Dictionary)["f"] as int:
				bi = i
		var cur: Dictionary = open[bi] as Dictionary
		open.remove_at(bi)
		var hex: Vector3i = cur["hex"] as Vector3i
		if hex == goal:
			return _reconstruct_path(cur)
		closed[hex] = cur
		for nb: Vector3i in get_neighbours(hex):
			if not is_in_bounds(nb): continue
			if nb in blocked:        continue
			if closed.has(nb):       continue
			var g: int = (cur["g"] as int) + 1
			var f: int = g + hex_distance(nb, goal)
			var skip: bool = false
			for ex: Variant in open:
				var ed: Dictionary = ex as Dictionary
				if ed["hex"] as Vector3i == nb and (ed["g"] as int) <= g:
					skip = true; break
			if not skip:
				open.append({"hex": nb, "g": g, "f": f, "parent": cur})
	return []


static func has_line_of_sight(
		from_hex: Vector3i,
		to_hex:   Vector3i,
		blocked:  Array[Vector3i]) -> bool:
	var n: int = hex_distance(from_hex, to_hex)
	if n == 0: return true
	for i: int in range(1, n):
		var t: float = float(i) / float(n)
		var s: Vector3i = _cube_round(
			lerp(float(from_hex.x), float(to_hex.x), t),
			lerp(float(from_hex.y), float(to_hex.y), t))
		if s in blocked: return false
	return true


static func _cube_round(q_f: float, r_f: float) -> Vector3i:
	var s_f: float = -q_f - r_f
	var q: int = roundi(q_f)
	var r: int = roundi(r_f)
	var s: int = roundi(s_f)
	if absf(float(q)-q_f) > absf(float(r)-r_f) and absf(float(q)-q_f) > absf(float(s)-s_f):
		q = -r - s
	elif absf(float(r)-r_f) > absf(float(s)-s_f):
		r = -q - s
	else:
		s = -q - r
	return Vector3i(q, r, s)


static func _reconstruct_path(node: Dictionary) -> Array[Vector3i]:
	var path: Array[Vector3i] = []
	var cur: Variant = node
	while cur != null:
		var d: Dictionary = cur as Dictionary
		if d["parent"] != null:
			path.push_front(d["hex"] as Vector3i)
		cur = d["parent"]
	return path

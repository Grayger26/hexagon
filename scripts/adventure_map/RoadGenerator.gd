## RoadGenerator.gd
## Generates road networks for the adventure map.
## Uses a hybrid approach:
##   - Cardinal roads (N/S/E/W) are placed via the TileSet terrain system,
##     which auto-selects straights, corners, T-junctions, etc.
##   - Pure diagonal tiles (no cardinal neighbours) are placed manually
##     with set_cell() since the terrain system only derives corner
##     peering bits from cardinal side bits and cannot resolve
##     corner-only tiles on its own.
##   - Corner cap fill tiles are placed at cardinal positions around
##     diagonal tiles to smooth the staircase visual.
class_name RoadGenerator
extends RefCounted


# ── DIRECTION HELPERS ───────────────────────────────────────────────────────────

const DIR_N:  int = 1 << 0
const DIR_NE: int = 1 << 1
const DIR_E:  int = 1 << 2
const DIR_SE: int = 1 << 3
const DIR_S:  int = 1 << 4
const DIR_SW: int = 1 << 5
const DIR_W:  int = 1 << 6
const DIR_NW: int = 1 << 7

## Neighbour offset for each direction bit.
const DIR_OFFSETS: Dictionary = {
	DIR_N:  Vector2i( 0, -1),
	DIR_NE: Vector2i( 1, -1),
	DIR_E:  Vector2i( 1,  0),
	DIR_SE: Vector2i( 1,  1),
	DIR_S:  Vector2i( 0,  1),
	DIR_SW: Vector2i(-1,  1),
	DIR_W:  Vector2i(-1,  0),
	DIR_NW: Vector2i(-1, -1),
}

## All 8 direction bits for iteration.
const DIR_BITS: Array[int] = [DIR_N, DIR_NE, DIR_E, DIR_SE, DIR_S, DIR_SW, DIR_W, DIR_NW]

## Cardinal-only bits.
const CARDINAL_BITS: int = DIR_N | DIR_S | DIR_E | DIR_W

## 8 neighbour offsets for quick iteration.
const _NEIGHBOUR_OFFSETS: Array[Vector2i] = [
	Vector2i( 0, -1),  # N
	Vector2i( 1, -1),  # NE
	Vector2i( 1,  0),  # E
	Vector2i( 1,  1),  # SE
	Vector2i( 0,  1),  # S
	Vector2i(-1,  1),  # SW
	Vector2i(-1,  0),  # W
	Vector2i(-1, -1),  # NW
]


# ── DIAGONAL TILE ATLAS LOOKUP ─────────────────────────────────────────────────

const DIAGONAL_BACKSLASH:     Vector2i = Vector2i(2, 4)  # \ (NW + SE connections)
const DIAGONAL_BSLASH_END_SE: Vector2i = Vector2i(4, 4)  # \ SE end cap
const DIAGONAL_BSLASH_END_NW: Vector2i = Vector2i(6, 4)  # \ NW end cap
const DIAGONAL_FORWARDSLASH:   Vector2i = Vector2i(5, 4)  # / (NE + SW connections)
const DIAGONAL_FSLASH_END_NE:  Vector2i = Vector2i(1, 4)  # / NE end cap
const DIAGONAL_FSLASH_END_SW:  Vector2i = Vector2i(2, 3)  # / SW end cap

## Diagonal mask → atlas coordinate for pure diagonal tiles (no cardinal bits).
const _DIAGONAL_TILE_MAP: Dictionary = {
	(DIR_NW | DIR_SE): DIAGONAL_BACKSLASH,       # \ middle
	DIR_SE:            DIAGONAL_BSLASH_END_SE,    # \ SE end
	DIR_NW:            DIAGONAL_BSLASH_END_NW,    # \ NW end
	(DIR_NE | DIR_SW): DIAGONAL_FORWARDSLASH,     # / middle
	DIR_NE:            DIAGONAL_FSLASH_END_NE,    # / NE end
	DIR_SW:            DIAGONAL_FSLASH_END_SW,    # / SW end
}

const SOURCE_ID: int = 0  # map_roads.png is always source 0


# ── CORNER CAP DEFINITIONS ─────────────────────────────────────────────────────
# Fill tiles at cardinal positions around diagonal tiles to smooth the
# staircase visual.

## For \ diagonal (NW→SE, upper-left → bottom-right).
## [offset, atlas_coord]
## N → lower left corner, W → upper right corner, E → lower left corner,
## S → upper right corner.
const _BSLASH_CORNERS: Array = [
	[Vector2i( 0, -1), Vector2i(2, 3)],  # N  → lower left corner  (BL)
	[Vector2i(-1,  0), Vector2i(1, 4)],  # W  → upper right corner (TR)
	[Vector2i( 1,  0), Vector2i(2, 3)],  # E  → lower left corner  (BL)
	[Vector2i( 0,  1), Vector2i(1, 4)],  # S  → upper right corner (TR)
]

## For / diagonal (SW→NE, bottom-right → upper-left).
## N → lower right corner, E → upper left corner, W → lower right corner,
## S → upper right corner.
const _FSLASH_CORNERS: Array = [
	[Vector2i( 0, -1), Vector2i(4, 4)],  # N  → lower right corner (BR)
	[Vector2i( 1,  0), Vector2i(6, 4)],  # E  → upper left corner  (TL)
	[Vector2i(-1,  0), Vector2i(4, 4)],  # W  → lower right corner (BR)
	[Vector2i( 0,  1), Vector2i(1, 4)],  # S  → upper right corner (TR)
]


# ── ROAD NETWORK GENERATION ────────────────────────────────────────────────────

## Generate a road network across the adventure map.
## Returns an Array[Vector2i] of tile positions that should have roads.
static func generate_network(
		rng: RandomNumberGenerator,
		map_cols: int,
		map_rows: int,
		blocked: Array[Vector2i],
		start_tile: Vector2i) -> Array[Vector2i]:

	var blocked_set: Dictionary = {}
	for b: Vector2i in blocked:
		blocked_set[b] = true

	var clear_zone: Dictionary = {}
	for dx: int in range(-3, 4):
		for dy: int in range(-3, 4):
			clear_zone[Vector2i(start_tile.x + dx, start_tile.y + dy)] = true

	var roads: Array[Vector2i] = []
	var road_set: Dictionary = {}

	var margin: int = 3

	# ── Primary horizontal roads ───────────────────────────────────────────
	var h_positions: Array[int] = []
	h_positions.append(rng.randi_range(margin + 1, map_rows / 3 - 1))
	h_positions.append(rng.randi_range(map_rows / 3 + 1, map_rows * 2 / 3))
	h_positions.append(rng.randi_range(map_rows * 2 / 3 + 1, map_rows - margin - 1))

	for hy: int in h_positions:
		var start_x: int = rng.randi_range(margin, margin + 5)
		var end_x: int = rng.randi_range(map_cols - margin - 5, map_cols - margin)
		for x: int in range(start_x, end_x + 1):
			_add_road_tile(Vector2i(x, hy), road_set, roads, blocked_set, clear_zone)

	# ── Primary vertical roads ─────────────────────────────────────────────
	var v_positions: Array[int] = []
	v_positions.append(rng.randi_range(margin + 1, map_cols / 3 - 1))
	v_positions.append(rng.randi_range(map_cols / 3 + 1, map_cols * 2 / 3))
	v_positions.append(rng.randi_range(map_cols * 2 / 3 + 1, map_cols - margin - 1))

	for vx: int in v_positions:
		var start_y: int = rng.randi_range(margin, margin + 3)
		var end_y: int = rng.randi_range(map_rows - margin - 3, map_rows - margin)
		for y: int in range(start_y, end_y + 1):
			_add_road_tile(Vector2i(vx, y), road_set, roads, blocked_set, clear_zone)

	# ── Diagonal roads ( \) — NW→SE ────────────────────────────────────────
	var diag_count: int = rng.randi_range(1, 2)
	for _d: int in range(diag_count):
		var dsx: int = rng.randi_range(margin + 2, map_cols * 2 / 5)
		var dsy: int = rng.randi_range(margin + 2, map_rows * 3 / 5)
		var dlen: int = rng.randi_range(5, 12)
		var dex: int = dsx + dlen
		var dey: int = dsy + dlen
		if dex >= map_cols - margin or dey >= map_rows - margin:
			continue
		for step: int in range(dlen + 1):
			_add_road_tile(Vector2i(dsx + step, dsy + step), road_set, roads, blocked_set, clear_zone)

	# ── Diagonal roads ( / ) — NE→SW ──────────────────────────────────────
	var diag2_count: int = rng.randi_range(0, 1)
	for _d2: int in range(diag2_count):
		var dsx: int = rng.randi_range(map_cols * 2 / 5, map_cols - margin - 8)
		var dsy: int = rng.randi_range(margin + 4, map_rows * 3 / 5)
		var dlen: int = rng.randi_range(5, 10)
		if dsx - dlen < margin or dsy + dlen >= map_rows - margin:
			continue
		for step: int in range(dlen + 1):
			_add_road_tile(Vector2i(dsx - step, dsy + step), road_set, roads, blocked_set, clear_zone)

	return roads


static func _add_road_tile(
		tile: Vector2i,
		road_set: Dictionary,
		roads: Array[Vector2i],
		blocked_set: Dictionary,
		clear_zone: Dictionary) -> void:
	if road_set.has(tile):
		return
	if blocked_set.has(tile):
		return
	if clear_zone.has(tile):
		return
	road_set[tile] = true
	roads.append(tile)


# ── TILE CLASSIFICATION ─────────────────────────────────────────────────────────

static func _get_connection_mask(tile: Vector2i, road_set: Dictionary) -> int:
	var mask: int = 0
	for i: int in 8:
		var offset: Vector2i = _NEIGHBOUR_OFFSETS[i]
		if road_set.has(tile + offset):
			mask |= DIR_BITS[i]
	return mask


## Return true if the mask has at least one \ diagonal bit (NW or SE).
static func _is_backslash(mask: int) -> bool:
	return mask & (DIR_NW | DIR_SE) != 0

## Return true if the mask has at least one / diagonal bit (NE or SW).
static func _is_forwardslash(mask: int) -> bool:
	return mask & (DIR_NE | DIR_SW) != 0


# ── MAIN ENTRY POINT ───────────────────────────────────────────────────────────

static func generate(
		rng: RandomNumberGenerator,
		map_cols: int,
		map_rows: int,
		blocked: Array[Vector2i],
		start_tile: Vector2i) -> Array[Vector2i]:
	return generate_network(rng, map_cols, map_rows, blocked, start_tile)


# ── PLACEMENT ───────────────────────────────────────────────────────────────────

## Place road tiles onto a TileMapLayer.
##
## Strategy:
##   1. Pass cardinal cells to the terrain system (auto-selects straights,
##      corners, T-junctions, etc.).
##   2. Place diagonal tiles + corner cap fill tiles manually using a
##      Dictionary for dedup (avoids terrain-system cell state issues).
static func place(
		road_layer: TileMapLayer,
		road_positions: Array[Vector2i],
		terrain_set: int = 0,
		terrain: int = 0) -> void:
	road_layer.clear()

	if road_positions.is_empty():
		return

	# Build a fast road-set for neighbour lookups
	var road_set: Dictionary = {}
	for pos: Vector2i in road_positions:
		road_set[pos] = true

	# Split positions into cardinal cells (terrain system) and
	# diagonal-only cells (manual placement).
	var cardinal_cells: Array[Vector2i] = []
	var diagonal_cells: Array[Vector2i] = []

	for pos: Vector2i in road_positions:
		var mask: int = _get_connection_mask(pos, road_set)
		if mask & CARDINAL_BITS != 0:
			cardinal_cells.append(pos)
		else:
			diagonal_cells.append(pos)

	# --- Phase 1: terrain system for cardinal roads only ---
	if not cardinal_cells.is_empty():
		road_layer.set_cells_terrain_connect(cardinal_cells, terrain_set, terrain)

	# --- Phase 2: manual diagonal tiles + corner caps ---
	# Use a Dictionary to track all occupied positions for dedup.
	var placed: Dictionary = {}
	for pos: Vector2i in cardinal_cells:
		placed[pos] = true

	for pos: Vector2i in diagonal_cells:
		var mask: int = _get_connection_mask(pos, road_set)
		var diag_mask: int = mask & ~CARDINAL_BITS

		# Place the diagonal tile itself
		var atlas_coord: Vector2i = _DIAGONAL_TILE_MAP.get(diag_mask, DIAGONAL_BACKSLASH)
		road_layer.set_cell(pos, SOURCE_ID, atlas_coord)
		placed[pos] = true

		# Place corner cap fill tiles at cardinal positions
		var corner_defs: Array
		if _is_backslash(diag_mask):
			corner_defs = _BSLASH_CORNERS
		elif _is_forwardslash(diag_mask):
			corner_defs = _FSLASH_CORNERS
		else:
			continue

		for entry: Array in corner_defs:
			var offset: Vector2i = entry[0] as Vector2i
			var cap_tile: Vector2i = entry[1] as Vector2i
			var cap_pos: Vector2i = pos + offset

			if not placed.has(cap_pos):
				road_layer.set_cell(cap_pos, SOURCE_ID, cap_tile)
				placed[cap_pos] = true

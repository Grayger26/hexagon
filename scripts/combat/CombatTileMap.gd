## CombatTileMap.gd
## Three TileMapLayer children on a Node2D parent.
## PNG atlas is 96×64 (3 cols × 2 rows, 32×32 per tile):
##   (0,0) green           — grass terrain
##   (1,0) orange          — unused (kept for future use)
##   (2,0) semi-transparent— movement range overlay  ← TILE_HL_MOVE
##   (0,1) red             — attack highlight + obstacle
##   (1,1) blue            — cursor hover / spell target
##   (2,1) pink            — unused (removed from gameplay use)
##
## THREE LAYERS:
##   TerrainLayer   z=0  permanent: grass + obstacles
##   HighlightLayer z=1  per-turn: movement/attack/spell — cleared each turn
##   CursorLayer    z=2  per-frame: single-hex hover glow — never cleared by highlights
class_name CombatTileMap
extends Node2D


# ── ATLAS COORDS ──────────────────────────────────────────────────────────────
const SRC: int = 0

const TILE_GRASS:     Vector2i = Vector2i(0, 0)   ## green
const TILE_OBSTACLE:  Vector2i = Vector2i(0, 1)   ## red

const TILE_HL_MOVE:   Vector2i = Vector2i(2, 0)   ## semi-transparent — reachable hexes
const TILE_HL_ATTACK: Vector2i = Vector2i(0, 1)   ## red              — attackable
const TILE_HL_SPELL:  Vector2i = Vector2i(1, 1)   ## blue             — spell target

## Path preview removed — movement overlay alone is sufficient.
## highlight_path() is kept as a no-op so callers don't error.

const TILE_CURSOR:    Vector2i = Vector2i(1, 1)   ## blue — hover glow

const TILE_TEXTURE_PATH: String = "res://assets/tilemaps/hex_tiles.png"
const TILE_SIZE: int = 32


# ── LAYERS ────────────────────────────────────────────────────────────────────
var terrain_layer:   TileMapLayer
var highlight_layer: TileMapLayer
var cursor_layer:    TileMapLayer

var obstacle_hexes: Array[Vector3i] = []
var _shared_tileset: TileSet


func _ready() -> void:
	_shared_tileset = _build_tileset()
	terrain_layer   = _get_or_make_layer("TerrainLayer",   0)
	highlight_layer = _get_or_make_layer("HighlightLayer", 1)
	cursor_layer    = _get_or_make_layer("CursorLayer",    2)


func _get_or_make_layer(node_name: String, z_idx: int) -> TileMapLayer:
	var existing: Node = get_node_or_null(node_name)
	if existing is TileMapLayer:
		(existing as TileMapLayer).tile_set = _shared_tileset
		return existing as TileMapLayer
	var layer := TileMapLayer.new()
	layer.name     = node_name
	layer.tile_set = _shared_tileset
	layer.z_index  = z_idx
	add_child(layer)
	return layer


# ── GRID BUILDING ─────────────────────────────────────────────────────────────

func build_grid(obstacle_count: int = 6, rng: RandomNumberGenerator = null) -> void:
	terrain_layer.clear()
	highlight_layer.clear()
	cursor_layer.clear()
	obstacle_hexes.clear()

	for col: int in range(HexGrid.COLS):
		for row: int in range(HexGrid.ROWS):
			terrain_layer.set_cell(Vector2i(col, row), SRC, TILE_GRASS)

	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()

	var candidates: Array[Vector2i] = []
	for col: int in range(5, 12):
		for row: int in range(1, HexGrid.ROWS - 1):
			candidates.append(Vector2i(col, row))

	for _i: int in range(obstacle_count):
		if candidates.is_empty():
			break
		var idx: int       = rng.randi_range(0, candidates.size() - 1)
		var cell: Vector2i = candidates[idx]
		candidates.remove_at(idx)
		terrain_layer.set_cell(cell, SRC, TILE_OBSTACLE)
		obstacle_hexes.append(HexGrid.offset_to_cube(cell.x, cell.y))


# ── HIGHLIGHT API ─────────────────────────────────────────────────────────────

func clear_highlights() -> void:
	highlight_layer.clear()

func highlight_movement(hexes: Array[Vector3i]) -> void:
	_paint(highlight_layer, hexes, TILE_HL_MOVE)

func highlight_attack(hexes: Array[Vector3i]) -> void:
	_paint(highlight_layer, hexes, TILE_HL_ATTACK)

func highlight_spell(hexes: Array[Vector3i]) -> void:
	_paint(highlight_layer, hexes, TILE_HL_SPELL)

## No-op — path preview removed. Keeping signature so call sites compile.
func highlight_path(_hexes: Array[Vector3i]) -> void:
	pass

func _paint(layer: TileMapLayer, hexes: Array[Vector3i], tile: Vector2i) -> void:
	for hex: Vector3i in hexes:
		layer.set_cell(HexGrid.cube_to_offset(hex), SRC, tile)


# ── CURSOR  (isolated layer — never affects HighlightLayer) ──────────────────

func set_cursor(hex: Vector3i) -> void:
	cursor_layer.clear()
	if HexGrid.is_in_bounds(hex):
		cursor_layer.set_cell(HexGrid.cube_to_offset(hex), SRC, TILE_CURSOR)

func clear_cursor() -> void:
	cursor_layer.clear()


# ── COORDINATE HELPERS ────────────────────────────────────────────────────────

func local_pos_to_hex(local_pos: Vector2) -> Vector3i:
	var offset: Vector2i = terrain_layer.local_to_map(local_pos)
	return HexGrid.offset_to_cube(offset.x, offset.y)

func hex_to_local(hex: Vector3i) -> Vector2:
	return terrain_layer.map_to_local(HexGrid.cube_to_offset(hex))


# ── TILESET ───────────────────────────────────────────────────────────────────

func _build_tileset() -> TileSet:
	var ts := TileSet.new()
	ts.tile_shape       = TileSet.TILE_SHAPE_HEXAGON
	ts.tile_layout      = TileSet.TILE_LAYOUT_STAIRS_RIGHT
	ts.tile_offset_axis = TileSet.TILE_OFFSET_AXIS_HORIZONTAL   ## flat-top
	ts.tile_size        = Vector2i(TILE_SIZE, TILE_SIZE)

	var source := TileSetAtlasSource.new()
	if ResourceLoader.exists(TILE_TEXTURE_PATH):
		source.texture = load(TILE_TEXTURE_PATH) as Texture2D
	else:
		push_warning("[CombatTileMap] %s not found — using fallback." % TILE_TEXTURE_PATH)
		source.texture = _make_fallback_texture()
	source.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)

	## All 6 tiles in the 3×2 atlas
	for col: int in range(3):
		for row: int in range(2):
			source.create_tile(Vector2i(col, row))

	ts.add_source(source, SRC)
	return ts


func _make_fallback_texture() -> ImageTexture:
	var img := Image.create(96, 64, false, Image.FORMAT_RGBA8)
	var tiles: Array = [
		[Vector2i(0,0), Color(0.22, 0.55, 0.20, 1.00)],
		[Vector2i(1,0), Color(1.00, 0.64, 0.00, 1.00)],
		[Vector2i(2,0), Color(0.20, 0.70, 0.20, 0.50)],
		[Vector2i(0,1), Color(0.75, 0.15, 0.15, 1.00)],
		[Vector2i(1,1), Color(0.10, 0.55, 0.85, 1.00)],
		[Vector2i(2,1), Color(0.90, 0.40, 0.70, 1.00)],
	]
	for entry: Variant in tiles:
		var arr: Array      = entry as Array
		var coord: Vector2i = arr[0] as Vector2i
		var col: Color      = arr[1] as Color
		for py: int in range(TILE_SIZE):
			for px: int in range(TILE_SIZE):
				img.set_pixel(coord.x * TILE_SIZE + px, coord.y * TILE_SIZE + py, col)
	return ImageTexture.create_from_image(img)

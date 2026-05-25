## CombatTileMap.gd
## Manages three TileMapLayer children for the combat hex grid.
## Parent type: Node2D.
##
## Layers (children, created in _ready if absent):
##   TerrainLayer   (z=0) — base grass/obstacle tiles
##   HighlightLayer (z=1) — move/attack/spell/path overlays
##   CursorLayer    (z=2) — single-hex hover glow
##
## Tileset is built from the PNG at TILE_TEXTURE_PATH (4 tiles, 2×2 layout, 32×32 each).
## Atlas layout:
##   (0,0) = tile 0 — green  — grass / normal terrain
##   (1,0) = tile 1 — orange — highlight move
##   (0,1) = tile 2 — red    — highlight attack / obstacle
##   (1,1) = tile 3 — blue   — cursor / spell highlight
class_name CombatTileMap
extends Node2D


# ── ATLAS COORDS ──────────────────────────────────────────────────────────────
const SRC: int = 0   ## TileSet source id

## Terrain
const TILE_GRASS:     Vector2i = Vector2i(0, 0)   ## green
const TILE_OBSTACLE:  Vector2i = Vector2i(0, 1)   ## red  (reusing red for rocks)

## Highlights — drawn on HighlightLayer on top of terrain
const TILE_HL_MOVE:   Vector2i = Vector2i(1, 0)   ## orange — reachable
const TILE_HL_ATTACK: Vector2i = Vector2i(0, 1)   ## red    — attackable
const TILE_HL_SPELL:  Vector2i = Vector2i(1, 1)   ## blue   — spell target
const TILE_HL_PATH:   Vector2i = Vector2i(1, 1)   ## blue   — path preview (same as spell for now)

## Cursor
const TILE_CURSOR:    Vector2i = Vector2i(1, 1)   ## blue glow on hover

const TILE_TEXTURE_PATH: String = "res://assets/tilemaps/hex_tiles.png"
const TILE_SIZE: int = 32   ## each tile cell in the atlas PNG is 32×32 pixels


# ── LAYER REFERENCES ──────────────────────────────────────────────────────────
var terrain_layer:   TileMapLayer
var highlight_layer: TileMapLayer
var cursor_layer:    TileMapLayer

var obstacle_hexes: Array[Vector3i] = []

var _shared_tileset: TileSet


# ── SETUP ─────────────────────────────────────────────────────────────────────

func _ready() -> void:
	_shared_tileset = _build_tileset()
	terrain_layer   = _get_or_make_layer("TerrainLayer",   0)
	highlight_layer = _get_or_make_layer("HighlightLayer", 1)
	cursor_layer    = _get_or_make_layer("CursorLayer",    2)


func _get_or_make_layer(node_name: String, z_idx: int) -> TileMapLayer:
	var existing: Node = get_node_or_null(node_name)
	if existing is TileMapLayer:
		var existing_layer := existing as TileMapLayer
		existing_layer.tile_set = _shared_tileset
		return existing_layer
	var layer := TileMapLayer.new()
	layer.name     = node_name
	layer.tile_set = _shared_tileset
	layer.z_index  = z_idx
	## Highlight and cursor layers need to be visible but not receive mouse events
	## (TileMapLayer does not extend Control, so no mouse_filter property exists —
	##  mouse picking is handled entirely in CombatScene._unhandled_input).
	add_child(layer)
	return layer


# ── GRID BUILDING ─────────────────────────────────────────────────────────────

func build_grid(obstacle_count: int = 6, rng: RandomNumberGenerator = null) -> void:
	terrain_layer.clear()
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

func highlight_path(hexes: Array[Vector3i]) -> void:
	for cell: Vector2i in highlight_layer.get_used_cells():
		if highlight_layer.get_cell_atlas_coords(cell) == TILE_HL_PATH:
			highlight_layer.erase_cell(cell)
	_paint(highlight_layer, hexes, TILE_HL_PATH)

func _paint(layer: TileMapLayer, hexes: Array[Vector3i], tile: Vector2i) -> void:
	for hex: Vector3i in hexes:
		layer.set_cell(HexGrid.cube_to_offset(hex), SRC, tile)


# ── CURSOR ────────────────────────────────────────────────────────────────────

func set_cursor(hex: Vector3i) -> void:
	cursor_layer.clear()
	if HexGrid.is_in_bounds(hex):
		cursor_layer.set_cell(HexGrid.cube_to_offset(hex), SRC, TILE_CURSOR)

func clear_cursor() -> void:
	cursor_layer.clear()


# ── COORDINATE HELPERS ────────────────────────────────────────────────────────

## Local pixel pos → cube hex. Uses HexGrid math tuned to 32×32 STAIRS_RIGHT.
func local_pos_to_hex(local_pos: Vector2) -> Vector3i:
	## TileMapLayer.local_to_map handles the offset-coord conversion exactly.
	var offset: Vector2i = terrain_layer.local_to_map(local_pos)
	return HexGrid.offset_to_cube(offset.x, offset.y)

## Cube hex → pixel centre in this Node2D's local space.
func hex_to_local(hex: Vector3i) -> Vector2:
	return terrain_layer.map_to_local(HexGrid.cube_to_offset(hex))


# ── TILESET BUILDER ───────────────────────────────────────────────────────────

func _build_tileset() -> TileSet:
	var ts := TileSet.new()
	ts.tile_shape       = TileSet.TILE_SHAPE_HEXAGON
	ts.tile_layout      = TileSet.TILE_LAYOUT_STAIRS_RIGHT
	ts.tile_offset_axis = TileSet.TILE_OFFSET_AXIS_HORIZONTAL   ## flat-top
	ts.tile_size        = Vector2i(TILE_SIZE, TILE_SIZE)

	var source := TileSetAtlasSource.new()

	## Load the real PNG if it exists, otherwise generate coloured placeholders.
	if ResourceLoader.exists(TILE_TEXTURE_PATH):
		source.texture = load(TILE_TEXTURE_PATH) as Texture2D
	else:
		push_warning("[CombatTileMap] Tile texture not found at %s — using fallback colours." \
			% TILE_TEXTURE_PATH)
		source.texture = _make_fallback_texture()

	source.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)

	## Register the four tiles that exist in the 2×2 atlas layout.
	for coord: Vector2i in [Vector2i(0,0), Vector2i(1,0), Vector2i(0,1), Vector2i(1,1)]:
		source.create_tile(coord)

	ts.add_source(source, SRC)
	return ts


## Generates a 64×64 RGBA image with four solid-colour hex-shaped tiles
## (matching the 2×2 layout of the real PNG) as a fallback.
func _make_fallback_texture() -> ImageTexture:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var tile_colours: Array[Color] = [
		Color(0.22, 0.55, 0.20),   ## (0,0) green  — grass
		Color(1.00, 0.64, 0.00),   ## (1,0) orange — move highlight
		Color(0.75, 0.15, 0.15),   ## (0,1) red    — attack / obstacle
		Color(0.10, 0.55, 0.85),   ## (1,1) blue   — cursor / spell
	]
	var positions: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(32, 0), Vector2i(0, 32), Vector2i(32, 32)
	]
	for i: int in range(4):
		var origin: Vector2i = positions[i]
		var col: Color       = tile_colours[i]
		for py: int in range(32):
			for px: int in range(32):
				img.set_pixel(origin.x + px, origin.y + py, col)
	return ImageTexture.create_from_image(img)

## AdventureMap.gd
## Main controller for the adventure map prototype.
## Handles tilemap rendering, player movement, path preview, and movement points.
extends Node2D


# ── CONSTANTS ────────────────────────────────────────────────────────────────────

## Number of columns and rows for the map.
const MAP_COLS: int = 50
const MAP_ROWS: int = 35

## Node scale (2x makes 32px tiles render as 64px on screen).
const MAP_SCALE: float = 2.0

## Player starting tile (roughly center of the map).
const START_TILE: Vector2i = Vector2i(25, 18)

## Obstacle count for random generation.
const OBSTACLE_COUNT: int = 80

## Movement points.
const MAX_MOVE_POINTS: int = 1500

# ── TEXTURE PATHS ────────────────────────────────────────────────────────────────

const SQUARE_TILES_PATH: String = "res://assets/tilemaps/square_tiles.png"
const PATH_ARROWS_PATH: String = "res://assets/tilemaps/path_arrows.png"
const PLAYER_SPRITE_PATH: String = "res://assets/sprites/swordman.png"

# ── SQUARE TILES ATLAS COORDS ────────────────────────────────────────────────────
# square_tiles.png is 64x64, 4 tiles in a 2x2 grid, each 32x32.

const SRC_SQUARE: int = 0
const TILE_GROUND:    Vector2i = Vector2i(0, 0)   # orange
const TILE_OBSTACLE:  Vector2i = Vector2i(1, 0)   # gray
const TILE_OTHER_A:   Vector2i = Vector2i(0, 1)   # brown (unused for now)
const TILE_OTHER_B:   Vector2i = Vector2i(1, 1)   # dark red (unused for now)

# ── PATH ARROWS ATLAS COORDS ─────────────────────────────────────────────────────
# path_arrows.png is 96x96, 9 arrows in a 3x3 grid, each 32x32.

const SRC_ARROW: int = 0

# Direction -> atlas lookup is handled by SquareGrid.DIRECTION_ARROW_ATLAS.
# We store the atlas coords as constants for the TileMapLayer.

# ── MOVEMENT COST ────────────────────────────────────────────────────────────────
const MOVE_COST_PER_TILE: int = 100


# ── STATE ────────────────────────────────────────────────────────────────────────

enum MapPhase {
	IDLE,       # waiting for player input
	MOVING,     # player sprite animating — input blocked
}

var phase: MapPhase = MapPhase.IDLE

var player_tile: Vector2i = START_TILE
var movement_points: int = MAX_MOVE_POINTS

var _blocked_tiles: Array[Vector2i] = []
var _path: Array[Vector2i] = []            # full A* path from player to hovered tile
var _reachable_path: Array[Vector2i] = []  # prefix truncated by movement budget

# ── CHILD NODES ──────────────────────────────────────────────────────────────────

var _terrain_layer: TileMapLayer
var _path_layer:    TileMapLayer
var _player_sprite: Sprite2D
var _camera:        Camera2D
var _move_label:    Label
var _end_turn_btn:  Button
var _tile_info:     Label


# ── ENTRY ────────────────────────────────────────────────────────────────────────

func _ready() -> void:
	_build_tilemaps()
	_generate_map()
	_setup_camera()
	_setup_player()
	_setup_ui()
	_refresh_hud()


# ── TILEMAP SETUP ────────────────────────────────────────────────────────────────

func _build_tilemaps() -> void:
	# --- Terrain layer ---
	_terrain_layer = TileMapLayer.new()
	_terrain_layer.name = "TerrainLayer"
	_terrain_layer.z_index = 0
	_terrain_layer.scale = Vector2(MAP_SCALE, MAP_SCALE)
	_terrain_layer.tile_set = _build_terrain_tileset()
	add_child(_terrain_layer)

	# --- Path arrow layer (sits above terrain) ---
	_path_layer = TileMapLayer.new()
	_path_layer.name = "PathLayer"
	_path_layer.z_index = 1
	_path_layer.scale = Vector2(MAP_SCALE, MAP_SCALE)
	_path_layer.tile_set = _build_arrow_tileset()
	add_child(_path_layer)


func _build_terrain_tileset() -> TileSet:
	var ts := TileSet.new()
	ts.tile_shape       = TileSet.TILE_SHAPE_SQUARE
	ts.tile_layout      = TileSet.TILE_LAYOUT_STACKED
	ts.tile_offset_axis = TileSet.TILE_OFFSET_AXIS_HORIZONTAL
	ts.tile_size        = Vector2i(SquareGrid.TILE_SIZE, SquareGrid.TILE_SIZE)

	var source := TileSetAtlasSource.new()
	if ResourceLoader.exists(SQUARE_TILES_PATH):
		source.texture = load(SQUARE_TILES_PATH) as Texture2D
	else:
		push_warning("[AdventureMap] square_tiles.png not found — using fallback.")
		source.texture = _make_fallback_square_texture()

	source.texture_region_size = Vector2i(SquareGrid.TILE_SIZE, SquareGrid.TILE_SIZE)

	# All 4 tiles in the 2x2 atlas
	for col: int in range(2):
		for row: int in range(2):
			source.create_tile(Vector2i(col, row))

	ts.add_source(source, SRC_SQUARE)
	return ts


func _build_arrow_tileset() -> TileSet:
	var ts := TileSet.new()
	ts.tile_shape       = TileSet.TILE_SHAPE_SQUARE
	ts.tile_layout      = TileSet.TILE_LAYOUT_STACKED
	ts.tile_offset_axis = TileSet.TILE_OFFSET_AXIS_HORIZONTAL
	ts.tile_size        = Vector2i(SquareGrid.TILE_SIZE, SquareGrid.TILE_SIZE)

	var source := TileSetAtlasSource.new()
	if ResourceLoader.exists(PATH_ARROWS_PATH):
		source.texture = load(PATH_ARROWS_PATH) as Texture2D
	else:
		push_warning("[AdventureMap] path_arrows.png not found — using fallback.")
		source.texture = _make_fallback_arrow_texture()

	source.texture_region_size = Vector2i(SquareGrid.TILE_SIZE, SquareGrid.TILE_SIZE)

	# All 9 tiles in the 3x3 atlas
	for col: int in range(3):
		for row: int in range(3):
			source.create_tile(Vector2i(col, row))

	ts.add_source(source, SRC_ARROW)
	return ts


# ── MAP GENERATION ───────────────────────────────────────────────────────────────

func _generate_map() -> void:
	_terrain_layer.clear()
	_blocked_tiles.clear()

	# Fill with ground tiles
	for col: int in range(MAP_COLS):
		for row: int in range(MAP_ROWS):
			_terrain_layer.set_cell(Vector2i(col, row), SRC_SQUARE, TILE_GROUND)

	# Place obstacles in the central area, avoiding the player start tile
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	var candidates: Array[Vector2i] = []
	for col: int in range(2, MAP_COLS - 2):
		for row: int in range(2, MAP_ROWS - 2):
			var tile := Vector2i(col, row)
			if tile == START_TILE:
				continue
			# Avoid blocking immediate neighbour around the start
			if SquareGrid.chebyshev_distance(tile, START_TILE) <= 2:
				continue
			candidates.append(tile)

	candidates.shuffle()

	var placed: int = 0
	for tile: Vector2i in candidates:
		if placed >= OBSTACLE_COUNT:
			break
		_terrain_layer.set_cell(tile, SRC_SQUARE, TILE_OBSTACLE)
		_blocked_tiles.append(tile)
		placed += 1


# ── CAMERA SETUP ─────────────────────────────────────────────────────────────────

func _setup_camera() -> void:
	_camera = Camera2D.new()
	_camera.name = "Camera2D"
	_camera.anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
	_camera.position_smoothing_enabled = true
	_camera.position_smoothing_speed = 8.0
	add_child(_camera)
	_camera.make_current()


# ── PLAYER SETUP ─────────────────────────────────────────────────────────────────

func _setup_player() -> void:
	_player_sprite = Sprite2D.new()
	_player_sprite.name = "Player"
	_player_sprite.scale = Vector2(MAP_SCALE, MAP_SCALE)
	_player_sprite.z_index = 2
	if ResourceLoader.exists(PLAYER_SPRITE_PATH):
		_player_sprite.texture = load(PLAYER_SPRITE_PATH) as Texture2D
	else:
		push_warning("[AdventureMap] swordsman.png not found — generating fallback sprite.")
		var fallback_img := Image.create(SquareGrid.TILE_SIZE, SquareGrid.TILE_SIZE, false, Image.FORMAT_RGBA8)
		fallback_img.fill(Color(0.2, 0.5, 0.9))
		_player_sprite.texture = ImageTexture.create_from_image(fallback_img)

	add_child(_player_sprite)
	_sync_player_position()


func _sync_player_position() -> void:
	var pos: Vector2 = _tile_to_local(player_tile)
	if _player_sprite:
		_player_sprite.position = pos
	_camera.position = pos


func _tile_to_local(tile: Vector2i) -> Vector2:
	return _terrain_layer.map_to_local(tile) * MAP_SCALE


# ── UI SETUP ─────────────────────────────────────────────────────────────────────

func _setup_ui() -> void:
	var ui := CanvasLayer.new()
	ui.name = "UI"
	ui.layer = 10
	add_child(ui)

	# Movement points label (top-left)
	_move_label = Label.new()
	_move_label.name = "MovePointsLabel"
	_move_label.position = Vector2(12, 12)
	_move_label.add_theme_font_size_override("font_size", 18)
	_move_label.add_theme_color_override("font_color", Color.WHITE)
	_move_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_move_label.add_theme_constant_override("shadow_offset_x", 1)
	_move_label.add_theme_constant_override("shadow_offset_y", 1)
	ui.add_child(_move_label)

	# Tile info (top-right)
	_tile_info = Label.new()
	_tile_info.name = "TileInfo"
	_tile_info.position = Vector2(1820, 12)
	_tile_info.add_theme_font_size_override("font_size", 14)
	_tile_info.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	ui.add_child(_tile_info)

	# End Turn button (bottom-center)
	_end_turn_btn = Button.new()
	_end_turn_btn.name = "EndTurnBtn"
	_end_turn_btn.text = "End Turn"
	_end_turn_btn.position = Vector2(860, 1020)
	_end_turn_btn.size = Vector2(180, 40)
	_end_turn_btn.pressed.connect(_on_end_turn)
	ui.add_child(_end_turn_btn)


func _refresh_hud() -> void:
	_move_label.text = "Movement: %d / %d" % [movement_points, MAX_MOVE_POINTS]
	if _end_turn_btn:
		_end_turn_btn.disabled = movement_points >= MAX_MOVE_POINTS


# ── INPUT ────────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if phase == MapPhase.MOVING:
		return

	var world_pos: Vector2 = get_global_mouse_position()

	if event is InputEventMouseMotion:
		_on_hover(_world_to_tile(world_pos))
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_on_click(_world_to_tile(world_pos))


## Convert a world-position (from get_global_mouse_position) into tile coordinates.
func _world_to_tile(world_pos: Vector2) -> Vector2i:
	var local: Vector2 = world_pos / MAP_SCALE
	return _terrain_layer.local_to_map(local)


# ── HOVER — PATH PREVIEW ─────────────────────────────────────────────────────────

func _on_hover(tile: Vector2i) -> void:
	# Clear old arrows
	_path_layer.clear()
	_path = []
	_reachable_path = []

	if not _is_in_bounds(tile):
		_tile_info.text = ""
		return

	_tile_info.text = "Tile: %s" % [str(tile)]

	# No path if hovering the player's tile or an obstacle
	if tile == player_tile or tile in _blocked_tiles:
		return

	# Compute full A* path
	var full_path: Array[Vector2i] = SquareGrid.find_path(
		player_tile, tile, _blocked_tiles)
	if full_path.is_empty():
		return

	_path = full_path

	# Walk the path to find how far movement points allow us to go
	var cost: int = 0
	for step: Vector2i in full_path:
		cost += MOVE_COST_PER_TILE
		if cost > movement_points:
			break
		_reachable_path.append(step)

	if _reachable_path.is_empty():
		return  # can't even afford the first step

	# Draw arrows on the PathLayer
	_draw_path_arrows(_reachable_path)


func _draw_path_arrows(path: Array[Vector2i]) -> void:
	## Draw arrows pointing FORWARD along the path.
	## Each tile (except the last) shows the direction to the NEXT tile.
	## The last tile shows the target marker.
	var n: int = path.size()
	for i: int in range(n):
		var curr: Vector2i = path[i]

		var atlas_coord: Vector2i
		if i == n - 1:
			# Last tile — show target marker
			atlas_coord = SquareGrid.DIRECTION_ARROW_ATLAS[Vector2i(0, 0)]
		else:
			# Arrow points toward the next tile in the path
			var nxt: Vector2i = path[i + 1]
			var diff: Vector2i = Vector2i(nxt.x - curr.x, nxt.y - curr.y)
			atlas_coord = SquareGrid.DIRECTION_ARROW_ATLAS.get(diff, Vector2i(1, 1))

		_path_layer.set_cell(curr, SRC_ARROW, atlas_coord)


# ── CLICK — MOVEMENT ─────────────────────────────────────────────────────────────

func _on_click(tile: Vector2i) -> void:
	if not _is_in_bounds(tile):
		return
	if phase != MapPhase.IDLE:
		return
	if tile == player_tile:
		return
	if tile in _blocked_tiles:
		return

	# If there's a cached path and the clicked tile is in the reachable prefix,
	# move to that tile. Otherwise, compute a fresh path.
	var target_path: Array[Vector2i] = []

	if tile in _reachable_path:
		# Move to the clicked tile within the reachable path
		var idx: int = _reachable_path.find(tile)
		target_path = _reachable_path.slice(0, idx + 1)
	else:
		# Clicked a tile not in current hover path — try to reach it
		var path: Array[Vector2i] = SquareGrid.find_path(
			player_tile, tile, _blocked_tiles, movement_points)
		if path.is_empty():
			return  # unreachable
		# Verify the path is within budget
		var cost: int = path.size() * MOVE_COST_PER_TILE
		if cost > movement_points:
			return  # not enough movement points
		target_path = path

	if target_path.is_empty():
		return

	_path_layer.clear()
	_animate_movement(target_path)


func _animate_movement(path: Array[Vector2i]) -> void:
	phase = MapPhase.MOVING

	# Deduct movement points
	var cost: int = path.size() * MOVE_COST_PER_TILE
	movement_points -= cost
	_refresh_hud()

	# Animate along the path
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_LINEAR)
	tween.set_ease(Tween.EASE_IN_OUT)

	var prev_tile: Vector2i = player_tile
	for step: Vector2i in path:
		var target_pos: Vector2 = _tile_to_local(step)
		tween.tween_property(_player_sprite, "position", target_pos, 0.1)

	player_tile = path[-1]  # last tile in the movement

	await tween.finished

	_sync_player_position()
	phase = MapPhase.IDLE
	_refresh_hud()


# ── END TURN ─────────────────────────────────────────────────────────────────────

func _on_end_turn() -> void:
	movement_points = MAX_MOVE_POINTS
	_refresh_hud()


# ── HELPERS ──────────────────────────────────────────────────────────────────────

func _is_in_bounds(tile: Vector2i) -> bool:
	return tile.x >= 0 and tile.x < MAP_COLS and tile.y >= 0 and tile.y < MAP_ROWS


# ── FALLBACK TEXTURES (for development without image files) ──────────────────────

func _make_fallback_square_texture() -> ImageTexture:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var tiles: Array = [
		[Vector2i(0,0), Color(0.70, 0.49, 0.13, 1.00)],  # orange ground
		[Vector2i(1,0), Color(0.43, 0.43, 0.43, 1.00)],  # gray obstacle
		[Vector2i(0,1), Color(0.30, 0.18, 0.07, 1.00)],  # brown spare
		[Vector2i(1,1), Color(0.34, 0.03, 0.03, 1.00)],  # dark red spare
	]
	_draw_fallback_tiles(img, tiles)
	return ImageTexture.create_from_image(img)


func _make_fallback_arrow_texture() -> ImageTexture:
	var img := Image.create(96, 96, false, Image.FORMAT_RGBA8)
	var tiles: Array = []
	for col: int in range(3):
		for row: int in range(3):
			var center: bool = (col == 1 and row == 1)
			var c: Color = Color(0, 0, 0, 0.5) if center else Color(0, 0, 0, 0.85)
			tiles.append([Vector2i(col, row), c])
	_draw_fallback_tiles(img, tiles)
	return ImageTexture.create_from_image(img)


func _draw_fallback_tiles(img: Image, tile_data: Array) -> void:
	var ts: int = SquareGrid.TILE_SIZE
	for entry: Variant in tile_data:
		var arr: Array = entry as Array
		var coord: Vector2i = arr[0] as Vector2i
		var col: Color = arr[1] as Color
		for py: int in range(ts):
			for px: int in range(ts):
				img.set_pixel(coord.x * ts + px, coord.y * ts + py, col)

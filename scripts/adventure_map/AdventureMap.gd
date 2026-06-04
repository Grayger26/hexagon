## AdventureMap.gd
## Main controller for the adventure map prototype.
## Handles tilemap rendering, player movement, path preview, movement points,
## enemy encounters, and combat transitions.
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
const ENEMY_SPRITE_PATH: String = "res://assets/sprites/enemy_swordman.png"
const MAP_ROADS_SCENE_PATH: String = "res://scenes/tilemaps/map_roads.tscn"
const BUILDINGS_PATH: String = "res://assets/buildings/vault.png"

# Building sprite sheet dimensions (vault.png = 160x96 = 5x3 tiles at 32px).
const BUILDING_TILES_W: int = 5
const BUILDING_TILES_H: int = 3
const BUILDING_COUNT: int = 7

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
const SRC_BUILDING: int = 0

# Direction -> atlas lookup is handled by SquareGrid.DIRECTION_ARROW_ATLAS.
# We store the atlas coords as constants for the TileMapLayer.

# ── MOVEMENT COST ────────────────────────────────────────────────────────────────
const MOVE_COST_PER_TILE: int = 100
const MOVE_COST_ROAD:   int = 70   # 30% less than normal tiles

# ── FOG OF WAR ───────────────────────────────────────────────────────────────────
## Vision radius around the hero (in tiles, Euclidean distance).
const VISION_RADIUS: int = 5

## Fog image value for the red channel (shader uses r → α transparency).
const FOG_UNSEEN:    float = 0.0   # fully opaque
const FOG_EXPLORED:  float = 1.0   # fully clear — same as visible

## Distance (in tiles) over which the fog red-channel fades from 1.0 down to 0.0.
## Larger values = a wider, smoother transition zone around explored-area edges.
const SMOOTH_RADIUS: int = 3


# ── STATE ────────────────────────────────────────────────────────────────────────

enum MapPhase {
	IDLE,       # waiting for player input
	MOVING,     # player sprite animating — input blocked
}

var phase: MapPhase = MapPhase.IDLE

var player_tile: Vector2i = START_TILE
var movement_points: int = MAX_MOVE_POINTS

var _blocked_tiles: Array[Vector2i] = []
var _path: Array[Vector2i] = []             # full A* path from player to hovered tile
var _reachable_path: Array[Vector2i] = []   # prefix truncated by movement budget
var _pathfinding_blocked: Array[Vector2i] = []  # obstacles + unreachable fog tiles
var _moveable_tiles: Dictionary = {}         # explored + gradient zone — set during _update_fog()

# ── CHILD NODES ──────────────────────────────────────────────────────────────────

var _terrain_layer: TileMapLayer
var _road_layer:    TileMapLayer
var _building_layer: TileMapLayer
var _path_layer:    TileMapLayer
var _player_sprite: Sprite2D
var _fog_sprite:    Sprite2D
var _fog_image: Image
var _camera:   Camera2D

## Parent node for all map-enemy sprites.
var _enemy_node: Node2D
## Map from enemy key ("x,y") to its Sprite2D node.
var _enemy_sprites: Dictionary = {}

## Guards against _ready() firing again when the scene is re-added
## to the tree after scene preservation (hide/restore across combat).
var _initialized: bool = false

var _move_label:    Label
var _end_turn_btn:  Button
var _tile_info:     Label


# ── ENTRY ────────────────────────────────────────────────────────────────────────

func _ready() -> void:
	# Guard against _ready() firing again when the preserved scene is
	# re-added to the tree after combat — all state is intact.
	if _initialized:
		return
	_initialized = true

	# Auto-initialize game state if it hasn't been started yet
	# (handles running AdventureMap directly from the editor).
	if not GameState.run_active:
		print("[AdventureMap] run_active=false — initialising new run")
		GameState.init_run("castle", "knight", randi())
	else:
		print("[AdventureMap] run_active=true — using existing run state")
		_print_army("player_army at _ready", GameState.player_army)
		print("[AdventureMap] map_enemies at _ready: " + str(GameState.map_enemies.keys()))

	_build_tilemaps()
	_generate_map()
	_setup_camera()
	_setup_player()
	_setup_enemy_node()
	_setup_fog()
	_setup_ui()
	_refresh_hud()
	_update_fog()
	# Process any pending combat result BEFORE setting up enemies
	# so the defeated enemy's sprite is never created.
	_process_combat_result()
	_setup_enemies()

## Called by SceneManager each time this scene is entered.
## On first load (from MainMenu): data is empty, combat_result is empty -> no-op.
## On restore (from CombatScene, after scene-preservation): processes combat
## result to remove defeated enemies, then syncs enemy sprites.
func _on_scene_entered(data: Dictionary) -> void:
	# Reset phase in case it was left as MOVING after combat transition
	phase = MapPhase.IDLE
	_process_combat_result()
	_setup_enemies()
	_refresh_hud()
	print("[AdventureMap] _on_scene_entered - map_enemies=%s" % str(GameState.map_enemies.keys()))





# ── TILEMAP SETUP ────────────────────────────────────────────────────────────────

func _build_tilemaps() -> void:
	# --- Terrain layer ---
	_terrain_layer = TileMapLayer.new()
	_terrain_layer.name = "TerrainLayer"
	_terrain_layer.z_index = 0
	_terrain_layer.scale = Vector2(MAP_SCALE, MAP_SCALE)
	_terrain_layer.tile_set = _build_terrain_tileset()
	add_child(_terrain_layer)

	# --- Road layer (sits above terrain, below fog and path) ---
	_road_layer = _make_road_layer()

	# --- Building layer (sits above terrain, below fog) ---
	_building_layer = TileMapLayer.new()
	_building_layer.name = "BuildingLayer"
	_building_layer.z_index = 0
	_building_layer.scale = Vector2(MAP_SCALE, MAP_SCALE)
	_building_layer.tile_set = _build_building_tileset()
	add_child(_building_layer)

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


func _build_building_tileset() -> TileSet:
	## Create a TileSet for the building sprite sheet (vault.png).
	## The atlas is 5 tiles wide x 3 tiles high, each tile 32x32.
	## Returns null if the texture file is missing (buildings are skipped).
	if not ResourceLoader.exists(BUILDINGS_PATH):
		push_warning("[AdventureMap] vault.png not found — buildings disabled.")
		return null

	var ts := TileSet.new()
	ts.tile_shape       = TileSet.TILE_SHAPE_SQUARE
	ts.tile_layout      = TileSet.TILE_LAYOUT_STACKED
	ts.tile_offset_axis = TileSet.TILE_OFFSET_AXIS_HORIZONTAL
	ts.tile_size        = Vector2i(SquareGrid.TILE_SIZE, SquareGrid.TILE_SIZE)

	var source := TileSetAtlasSource.new()
	source.texture = load(BUILDINGS_PATH) as Texture2D
	source.texture_region_size = Vector2i(SquareGrid.TILE_SIZE, SquareGrid.TILE_SIZE)

	# Create all 15 tiles (5 cols x 3 rows) from the atlas
	for col: int in range(BUILDING_TILES_W):
		for row: int in range(BUILDING_TILES_H):
			source.create_tile(Vector2i(col, row))

	ts.add_source(source, SRC_BUILDING)
	return ts


## Create the road TileMapLayer from the pre-configured map_roads.tscn scene.
## Falls back to a blank TileMapLayer if the scene is missing.
func _make_road_layer() -> TileMapLayer:
	if ResourceLoader.exists(MAP_ROADS_SCENE_PATH):
		var packed := load(MAP_ROADS_SCENE_PATH) as PackedScene
		if packed != null:
			var layer: TileMapLayer = packed.instantiate()
			layer.name = "RoadLayer"
			layer.z_index = 0
			layer.scale = Vector2(MAP_SCALE, MAP_SCALE)
			add_child(layer)
			return layer
	push_warning("[AdventureMap] map_roads.tscn not found — roads disabled.")
	var fallback := TileMapLayer.new()
	fallback.name = "RoadLayer"
	fallback.z_index = 0
	fallback.scale = Vector2(MAP_SCALE, MAP_SCALE)
	add_child(fallback)
	return fallback


func _setup_fog() -> void:
	## Create the fog-of-war overlay using a pixelated Sprite2D with a shader.
	## The fog image maps 1 pixel per tile; the shader adds noise for an organic look
	## and uses the red channel to control transparency (r → α).

	# --- Fog Sprite ---
	_fog_sprite = Sprite2D.new()
	_fog_sprite.name = "FogSprite"
	_fog_sprite.z_index = 0  # above terrain, below path/player
	_fog_sprite.centered = false
	# Linear filtering makes the 1px-per-tile fog image smoothly interpolate
	# between adjacent pixels — softens the gradient so it doesn't look
	# like hard tile-to-tile steps. The noise sampler is unaffected.
	_fog_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_fog_sprite.scale = Vector2(
		SquareGrid.TILE_SIZE * MAP_SCALE,
		SquareGrid.TILE_SIZE * MAP_SCALE
	)
	add_child(_fog_sprite)

	# --- Fog image (1 pixel = 1 tile) ---
	_fog_image = Image.create(MAP_COLS, MAP_ROWS, false, Image.FORMAT_RGBA8)
	_fog_image.fill(Color(0, 0, 0, 1))
	_fog_sprite.texture = ImageTexture.create_from_image(_fog_image)

	# --- Noise texture for organic fog texture ---
	# Higher frequency (0.35) + larger texture (256×256) gives finer
	# mist detail so it doesn't feel like large "too close" blobs.
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.35

	var noise_texture := NoiseTexture2D.new()
	noise_texture.noise = noise
	noise_texture.width = 256
	noise_texture.height = 256
	noise_texture.seamless = true

	# --- Shader material ---
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/fog_of_war.gdshader")
	material.set_shader_parameter("noise", noise_texture)
	_fog_sprite.material = material



# ── MAP GENERATION ───────────────────────────────────────────────────────────────

func _generate_map() -> void:
	_terrain_layer.clear()
	if is_instance_valid(_building_layer):
		_building_layer.clear()
	_blocked_tiles.clear()

	# Fill with ground tiles
	for col: int in range(MAP_COLS):
		for row: int in range(MAP_ROWS):
			_terrain_layer.set_cell(Vector2i(col, row), SRC_SQUARE, TILE_GROUND)

	# Build a set of tiles that enemy units occupy
	var enemy_tiles: Dictionary = {}
	for key: Variant in GameState.map_enemies:
		var entry: Dictionary = GameState.map_enemies[key] as Dictionary
		enemy_tiles[entry["tile"] as Vector2i] = true

	# ── BUILDING PLACEMENT ─────────────────────────────────────────────────
	# Place buildings using a seeded RNG (deterministic per run).
	# Building footprint: BUILDING_TILES_W x BUILDING_TILES_H tiles.
	# The entrance tile (bottom row, 4th column) is NOT blocked so the player
	# can walk up to it; all other footprint tiles block movement.
	var all_building_tiles: Dictionary = {}
	var _building_bases: Array[Vector2i] = []
	## Track center tile of each building entrance for road connection.
	var building_entrances: Array[Vector2i] = []

	if _building_layer != null and _building_layer.tile_set != null:
		var bld_rng := RandomNumberGenerator.new()
		bld_rng.seed = _get_map_seed() ^ 0xBEEF

		var bld_candidates: Array[Vector2i] = []
		for col: int in range(3, MAP_COLS - BUILDING_TILES_W - 3):
			for row: int in range(3, MAP_ROWS - BUILDING_TILES_H - 3):
				var tile := Vector2i(col, row)
				if SquareGrid.chebyshev_distance(tile, START_TILE) <= 5:
					continue
				bld_candidates.append(tile)

		# Fisher-Yates shuffle for deterministic placement
		for i in range(bld_candidates.size() - 1, 0, -1):
			var j := bld_rng.randi_range(0, i)
			var tmp = bld_candidates[i]
			bld_candidates[i] = bld_candidates[j]
			bld_candidates[j] = tmp

		var buildings_placed: int = 0
		for base_tile: Vector2i in bld_candidates:
			if buildings_placed >= BUILDING_COUNT:
				break

			# Check for overlap with existing buildings or enemies
			var blocked: bool = false
			for cx: int in range(BUILDING_TILES_W):
				for ry: int in range(BUILDING_TILES_H):
					var wt: Vector2i = Vector2i(base_tile.x + cx, base_tile.y + ry)
					if all_building_tiles.has(wt) or enemy_tiles.has(wt):
						blocked = true
						break
				if blocked:
					break
			if blocked:
				continue

			# Place the building tiles on the building layer
			for cx: int in range(BUILDING_TILES_W):
				for ry: int in range(BUILDING_TILES_H):
					var wt: Vector2i = Vector2i(base_tile.x + cx, base_tile.y + ry)
					all_building_tiles[wt] = true
					_building_layer.set_cell(wt, SRC_BUILDING, Vector2i(cx, ry))

			# Mark all tiles except the entrance as blocked for movement
			for cx: int in range(BUILDING_TILES_W):
				for ry: int in range(BUILDING_TILES_H):
					var wt: Vector2i = Vector2i(base_tile.x + cx, base_tile.y + ry)
					# Entrance: bottom row, tiles 1-3 are open (no collision).
					# Tiles 0 and 4 on the bottom row remain blocked (building walls).
					if ry == BUILDING_TILES_H - 1 and cx >= 1 and cx <= 3:
						continue  # entrance opening — no collision
					# Middle center tile — open so the road can run under the building.
					if ry == 1 and cx == 2:
						continue
					_blocked_tiles.append(wt)

			# Record the middle center tile for road connection.
			# The BFS spur exits through bottom center (open entrance)
			# and goes south to the nearest road. Side entrance tiles
			# (bottom col 1 and 3) are blocked in the road-BFS set.
			var entrance_tile := Vector2i(
				base_tile.x + 2,
				base_tile.y + 1)
			building_entrances.append(entrance_tile)
			_building_bases.append(base_tile)

			buildings_placed += 1

	# ── OBSTACLE PLACEMENT ──────────────────────────────────────────────────
	# Place obstacles in the central area, avoiding the player start tile,
	# enemy tiles, and all building footprint tiles.
	# Also reserve the tile directly below each building's entrance so the
	# road BFS can always connect through it (otherwise obstacles may block
	# the only open neighbor of the building's entrance tiles).
	var reserved_road_tiles: Dictionary = {}
	for base: Vector2i in _building_bases:
		reserved_road_tiles[Vector2i(base.x + 2, base.y + BUILDING_TILES_H)] = true

	var rng := RandomNumberGenerator.new()
	rng.seed = _get_map_seed()

	var candidates: Array[Vector2i] = []
	for col: int in range(2, MAP_COLS - 2):
		for row: int in range(2, MAP_ROWS - 2):
			var tile := Vector2i(col, row)
			if tile == START_TILE:
				continue
			if enemy_tiles.has(tile):
				continue
			if all_building_tiles.has(tile):
				continue
			if reserved_road_tiles.has(tile):
				continue
			# Avoid blocking immediate neighbour around the start
			if SquareGrid.chebyshev_distance(tile, START_TILE) <= 2:
				continue
			candidates.append(tile)

	# Fisher-Yates shuffle using the seeded RNG for deterministic obstacle placement
	for i in range(candidates.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = tmp

	var placed: int = 0
	for tile: Vector2i in candidates:
		if placed >= OBSTACLE_COUNT:
			break
		_terrain_layer.set_cell(tile, SRC_SQUARE, TILE_OBSTACLE)
		_blocked_tiles.append(tile)
		placed += 1

	# ── ROAD GENERATION ─────────────────────────────────────────────────────
	# Generate and place road network using the same deterministic seed.
	# Road tiles are placed via the terrain system so the engine
	# auto-selects the correct atlas tile (straights, corners,
	# T-junctions, diagonals, etc.) based on neighbour connections.
	# Roads naturally route around blocked tiles (building footprints).
	_road_layer.clear()
	var road_rng := RandomNumberGenerator.new()
	road_rng.seed = _get_map_seed() ^ 0x5EED
	# Build a blocked set for road generation that also blocks
	# building side entrance tiles (bottom col 1 and 3) so the BFS
	# spur always exits through the center column only.
	var road_blocked: Array[Vector2i] = _blocked_tiles.duplicate()
	for base: Vector2i in _building_bases:
		road_blocked.append(Vector2i(base.x + 1, base.y + BUILDING_TILES_H - 1))
		road_blocked.append(Vector2i(base.x + 3, base.y + BUILDING_TILES_H - 1))
	var road_positions: Array[Vector2i] = RoadGenerator.generate(
		road_rng, MAP_COLS, MAP_ROWS, road_blocked, START_TILE,
		building_entrances)
	RoadGenerator.place(_road_layer, road_positions)


# ── CAMERA SETUP ─────────────────────────────────────────────────────────────────

## Distance from screen edge (px) that triggers edge-scrolling.
const EDGE_SCROLL_MARGIN: int = 20

## Camera scroll speed when edge-scrolling (px/sec).
const SCROLL_SPEED: float = 1000.0

func _setup_camera() -> void:
	_camera = Camera2D.new()
	_camera.name = "Camera2D"
	_camera.anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
	# Smoothing is disabled — the movement tween handles camera smoothly.
	_camera.position_smoothing_enabled = false
	add_child(_camera)
	_camera.make_current()


func _process(delta: float) -> void:
	# Edge-scrolling — only when not moving
	if phase != MapPhase.IDLE:
		return

	var viewport := get_viewport()
	if viewport == null:
		return
	var mouse_pos: Vector2 = viewport.get_mouse_position()
	var screen_size: Vector2 = viewport.get_visible_rect().size

	var scroll: Vector2 = Vector2.ZERO

	if mouse_pos.x < EDGE_SCROLL_MARGIN:
		scroll.x -= 1.0
	elif mouse_pos.x > screen_size.x - EDGE_SCROLL_MARGIN:
		scroll.x += 1.0

	if mouse_pos.y < EDGE_SCROLL_MARGIN:
		scroll.y -= 1.0
	elif mouse_pos.y > screen_size.y - EDGE_SCROLL_MARGIN:
		scroll.y += 1.0

	if scroll != Vector2.ZERO:
		_camera.position += scroll.normalized() * SCROLL_SPEED * delta

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


## Snap camera focus to the player's current tile.
func _center_camera_on_player() -> void:
	_camera.position = _tile_to_local(player_tile)


# ── COMBAT RESULT HANDLING ─────────────────────────────────────────────────────

func _process_combat_result() -> void:
	## Read GameState.combat_result after returning from CombatScene
	## and update the adventure map state accordingly.
	var cr: Dictionary = GameState.combat_result
	if cr.is_empty():
		return

	var result: String    = cr.get("result", "") as String
	var enemy_key: String = cr.get("enemy_key", "") as String
	var player_survivors: Array = cr.get("player_army", []) as Array

	print("[AdventureMap] Combat result: %s  enemy_key=%s  survivors=%d" % [result, enemy_key, player_survivors.size()])

	if result == "victory" and not enemy_key.is_empty():
		# Remove the defeated enemy from data and visuals
		GameState.map_enemies.erase(enemy_key)
		_remove_enemy_sprite(enemy_key)
		# Update the player's army to reflect survivors
		GameState.player_army = player_survivors
	elif result == "defeat":
		# Keep the enemy on the map, but update the player's army
		GameState.player_army = player_survivors

	# Restore the player's tile position saved before combat,
	# and sync the player sprite and camera to match.
	var saved_tile: Vector2i = cr.get("saved_player_tile", player_tile) as Vector2i
	player_tile = saved_tile
	_sync_player_position()

	# Clear the combat result so it doesn't re-process on the next entry
	GameState.combat_result = {}


# ── ENEMY SETUP (ADVENTURE MAP) ────────────────────────────────────────────────

func _setup_enemy_node() -> void:
	_enemy_node = Node2D.new()
	_enemy_node.name = "EnemyLayer"
	_enemy_node.z_index = 2  # same as player sprite
	add_child(_enemy_node)


func _setup_enemies() -> void:
	## Sync enemy sprites with GameState.map_enemies.
	## Creates sprites for enemies in the data and removes sprites for enemies
	## that have been removed from the data (e.g. after combat victory).
	if not is_instance_valid(_enemy_node):
		return

	# Load the enemy sprite texture once
	var enemy_texture: Texture2D = null
	if ResourceLoader.exists(ENEMY_SPRITE_PATH):
		enemy_texture = load(ENEMY_SPRITE_PATH) as Texture2D

	# Track which keys are still in the data so we can remove stale sprites.
	var keep: Dictionary = {}

	# Create or reposition sprites for current map enemies
	for key: Variant in GameState.map_enemies:
		var key_str: String = String(key)
		var entry: Dictionary  = GameState.map_enemies[key] as Dictionary
		var tile: Vector2i     = entry["tile"] as Vector2i
		keep[key_str] = true

		if _enemy_sprites.has(key_str) and is_instance_valid(_enemy_sprites[key_str]):
			# Sprite already exists — just update position
			_enemy_sprites[key_str].position = _tile_to_local(tile)
		else:
			# Create new sprite
			var sprite := Sprite2D.new()
			sprite.name = "Enemy_" + key_str
			sprite.scale = Vector2(MAP_SCALE, MAP_SCALE)
			sprite.position = _tile_to_local(tile)
			if enemy_texture != null:
				sprite.texture = enemy_texture
			else:
				var fallback_img := Image.create(
					SquareGrid.TILE_SIZE, SquareGrid.TILE_SIZE, false, Image.FORMAT_RGBA8)
				fallback_img.fill(Color(0.8, 0.1, 0.1))
				sprite.texture = ImageTexture.create_from_image(fallback_img)
			_enemy_node.add_child(sprite)
			_enemy_sprites[key_str] = sprite

	# Remove sprites for enemies no longer in the data
	var to_remove: Array[String] = []
	for existing_key: Variant in _enemy_sprites:
		if not keep.has(String(existing_key)):
			to_remove.append(String(existing_key))
	for rk: String in to_remove:
		print("[AdventureMap] Removing stale enemy sprite: %s" % rk)
		_remove_enemy_sprite(rk)

	# Sync visibility with fog after syncing sprites
	_update_enemy_visibility()


func _remove_enemy_sprite(enemy_key: String) -> void:
	## Remove the sprite for a map enemy (called after combat victory).
	if not _enemy_sprites.has(enemy_key):
		return
	var sprite: Sprite2D = _enemy_sprites[enemy_key] as Sprite2D
	if is_instance_valid(sprite):
		sprite.queue_free()
	_enemy_sprites.erase(enemy_key)


## Hide enemy sprites on tiles that haven't been explored yet (fog of war).
func _update_enemy_visibility() -> void:
	if not is_instance_valid(_enemy_node):
		return
	for key: Variant in _enemy_sprites:
		var sprite: Sprite2D = _enemy_sprites[key] as Sprite2D
		if not is_instance_valid(sprite):
			continue
		var entry: Dictionary = GameState.map_enemies.get(key, {}) as Dictionary
		var tile: Vector2i = entry.get("tile", Vector2i(-1, -1)) as Vector2i
		sprite.visible = tile in GameState.explored_tiles


# ── COMBAT TRIGGER ─────────────────────────────────────────────────────────────

func _trigger_combat(enemy_key: String) -> void:
	## Transition to CombatScene with the player's army vs the enemy at enemy_key.
	if phase != MapPhase.IDLE:
		return
	phase = MapPhase.MOVING  # block further input during transition

	var enemy: Dictionary = GameState.map_enemies[enemy_key] as Dictionary

	print("[AdventureMap] _trigger_combat  enemy=%s  count=%d" % [enemy_key, enemy.get("count", 30)])
	_print_army("  sending army", GameState.player_army)

	# Store combat context so CombatScene can write the result back.
	# Save player_tile so we can restore the player position after combat.
	GameState.combat_result = {
		"enemy_key": enemy_key,
		"saved_player_tile": player_tile,
	}

	var data: Dictionary = {
		"attacker_army": GameState.player_army.duplicate(true),
		"defender_army": [{"unit_id": "goblin", "count": enemy.get("count", 30)}],
		"return_scene": SceneManager.Scene.ADVENTURE_MAP,
	}
	SceneManager.go_to(SceneManager.Scene.COMBAT, data)


# ── FOG OF WAR ─────────────────────────────────────────────────────────────────


func _get_visible_tiles(center: Vector2i, radius: int) -> Array[Vector2i]:
	## Return all in-bounds tiles within Euclidean distance ≤ radius of center.
	## Euclidean gives a round reveal area (Chebyshev would be square).
	var radius_sq: int = radius * radius
	var tiles: Array[Vector2i] = []
	for x in range(center.x - radius, center.x + radius + 1):
		for y in range(center.y - radius, center.y + radius + 1):
			var tile := Vector2i(x, y)
			if not _is_in_bounds(tile):
				continue
			var dx: int = tile.x - center.x
			var dy: int = tile.y - center.y
			if dx * dx + dy * dy <= radius_sq:
				tiles.append(tile)
	return tiles


func _update_fog() -> void:
	## Recompute visibility from the current player position and draw the fog image
	## with a smooth gradient border at the explored/unexplored boundary.
	##
	## The fog image uses the red channel as a transparency mask:
	##   r=1.0 → shader subtracts from alpha → fully clear
	##   r=0.0 → shader keeps alpha at 1.0    → fully opaque (fogged)
	##   r=0.0..1.0 → gradient blend zone at the explored frontier
	##
	## A BFS starting from every explored tile feathers the red value outward
	## over SMOOTH_RADIUS tiles, so the fog fades in gradually rather than
	## cutting off sharply at tile boundaries.
	if not is_instance_valid(_fog_sprite):
		return

	# 1. Record newly visible tiles so they persist across turns
	var visible_tiles: Array[Vector2i] = _get_visible_tiles(player_tile, VISION_RADIUS)
	for vt: Vector2i in visible_tiles:
		if not vt in GameState.explored_tiles:
			GameState.explored_tiles.append(vt)

	# 2. Build a fast explored lookup
	var explored: Dictionary = {}
	for et: Vector2i in GameState.explored_tiles:
		explored[et] = true

	# 3. Initialise the fog image: explored=1.0, unexplored=0.0
	for x: int in range(MAP_COLS):
		for y: int in range(MAP_ROWS):
			var tile := Vector2i(x, y)
			var red: float = FOG_EXPLORED if explored.has(tile) else FOG_UNSEEN
			_fog_image.set_pixel(x, y, Color(red, red, red, 1.0))

	# 4. BFS from the explored frontier to create a smooth gradient.
	#    Each step outward from an explored tile reduces the red value,
	#    creating a gradual fade over SMOOTH_RADIUS tiles.
	var queue: Array[Vector2i] = []
	queue.assign(GameState.explored_tiles)
	var dist: Dictionary = {}
	for et: Vector2i in GameState.explored_tiles:
		dist[et] = 0

	var idx: int = 0
	while idx < queue.size():
		var current: Vector2i = queue[idx]
		idx += 1
		var d: int = dist[current] as int
		if d >= SMOOTH_RADIUS:
			continue

		for nb: Vector2i in SquareGrid.get_neighbours(current):
			if not _is_in_bounds(nb):
				continue
			if dist.has(nb):
				continue
			dist[nb] = d + 1
			queue.append(nb)
			var red: float = 1.0 - float(d + 1) / float(SMOOTH_RADIUS)
			_fog_image.set_pixel(nb.x, nb.y, Color(red, red, red, 1.0))

	# 5. Build the moveable set for input + pathfinding.
	#    Include all explored tiles and gradient neighbours where the red
	#    value is still > 0. The outermost BFS ring (distance == SMOOTH_RADIUS)
	#    gets red=0.0 (fully fogged) — those tiles stay blocked to prevent
	#    clicking into solid fog beyond the blend zone.
	_moveable_tiles = {}
	for tile: Variant in dist:
		if (dist[tile] as int) < SMOOTH_RADIUS:
			_moveable_tiles[tile as Vector2i] = true

	_fog_sprite.texture = ImageTexture.create_from_image(_fog_image)
	EventBus.fog_updated.emit(visible_tiles)

	# Rebuild pathfinding blocked cache to exclude unreachable fog tiles
	_rebuild_pathfinding_blocked()
	# Sync enemy visibility with explored tiles
	_update_enemy_visibility()


func _rebuild_pathfinding_blocked() -> void:
	## Combine obstacles and non-moveable tiles into one blocked set for pathfinding.
	## A tile is moveable if it's explored OR within SMOOTH_RADIUS of an explored tile
	## (the gradient/blend zone). Everything else is blocked.
	## This lets the player pathfind and click through the smooth border zone.
	if _moveable_tiles.is_empty():
		return

	var blocked_dict: Dictionary = {}
	for bt: Vector2i in _blocked_tiles:
		blocked_dict[bt] = true
	var result: Array[Vector2i] = _blocked_tiles.duplicate()
	for x: int in range(MAP_COLS):
		for y: int in range(MAP_ROWS):
			var tile := Vector2i(x, y)
			if not _moveable_tiles.has(tile) and not blocked_dict.has(tile):
				result.append(tile)

	_pathfinding_blocked = result


func _tile_to_local(tile: Vector2i) -> Vector2:
	return _terrain_layer.map_to_local(tile) * MAP_SCALE


func _tile_move_cost(tile: Vector2i) -> int:
	## Returns movement cost for a single tile.
	## Road tiles cost 30% less than normal tiles.
	if _road_layer and _road_layer.get_cell_source_id(tile) != -1:
		return MOVE_COST_ROAD
	return MOVE_COST_PER_TILE


func _path_cost(path: Array[Vector2i]) -> int:
	## Returns total movement cost for the entire path,
	## summing per-tile costs (road tiles are cheaper).
	var total: int = 0
	for tile: Vector2i in path:
		total += _tile_move_cost(tile)
	return total


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

	# Camera control: Space snaps to player
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and key_event.keycode == KEY_SPACE:
			_center_camera_on_player()
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

	# No path if hovering the player's tile, an obstacle, or a tile
	# beyond the moveable frontier (explored + gradient blend zone).
	if tile == player_tile or tile in _blocked_tiles:
		return

	if not _moveable_tiles.has(tile):
		return

	# Compute full A* path
	var full_path: Array[Vector2i] = SquareGrid.find_path(
		player_tile, tile, _pathfinding_blocked)
	if full_path.is_empty():
		return

	_path = full_path

	# Walk the path to find how far movement points allow us to go
	var cost: int = 0
	for step: Vector2i in full_path:
		cost += _tile_move_cost(step)
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

	if not _moveable_tiles.has(tile):
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
			player_tile, tile, _pathfinding_blocked)
		if path.is_empty():
			return  # unreachable
		# Verify the path is within budget
		var cost: int = _path_cost(path)
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
	var cost: int = _path_cost(path)
	movement_points -= cost
	_refresh_hud()

	# Animate step by step, revealing fog after each tile
	for step: Vector2i in path:
		player_tile = step
		var target_pos: Vector2 = _tile_to_local(step)
		var tween := create_tween()
		tween.set_parallel(true)
		tween.set_trans(Tween.TRANS_LINEAR)
		tween.set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(_player_sprite, "position", target_pos, 0.1)
		tween.tween_property(_camera, "position", target_pos, 0.1)
		await tween.finished

		_update_fog()

	phase = MapPhase.IDLE
	_refresh_hud()

	# After movement completes, check if the player landed on an enemy tile.
	# If so, trigger combat immediately.
	var enemy_key: String = GameState.enemy_key(player_tile)
	if GameState.map_enemies.has(enemy_key):
		_trigger_combat(enemy_key)


# ── END TURN ─────────────────────────────────────────────────────────────────────

func _on_end_turn() -> void:
	movement_points = MAX_MOVE_POINTS
	_refresh_hud()


# ── HELPERS ──────────────────────────────────────────────────────────────────────

func _is_in_bounds(tile: Vector2i) -> bool:
	return tile.x >= 0 and tile.x < MAP_COLS and tile.y >= 0 and tile.y < MAP_ROWS


## Returns a deterministic seed for map generation so obstacles stay in
## the same positions when the map is regenerated (e.g. after combat).
## Uses GameState.run_seed as the base so each run has a unique layout.
func _get_map_seed() -> int:
	return GameState.run_seed ^ 0xAD7E9


func _print_army(label: String, army: Array) -> void:
	var parts: Array[String] = []
	for entry: Variant in army:
		var e: Dictionary = entry as Dictionary
		parts.append("%s:%d" % [e.get("unit_id", "?"), e.get("count", 0)])
	print("[AdventureMap] %s — %s" % [label, ", ".join(parts)])


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

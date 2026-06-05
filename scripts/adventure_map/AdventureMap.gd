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
const LIGHTHOUSE_PATH: String = "res://assets/buildings/lighthouse.png"

# Building sprite sheet dimensions (vault.png = 160x96 = 5x3 tiles at 32px).
const BUILDING_TILES_W: int = 5
const BUILDING_TILES_H: int = 3
const BUILDING_COUNT: int = 5

# Lighthouse dimensions (lighthouse.png = 96x96 = 3x3 tiles at 32px).
const LIGHTHOUSE_TILES_W: int = 3
const LIGHTHOUSE_TILES_H: int = 3

# ── SQUARE TILES ATLAS ───────────────────────────────────────────────────────────
# square_tiles.png is 96x96, 9 tiles in a 3x3 grid, each 32x32.
# All 9 tiles are ground variations (no obstacle tile — obstacles use blocked_tiles only).

const SRC_SQUARE: int = 0
const SQUARE_ATLAS_COLS: int = 3
const SQUARE_ATLAS_ROWS: int = 3

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

## Radius (in tiles, Euclidean) revealed when visiting the lighthouse.
const LIGHTHOUSE_REVEAL_RADIUS: int = 15


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

## Tiles occupied by enemies — used to block pathfinding passage.
var _enemy_tiles: Dictionary = {}           # Vector2i -> true

# ── CHILD NODES ──────────────────────────────────────────────────────────────────

var _terrain_layer: TileMapLayer
var _road_layer:    TileMapLayer
var _building_layer: TileMapLayer
var _lighthouse_bottom_layer: TileMapLayer  # bottom row (under player, z=1)
var _lighthouse_top_layer: TileMapLayer     # top rows (above player, z=3)
## Top-left corner of the lighthouse on the map (-1,-1 if not placed).
var _lighthouse_base: Vector2i = Vector2i(-1, -1)
## Whether the player has already visited the lighthouse this run.
var _lighthouse_activated: bool = false
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
	# Refresh enemy tiles and pathfinding blocking after combat results
	# (defeated enemies no longer block pathfinding).
	_refresh_enemy_tiles()
	_rebuild_pathfinding_blocked()
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

	# --- Lighthouse bottom layer (below player, z=1) ---
	# Bottom row renders under the player sprite; top rows render above.
	_lighthouse_bottom_layer = TileMapLayer.new()
	_lighthouse_bottom_layer.name = "LighthouseBottomLayer"
	_lighthouse_bottom_layer.z_index = 1
	_lighthouse_bottom_layer.scale = Vector2(MAP_SCALE, MAP_SCALE)
	var lighthouse_ts := _build_lighthouse_tileset()
	_lighthouse_bottom_layer.tile_set = lighthouse_ts
	add_child(_lighthouse_bottom_layer)

	# --- Lighthouse top layer (above player, z=3) ---
	_lighthouse_top_layer = TileMapLayer.new()
	_lighthouse_top_layer.name = "LighthouseTopLayer"
	_lighthouse_top_layer.z_index = 3
	_lighthouse_top_layer.scale = Vector2(MAP_SCALE, MAP_SCALE)
	_lighthouse_top_layer.tile_set = lighthouse_ts
	add_child(_lighthouse_top_layer)

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

	# All 9 tiles in the 3x3 atlas
	for col: int in range(SQUARE_ATLAS_COLS):
		for row: int in range(SQUARE_ATLAS_ROWS):
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


func _build_lighthouse_tileset() -> TileSet:
	## Create a TileSet for the lighthouse sprite sheet (lighthouse.png).
	## The atlas is 3 tiles wide x 3 tiles high, each tile 32x32.
	## Returns null if the texture file is missing (lighthouse is skipped).
	if not ResourceLoader.exists(LIGHTHOUSE_PATH):
		push_warning("[AdventureMap] lighthouse.png not found — lighthouse disabled.")
		return null

	var ts := TileSet.new()
	ts.tile_shape       = TileSet.TILE_SHAPE_SQUARE
	ts.tile_layout      = TileSet.TILE_LAYOUT_STACKED
	ts.tile_offset_axis = TileSet.TILE_OFFSET_AXIS_HORIZONTAL
	ts.tile_size        = Vector2i(SquareGrid.TILE_SIZE, SquareGrid.TILE_SIZE)

	var source := TileSetAtlasSource.new()
	source.texture = load(LIGHTHOUSE_PATH) as Texture2D
	source.texture_region_size = Vector2i(SquareGrid.TILE_SIZE, SquareGrid.TILE_SIZE)

	# Create all 9 tiles (3 cols x 3 rows) from the atlas
	for col: int in range(LIGHTHOUSE_TILES_W):
		for row: int in range(LIGHTHOUSE_TILES_H):
			source.create_tile(Vector2i(col, row))

	ts.add_source(source, 0)
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
	_fog_sprite.z_index = 4  # above all building layers (max z=3), so fog hides everything
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
	if is_instance_valid(_lighthouse_bottom_layer):
		_lighthouse_bottom_layer.clear()
	if is_instance_valid(_lighthouse_top_layer):
		_lighthouse_top_layer.clear()
	_blocked_tiles.clear()

	# Fill with varied ground tiles from the 3x3 atlas
	var ground_rng := RandomNumberGenerator.new()
	ground_rng.seed = _get_map_seed() ^ 0xDEAD
	for col: int in range(MAP_COLS):
		for row: int in range(MAP_ROWS):
			var atlas_tile := Vector2i(
				ground_rng.randi_range(0, SQUARE_ATLAS_COLS - 1),
				ground_rng.randi_range(0, SQUARE_ATLAS_ROWS - 1))
			_terrain_layer.set_cell(Vector2i(col, row), SRC_SQUARE, atlas_tile)

	# Build a set of tiles that enemy units occupy
	_refresh_enemy_tiles()

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
					if all_building_tiles.has(wt) or _enemy_tiles.has(wt):
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

	# ── LIGHTHOUSE PLACEMENT ─────────────────────────────────────────────
	# Place one lighthouse with y-sorting:
	#   - Bottom row renders on LighthouseBottomLayer (z=1, under player at z=2)
	#   - Top two rows render on LighthouseTopLayer (z=3, above player)
	# The middle tile (1,1) blocks movement; bottom-center (1,2) is the entrance.
	# Use a separate seeded RNG so lighthouse position is deterministic per run.
	_lighthouse_base = Vector2i(-1, -1)
	_lighthouse_activated = false
	if _lighthouse_bottom_layer != null and _lighthouse_bottom_layer.tile_set != null:
		var lh_rng := RandomNumberGenerator.new()
		lh_rng.seed = _get_map_seed() ^ 0xF00D

		var lh_candidates: Array[Vector2i] = []
		for col: int in range(3, MAP_COLS - LIGHTHOUSE_TILES_W - 3):
			for row: int in range(3, MAP_ROWS - LIGHTHOUSE_TILES_H - 3):
				var tile := Vector2i(col, row)
				if SquareGrid.chebyshev_distance(tile, START_TILE) <= 5:
					continue
				# Check no overlap with existing buildings or enemies
				var overlap: bool = false
				for cx: int in range(LIGHTHOUSE_TILES_W):
					for ry: int in range(LIGHTHOUSE_TILES_H):
						var wt: Vector2i = Vector2i(tile.x + cx, tile.y + ry)
						if all_building_tiles.has(wt) or _enemy_tiles.has(wt):
							overlap = true
							break
					if overlap:
						break
				if overlap:
					continue
				lh_candidates.append(tile)

		if not lh_candidates.is_empty():
			var lh_idx: int = lh_rng.randi_range(0, lh_candidates.size() - 1)
			_lighthouse_base = lh_candidates[lh_idx]

			# Place bottom row (ry=2) on bottom layer (z_index=1, under player)
			for cx: int in range(LIGHTHOUSE_TILES_W):
				var wt: Vector2i = Vector2i(_lighthouse_base.x + cx, _lighthouse_base.y + 2)
				all_building_tiles[wt] = true
				_lighthouse_bottom_layer.set_cell(wt, 0, Vector2i(cx, 2))

			# Place top two rows (ry=0,1) on top layer (z_index=3, above player)
			for cx: int in range(LIGHTHOUSE_TILES_W):
				for ry: int in range(LIGHTHOUSE_TILES_H - 1):
					var wt: Vector2i = Vector2i(_lighthouse_base.x + cx, _lighthouse_base.y + ry)
					all_building_tiles[wt] = true
					_lighthouse_top_layer.set_cell(wt, 0, Vector2i(cx, ry))

			# Set collision: only the middle tile (1,1) blocks movement.
			# The entrance, top row, and side columns are all open for pathfinding.
			for cx: int in range(LIGHTHOUSE_TILES_W):
				for ry: int in range(LIGHTHOUSE_TILES_H):
					var wt: Vector2i = Vector2i(_lighthouse_base.x + cx, _lighthouse_base.y + ry)
					if cx == 1 and ry == 1:
						_blocked_tiles.append(wt)

			# Record the center tile for road connection (like vault buildings).
			# The BFS spur exits from the center in any direction since all other
			# footprint tiles are open. The center tile is removed from road_blocked
			# below so the road BFS can traverse through it (player pathfinding via
			# _blocked_tiles still blocks the center).
			var lh_entrance := Vector2i(
				_lighthouse_base.x + 1,
				_lighthouse_base.y + 1)
			building_entrances.append(lh_entrance)

	# ── OBSTACLE PLACEMENT ──────────────────────────────────────────────────
	# Place obstacles in the central area, avoiding the player start tile,
	# enemy tiles, and all building footprint tiles.
	# Also reserve the tile directly below each building's entrance so the
	# road BFS can always connect through it (otherwise obstacles may block
	# the only open neighbor of the building's entrance tiles).
	var reserved_road_tiles: Dictionary = {}
	for base: Vector2i in _building_bases:
		reserved_road_tiles[Vector2i(base.x + 2, base.y + BUILDING_TILES_H)] = true
	# Lighthouse: reserve tile directly below the entrance so road BFS can exit south.
	if _lighthouse_base != Vector2i(-1, -1):
		reserved_road_tiles[Vector2i(_lighthouse_base.x + 1, _lighthouse_base.y + LIGHTHOUSE_TILES_H)] = true

	var rng := RandomNumberGenerator.new()
	rng.seed = _get_map_seed()

	var candidates: Array[Vector2i] = []
	for col: int in range(2, MAP_COLS - 2):
		for row: int in range(2, MAP_ROWS - 2):
			var tile := Vector2i(col, row)
			if tile == START_TILE:
				continue
			if _enemy_tiles.has(tile):
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
		# Obstacles block pathfinding but keep the ground tile already placed
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
	# Lighthouse: unblock the center tile so the road BFS can traverse through it
	# (the center remains in _blocked_tiles for player pathfinding — they cannot
	# walk on it, but the road can pass underneath).
	if _lighthouse_base != Vector2i(-1, -1):
		road_blocked.erase(Vector2i(_lighthouse_base.x + 1, _lighthouse_base.y + 1))
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


# ── LIGHTHOUSE ACTIVATION ──────────────────────────────────────────────────

func _activate_lighthouse() -> void:
	## Called when the player reaches the lighthouse entrance tile.
	## Permanently reveals a large area around the lighthouse.
	_lighthouse_activated = true
	print("[AdventureMap] Lighthouse activated! Revealing %.1f-tile radius." % LIGHTHOUSE_REVEAL_RADIUS)

	var center: Vector2i = Vector2i(
		_lighthouse_base.x + 1,
		_lighthouse_base.y + 1)
	var radius_sq: int = LIGHTHOUSE_REVEAL_RADIUS * LIGHTHOUSE_REVEAL_RADIUS
	var newly_revealed: int = 0

	# Iterate over a bounding box and check Euclidean distance
	var half: int = LIGHTHOUSE_REVEAL_RADIUS + 2  # +2 covers the building footprint
	for x: int in range(center.x - half, center.x + half + 1):
		for y: int in range(center.y - half, center.y + half + 1):
			if not _is_in_bounds(Vector2i(x, y)):
				continue
			var dx: int = x - center.x
			var dy: int = y - center.y
			if dx * dx + dy * dy <= radius_sq:
				var tile := Vector2i(x, y)
				if not tile in GameState.explored_tiles:
					GameState.explored_tiles.append(tile)
					newly_revealed += 1

	# Refresh fog to show the newly revealed area
	_update_fog()
	print("[AdventureMap] Lighthouse revealed %d new tiles" % newly_revealed)


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

	# Add enemy tiles to the blocked set — you cannot walk through enemies.
	for et: Vector2i in _enemy_tiles:
		if not blocked_dict.has(et):
			result.append(et)

	_pathfinding_blocked = result


func _refresh_enemy_tiles() -> void:
	## Rebuild _enemy_tiles from GameState.map_enemies.
	## Call after combat results are processed or enemies are added/removed.
	_enemy_tiles.clear()
	for key: Variant in GameState.map_enemies:
		var entry: Dictionary = GameState.map_enemies[key] as Dictionary
		_enemy_tiles[entry["tile"] as Vector2i] = true


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

	# Compute full A* path.
	# Enemy tiles block passage but can be targeted for attack.
	var path_blocked: Array[Vector2i] = _pathfinding_blocked
	if _enemy_tiles.has(tile):
		path_blocked = _pathfinding_blocked.duplicate()
		path_blocked.erase(tile)
	var full_path: Array[Vector2i] = SquareGrid.find_path(
		player_tile, tile, path_blocked)
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
		# Clicked a tile not in current hover path — try to reach it.
		# Enemy tiles block passage but can be targeted for attack.
		var path_blocked: Array[Vector2i] = _pathfinding_blocked
		if _enemy_tiles.has(tile):
			path_blocked = _pathfinding_blocked.duplicate()
			path_blocked.erase(tile)
		var path: Array[Vector2i] = SquareGrid.find_path(
			player_tile, tile, path_blocked)
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

	# After movement completes, check if the player reached the lighthouse entrance.
	# If so, reveal a large area around the lighthouse permanently.
	if not _lighthouse_activated and _lighthouse_base != Vector2i(-1, -1):
		var lh_entrance := Vector2i(_lighthouse_base.x + 1, _lighthouse_base.y + 2)
		if player_tile == lh_entrance:
			_activate_lighthouse()


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
	var img := Image.create(96, 96, false, Image.FORMAT_RGBA8)
	var tiles: Array = []
	var ground_colors: Array[Color] = [
		Color(0.55, 0.42, 0.22, 1.00),  # (0,0) brown
		Color(0.40, 0.55, 0.25, 1.00),  # (1,0) green
		Color(0.65, 0.55, 0.30, 1.00),  # (2,0) beige
		Color(0.50, 0.45, 0.20, 1.00),  # (0,1) tan
		Color(0.35, 0.50, 0.20, 1.00),  # (1,1) darker green
		Color(0.60, 0.48, 0.28, 1.00),  # (2,1) light brown
		Color(0.45, 0.38, 0.18, 1.00),  # (0,2) dark tan
		Color(0.30, 0.45, 0.15, 1.00),  # (1,2) forest green
		Color(0.70, 0.58, 0.35, 1.00),  # (2,2) sandy
	]
	for col: int in range(SQUARE_ATLAS_COLS):
		for row: int in range(SQUARE_ATLAS_ROWS):
			tiles.append([Vector2i(col, row), ground_colors[col + row * SQUARE_ATLAS_COLS]])
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

@tool
extends Node3D

signal player_moved(coords: Vector2i)
signal boss_decided(coords: Vector2i)
signal game_ended(status: String) # "WIN", "LOSS", "DRAW"
signal boss_won_lookat() # For looking at the camera when the player loses

@export var cell_size: float = 1.1
@export var grid_size: int = 10
@export var table_thickness: float = 0.5

@export var stone_scene: PackedScene = preload("res://Scenes/stone_white.tscn")
@export var finger_scene: PackedScene = preload("res://Scenes/stone_black.tscn")
@export var table_scene: PackedScene = preload("res://Scenes/GomokuBoard.tscn")

var dice_scene = preload("res://Scenes/dice_physical.tscn")
var active_rope_node: Node3D = null
var boss_selection_body: StaticBody3D = null
var turn_counter: int = 0
var player_inventory: Array = []
var boss_inventory: Array = []
var boss_skip_next_turn: bool = false
var player_skip_next_turn: bool = false
var item_nodes = {}
var board_visuals: Dictionary = {} # (coords) -> Node3D
var player_item_nodes: Dictionary = {} # type -> node
var hover_indicator: MeshInstance3D

var active_item: String = "" # "piston", "rope", "mirror"
var mirror_source_coord: Vector2i = Vector2i(-1, -1)
var ui_layer: CanvasLayer
var audio_streams = {}
var bg_music: AudioStreamPlayer
var looping_sfx_node: AudioStreamPlayer = null


@export var refresh_and_create: bool = false : set = set_create

var board: Array = []
var multimesh_instance: MultiMeshInstance3D
var hover_material: StandardMaterial3D
var default_material: StandardMaterial3D
var is_boss_turn: bool = false
var game_over: bool = false

const WEIGHT_FIVE = 100000
const WEIGHT_PLAYER_FOUR_OPEN = 15000
const WEIGHT_BOSS_FOUR_OPEN = 10000
const WEIGHT_PLAYER_FOUR_BLOCKED = 5000
const WEIGHT_BOSS_FOUR_BLOCKED = 2000
const WEIGHT_PLAYER_THREE_OPEN = 2000
const WEIGHT_BOSS_THREE_OPEN = 1000
const WEIGHT_PLAYER_TWO_OPEN = 200
const WEIGHT_BOSS_TWO_OPEN = 100

func _ready():
	default_material = StandardMaterial3D.new()
	default_material.albedo_color = Color(0.2, 0.2, 0.22) # Lighter slate
	default_material.metallic = 0.4
	default_material.roughness = 0.4
	
	hover_material = StandardMaterial3D.new()
	hover_material.albedo_color = Color(0.1, 0.1, 0.15)
	hover_material.emission_enabled = true
	hover_material.emission = Color(0.0, 0.5, 0.8) # Muted Cyan
	hover_material.emission_energy_multiplier = 1.5 # Reduced from 4.0

	if not Engine.is_editor_hint():
		# World Environment Polish
		var world_env = get_tree().root.find_child("WorldEnvironment", true, false)
		if world_env and world_env.environment:
			var env = world_env.environment
			env.tonemap_mode = 3 # ACES
			env.glow_enabled = true
			env.glow_bloom = 0.05
			env.glow_intensity = 0.4
			env.glow_strength = 0.8
			env.glow_blend_mode = 1 # Screen
			
			# Compatibility Mode Fixes (Disable Forward+ features)
			env.volumetric_fog_enabled = false
			if "ssao_enabled" in env: env.ssao_enabled = false
			if "ssil_enabled" in env: env.ssil_enabled = false
			if "sdfgi_enabled" in env: env.sdfgi_enabled = false
			if "ssr_enabled" in env: env.ssr_enabled = false

		# Table Collision Isolation
		for table_name in ["PlayerTable", "BossTable"]:
			var table = get_parent().find_child(table_name, true, false)
			if table: table.collision_layer = 1 # Keep on default layer, away from Props (4)
		for type in ["mirror", "piston", "rope"]:
			var item = get_parent().find_child(type, true, false)
			if item:
				item_nodes[type] = item
				_ensure_item_collision(item, type)
				item.visible = false

		clear_grid()
		generate_table()
		generate_grid()

		reset_board()

		setup_boss_animation()
		
		# Audio Setup
		bg_music = AudioStreamPlayer.new()
		var bg_stream = load("res://Assets/Music/background.mp3")
		if bg_stream:
			bg_stream.loop = true
			bg_music.stream = bg_stream
			bg_music.autoplay = true
			add_child(bg_music)
		
		var sfx_files = {
			"player_placement": "res://Assets/Music/player_placement.mp3",
			"devil_placement": "res://Assets/Music/devil_placement.mp3",
			"dice": "res://Assets/Music/dice1.mp3",
			"use": "res://Assets/Music/use.mp3",
			"laugh": "res://Assets/Music/devil_laugh.mp3",
			"rope": "res://Assets/Music/rope.mp3"
		}
		for s_name in sfx_files:
			audio_streams[s_name] = load(sfx_files[s_name])
		
		ui_layer = CanvasLayer.new()
		ui_layer.set_script(load("res://Scripts/game_ui.gd"))
		add_child(ui_layer)
		
		# Hover Indicator setup
		hover_indicator = MeshInstance3D.new()
		var ind_mesh = CylinderMesh.new()
		ind_mesh.top_radius = cell_size * 0.4
		ind_mesh.bottom_radius = cell_size * 0.4
		ind_mesh.height = 0.01
		hover_indicator.mesh = ind_mesh
		var ind_mat = StandardMaterial3D.new()
		ind_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ind_mat.albedo_color = Color(1, 1, 1, 0.3)
		ind_mat.emission_enabled = true
		ind_mat.emission = Color(1, 1, 1)
		ind_mat.emission_energy_multiplier = 2.0
		hover_indicator.material_override = ind_mat
		hover_indicator.name = "HoverIndicator"
		add_child(hover_indicator)


func setup_boss_animation():
	var sitting = get_parent().find_child("Sitting", true, false)
	if sitting:
		if not sitting.get_script():
			var lookat_script = load("res://Scripts/boss_lookat.gd")
			if lookat_script: sitting.set_script(lookat_script)
		
		var anim_player = sitting.find_child("AnimationPlayer", true, false)
		if anim_player and anim_player is AnimationPlayer:
			# Godot 4: Animations are added to libraries (AnimationLibrary)
			var lib = anim_player.get_animation_library("")
			if not lib:
				lib = AnimationLibrary.new()
				anim_player.add_animation_library("", lib)
			
			# Load new animations and add to library
			var anims = {
				"dice": "res://dice.res",
				"lose": "res://lose.res",
				"win": "res://win.res",
				"use": "res://use.res"
			}
			
			for a_name in anims:
				var res_path = anims[a_name]
				if FileAccess.file_exists(res_path):
					var a_res = load(res_path)
					if a_res:
						# Remove old animation from library and add new one
						if lib.has_animation(a_name):
							lib.remove_animation(a_name)
						lib.add_animation(a_name, a_res)
						
						# Loop settings
						if a_name == "win" or a_name == "lose":
							a_res.loop_mode = Animation.LOOP_LINEAR
						else:
							a_res.loop_mode = Animation.LOOP_NONE
			
			# Find and start default idle animation
			var idle_names = ["mixamo.com", "mixamo_com"]
			for n in idle_names:
				if anim_player.has_animation(n):
					var anim = anim_player.get_animation(n)
					anim.loop_mode = Animation.LOOP_LINEAR
					if not anim_player.is_playing() or anim_player.current_animation != n:
						anim_player.play(n)
					break

func play_boss_anim(anim_name: String):
	var sitting = get_parent().find_child("Sitting", true, false)
	if not sitting: return
	var anim_player = sitting.find_child("AnimationPlayer", true, false)
	if anim_player and anim_player.has_animation(anim_name):
		anim_player.play(anim_name)
		if anim_name == "dice" or anim_name == "use":
			await anim_player.animation_finished
			# Return to idle
			var idle_names = ["mixamo.com", "mixamo_com"]
			for n in idle_names:
				if anim_player.has_animation(n):
					anim_player.play(n)
					break

func reset_board():
	board.clear()
	for i in range(grid_size):
		var row = []
		for j in range(grid_size):
			row.append(0)
		board.append(row)

func set_create(_val):
	if not is_inside_tree(): return
	clear_grid()
	generate_table()
	generate_grid()

func clear_grid():
	for child in get_children(): 
		if child is MultiMeshInstance3D or child.name == "GridMultiMesh" or child.name == "VisualTable" or child.name == "GridBase" or child.name == "GridCollision":
			child.free()
	multimesh_instance = null

func generate_table():
	if not table_scene: return
	var t = table_scene.instantiate()
	t.name = "VisualTable"
	add_child(t)
	
	# Scale table based on grid size
	var total_size = grid_size * cell_size + 1.0
	t.scale = Vector3(total_size / 12.0, 1.0, total_size / 12.0)
	
	if Engine.is_editor_hint() and get_tree().edited_scene_root:
		t.owner = get_tree().edited_scene_root

func generate_grid():
	# Grid Base (A unified "board" surface under the cells)
	var base_mesh = MeshInstance3D.new()
	var base_box = BoxMesh.new()
	var total_size = grid_size * cell_size
	base_box.size = Vector3(total_size, 0.05, total_size)
	base_mesh.mesh = base_box
	var base_mat = StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.12, 0.12, 0.15) # Lighter base
	base_mat.metallic = 0.5
	base_mat.roughness = 0.5
	base_mesh.material_override = base_mat
	base_mesh.name = "GridBase"
	add_child(base_mesh)

	# Grid Cells (The interactive squares)
	multimesh_instance = MultiMeshInstance3D.new()
	multimesh_instance.multimesh = MultiMesh.new()
	multimesh_instance.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh_instance.multimesh.use_colors = true
	multimesh_instance.multimesh.instance_count = grid_size * grid_size
	
	var cell_mesh = BoxMesh.new() # Use BoxMesh for "weight"
	cell_mesh.size = Vector3(cell_size * 0.95, 0.02, cell_size * 0.95) # Smaller gaps
	multimesh_instance.multimesh.mesh = cell_mesh
	multimesh_instance.material_override = default_material
	multimesh_instance.name = "GridMultiMesh"
	
	var offset = (grid_size - 1) * cell_size / 2.0
	for x in range(grid_size):
		for z in range(grid_size):
			var idx = x * grid_size + z
			var t = Transform3D()
			t.origin = Vector3(x * cell_size - offset, 0.04, z * cell_size - offset)
			multimesh_instance.multimesh.set_instance_transform(idx, t)
			multimesh_instance.multimesh.set_instance_color(idx, Color(1, 1, 1, 1))
	add_child(multimesh_instance)
	
	if Engine.is_editor_hint() and get_tree().edited_scene_root:
		base_mesh.owner = get_tree().edited_scene_root
		multimesh_instance.owner = get_tree().edited_scene_root
		
	# Grid Collision Plane (To ensure raycasts hit the EXACT surface level)
	var static_body = StaticBody3D.new()
	static_body.name = "GridCollision"
	static_body.collision_layer = 2 # Layer 2: Grid
	var col_shape = CollisionShape3D.new()
	var box_shape = BoxShape3D.new()
	box_shape.size = Vector3(total_size + 1.2, 0.01, total_size + 1.2)
	col_shape.shape = box_shape
	static_body.add_child(col_shape)
	add_child(static_body)
	# Position collision at the EXACT height of cell surfaces
	static_body.position = Vector3(0, 0.05, 0) 
	
	# Boss Selection Body
	var boss = get_parent().find_child("Sitting", true, false)
	if boss:
		boss_selection_body = StaticBody3D.new()
		boss_selection_body.name = "BossSelectionBody"
		boss_selection_body.collision_layer = 8 # Layer 4: Boss
		var b_col = CollisionShape3D.new()
		var b_shape = CapsuleShape3D.new()
		b_shape.radius = 0.5
		b_shape.height = 1.8
		b_col.shape = b_shape
		boss_selection_body.add_child(b_col)
		# Position relative to boss
		boss.add_child(boss_selection_body)
		boss_selection_body.position = Vector3(0, 1.0, 0)

var raycast_timer: float = 0.0
const RAYCAST_INTERVAL: float = 0.02 # Faster updates

func spawn_placement_vfx(coords: Vector2i, type: int):
	# Flash effect
	var flash = MeshInstance3D.new()
	var flash_mesh = CylinderMesh.new()
	flash_mesh.top_radius = cell_size * 0.5
	flash_mesh.bottom_radius = cell_size * 0.5
	flash_mesh.height = 0.1
	flash.mesh = flash_mesh
	
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1, 1, 1, 0.8) if type == 1 else Color(1, 0, 0, 0.8)
	mat.emission_enabled = true
	mat.emission = Color(1, 1, 1) if type == 1 else Color(1, 0, 0)
	mat.emission_energy_multiplier = 2.0 # Reduced from 5.0
	flash.material_override = mat
	
	add_child(flash)
	var offset = (grid_size - 1) * cell_size / 2.0
	flash.position = Vector3(coords.x * cell_size - offset, 0.1, coords.y * cell_size - offset)
	
	var tween = create_tween().set_parallel(true)
	tween.tween_property(flash, "scale", Vector3(1.5, 0.1, 1.5), 0.2)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.2)
	tween.tween_property(mat, "emission_energy_multiplier", 0.0, 0.2)
	tween.chain().finished.connect(flash.queue_free)

func _process(delta):
	if Engine.is_editor_hint(): return
	raycast_timer += delta
	if raycast_timer >= RAYCAST_INTERVAL:
		raycast_timer = 0.0
		perform_raycast()
	
	# Light pulsing during boss turn
	if is_boss_turn and not game_over:
		animate_boss_lights(delta)

func animate_boss_lights(delta):
	var world_env = get_tree().root.find_child("WorldEnvironment", true, false)
	if not world_env: return
	
	for light in world_env.get_children():
		if light is SpotLight3D:
			var pulse = (sin(Time.get_ticks_msec() * 0.005) + 1.0) / 2.0 # 0 to 1
			light.light_energy = lerp(10.0, 25.0, pulse)
			light.light_indirect_energy = lerp(2.0, 8.0, pulse)

func _input(event):
	if Engine.is_editor_hint(): return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		perform_raycast(true)

func perform_raycast(is_click: bool = false):
	var camera = get_viewport().get_camera_3d()
	if not camera: return
	
	var crosshair_pos = get_viewport().get_visible_rect().size / 2.0
	# All offsets removed to ensure perfect center-to-center alignment
	
	var from = camera.project_ray_origin(crosshair_pos)
	var to = from + camera.project_ray_normal(crosshair_pos) * 100.0
	var space_state = get_world_3d().direct_space_state
	# Collision masks: 2 (Grid), 4 (Props), 8 (Boss)
	var mask = 2 | 4 | 8 
	var query = PhysicsRayQueryParameters3D.create(from, to, mask)
	var result = space_state.intersect_ray(query)
	
	if is_click and result:
		var collider = result.collider
		
		# Propların masadaki halleri (Layer 4)
		for type in player_item_nodes:
			var body = player_item_nodes[type]
			if body == collider:
				if player_inventory.has(type):
					var node = item_nodes[type]
					var target_scale = 0.08 if type == "piston" else 0.15
					if active_item == type:
						active_item = "" # Deselect
						node.scale = Vector3.ONE * target_scale
						# Reset previous source scale if deselected
						if mirror_source_coord != Vector2i(-1, -1):
							var piece = board_visuals.get(mirror_source_coord)
							if piece: piece.scale = Vector3.ONE
						mirror_source_coord = Vector2i(-1, -1)
					else:
						active_item = type # Select
						node.scale = Vector3.ONE * target_scale * 1.5 # Relative scale up
						if ui_layer: ui_layer.show_info_message(type.to_upper() + " SELECTED" + ("! (BIND THE DEMON!)" if type == "rope" else ""))
						play_sfx("use")
					return
		
		# Boss tıklama (Layer 8)
		if active_item == "rope" and collider == boss_selection_body:
			use_rope(false)
			active_item = ""
			return

	handle_hover(result)
	if is_click:
		handle_click(result)

func handle_hover(result):
	if result and result.collider.collision_layer == 2 and not is_boss_turn and not game_over:
		var coords = get_coords_from_pos(result.position)
		if is_valid_coord(coords):
			hover_indicator.visible = true
			var offset = (grid_size - 1) * cell_size / 2.0
			hover_indicator.global_position = Vector3(coords.x * cell_size - offset, 0.06, coords.y * cell_size - offset) + global_position
			
			if board[coords.x][coords.y] == 0:
				hover_indicator.material_override.albedo_color = Color(0, 1, 0, 0.4) # Green for valid
				hover_indicator.material_override.emission = Color(0, 1, 0)
			else:
				hover_indicator.material_override.albedo_color = Color(1, 0, 0, 0.4) # Red for invalid
				hover_indicator.material_override.emission = Color(1, 0, 0)
		else:
			hover_indicator.visible = false
	else:
		hover_indicator.visible = false

	var current_hover = Vector2i(-1, -1)
	if result: current_hover = get_coords_from_pos(result.position)
	if current_hover != last_hovered:
		if is_valid_coord(last_hovered): set_cell_hover_state(last_hovered, false)
		if is_valid_coord(current_hover): set_cell_hover_state(current_hover, true)
		last_hovered = current_hover

var last_hovered: Vector2i = Vector2i(-1, -1)

func set_cell_hover_state(coords: Vector2i, is_hover: bool):
	if not multimesh_instance: return
	var idx = coords.x * grid_size + coords.y
	var c = Color(2.0, 2.0, 1.0, 1.0) if is_hover else Color(1, 1, 1, 1)
	multimesh_instance.multimesh.set_instance_color(idx, c)

func handle_click(result):
	if game_over or is_boss_turn: return
	if not result or result.collider.collision_layer != 2: return
	var coords = get_coords_from_pos(result.position)
	if not is_valid_coord(coords): return

	if active_item != "":
		execute_item_logic(coords)
		return

	if board[coords.x][coords.y] == 0:
		place_piece(coords, 1)
		player_moved.emit(coords)
		
		# Immediate Win Check
		if check_win(coords, 1): 
			end_game("WIN")
			return
		elif check_draw(): 
			end_game("DRAW")
			return
			
		turn_counter += 1
		if turn_counter % 3 == 0:
			var player_keeps_turn = await trigger_gamble()
			if player_keeps_turn:
				if ui_layer: ui_layer.show_info_message("STILL YOUR TURN!")
				return # Skip boss turn

		# Boss turn transition
		if boss_skip_next_turn:
			boss_skip_next_turn = false
			if ui_layer: ui_layer.show_info_message("YOUR TURN! (DEMON BOUND)")
		else:
			if active_rope_node:
				_clear_rope_visual()
			boss_turn()

func execute_item_logic(coords: Vector2i):
	match active_item:
		"piston":
			if board[coords.x][coords.y] == 2:
				use_piston(coords)
				active_item = ""
			else:
				if ui_layer: ui_layer.show_info_message("INVALID: SELECT OPPONENT PIECE")
		"rope":
			pass # Use via direct boss click only
		"mirror":
			if mirror_source_coord == Vector2i(-1, -1):
				if board[coords.x][coords.y] == 1:
					mirror_source_coord = coords
					if ui_layer: ui_layer.show_info_message("SELECT OPPONENT PIECE")
					# Visual feedback for selected stone (Pulse UP and stay at 1.0)
					var piece = board_visuals.get(coords)
					if piece:
						var tween = create_tween()
						tween.tween_property(piece, "scale", Vector3.ONE * 1.3, 0.2)
						tween.tween_property(piece, "scale", Vector3.ONE, 0.2)
				else:
					if ui_layer: ui_layer.show_info_message("INVALID: SELECT YOUR PIECE")
			else:
				if board[coords.x][coords.y] == 2:
					use_mirror(mirror_source_coord, coords)
					active_item = ""
					mirror_source_coord = Vector2i(-1, -1)
				else:
					if ui_layer: ui_layer.show_info_message("INVALID: SELECT OPPONENT PIECE")

func use_piston(coords: Vector2i):
	var node = item_nodes.get("piston")
	if node:
		var target_base = Vector3(coords.x * cell_size - ((grid_size - 1) * cell_size / 2.0), 0.05, coords.y * cell_size - ((grid_size - 1) * cell_size / 2.0)) + global_position
		# Ensure we are on top of the stone if present
		var piece = board_visuals.get(coords)
		if piece:
			place_object_on_surface(node, target_base + Vector3(0, 0.05, 0)) # Offset slightly for collision if needed, but logic handles it
		else:
			place_object_on_surface(node, target_base)
		
		var final_target = node.global_position
		# Reset to flight start for animation
		node.global_position = node.global_position # (Keep it for now, _animate handles flight)
		await _animate_prop_flight(node, final_target, true)
		node.visible = false
		node.global_position = Vector3(0, -100, 0) # Move away to clear collision
	
	spawn_blood_particles(coords)
	var piece = board_visuals.get(coords)
	if piece:
		piece.queue_free()
		board_visuals.erase(coords)
	board[coords.x][coords.y] = 0
	if ui_layer: ui_layer.show_info_message("PISTON USED")
	
	player_inventory.erase("piston")
	boss_inventory.erase("piston")

func use_rope(from_boss: bool):
	if active_rope_node: _clear_rope_visual()
	play_sfx("rope")
	
	var node = item_nodes.get("rope")
	var target_pos: Vector3
	
	if from_boss:
		player_skip_next_turn = true
		if ui_layer: ui_layer.show_info_message("THE DEMON BOUND YOU!")
		var cam = get_viewport().get_camera_3d()
		target_pos = cam.global_position + cam.global_transform.basis.z * -0.5
	else:
		boss_skip_next_turn = true
		if ui_layer: ui_layer.show_info_message("YOU BOUND THE DEMON!")
		var boss = get_parent().find_child("Sitting", true, false)
		target_pos = boss.global_position + Vector3(0, 1.5, 0) if boss else global_position + Vector3(0, 2, -1)
	
	if node:
		active_rope_node = node
		await _animate_prop_flight(node, target_pos, false)
		# NOTE: Removal is now handled in turn transition logic
	
	player_inventory.erase("rope")
	boss_inventory.erase("rope")

func _clear_rope_visual():
	if active_rope_node:
		var node = active_rope_node
		active_rope_node = null
		var tween = create_tween()
		tween.tween_property(node, "scale", Vector3.ZERO, 0.4)
		await tween.finished
		node.visible = false
		node.global_position = Vector3(0, -100, 0) # Displacement cleanup

func use_mirror(c1: Vector2i, c2: Vector2i):
	var t1 = board[c1.x][c1.y]
	board[c1.x][c1.y] = board[c2.x][c2.y]
	board[c2.x][c2.y] = t1
	var v1 = board_visuals[c1]
	var v2 = board_visuals[c2]
	var p1 = v1.global_position
	var p2 = v2.global_position
	var tween = create_tween().set_parallel(true)
	tween.tween_property(v1, "global_position", p2, 0.5)
	tween.tween_property(v2, "global_position", p1, 0.5)
	
	# Explicitly reset scales to 1.0 to ensure they are not "stuck small"
	tween.tween_property(v1, "scale", Vector3.ONE, 0.1)
	tween.tween_property(v2, "scale", Vector3.ONE, 0.1)
	board_visuals[c1] = v2
	board_visuals[c2] = v1
	if ui_layer: ui_layer.show_info_message("MIRROR USED")
	
	# Win Check after swap
	if check_win(c1, board[c1.x][c1.y]) or check_win(c2, board[c2.x][c2.y]):
		var winner = board[c1.x][c1.y] if check_win(c1, board[c1.x][c1.y]) else board[c2.x][c2.y]
		end_game("WIN" if winner == 1 else "LOSS")
		return

	if item_nodes["mirror"] and not is_boss_turn:
		var itween = create_tween()
		itween.tween_property(item_nodes["mirror"], "scale", Vector3.ZERO, 0.3)
		player_inventory.erase("mirror")
	elif is_boss_turn:
		boss_inventory.erase("mirror")

func spawn_blood_particles(coords: Vector2i):
	var particles = CPUParticles3D.new()
	add_child(particles)
	var offset = (grid_size - 1) * cell_size / 2.0
	particles.position = Vector3(coords.x * cell_size - offset, 0.2, coords.y * cell_size - offset)
	
	particles.amount = 40
	particles.lifetime = 1.0
	particles.one_shot = true
	particles.explosiveness = 0.9
	particles.mesh = BoxMesh.new()
	particles.mesh.size = Vector3(0.05, 0.05, 0.05)
	
	particles.direction = Vector3(0, 1, 0)
	particles.spread = 45.0
	particles.initial_velocity_min = 2.0
	particles.initial_velocity_max = 5.0
	particles.gravity = Vector3(0, -9.8, 0)
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0, 0) # Deep blood red
	mat.metallic = 0.5
	mat.roughness = 0.2
	particles.material_override = mat
	
	particles.emitting = true
	get_tree().create_timer(1.2).timeout.connect(particles.queue_free)

func place_object_on_surface(object_node: Node3D, contact_point: Vector3):
	var mesh_node = _find_mesh_recursive(object_node)
	if not mesh_node:
		object_node.global_position = contact_point
		return

	var aabb: AABB
	if mesh_node is MeshInstance3D:
		aabb = mesh_node.mesh.get_aabb()
	elif mesh_node is CSGBox3D:
		aabb = AABB(Vector3(-mesh_node.size.x/2, -mesh_node.size.y/2, -mesh_node.size.z/2), mesh_node.size)
	
	# More robust math: Calculate current global Y of the bottom point
	# and move the root node by the required difference.
	var local_bottom_center = Vector3(0, aabb.position.y, 0)
	var global_bottom_center = mesh_node.to_global(local_bottom_center)
	
	var y_diff = (contact_point.y + 0.02) - global_bottom_center.y # Added 0.02 safe offset
	object_node.global_position.y += y_diff
	
	# Horizontal alignment
	object_node.global_position.x = contact_point.x
	object_node.global_position.z = contact_point.z

func _find_mesh_recursive(node: Node) -> Node:
	if node is MeshInstance3D or node is CSGBox3D: return node
	for child in node.get_children():
		var found = _find_mesh_recursive(child)
		if found: return found
	return null

func trigger_gamble():
	play_boss_anim("dice")
	play_sfx("dice")
	if ui_layer: ui_layer.show_info_message("DICE ROLLED...")
	
	# Fiziksel zarları fırlat
	var dice_nodes = []
	for i in range(2):
		var d = dice_scene.instantiate()
		get_parent().add_child(d)
		# Toss dice slightly above the grid
		d.global_position = global_position + Vector3(randf_range(-0.5, 0.5), 3.0, randf_range(-0.5, 0.5))
		# Apply random rotation and velocity
		d.apply_impulse(Vector3(randf_range(-1, 1), -2, randf_range(-1, 1)))
		d.apply_torque_impulse(Vector3(randf_range(-5, 5), randf_range(-5, 5), randf_range(-5, 5)))
		dice_nodes.append(d)
	
	# Wait for dice to fall
	await get_tree().create_timer(2.5).timeout
	
	var total = (randi() % 6 + 1) + (randi() % 6 + 1)
	if ui_layer: ui_layer.show_info_message("Dice rolled " + str(total) + "!")
	await get_tree().create_timer(1.0).timeout
	
	if total < 7: 
		if ui_layer: ui_layer.show_info_message("Luck is on your side! YOUR TURN!")
		await get_tree().create_timer(1.0).timeout
		give_random_item("player")
		return true # Player gets another turn / keeps turn
	elif total > 7: 
		if ui_layer: ui_layer.show_info_message("Luck is on the demon's side! DEMON MOVES!")
		play_sfx("laugh")
		await get_tree().create_timer(1.0).timeout
		give_random_item("boss")
		return false # Transition to boss
	else: 
		# Repeat on draw
		for d in dice_nodes: d.queue_free()
		return await trigger_gamble()
	
	# Clear dice (fade out slowly)
	await get_tree().create_timer(1.5).timeout
	for d in dice_nodes:
		var tween = create_tween()
		tween.tween_property(d, "scale", Vector3.ZERO, 0.5)
		tween.finished.connect(d.queue_free)
	
	# Hide remaining dice from character animation (legacy support)
	var char_dice = get_parent().find_child("dice", true, false)
	if not char_dice: char_dice = get_parent().find_child("zar", true, false)
	if char_dice: char_dice.visible = false

func give_random_item(target: String):
	var type = ["mirror", "piston", "rope"][randi() % 3]
	var item_names_en = {"mirror": "MIRROR", "piston": "PISTON", "rope": "ROPE"}
	
	var node = item_nodes.get(type)
	if not node: return
	
	node.visible = true
	var target_scale = 0.08 if type == "piston" else 0.15
	node.scale = Vector3.ONE * target_scale
	
	if target == "player":
		player_inventory.append(type)
		if ui_layer: ui_layer.show_info_message(item_names_en[type] + " GIVEN")
		
		var slot_pos = _get_item_slot_pos("player", player_inventory.size() - 1)
		place_object_on_surface(node, slot_pos)
		_animate_to_table(node, node.global_position)
	else:
		boss_inventory.append(type)
		if ui_layer: ui_layer.show_info_message(item_names_en[type] + " GIVEN TO THE DEMON")
		
		var slot_pos = _get_item_slot_pos("boss", boss_inventory.size() - 1)
		place_object_on_surface(node, slot_pos)
		_animate_to_table(node, node.global_position)

func _animate_to_table(node, target_pos):
	var type = ""
	for k in item_nodes:
		if item_nodes[k] == node: type = k
	
	var target_scale = 0.08 if type == "piston" else 0.15
	var tween = create_tween().set_parallel(true)
	tween.tween_property(node, "global_position", target_pos, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(node, "scale", Vector3.ONE * target_scale, 1.2)
	
	# Explicitly clear any X/Z rotations from the scene to prevent collision offset
	tween.tween_property(node, "rotation_degrees:x", 0.0, 1.2)
	tween.tween_property(node, "rotation_degrees:z", 0.0, 1.2)
	
	# Add randomized yaw rotation for "solid" feeling
	tween.tween_property(node, "rotation_degrees:y", randf_range(-25, 25), 1.2)

func _get_item_slot_pos(target: String, idx: int) -> Vector3:
	var table_name = "PlayerTable" if target == "player" else "BossTable"
	var table = get_parent().find_child(table_name, true, false)
	if not table: return global_position + Vector3(0, 1, 0)
	
	# Determine table top Y (assuming CSGBox3D or MeshInstance3D)
	var top_y = 0.0
	if table is CSGBox3D:
		top_y = table.size.y / 2.0
	elif table is MeshInstance3D:
		top_y = table.mesh.get_aabb().size.y / 2.0
	
	# Slot spacing: 1.0 units apart for better separation
	var x_offset = -1.0 + (idx * 1.0) if target == "player" else 1.0 - (idx * 1.0)
	var local_pos = Vector3(x_offset, top_y, 0.2) 
	return table.to_global(local_pos)

func _animate_prop_flight(node, target_pos, slam: bool):
	var tween = create_tween()
	var mid_pos = (node.global_position + target_pos) / 2.0 + Vector3(0, 3.5, 0)
	
	# Arched flight
	tween.tween_property(node, "global_position", mid_pos, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(node, "rotation_degrees:y", node.rotation_degrees.y + 720, 0.8) # Double spin
	tween.tween_property(node, "global_position", target_pos + (Vector3(0, 0.6, 0) if slam else Vector3.ZERO), 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	
	if slam:
		# Piston slam animation
		tween.tween_property(node, "global_position", target_pos, 0.15).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_IN)
		tween.tween_property(node, "scale", Vector3(0.25, 0.1, 0.25), 0.1) # Harder squeeze
		tween.tween_property(node, "scale", Vector3(0.2, 0.2, 0.2), 0.2) # Restore
	
	await tween.finished

func boss_turn():
	if boss_skip_next_turn:
		boss_skip_next_turn = false
		return
	is_boss_turn = true
	if boss_inventory.size() > 0:
		await evaluate_boss_item_usage()
		await get_tree().create_timer(1.0).timeout
	await get_tree().create_timer(1.2).timeout
	if game_over: return
	var best_move = _get_best_move()
	if best_move == Vector2i(-1, -1):
		end_game("DRAW")
		return
	boss_decided.emit(best_move)
	await get_tree().create_timer(0.8).timeout
	if game_over: return
	place_piece(best_move, 2)
	if check_win(best_move, 2): end_game("LOSS")
	elif check_draw(): end_game("DRAW")
	else:
		# Player turn skip handling (Consecutive moves for Boss)
		if player_skip_next_turn:
			player_skip_next_turn = false
			if ui_layer: ui_layer.show_info_message("YOUR TURN SKIPPED! (YOU ARE BOUND)")
			await get_tree().create_timer(1.5).timeout
			boss_turn()
		else:
			# Clear player rope visual if it exists
			if active_rope_node:
				_clear_rope_visual()
			is_boss_turn = false

func evaluate_boss_item_usage():
	if boss_inventory.has("piston"):
		var threat = _find_player_threat()
		if threat != Vector2i(-1, -1):
			play_boss_anim("use")
			await get_tree().create_timer(0.5).timeout
			await use_piston(threat)
	elif boss_inventory.has("mirror"):
		var swap = _find_best_mirror_swap()
		if swap.size() == 2:
			play_boss_anim("use")
			await get_tree().create_timer(0.5).timeout
			use_mirror(swap[0], swap[1])
	elif boss_inventory.has("rope"):
		play_boss_anim("use")
		await get_tree().create_timer(0.5).timeout
		await use_rope(true)

func _find_best_mirror_swap() -> Array:
	# Try to find a swap that wins or creates a strong position
	for bx in range(grid_size):
		for bz in range(grid_size):
			if board[bx][bz] == 2: # Boss piece
				for px in range(grid_size):
					for pz in range(grid_size):
						if board[px][pz] == 1: # Player piece
							# Test swap
							var c1 = Vector2i(bx, bz)
							var c2 = Vector2i(px, pz)
							board[bx][bz] = 1
							board[px][pz] = 2
							if check_win(c2, 2):
								# Cleanup and return
								board[bx][bz] = 2
								board[px][pz] = 1
								return [c1, c2]
							board[bx][bz] = 2
							board[px][pz] = 1
	return []

func _find_player_threat() -> Vector2i:
	for x in range(grid_size):
		for z in range(grid_size):
			if board[x][z] == 1: return Vector2i(x, z)
	return Vector2i(-1, -1)

func place_piece(coords: Vector2i, type: int):
	board[coords.x][coords.y] = type
	
	var scene = stone_scene if type == 1 else finger_scene
	if not scene:
		print("ERROR: Scene could not be loaded! Reloading...")
		stone_scene = load("res://Assets/stone/scene.gltf")
		finger_scene = load("res://Assets/finger/scene.gltf")
		scene = stone_scene if type == 1 else finger_scene
	
	if not scene: return # Hala null ise cik
	
	var piece = scene.instantiate()
	var offset = (grid_size - 1) * cell_size / 2.0
	
	if type == 1: # Stone (Oyuncu)
		piece.position = Vector3(coords.x * cell_size - offset, 0.05, coords.y * cell_size - offset)
		play_sfx("player_placement")
	else: # Finger (Boss) - Now using black stone
		piece.position = Vector3(coords.x * cell_size - offset, 0.05, coords.y * cell_size - offset)
		play_sfx("devil_placement")
		
	add_child(piece)
	board_visuals[coords] = piece

	# Visibility fix for boss stones (Type 2)
	if type == 2:
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.15, 0.15, 0.18) # Dark grey, not pitch black
		mat.metallic = 0.8
		mat.roughness = 0.2
		mat.rim_enabled = true
		mat.rim = 1.0
		mat.emission_enabled = true
		mat.emission = Color(0.4, 0, 0) # Faint red glow
		mat.emission_energy_multiplier = 0.5
		piece.set("material_override", mat)

	# Camera Shake on placement
	var cam = get_viewport().get_camera_3d()
	if cam and cam.has_method("apply_shake"):
		cam.apply_shake(0.05 if type == 1 else 0.12, 0.2)
	
	# Placement VFX
	spawn_placement_vfx(coords, type)

func check_win(c: Vector2i, p: int) -> bool:
	var directions = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]
	for dir in directions:
		var count = 1
		for side in [1, -1]:
			var cur = c + dir * side
			while is_valid_coord(cur) and board[cur.x][cur.y] == p:
				count += 1
				cur += dir * side
		if count >= 5: return true
	return false

func check_draw() -> bool:
	var directions = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]
	for x in range(grid_size):
		for z in range(grid_size):
			for dir in directions:
				var p1_possible = true
				var p2_possible = true
				for i in range(5):
					var cur = Vector2i(x, z) + dir * i
					if not is_valid_coord(cur):
						p1_possible = false
						p2_possible = false
						break
					if board[cur.x][cur.y] == 1: p2_possible = false
					elif board[cur.x][cur.y] == 2: p1_possible = false
				if p1_possible or p2_possible: return false
	return true

func _get_best_move() -> Vector2i:
	var best_score = -1.0
	var best_move = Vector2i(-1, -1)
	var candidates = []
	for x in range(grid_size):
		for z in range(grid_size):
			if board[x][z] == 0:
				var score = _evaluate_cell(Vector2i(x, z))
				if score > best_score:
					best_score = score
					candidates = [Vector2i(x, z)]
				elif score == best_score: candidates.append(Vector2i(x, z))
	return candidates[randi() % candidates.size()] if candidates.size() > 0 else Vector2i(-1, -1)

func _evaluate_cell(c: Vector2i) -> float:
	var score = 0.0
	var directions = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]
	for dir in directions:
		score += _score_direction(c, dir, 2)
		score += _score_direction(c, dir, 1)
	var center = float(grid_size) / 2.0
	score += (5.0 - Vector2(c.x, c.y).distance_to(Vector2(center, center))) * 2.0
	return score

func _ensure_item_collision(item: Node3D, type: String):
	# Add a StaticBody3D wrapper so the FBX model is clickable
	var static_body = StaticBody3D.new()
	static_body.name = "SelectionBody"
	static_body.collision_layer = 4 # Layer 3: Props
	item.add_child(static_body)
	
	var col_shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	
	# Use a static base size for the box relative to the prop scale
	# Piston is small (0.08), so its click area should be about 0.5 in world units
	# If parent is 0.08, then 6.0 in local units is 0.48 in world units.
	var local_size = 8.0 if type == "piston" else 5.0
	box.size = Vector3.ONE * local_size
	
	col_shape.shape = box
	static_body.add_child(col_shape)
	
	static_body.position = Vector3(0, local_size/2, 0) # Centered on mesh
	
	# Force model nodes to ignore collision to avoid interference
	_strip_collisions(item)
	
	player_item_nodes[type] = static_body

func _strip_collisions(node: Node):
	if node is CollisionObject3D and node.name != "SelectionBody":
		node.collision_layer = 0
		node.collision_mask = 0
	for child in node.get_children():
		_strip_collisions(child)

func _score_direction(c: Vector2i, dir: Vector2i, p: int) -> float:
	var count = 1
	var open_ends = 0
	for side in [1, -1]:
		var next = c + dir * side
		while is_valid_coord(next) and board[next.x][next.y] == p:
			count += 1
			next += dir * side
		if is_valid_coord(next) and board[next.x][next.y] == 0: open_ends += 1
	if count >= 5: return WEIGHT_FIVE
	if p == 2:
		if count == 4: return WEIGHT_BOSS_FOUR_OPEN if open_ends == 2 else WEIGHT_BOSS_FOUR_BLOCKED
		if count == 3: return WEIGHT_BOSS_THREE_OPEN if open_ends == 2 else 100
		if count == 2: return WEIGHT_BOSS_TWO_OPEN if open_ends == 2 else 10
	else:
		if count == 4: return WEIGHT_PLAYER_FOUR_OPEN if open_ends >= 1 else WEIGHT_PLAYER_FOUR_BLOCKED
		if count == 3: return WEIGHT_PLAYER_THREE_OPEN if open_ends == 2 else 400
		if count == 2: return WEIGHT_PLAYER_TWO_OPEN if open_ends == 2 else 50
	return 0.0

func get_coords_from_pos(pos: Vector3) -> Vector2i:
	var local_pos = to_local(pos)
	var offset = (grid_size - 1) * cell_size / 2.0
	var x = round((local_pos.x + offset) / cell_size)
	var z = round((local_pos.z + offset) / cell_size)
	return Vector2i(int(x), int(z))

func is_valid_coord(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < grid_size and c.y >= 0 and c.y < grid_size

func end_game(status: String):
	game_over = true
	var camera = get_viewport().get_camera_3d()
	if camera and camera.has_method("set"):
		camera.set("is_locked", true)
		
	if status == "LOSS":
		play_boss_anim("win")
		boss_won_lookat.emit()
		play_sfx("laugh", true)
		await get_tree().create_timer(1.0).timeout
	elif status == "WIN":
		play_boss_anim("lose")
		
	game_ended.emit(status)

func play_sfx(s_name: String, loop: bool = false):
	if audio_streams.has(s_name) and audio_streams[s_name]:
		var stream = audio_streams[s_name]
		if loop:
			stream.loop = true
			if looping_sfx_node: looping_sfx_node.queue_free()
			looping_sfx_node = AudioStreamPlayer.new()
			add_child(looping_sfx_node)
			looping_sfx_node.stream = stream
			looping_sfx_node.play()
		else:
			stream.loop = false
			var p = AudioStreamPlayer.new()
			add_child(p)
			p.stream = stream
			p.play()
			p.finished.connect(p.queue_free)

func restart_game():
	if looping_sfx_node:
		looping_sfx_node.stop()
		looping_sfx_node.queue_free()
		looping_sfx_node = null
		
	game_over = false
	var camera = get_viewport().get_camera_3d()
	if camera and camera.has_method("reset_rotation"):
		camera.reset_rotation()
	# Return to idle animation
	var sitting = get_parent().find_child("Sitting", true, false)
	if sitting:
		var anim_player = sitting.find_child("AnimationPlayer", true, false)
		if anim_player:
			var idle_names = ["mixamo.com", "mixamo_com"]
			for n in idle_names:
				if anim_player.has_animation(n):
					anim_player.play(n)
					break

	is_boss_turn = false
	turn_counter = 0
	player_inventory.clear()
	boss_inventory.clear()
	active_item = ""
	if active_rope_node:
		active_rope_node.visible = false
		active_rope_node = null
	for type in item_nodes:
		if item_nodes[type]:
			item_nodes[type].visible = false
			item_nodes[type].scale = Vector3.ONE * 0.2
	board_visuals.clear()
	reset_board()
	# Clear visual stones and particles
	for child in get_children():
		if child.name != "Table" and child.name != "GridMultiMesh" and child.name != "HoverIndicator" and child.name != "GridBase" and child.name != "GridCollision" and (child is Node3D or child is CPUParticles3D):
			child.queue_free()

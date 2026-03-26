@tool
extends Node3D

signal player_moved(coords: Vector2i)
signal boss_decided(coords: Vector2i)
signal game_ended(status: String) # "WIN", "LOSS", "DRAW"
signal boss_won_lookat() # Oyuncu kaybettiğinde kameraya bakması için

@export var hucre_boyutu: float = 1.1
@export var grid_boyutu: int = 10
@export var masa_kalinligi: float = 0.5

@export var stone_scene: PackedScene = preload("res://Assets/stone/scene.gltf")
@export var finger_scene: PackedScene = preload("res://Assets/finger/scene.gltf")
@export var table_scene: PackedScene = preload("res://Scenes/GomokuBoard.tscn")

var turn_counter: int = 0
var player_inventory: Array = []
var boss_inventory: Array = []
var boss_skip_next_turn: bool = false
var player_skip_next_turn: bool = false
var item_nodes = {}
var board_visuals: Dictionary = {} # (coords) -> Node3D

var active_item: String = "" # "piston", "rope", "mirror"
var mirror_source_coord: Vector2i = Vector2i(-1, -1)
var ui_layer: CanvasLayer


@export var yenile_ve_olustur: bool = false : set = set_olustur

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
	default_material.albedo_color = Color(0.2, 0.2, 0.2)
	default_material.vertex_color_use_as_albedo = true
	
	hover_material = StandardMaterial3D.new()
	hover_material.albedo_color = Color(0.3, 0.3, 0.3)
	hover_material.emission_enabled = true
	hover_material.emission = Color(0.5, 0.5, 0.2)
	hover_material.emission_energy_multiplier = 2.0

	if not Engine.is_editor_hint():
		item_nodes["mirror"] = get_parent().find_child("mirror", true, false)
		item_nodes["piston"] = get_parent().find_child("piston", true, false)
		item_nodes["rope"] = get_parent().find_child("rope", true, false)
		
		for type in item_nodes:
			var item = item_nodes[type]
			if item: 
				item.visible = false
				# Raycast için static body ekleyelim eğer yoksa (Basit kutu collider)
				if item.get_child_count() > 0:
					var sb = StaticBody3D.new()
					var col = CollisionShape3D.new()
					var shape = BoxShape3D.new()
					shape.size = Vector3(1, 1, 1) # Yaklaşık boyut
					col.shape = shape
					sb.add_child(col)
					item.add_child(sb)

		temizle()
		generate_table()
		generate_grid()

		reset_board()

		setup_boss_animation()
		
		ui_layer = CanvasLayer.new()
		ui_layer.set_script(load("res://Scripts/game_ui.gd"))
		add_child(ui_layer)


func setup_boss_animation():
	var sitting = get_parent().find_child("Sitting", true, false)
	if sitting:
		if not sitting.get_script():
			var lookat_script = load("res://Scripts/boss_lookat.gd")
			if lookat_script: sitting.set_script(lookat_script)
		
		var anim_player = sitting.find_child("AnimationPlayer", true, false)
		if anim_player and anim_player is AnimationPlayer:
			var anim_name = "mixamo.com"
			if anim_player.has_animation(anim_name):
				var anim = anim_player.get_animation(anim_name)
				anim.loop_mode = Animation.LOOP_LINEAR
				anim_player.play(anim_name)

func reset_board():
	board.clear()
	for i in range(grid_boyutu):
		var row = []
		for j in range(grid_boyutu):
			row.append(0)
		board.append(row)

func set_olustur(_val):
	if not is_inside_tree(): return
	temizle()
	generate_table()
	generate_grid()

func temizle():
	for child in get_children(): 
		if child is MultiMeshInstance3D or child.name == "GridMultiMesh" or child.name == "VisualTable":
			child.free()
	multimesh_instance = null

func generate_table():
	if not table_scene: return
	var t = table_scene.instantiate()
	t.name = "VisualTable"
	add_child(t)
	
	# Tablayı grid boyutuna göre ölçekle
	var total_size = grid_boyutu * hucre_boyutu + 1.0
	t.scale = Vector3(total_size / 12.0, 1.0, total_size / 12.0)
	
	if Engine.is_editor_hint() and get_tree().edited_scene_root:
		t.owner = get_tree().edited_scene_root

func generate_grid():
	multimesh_instance = MultiMeshInstance3D.new()
	multimesh_instance.multimesh = MultiMesh.new()
	multimesh_instance.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh_instance.multimesh.use_colors = true
	multimesh_instance.multimesh.instance_count = grid_boyutu * grid_boyutu
	var mesh = PlaneMesh.new()
	mesh.size = Vector2(hucre_boyutu * 0.9, hucre_boyutu * 0.9)
	multimesh_instance.multimesh.mesh = mesh
	multimesh_instance.material_override = default_material
	multimesh_instance.name = "GridMultiMesh"
	var offset = (grid_boyutu - 1) * hucre_boyutu / 2.0
	for x in range(grid_boyutu):
		for z in range(grid_boyutu):
			var idx = x * grid_boyutu + z
			var t = Transform3D()
			t.origin = Vector3(x * hucre_boyutu - offset, 0.02, z * hucre_boyutu - offset)
			multimesh_instance.multimesh.set_instance_transform(idx, t)
			multimesh_instance.multimesh.set_instance_color(idx, Color(1, 1, 1, 1))
	add_child(multimesh_instance)
	if Engine.is_editor_hint() and get_tree().edited_scene_root:
		multimesh_instance.owner = get_tree().edited_scene_root

var raycast_timer: float = 0.0
const RAYCAST_INTERVAL: float = 0.05

func _process(delta):
	if Engine.is_editor_hint(): return
	raycast_timer += delta
	if raycast_timer >= RAYCAST_INTERVAL:
		raycast_timer = 0.0
		perform_raycast()

func _input(event):
	if Engine.is_editor_hint(): return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		perform_raycast(true)

func perform_raycast(is_click: bool = false):
	var camera = get_viewport().get_camera_3d()
	if not camera: return
	
	var crosshair_pos = get_viewport().get_visible_rect().size / 2.0
	crosshair_pos.y -= 40
	
	var from = camera.project_ray_origin(crosshair_pos)
	var to = from + camera.project_ray_normal(crosshair_pos) * 100.0
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	var result = space_state.intersect_ray(query)
	
	if is_click and result:
		var collider = result.collider
		for type in item_nodes:
			var node = item_nodes[type]
			if node and (node == collider or node.is_ancestor_of(collider)):
				if player_inventory.has(type):
					active_item = type
					print("ESYA AKTIF: ", type)
					return

	handle_hover(result)
	if is_click:
		handle_click(result)

func handle_hover(result):
	var current_hover = Vector2i(-1, -1)
	if result: current_hover = get_coords_from_pos(result.position)
	if current_hover != last_hovered:
		if is_valid_coord(last_hovered): set_cell_hover_state(last_hovered, false)
		if is_valid_coord(current_hover): set_cell_hover_state(current_hover, true)
		last_hovered = current_hover

var last_hovered: Vector2i = Vector2i(-1, -1)

func set_cell_hover_state(coords: Vector2i, is_hover: bool):
	if not multimesh_instance: return
	var idx = coords.x * grid_boyutu + coords.y
	var c = Color(2.0, 2.0, 1.0, 1.0) if is_hover else Color(1, 1, 1, 1)
	multimesh_instance.multimesh.set_instance_color(idx, c)

func handle_click(result):
	if game_over or is_boss_turn: return
	if player_skip_next_turn:
		player_skip_next_turn = false
		print("TUR PAS GECTI")
		boss_turn()
		return

	if not result: return
	var coords = get_coords_from_pos(result.position)
	if not is_valid_coord(coords): return

	if active_item != "":
		execute_item_logic(coords)
		return

	if board[coords.x][coords.y] == 0:
		place_piece(coords, 1)
		player_moved.emit(coords)
		turn_counter += 1
		if turn_counter % 3 == 0: await trigger_gamble()
		if check_win(coords, 1): end_game("WIN")
		elif check_draw(): end_game("DRAW")
		else: boss_turn()

func execute_item_logic(coords: Vector2i):
	match active_item:
		"piston":
			if board[coords.x][coords.y] == 2:
				use_piston(coords)
				active_item = ""
		"rope":
			use_rope()
			active_item = ""
		"mirror":
			if mirror_source_coord == Vector2i(-1, -1):
				if board[coords.x][coords.y] == 1:
					mirror_source_coord = coords
			else:
				if board[coords.x][coords.y] == 2:
					use_mirror(mirror_source_coord, coords)
					active_item = ""
					mirror_source_coord = Vector2i(-1, -1)

func use_piston(coords: Vector2i):
	spawn_blood_particles(coords)
	var piece = board_visuals.get(coords)
	if piece:
		piece.queue_free()
		board_visuals.erase(coords)
	board[coords.x][coords.y] = 0
	if ui_layer: ui_layer.show_perk_message("PISTON KULLANILDI", 1.5)
	if item_nodes["piston"] and not is_boss_turn:

		var tween = create_tween()
		tween.tween_property(item_nodes["piston"], "scale", Vector3.ZERO, 0.3)
		player_inventory.erase("piston")

func use_rope():
	boss_skip_next_turn = true
	if ui_layer: ui_layer.show_perk_message("BOSS BAGLANDI! KALAN TUR: 1", 2.0)
	if item_nodes["rope"] and not is_boss_turn:

		var tween = create_tween()
		tween.tween_property(item_nodes["rope"], "scale", Vector3.ZERO, 0.3)
		player_inventory.erase("rope")

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
	board_visuals[c1] = v2
	board_visuals[c2] = v1
	if ui_layer: ui_layer.show_perk_message("AYNA KULLANILDI", 1.5)
	if item_nodes["mirror"] and not is_boss_turn:

		var itween = create_tween()
		itween.tween_property(item_nodes["mirror"], "scale", Vector3.ZERO, 0.3)
		player_inventory.erase("mirror")

func spawn_blood_particles(coords: Vector2i):
	var particles = CPUParticles3D.new()
	add_child(particles)
	var offset = (grid_boyutu - 1) * hucre_boyutu / 2.0
	particles.position = Vector3(coords.x * hucre_boyutu - offset, 0.2, coords.y * hucre_boyutu - offset)
	particles.amount = 30
	particles.one_shot = true
	particles.explosiveness = 0.8
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color.RED
	particles.material_override = mat
	particles.emitting = true
	get_tree().create_timer(1.5).timeout.connect(particles.queue_free)

func trigger_gamble():
	var total = (randi() % 6 + 1) + (randi() % 6 + 1)
	if ui_layer: ui_layer.show_perk_message("ZAR ATILDI: " + str(total), 1.5)
	if total < 7: give_random_item("player")

	elif total > 7: give_random_item("boss")
	else: await trigger_gamble()

func give_random_item(target: String):
	var type = ["mirror", "piston", "rope"][randi() % 3]
	if target == "player":
		player_inventory.append(type)
		if item_nodes.has(type) and item_nodes[type]:
			var camera = get_viewport().get_camera_3d()
			item_nodes[type].visible = true
			var tween = create_tween()
			
			# Kameraya göre sağ tarafa konumlandır (HUD efekti)
			var target_pos = camera.global_position + camera.global_transform.basis.z * -0.8
			target_pos += camera.global_transform.basis.x * 0.4 # Sağ
			target_pos += camera.global_transform.basis.y * -0.3 # Alt
			
			item_nodes[type].global_position = camera.global_position
			tween.tween_property(item_nodes[type], "global_position", target_pos, 0.5)
			tween.tween_property(item_nodes[type], "scale", Vector3.ONE * 0.4, 0.4).from(Vector3(0.001, 0.001, 0.001))
	else:
		boss_inventory.append(type)

func boss_turn():
	if boss_skip_next_turn:
		boss_skip_next_turn = false
		return
	is_boss_turn = true
	if boss_inventory.size() > 0:
		evaluate_boss_item_usage()
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
	is_boss_turn = false

func evaluate_boss_item_usage():
	if boss_inventory.has("piston"):
		var threat = _find_player_threat()
		if threat != Vector2i(-1, -1):
			use_piston(threat)
			boss_inventory.erase("piston")
	elif boss_inventory.has("rope"):
		player_skip_next_turn = true
		boss_inventory.erase("rope")

func _find_player_threat() -> Vector2i:
	for x in range(grid_boyutu):
		for z in range(grid_boyutu):
			if board[x][z] == 1: return Vector2i(x, z)
	return Vector2i(-1, -1)

func place_piece(coords: Vector2i, type: int):
	board[coords.x][coords.y] = type
	
	var scene = stone_scene if type == 1 else finger_scene
	if not scene:
		print("HATA: Scene yuklenemedi! Yeniden yukleniyor...")
		stone_scene = load("res://Assets/stone/scene.gltf")
		finger_scene = load("res://Assets/finger/scene.gltf")
		scene = stone_scene if type == 1 else finger_scene
	
	if not scene: return # Hala null ise cik
	
	var piece = scene.instantiate()
	var offset = (grid_boyutu - 1) * hucre_boyutu / 2.0
	
	if type == 1: # Stone (Oyuncu)
		piece.scale = Vector3(hucre_boyutu * 1.5, hucre_boyutu * 1.5, hucre_boyutu * 1.5)
		piece.position = Vector3(coords.x * hucre_boyutu - offset, 0.1, coords.y * hucre_boyutu - offset)
	else: # Finger (Boss)
		piece.scale = Vector3(hucre_boyutu * 0.1, hucre_boyutu * 0.1, hucre_boyutu * 0.1)
		piece.position = Vector3(coords.x * hucre_boyutu - offset, 0.05, coords.y * hucre_boyutu - offset)
		# Parmağı dik ve görünür yapalım
		piece.rotation_degrees.x = 0
		piece.rotation_degrees.y = 180
		
	add_child(piece)
	board_visuals[coords] = piece

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
	for x in range(grid_boyutu):
		for z in range(grid_boyutu):
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
	for x in range(grid_boyutu):
		for z in range(grid_boyutu):
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
	var center = float(grid_boyutu) / 2.0
	score += (5.0 - Vector2(c.x, c.y).distance_to(Vector2(center, center))) * 2.0
	return score

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
	var offset = (grid_boyutu - 1) * hucre_boyutu / 2.0
	var x = round((local_pos.x + offset) / hucre_boyutu)
	var z = round((local_pos.z + offset) / hucre_boyutu)
	return Vector2i(int(x), int(z))

func is_valid_coord(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < grid_boyutu and c.y >= 0 and c.y < grid_boyutu

func end_game(status: String):
	game_over = true
	if status == "LOSS":
		boss_won_lookat.emit()
		await get_tree().create_timer(1.0).timeout
	game_ended.emit(status)

func restart_game():
	game_over = false
	is_boss_turn = false
	turn_counter = 0
	player_inventory.clear()
	boss_inventory.clear()
	board_visuals.clear()
	reset_board()
	# Görsel taşları ve particlesları temizle
	for child in get_children():
		if child.name != "Masa" and child.name != "GridMultiMesh" and (child is Node3D or child is CPUParticles3D):
			child.queue_free()

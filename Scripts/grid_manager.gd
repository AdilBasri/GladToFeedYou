@tool
extends Node3D

signal player_moved(coords: Vector2i)
signal boss_decided(coords: Vector2i)
signal game_ended(status: String) # "WIN", "LOSS", "DRAW"
signal boss_won_lookat() # Oyuncu kaybettiğinde kameraya bakması için

@export var hucre_boyutu: float = 1.1
@export var grid_boyutu: int = 10
@export var masa_kalinligi: float = 0.5

# Editörde basınca her şeyi silecek ve yeniden kuracak buton
@export var yenile_ve_olustur: bool = false : set = set_olustur

var board: Array = []
var multimesh_instance: MultiMeshInstance3D
var hover_material: StandardMaterial3D
var default_material: StandardMaterial3D
var is_boss_turn: bool = false
var game_over: bool = false

# Puanlama Ağırlıkları
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
	# Materyal Ayarları
	default_material = StandardMaterial3D.new()
	default_material.albedo_color = Color(0.2, 0.2, 0.2)
	default_material.vertex_color_use_as_albedo = true
	
	hover_material = StandardMaterial3D.new()
	hover_material.albedo_color = Color(0.3, 0.3, 0.3)
	hover_material.emission_enabled = true
	hover_material.emission = Color(0.5, 0.5, 0.2)
	hover_material.emission_energy_multiplier = 2.0

	if not Engine.is_editor_hint():
		temizle()
		generate_table()
		generate_grid()
		reset_board()
		setup_boss_animation()
		
		# UI Katmanını ekle
		var ui = CanvasLayer.new()
		ui.set_script(load("res://Scripts/game_ui.gd"))
		add_child(ui)



func setup_boss_animation():
	var sitting = get_parent().find_child("Sitting", true, false)
	if sitting:
		# Script'i çalışma anında ekleyelim (Sahne dosyası çok büyük olduğu için güvenli yol)
		if not sitting.get_script():
			var lookat_script = load("res://Scripts/boss_lookat.gd")
			if lookat_script:
				sitting.set_script(lookat_script)
		
		var anim_player = sitting.find_child("AnimationPlayer", true, false)

		if anim_player and anim_player is AnimationPlayer:
			var anim_name = "mixamo.com"
			if anim_player.has_animation(anim_name):
				var anim = anim_player.get_animation(anim_name)
				anim.loop_mode = Animation.LOOP_LINEAR
				anim_player.play(anim_name)
				print("BOSS ANIMASYONU DONGUYE ALINDI VE BASLATILDI")
			else:
				var list = anim_player.get_animation_list()
				if list.size() > 0:
					var first_anim = anim_player.get_animation(list[0])
					first_anim.loop_mode = Animation.LOOP_LINEAR
					anim_player.play(list[0])

func reset_board():
	board.clear()
	for i in range(grid_boyutu):
		var row = []
		for j in range(grid_boyutu):
			row.append(0) # 0: empty, 1: player, 2: boss
		board.append(row)

func set_olustur(_val):
	if not is_inside_tree(): return
	temizle()
	generate_table()
	generate_grid()

func temizle():
	for child in get_children():
		child.free()
	multimesh_instance = null

func generate_table():
	var masa = MeshInstance3D.new()
	masa.mesh = BoxMesh.new()
	var boy = grid_boyutu * hucre_boyutu + 1.0
	masa.mesh.size = Vector3(boy, masa_kalinligi, boy)
	masa.position.y = -masa_kalinligi / 2.0
	masa.name = "Masa"
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.08, 0.08)
	masa.material_override = mat
	
	var static_body = StaticBody3D.new()
	var collision = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = masa.mesh.size
	collision.shape = shape
	static_body.add_child(collision)
	masa.add_child(static_body)
	
	add_child(masa)
	if Engine.is_editor_hint():
		masa.owner = get_tree().edited_scene_root

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
	if Engine.is_editor_hint():
		multimesh_instance.owner = get_tree().edited_scene_root

var mouse_pos: Vector2 = Vector2.ZERO
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
	
	# Sol tıklandığında (veya controller butonu) nişangahın baktığı yere taş koy
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		perform_raycast(true)

func perform_raycast(is_click: bool = false):
	var camera = get_viewport().get_camera_3d()
	if not camera: return
	
	# Ekranın tam ortasını (nişangahın yerini) baz al
	var crosshair_pos = get_viewport().get_visible_rect().size / 2.0
	crosshair_pos.y -= 40 # UI'daki yeni ofset ile aynı
	
	var from = camera.project_ray_origin(crosshair_pos)
	var to = from + camera.project_ray_normal(crosshair_pos) * 100.0


	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	var result = space_state.intersect_ray(query)
	handle_hover(result)
	if is_click:
		handle_click(result)

var last_hovered: Vector2i = Vector2i(-1, -1)

func handle_hover(result):
	var current_hover = Vector2i(-1, -1)
	if result:
		current_hover = get_coords_from_pos(result.position)
	if current_hover != last_hovered:
		if is_valid_coord(last_hovered):
			set_cell_hover_state(last_hovered, false)
		if is_valid_coord(current_hover):
			set_cell_hover_state(current_hover, true)
		last_hovered = current_hover

func set_cell_hover_state(coords: Vector2i, is_hover: bool):
	if not multimesh_instance: return
	var idx = coords.x * grid_boyutu + coords.y
	var c = Color(2.0, 2.0, 1.0, 1.0) if is_hover else Color(1, 1, 1, 1)
	multimesh_instance.multimesh.set_instance_color(idx, c)

func handle_click(result):
	if game_over or is_boss_turn: return
	if not result: return
	var coords = get_coords_from_pos(result.position)
	if is_valid_coord(coords) and board[coords.x][coords.y] == 0:
		place_stone(coords, 1)
		player_moved.emit(coords)
		
		if check_win(coords, 1):
			end_game("WIN")
			return
		
		if check_draw():
			end_game("DRAW")
			return
			
		boss_turn()

func boss_turn():
	is_boss_turn = true
	await get_tree().create_timer(1.2).timeout
	if game_over: return
	
	var best_move = _get_best_move()
	if best_move == Vector2i(-1, -1):
		end_game("DRAW")
		return
	
	boss_decided.emit(best_move)
	await get_tree().create_timer(0.8).timeout
	if game_over: return
	
	place_stone(best_move, 2)
	if check_win(best_move, 2):
		end_game("LOSS")
	elif check_draw():
		end_game("DRAW")
	
	is_boss_turn = false

func end_game(status: String):
	game_over = true
	if status == "LOSS":
		boss_won_lookat.emit()
		await get_tree().create_timer(1.0).timeout
	game_ended.emit(status)

func restart_game():
	game_over = false
	is_boss_turn = false
	reset_board()
	# Görsel taşları temizle
	for child in get_children():
		if child is MeshInstance3D and child.name != "Masa" and child.name != "GridMultiMesh":
			child.queue_free()

func check_draw() -> bool:
	# Akıllı Beraberlik: Hiçbir taraf 5'li yapamıyorsa
	var directions = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]
	
	for x in range(grid_boyutu):
		for z in range(grid_boyutu):
			for dir in directions:
				# 5'li bir pencereye bakalım
				var p1_possible = true
				var p2_possible = true
				
				for i in range(5):
					var cur = Vector2i(x, z) + dir * i
					if not is_valid_coord(cur):
						p1_possible = false
						p2_possible = false
						break
					
					if board[cur.x][cur.y] == 1: # Oyuncu taşı varsa Boss kazanamaz
						p2_possible = false
					elif board[cur.x][cur.y] == 2: # Boss taşı varsa Oyuncu kazanamaz
						p1_possible = false
				
				# Eğer hala birisi için kazanma ihtimali olan bir pencere varsa, oyun bitmemiştir
				if p1_possible or p2_possible:
					return false
	
	return true

func _get_best_move() -> Vector2i:
	var best_score = -1.0
	var best_move = Vector2i(-1, -1)
	var candidate_moves = []
	for x in range(grid_boyutu):
		for z in range(grid_boyutu):
			if board[x][z] == 0:
				var score = _evaluate_cell(Vector2i(x, z))
				if score > best_score:
					best_score = score
					best_move = Vector2i(x, z)
					candidate_moves = [Vector2i(x, z)]
				elif score == best_score:
					candidate_moves.append(Vector2i(x, z))
	if candidate_moves.size() > 0:
		return candidate_moves[randi() % candidate_moves.size()]
	return best_move

func _evaluate_cell(c: Vector2i) -> float:
	var score = 0.0
	var directions = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]
	for dir in directions:
		score += _score_direction(c, dir, 2)
		score += _score_direction(c, dir, 1)
	var center = float(grid_boyutu) / 2.0
	var dist_to_center = Vector2(c.x, c.y).distance_to(Vector2(center, center))
	score += (5.0 - dist_to_center) * 2.0
	return score

func _score_direction(c: Vector2i, dir: Vector2i, p: int) -> float:
	var count = 1
	var open_ends = 0
	for side in [1, -1]:
		var next = c + dir * side
		while is_valid_coord(next) and board[next.x][next.y] == p:
			count += 1
			next += dir * side
		if is_valid_coord(next) and board[next.x][next.y] == 0:
			open_ends += 1
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

func place_stone(coords: Vector2i, type: int):
	board[coords.x][coords.y] = type
	var stone = MeshInstance3D.new()
	stone.mesh = SphereMesh.new()
	stone.mesh.radius = hucre_boyutu * 0.3
	stone.mesh.height = hucre_boyutu * 0.3
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color.WHITE if type == 1 else Color.BLACK
	stone.material_override = mat
	var offset = (grid_boyutu - 1) * hucre_boyutu / 2.0
	stone.position = Vector3(coords.x * hucre_boyutu - offset, 0.1, coords.y * hucre_boyutu - offset)
	add_child(stone)

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

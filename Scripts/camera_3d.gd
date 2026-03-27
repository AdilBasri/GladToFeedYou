extends Camera3D

@export var hassasiyet = 0.08
@export var limit_y = 100.0  # Yatay (Sağ/Sol)
@export var limit_x = 75.0  # Dikey (Yukarı/Aşağı)

var yaw: float = 0.0
var pitch: float = 0.0
var baslangic_y: float = 0.0
var baslangic_x: float = 0.0
var is_locked: bool = false

func _ready():
	# Mouse yakala (GİZLE)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	# Masayı bul ve ona bakarak açıyı ortala
	var grid = get_tree().root.find_child("GridManager", true, false)
	if grid:
		look_at(grid.global_position)
		baslangic_y = rotation_degrees.y
		baslangic_x = rotation_degrees.x
		yaw = baslangic_y
		pitch = baslangic_x
	else:
		yaw = rotation_degrees.y
		pitch = rotation_degrees.x
		baslangic_y = yaw
		baslangic_x = pitch
	
	setup_viewmodel_rendering()

func reset_rotation():
	yaw = baslangic_y
	pitch = baslangic_x
	rotation_degrees.y = yaw
	rotation_degrees.x = pitch
	# Warp mouse to center to sync with reset yaw/pitch
	Input.warp_mouse(get_viewport().size / 2.0)
	is_locked = false

func setup_viewmodel_rendering():
	var el = find_child("el_tam", true, false)
	if el:
		_apply_no_depth_recursive(el, 10)
	
	var mice = find_child("mice", true, false)
	if mice:
		_apply_no_depth_recursive(mice, 11)
		setup_mice_animations(mice)

func setup_mice_animations(mice_node: Node):
	var anim_player = mice_node.find_child("AnimationPlayer", true, false)
	if anim_player and anim_player is AnimationPlayer:
		var all_anims = anim_player.get_animation_list()
		var sequence = []
		
		# Animasyonları 1, 2, 3 sırasına göre dizelim
		for suffix in ["1", "2", "3"]:
			for a in all_anims:
				if a.ends_with(suffix):
					sequence.append(a)
					break
		
		if sequence.size() > 0:
			# İlkini başlat
			anim_player.play(sequence[0])
			# Bittiğinde sonrakine geçmesi için sinyal bağla
			anim_player.animation_finished.connect(func(anim_name):
				var idx = sequence.find(anim_name)
				if idx != -1:
					var next_idx = (idx + 1) % sequence.size()
					anim_player.play(sequence[next_idx])
			)

func _apply_no_depth_recursive(node: Node, priority: int):
	if node is MeshInstance3D:
		for i in range(node.get_surface_override_material_count()):
			var mat = node.get_surface_override_material(i)
			if not mat:
				if node.mesh:
					mat = node.mesh.surface_get_material(i)
			
			if mat:
				var new_mat = mat.duplicate()
				if new_mat is StandardMaterial3D:
					new_mat.no_depth_test = true
					new_mat.render_priority = priority
				node.set_surface_override_material(i, new_mat)
	
	for child in node.get_children():
		_apply_no_depth_recursive(child, priority)

func _input(event):
	if is_locked: return
	if event is InputEventMouseMotion:
		# Mouse hareketini doğrudan bakışa çevir
		yaw -= event.relative.x * hassasiyet
		pitch -= event.relative.y * hassasiyet
		
		# Limitler (BAŞLANGIÇ AÇILARINA GÖRE GÖRELİ)
		yaw = clamp(yaw, baslangic_y - limit_y, baslangic_y + limit_y)
		pitch = clamp(pitch, baslangic_x - limit_x, baslangic_x + limit_x)

func _process(_delta):
	if is_locked: return
	# Nefes alma (Breathing) efekti
	var t = Time.get_ticks_msec() * 0.001
	var breath_yaw = sin(t * 1.1) * 0.12
	var breath_pitch = cos(t * 0.8) * 0.15
	var breath_roll = sin(t * 0.5) * 0.08
	
	rotation_degrees.y = yaw + breath_yaw
	rotation_degrees.x = pitch + breath_pitch
	rotation_degrees.z = breath_roll

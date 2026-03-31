extends Camera3D

@export var sensitivity = 0.08
@export var limit_y = 100.0  # Horizontal (Left/Right)
@export var limit_x = 75.0  # Vertical (Up/Down)

var yaw: float = 0.0
var pitch: float = 0.0
var start_y: float = 0.0
var start_x: float = 0.0
var is_locked: bool = false

# Shake Params
var shake_intensity: float = 0.0
var shake_duration: float = 0.0
var shake_offset: Vector3 = Vector3.ZERO

func _ready():
	# Capture mouse (HIDE)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if OS.get_name() == "Linux":
		Input.mouse_mode = Input.MOUSE_MODE_CONFINED
	
	# Find table and center view
	var grid = get_tree().root.find_child("GridManager", true, false)
	if grid:
		look_at(grid.global_position)
		start_y = rotation_degrees.y
		start_x = rotation_degrees.x
		yaw = start_y
		pitch = start_x
	else:
		yaw = rotation_degrees.y
		pitch = rotation_degrees.x
		start_y = yaw
		start_x = pitch
	
	setup_viewmodel_rendering()

func reset_rotation():
	yaw = start_y
	pitch = start_x
	rotation_degrees.y = yaw
	rotation_degrees.x = pitch
	# Warp mouse to center to sync with reset yaw/pitch
	Input.warp_mouse(get_viewport().get_visible_rect().size / 2.0)
	is_locked = false

func apply_shake(intensity: float, duration: float):
	shake_intensity = intensity
	shake_duration = duration

func setup_viewmodel_rendering():
	var hand = find_child("el_tam", true, false)
	if hand:
		_apply_no_depth_recursive(hand, 10)
	
	var mice = find_child("mice", true, false)
	if mice:
		_apply_no_depth_recursive(mice, 11)
		setup_mice_animations(mice)

func setup_mice_animations(mice_node: Node):
	var anim_player = mice_node.find_child("AnimationPlayer", true, false)
	if anim_player and anim_player is AnimationPlayer:
		var all_anims = anim_player.get_animation_list()
		var sequence = []
		
		# Sequence animations 1, 2, 3
		for suffix in ["1", "2", "3"]:
			for a in all_anims:
				if a.ends_with(suffix):
					sequence.append(a)
					break
		
		if sequence.size() > 0:
			# Play the first one
			anim_player.play(sequence[0])
			# Connect signal to play the next one when finished
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
		# Only rotate if the mouse is captured (Fixes browser/itch.io mouse fight)
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			return
			
		# Convert mouse motion to rotation
		yaw -= event.relative.x * sensitivity
		pitch -= event.relative.y * sensitivity
		
		# Limits (RELATIVE TO START ANGLES)
		yaw = clamp(yaw, start_y - limit_y, start_y + limit_y)
		pitch = clamp(pitch, start_x - limit_x, start_x + limit_x)

func _process(_delta):
	if is_locked: return
	
	# Shake logic
	if shake_duration > 0:
		shake_duration -= _delta
		var current_intensity = shake_intensity * (shake_duration / shake_duration + 0.1) # Decaying
		shake_offset = Vector3(
			randf_range(-1, 1) * current_intensity,
			randf_range(-1, 1) * current_intensity,
			0
		)
	else:
		shake_offset = shake_offset.lerp(Vector3.ZERO, _delta * 10.0)

	# Breathing effect
	var t = Time.get_ticks_msec() * 0.001
	var breath_yaw = sin(t * 1.1) * 0.12
	var breath_pitch = cos(t * 0.8) * 0.15
	var breath_roll = sin(t * 0.5) * 0.08
	
	rotation_degrees.y = yaw + breath_yaw + (shake_offset.x * 2.0)
	rotation_degrees.x = pitch + breath_pitch + (shake_offset.y * 2.0)
	rotation_degrees.z = breath_roll + (shake_offset.z * 5.0)

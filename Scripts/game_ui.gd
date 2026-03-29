extends CanvasLayer

var status_label: Label
var restart_button: Button
var quit_button: Button
var overlay: ColorRect
var perk_status_label: Label
var info_label: Label
var level_label: Label
var current_level: int = 1

var start_hint: Label

func _ready():
	# Create UI elements
	setup_ui()
	hide_ui()
	
	# Start Level 1
	animate_level_start()
	
	# Connect to GridManager
	var grid = get_tree().root.find_child("GridManager", true, false)
	if grid:
		grid.game_ended.connect(_on_game_ended)

func _input(event):
	# On Web/itch.io, we need a click to capture the mouse
	if event is InputEventMouseButton and event.pressed:
		print("Mouse Click Detected. Mode: ", Input.mouse_mode)
		# Only capture if the overlay (Win/Loss menu) is not showing
		if overlay and not overlay.visible:
			if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				if start_hint:
					start_hint.visible = false

func setup_ui():
	# Add Crosshair
	var crosshair = Control.new()
	crosshair.name = "Crosshair"
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	# Center it perfectly
	# crosshair.position.y -= 40 
	add_child(crosshair)
	crosshair.modulate.a = 0
	create_tween().tween_property(crosshair, "modulate:a", 1.0, 1.0)
	
	var dot = ColorRect.new()
	dot.custom_minimum_size = Vector2(4, 4)
	dot.position = Vector2(-2, -2)
	dot.color = Color(1, 1, 0.8) # Light yellow
	crosshair.add_child(dot)
	
	var glow = ColorRect.new()
	glow.custom_minimum_size = Vector2(10, 10)
	glow.position = Vector2(-5, -5)
	glow.color = Color(1, 0.5, 0, 0.2) # Orange-Yellow Glow
	crosshair.add_child(glow)

	# Perk/Status Message (Top Left Corner)
	var perk_container = MarginContainer.new()
	perk_container.add_theme_constant_override("margin_left", 20)
	perk_container.add_theme_constant_override("margin_top", 20)
	add_child(perk_container)
	
	perk_status_label = Label.new()
	perk_status_label.add_theme_color_override("font_color", Color(0.8, 0, 0))
	perk_status_label.add_theme_font_size_override("font_size", 24)
	perk_container.add_child(perk_status_label)
	
	# Level Label (Persistent on screen)
	level_label = Label.new()
	level_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	level_label.add_theme_font_size_override("font_size", 32)
	add_child(level_label)
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_label.modulate.a = 0
	
	# Top Info Label (Top Center)
	var info_container = CenterContainer.new()
	info_container.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	info_container.custom_minimum_size.y = 100
	add_child(info_container)
	
	info_label = Label.new()
	info_label.add_theme_color_override("font_color", Color(1, 0.8, 0.2)) # Gold/Yellow
	info_label.add_theme_font_size_override("font_size", 42) # Larger
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_label.modulate.a = 0
	info_container.add_child(info_label)

	# Background dimming
	overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.0) # Start transparent
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	
	# CenterContainer for perfect alignment
	var center_container = CenterContainer.new()
	center_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center_container)
	
	var container = VBoxContainer.new()
	container.alignment = BoxContainer.ALIGNMENT_CENTER
	container.add_theme_constant_override("separation", 20)
	center_container.add_child(container)
	
	# Status Message
	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_color_override("font_color", Color(0.9, 0.1, 0.1)) # Brighter Red
	status_label.add_theme_font_size_override("font_size", 100) # MUCH LARGER
	container.add_child(status_label)
	
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 60)
	container.add_child(spacer)
	
	# Buttons
	restart_button = Button.new()
	restart_button.text = "RETRY"
	restart_button.custom_minimum_size = Vector2(400, 100)
	restart_button.add_theme_font_size_override("font_size", 44)
	restart_button.flat = true # Use flat but with custom hover
	restart_button.add_theme_color_override("font_color", Color(1, 1, 1))
	restart_button.add_theme_color_override("font_hover_color", Color(1, 0.5, 0))
	restart_button.pressed.connect(_on_restart_pressed)
	container.add_child(restart_button)
	
	quit_button = Button.new()
	quit_button.text = "RETURN TO VOID"
	quit_button.custom_minimum_size = Vector2(400, 80)
	quit_button.add_theme_font_size_override("font_size", 32)
	quit_button.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	quit_button.flat = true
	quit_button.pressed.connect(_on_quit_pressed)
	container.add_child(quit_button)

	# Start Hint (Web/Initial Capture)
	start_hint = Label.new()
	start_hint.text = "CLICK TO CAPTURE MOUSE"
	start_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	start_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	start_hint.add_theme_font_size_override("font_size", 40)
	start_hint.add_theme_color_override("font_color", Color(1, 1, 0)) # Yellow
	add_child(start_hint)
	
	# Pulsing animation for start hint
	var hint_tween = create_tween().set_loops()
	hint_tween.tween_property(start_hint, "modulate:a", 0.3, 0.8)
	hint_tween.tween_property(start_hint, "modulate:a", 1.0, 0.8)

func show_ui(status: String):
	overlay.visible = true
	var tween_f = create_tween()
	tween_f.tween_property(overlay, "color", Color(0, 0, 0, 0.85), 0.5)
	
	match status:
		"WIN":
			status_label.text = "WINDOW OF OPPORTUNITY"
			restart_button.text = "CONTINUE"
		"LOSS":
			status_label.text = "YOU WERE HARVESTED"
			restart_button.text = "RETRY"
		"DRAW":
			status_label.text = "INFINITE LOOP"
			restart_button.text = "RETRY"
	
	status_label.scale = Vector2.ZERO
	var tween_s = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween_s.tween_property(status_label, "scale", Vector2.ONE, 0.6)
	
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func hide_ui():
	visible = true 
	if overlay:
		var tween = create_tween()
		tween.tween_property(overlay, "color", Color(0, 0, 0, 0), 0.3)
		await tween.finished
		overlay.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED 

func show_perk_message(msg: String, duration: float = 3.0):
	perk_status_label.text = msg
	perk_status_label.add_theme_color_override("font_color", Color(0, 1, 1)) # Cyan
	var tween = create_tween().set_parallel(true)
	tween.tween_property(perk_status_label, "modulate:a", 1.0, 0.3).from(0.0)
	tween.tween_property(perk_status_label, "scale", Vector2.ONE, 0.3).from(Vector2(0.5, 0.5))
	
	await get_tree().create_timer(duration).timeout
	
	var hide = create_tween()
	hide.tween_property(perk_status_label, "modulate:a", 0.0, 1.0)

func show_info_message(msg: String, duration: float = 2.5):
	if not info_label: return
	
	# If already showing a message, fade it out first
	if info_label.modulate.a > 0.1:
		var fade_out = create_tween()
		fade_out.tween_property(info_label, "modulate:a", 0.0, 0.2)
		await fade_out.finished
	
	info_label.text = msg
	info_label.modulate.a = 0
	info_label.scale = Vector2(0.8, 0.8) # Start small
	
	var tween = create_tween().set_parallel(true)
	tween.tween_property(info_label, "modulate:a", 1.0, 0.3)
	tween.tween_property(info_label, "scale", Vector2(1.0, 1.0), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	await get_tree().create_timer(duration).timeout
	
	var fade_final = create_tween()
	fade_final.tween_property(info_label, "modulate:a", 0.0, 0.5)

func animate_level_start():
	if not level_label: return
	
	var viewport_size = get_viewport().get_visible_rect().size
	level_label.text = "LEVEL " + str(current_level)
	level_label.add_theme_font_size_override("font_size", 90)
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_label.modulate.a = 0
	level_label.scale = Vector2(0.3, 0.3)
	
	# Initial centering
	level_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	# Wait for size update (optional but safer)
	await get_tree().process_frame 
	level_label.pivot_offset = level_label.size / 2.0
	
	var tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(level_label, "modulate:a", 1.0, 0.8)
	tween.tween_property(level_label, "scale", Vector2.ONE, 0.8)
	
	await get_tree().create_timer(1.8).timeout
	
	# Move and align to bottom-left HUD
	var move_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN_OUT)
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	
	var hud_y = viewport_size.y - 80
	move_tween.tween_property(level_label, "global_position", Vector2(30, hud_y), 1.2)
	move_tween.tween_property(level_label, "scale", Vector2(0.4, 0.4), 1.2)
	move_tween.tween_property(level_label, "modulate:a", 0.6, 1.2)

func _on_game_ended(status: String):
	if status == "WIN":
		current_level += 1
	elif status == "LOSS":
		current_level = 1
		
	# Show after a short delay (for Boss LookAt and animations)
	await get_tree().create_timer(1.2).timeout
	show_ui(status)

func _on_restart_pressed():
	hide_ui()
	var grid = get_tree().root.find_child("GridManager", true, false)
	if grid:
		grid.restart_game()
	
	# Start new level sequence
	animate_level_start()

func _on_quit_pressed():
	get_tree().quit()

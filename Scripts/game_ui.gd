extends CanvasLayer

var status_label: Label
var restart_button: Button
var quit_button: Button
var overlay: ColorRect
var perk_status_label: Label
var info_label: Label

func _ready():
	# Create UI elements
	setup_ui()
	hide_ui()
	
	# Connect to GridManager
	var grid = get_tree().root.find_child("GridManager", true, false)
	if grid:
		grid.game_ended.connect(_on_game_ended)

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

func show_ui(status: String):
	overlay.visible = true
	var tween_f = create_tween()
	tween_f.tween_property(overlay, "color", Color(0, 0, 0, 0.85), 0.5)
	
	match status:
		"WIN":
			status_label.text = "WINDOW OF OPPORTUNITY"
		"LOSS":
			status_label.text = "YOU WERE HARVESTED"
		"DRAW":
			status_label.text = "INFINITE LOOP"
	
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

func _on_game_ended(status: String):
	# Show after a short delay (for Boss LookAt and animations)
	await get_tree().create_timer(1.2).timeout
	show_ui(status)

func _on_restart_pressed():
	hide_ui()
	var grid = get_tree().root.find_child("GridManager", true, false)
	if grid:
		grid.restart_game()

func _on_quit_pressed():
	get_tree().quit()

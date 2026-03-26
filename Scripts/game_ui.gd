extends CanvasLayer

var status_label: Label
var restart_button: Button
var quit_button: Button
var overlay: ColorRect
var perk_status_label: Label

func _ready():
	# UI elementlerini oluştur
	setup_ui()
	hide_ui()
	
	# GridManager'a bağlan
	var grid = get_tree().root.find_child("GridManager", true, false)
	if grid:
		grid.game_ended.connect(_on_game_ended)

func setup_ui():
	# Crosshair (Nişangah) ekle
	var crosshair = Control.new()
	crosshair.name = "Crosshair"
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	# Nişangahı hafif yukarı alalım (Oyuncu isteği)
	crosshair.position.y -= 40 
	add_child(crosshair)
	
	var dot = ColorRect.new()
	dot.custom_minimum_size = Vector2(4, 4)
	dot.position = Vector2(-2, -2)
	dot.color = Color(1, 1, 0.8) # Hafif sarımsı
	crosshair.add_child(dot)
	
	var glow = ColorRect.new()
	glow.custom_minimum_size = Vector2(10, 10)
	glow.position = Vector2(-5, -5)
	glow.color = Color(1, 0.5, 0, 0.2) # Turuncu-Sarı Glow
	crosshair.add_child(glow)

	# Perk/Durum Mesajı (Sol Üst Köşe)
	var perk_container = MarginContainer.new()
	perk_container.add_theme_constant_override("margin_left", 20)
	perk_container.add_theme_constant_override("margin_top", 20)
	add_child(perk_container)
	
	perk_status_label = Label.new()
	perk_status_label.add_theme_color_override("font_color", Color(0.8, 0, 0))
	perk_status_label.add_theme_font_size_override("font_size", 24)
	perk_container.add_child(perk_status_label)

	# Arka plan karartma
	overlay = ColorRect.new()

	overlay.color = Color(0, 0, 0, 0.8)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	
	var container = VBoxContainer.new()
	container.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	container.alignment = BoxContainer.ALIGNMENT_CENTER
	overlay.add_child(container) # Overlay'in çocuğu yap, böylece overlay gizlenince bu da gizlenir
	
	# Durum Mesajı
	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_color_override("font_color", Color(0.8, 0, 0)) # Koyu Kırmızı
	status_label.add_theme_font_size_override("font_size", 64)
	container.add_child(status_label)
	
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 40)
	container.add_child(spacer)
	
	# Butonlar
	restart_button = Button.new()
	restart_button.text = "YENİDEN DENE"
	restart_button.flat = true
	restart_button.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	restart_button.add_theme_color_override("font_hover_color", Color(0.8, 0, 0))
	restart_button.pressed.connect(_on_restart_pressed)
	container.add_child(restart_button)
	
	quit_button = Button.new()
	quit_button.text = "BOŞLUĞA DÖN"
	quit_button.flat = true
	quit_button.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	quit_button.add_theme_color_override("font_hover_color", Color(0.8, 0, 0))
	quit_button.pressed.connect(_on_quit_pressed)
	container.add_child(quit_button)

func show_ui(status: String):
	overlay.visible = true
	
	match status:
		"WIN":
			status_label.text = "FIRSAT PENCERESİ"
		"LOSS":
			status_label.text = "HASAT EDİLDİN"
		"DRAW":
			status_label.text = "SONSUZ DÖNGÜ"
	
	# Basit bir glitch efekti (ölçekleme ile)
	var tween = create_tween()
	tween.tween_property(status_label, "scale", Vector2(1.1, 0.9), 0.05)
	tween.tween_property(status_label, "scale", Vector2(1.0, 1.0), 0.05)
	
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func hide_ui():
	visible = true # Nişangahın görünmesi için layer aktif kalmalı
	overlay.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED # Oyun içinde mouse yakalı



func show_perk_message(msg: String, duration: float = 2.0):
	perk_status_label.text = msg
	var tween = create_tween()
	tween.tween_property(perk_status_label, "modulate:a", 1.0, 0.2).from(0.0)
	await get_tree().create_timer(duration).timeout
	tween = create_tween()
	tween.tween_property(perk_status_label, "modulate:a", 0.0, 0.5)

func _on_game_ended(status: String):

	# Kısa bir gecikme ile göster (Boss LookAt ve animasyonlar için)
	await get_tree().create_timer(1.2).timeout
	show_ui(status)

func _on_restart_pressed():
	hide_ui()
	var grid = get_tree().root.find_child("GridManager", true, false)
	if grid:
		grid.restart_game()

func _on_quit_pressed():
	get_tree().quit()

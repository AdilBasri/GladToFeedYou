extends Area3D

@export var animation_player_path: NodePath = ".."

func _ready():
	# Ensure the Area3D is pickable
	input_ray_pickable = true
	# No need to connect signals in script if we can use _input_event
	# But using signal connection is safer for dynamic nodes

func _input_event(camera, event, position, normal, shape_idx):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		play_animation()

func play_animation():
	var parent_node = get_node_or_null(animation_player_path)
	if not parent_node: return
	
	var anim_player = parent_node.find_child("AnimationPlayer", true, false)
	if anim_player and anim_player is AnimationPlayer:
		var anim_list = anim_player.get_animation_list()
		if anim_list.size() > 0:
			# Play the first animation (usually "Take 01" in GLTFs)
			var anim_name = anim_list[0]
			anim_player.play(anim_name)

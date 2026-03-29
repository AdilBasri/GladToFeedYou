extends Node3D

@export var animation_to_play: String = ""
@export var loop: bool = true

func _ready():
	var anim_player = find_child("AnimationPlayer", true, false)
	if anim_player and anim_player is AnimationPlayer:
		var anim_list = anim_player.get_animation_list()
		if anim_list.size() > 0:
			var anim_name = animation_to_play if animation_to_play != "" else anim_list[0]
			
			if anim_player.has_animation(anim_name):
				var anim = anim_player.get_animation(anim_name)
				if loop:
					anim.loop_mode = Animation.LOOP_LINEAR
				
				anim_player.play(anim_name)
				if not anim_player.is_playing() or anim_player.current_animation != anim_name:
					anim_player.autoplay = anim_name

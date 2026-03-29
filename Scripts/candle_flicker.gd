extends OmniLight3D

@export var min_energy: float = 0.5
@export var max_energy: float = 1.5
@export var flicker_speed: float = 8.0
@export var position_wobble: float = 0.02

var base_energy: float
var base_pos: Vector3
var time: float = 0.0

func _ready():
	base_energy = light_energy
	base_pos = position
	# Randomize start time to avoid synchronization
	time = randf() * 100.0

func _process(delta):
	time += delta * flicker_speed
	
	# Noise-like flickering using sine waves of different frequencies
	var flicker = sin(time) * 0.5 + sin(time * 0.7) * 0.3 + sin(time * 1.3) * 0.2
	flicker = (flicker + 1.0) / 2.0 # Normalize to 0..1
	
	light_energy = lerp(base_energy * min_energy, base_energy * max_energy, flicker)
	
	# Slight position wobble for "dancing" flame effect
	var wobble = Vector3(
		sin(time * 0.5),
		sin(time * 0.8),
		sin(time * 0.6)
	) * position_wobble
	
	position = base_pos + wobble

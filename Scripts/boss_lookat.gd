extends Node3D

@onready var skeleton = $Skeleton3D
@onready var head_attachment = $Skeleton3D/BoneAttachment3D
@onready var skull = $Skeleton3D/BoneAttachment3D/skull

var target_pos: Vector3
var is_looking: bool = false
var look_weight: float = 0.0

func _ready():
	var grid = get_tree().root.find_child("GridManager", true, false)
	if grid:
		grid.boss_decided.connect(_on_boss_decided)
		grid.boss_won_lookat.connect(_on_boss_won_lookat)

func _on_boss_won_lookat():
	var camera = get_viewport().get_camera_3d()
	if camera:
		target_pos = camera.global_position
		var tween = create_tween()
		# Oyuncuya dik dik bakma (uzun sürsün)
		tween.tween_property(self, "look_weight", 1.0, 0.4).set_trans(Tween.TRANS_SINE)

func _on_boss_decided(coords: Vector2i):

	var grid = get_tree().root.find_child("GridManager", true, false)
	if grid:
		# Koordinatı dünya pozisyonuna çevir
		var offset = (grid.grid_boyutu - 1) * grid.hucre_boyutu / 2.0
		target_pos = grid.global_position + Vector3(coords.x * grid.hucre_boyutu - offset, 0.1, coords.y * grid.hucre_boyutu - offset)
		
		# Bakışı başlat
		var tween = create_tween()
		tween.tween_property(self, "look_weight", 1.0, 0.5).set_trans(Tween.TRANS_SINE)
		await get_tree().create_timer(1.5).timeout
		var tween_back = create_tween()
		tween_back.tween_property(self, "look_weight", 0.0, 1.0).set_trans(Tween.TRANS_SINE)

func _process(delta):
	if look_weight > 0.01:
		# Kafatasını hedefe doğru döndür
		# Skull'un kendi transformu BoneAttachment tarafından eziliyor olabilir, 
		# bu yüzden Skeleton3D üzerinden müdahale etmek daha garanti.
		var bone_idx = skeleton.find_bone("mixamorig_Head")
		if bone_idx != -1:
			var current_pose = skeleton.get_bone_pose(bone_idx)
			
			# Hedefe bakış rotasyonu hesapla (local space)
			var local_target = skeleton.to_local(target_pos)
			var look_trans = skeleton.get_bone_global_pose(bone_idx).looking_at(local_target, Vector3.UP)
			var look_quat = look_trans.basis.get_rotation_quaternion()
			
			# Mevcut animasyon pozu ile hedef poz arasında yumuşak geçiş
			var final_quat = current_pose.get_rotation_quaternion().slerp(look_quat, look_weight)
			skeleton.set_bone_pose_rotation(bone_idx, final_quat)

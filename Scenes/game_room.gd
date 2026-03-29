# Antigravity Bloat Finder
extends Node

func _ready():
	print("--- HUSK DOSYA BOYUTU ANALİZİ BAŞLADI ---")
	var dir = DirAccess.open("res://")
	_list_files_recursive("res://")

func _list_files_recursive(path):
	var dir = DirAccess.open(path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if dir.current_is_dir():
				if file_name != "." and file_name != "..":
					_list_files_recursive(path + file_name + "/")
			else:
				var file_path = path + file_name
				var file = FileAccess.open(file_path, FileAccess.READ)
				if file:
					var size_mb = file.get_length() / 1024.0 / 1024.0
					if size_mb > 5.0: # 5MB'dan büyük her şeyi raporla
						print("DİKKAT: ", file_path, " -> ", snapped(size_mb, 0.01), " MB")
			file_name = dir.get_next()

extends SceneTree

# gen_global_class_cache.gd — 离线生成 Godot 4.3 全局类缓存（global_script_class_cache.cfg）。
# ---------------------------------------------------------------------------
# 背景：Godot 4.3 的 headless（非编辑器）模式不会执行编辑器文件系统扫描来注册
# class_name 全局类，而仅从 project data 目录下的 global_script_class_cache.cfg
# 读取（见 core/config/project_settings.cpp 的 refresh_global_class_list）。
# 若缺该文件，GUT 等依赖全局类（如 GutUtils）的脚本会以
#   "Identifier 'GutUtils' not declared" 解析失败。
# 本脚本扫描 res:// 下全部 .gd 的 class_name / extends，按 Godot 期望的
#   list=[{ "class":.., "language":.., "path":.., "base":.. }, ...]
# 格式写出缓存，使 `godot --headless -s res://addons/gut/gut_cmdln.gd` 等命令
# 在 CI / 本地无编辑器导入时也能解析全局类。
# 用法：godot --headless --path . -s res://tools/gen_global_class_cache.gd
# 幂等：可重复运行；应在 GUT（addons/gut）安装之后调用，以纳入其 class_name。

func _init() -> void:
	var classes: Array = []
	_scan_dir("res://", classes)
	# make_dir_recursive 是实例方法，须经 DirAccess 实例调用（Godot 4.x）。
	var da := DirAccess.open("res://")
	if da != null and not da.dir_exists(".godot"):
		da.make_dir_recursive(".godot")
	var cf := ConfigFile.new()
	cf.set_value("", "list", classes)
	var err := cf.save("res://.godot/global_script_class_cache.cfg")
	if err != OK:
		push_error("gen_global_class_cache: failed to save cache, err=%d" % err)
		quit(1)
	print("gen_global_class_cache: wrote %d global classes" % classes.size())
	quit()


func _scan_dir(dir_path: String, classes: Array) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if name == "." or name == ".." or name.begins_with("."):
			name = d.get_next()
			continue
		var full := dir_path.path_join(name)
		if d.current_is_dir():
			_scan_dir(full, classes)
		elif name.ends_with(".gd"):
			_collect(full, classes)
		name = d.get_next()
	d.list_dir_end()


func _collect(path: String, classes: Array) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var cls_name := ""
	var base := ""
	var limit := 0
	while not f.eof_reached() and limit < 80:
		var line := f.get_line()
		limit += 1
		if cls_name == "" and line.begins_with("class_name "):
			cls_name = line.substr("class_name ".length()).strip_edges()
		if base == "" and line.begins_with("extends "):
			base = line.substr("extends ".length()).strip_edges()
			# 支持 `extends "res://..."`（按路径继承）的引号去除。
			if base.length() >= 2 and ((base.begins_with("\"") and base.ends_with("\"")) or (base.begins_with("'") and base.ends_with("'"))):
				base = base.substr(1, base.length() - 2)
		if cls_name != "" and base != "":
			break
	f.close()
	if cls_name != "":
		if base == "":
			base = "RefCounted"
		var e := {}
		e["class"] = cls_name
		e["language"] = "GDScript"
		e["path"] = path
		e["base"] = base
		classes.append(e)

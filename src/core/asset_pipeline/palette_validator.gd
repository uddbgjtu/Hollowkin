# =============================================================================
# ADR-4 · PaletteValidator（GDScript）
# =============================================================================
# 落地自 docs/art-bible/pixel-asset-pipeline.md §4（扩展自 feasibility-review §6.5）。
# 验收规则（任一不满足 → 阻断导入，除非标注为软警告）：
#   R1 不透明色数 ≤ 16            R2 每色 ∈ 母库(art-bible §2.2, 19色)
#   R3 每色 ∈ 场景子集(bestiary §4：上层9/中层7/boss10/sanctuary9) R4 无半透明像素(alpha∈{0,255})
#   R5 color_count/checksum 与 manifest 一致   R6 命名符合 {category}_{entity}_{variant}_{size}.png
#
# 用法（headless，Godot 4.3）：
#   godot --headless --path . -s res://src/core/asset_pipeline/palette_validator.gd
#   退出码 = 失败资产数（0 = 全通过），push_error 逐条打印原因。
#   四场景(upper/mid/boss/sanctuary)均按 bestiary §4 子集执行完整 R3 硬阻断，无降级兜底分支。
#
# 注意：引擎版本钉定见 docs/engine-reference/godot/VERSION.md（已签字 Godot 4.3，2026-11-03）。
#       文件加载经 _load_png（FileAccess.open + Image.load_png_from_buffer）直接读原始 PNG 字节，
#       绕过 Godot 导入系统（否则 .png 被当作 Texture2D 拦截、load_from_file 返回空图像）。
#       2026-11-07 修正：原稿 extends EditorScript 导致 -s headless 永远无法实例化、R5/R6 从未真正跑过；
#       改为 extends SceneTree + _initialize() 入口，使 CI headless 命令真实可执行。
# =============================================================================

extends SceneTree

# —— 母库（art-bible §2.2，19 色 ≤32）——
# 注：原稿误用 { "FF8C42", ... } 字典字面量（GDScript 字典必须 key:value），
#     导致脚本 Parse Error、R1–R6 从未真正可执行。此处修正为数组，
#     MASTER.has(col) 语义不变，是零行为变化的最小语法修复。
const MASTER := [
	"FF8C42", "3FA7FF", "5FD35A", "7BC9B0", "FFD23F", "7A5E9E", "D98E32",
	"2B3A66", "FF6A2C", "9B6BFF", "2EC4B6", "FF6FB5", "A56A43", "FF4D4D",
	"A6FF4D", "1A1C2C", "2B2F4A", "F4E4C1", "9AA0B5"
]

# —— 场景子集（bestiary §4：上层9 / 中层7 / boss10 / sanctuary9，均 ≤16）——
const SCENE := {
	"upper":     ["7BC9B0", "5FD35A", "FFD23F", "A56A43", "2EC4B6", "1A1C2C", "F4E4C1", "FF8C42", "2B2F4A"],
	"mid":       ["D98E32", "FF6A2C", "7A5E9E", "3FA7FF", "2EC4B6", "F4E4C1", "1A1C2C"],
	"boss":      ["1A1C2C", "2B3A66", "FF6A2C", "FFD23F", "2EC4B6", "FF4D4D", "7A5E9E", "A6FF4D", "F4E4C1", "9AA0B5"],
	"sanctuary": ["FF8C42", "F4E4C1", "FFD23F", "A56A43", "2B2F4A", "3FA7FF", "5FD35A", "1A1C2C", "9AA0B5"]
}

# —— bestiary §0.1 实体 slug（R6 命名校验）——
# 注：E1（2026-11-07）扩产后 slug 集合覆盖 char/tile/prop/ui 全部实体；
#     SLUGS 改为「manifest 实际登记的全部 entity_slug」，避免 R6 对扩展清单误判 FAIL。
const SLUGS := [
	"tamer", "mossback", "emberhorn", "frostling", "voltsprite", "boss_deep",
	"upper_floor", "upper_wall", "mid_floor", "boss_lava", "sanctuary_floor",
	"chest", "trap", "rune"
]
const CATEGORIES := ["char", "tile", "ui", "fx", "prop"]

const ALPHA_CUTOFF := 128          # 与 pipeline / art-bible §1.3 ①a 一致
const MAX_COLORS := 16

# ---------------------------------------------------------------------------
# 主校验：输入 Texture2D 或 Image；返回是否通过（硬阻断项）。push_error/push_warning 记录原因。
# ---------------------------------------------------------------------------
func validate(source, scene: String, cap: int = MAX_COLORS) -> bool:
	var img: Image
	if source is Texture2D:
		img = source.get_image()
	elif source is Image:
		img = source
	else:
		push_error("PaletteValidator: 不支持的源类型 %s" % typeof(source))
		return false
	return _validate_image(img, scene, cap)

# 文件入口：绕过 Godot 导入系统，直接读原始 PNG 字节解析（避免 .png 被当作 Texture2D 拦截）。
func validate_file(path: String, scene: String, cap: int = MAX_COLORS) -> bool:
	var img := _load_png(path)
	return _validate_image(img, scene, cap)

# 用 FileAccess 读取 res:///user:// 原始字节并 load_png_from_buffer（PNG-8 真 PNG 可直接解析）。
func _load_png(path: String) -> Image:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("PaletteValidator: 无法读取 %s" % path)
		return Image.new()
	var buf := f.get_buffer(f.get_length())
	var img := Image.new()
	if img.load_png_from_buffer(buf) != OK:
		push_error("PaletteValidator: PNG 解析失败 %s" % path)
		return Image.new()
	return img

func _validate_image(img: Image, scene: String, cap: int) -> bool:
	if img.is_empty():
		push_error("PaletteValidator: 空图像")
		return false
	var used := {}
	var h := 0
	var w := img.get_width(); var hh := img.get_height()
	for y in hh:
		for x in w:
			var c := img.get_pixel(x, y)
			if c.a < ALPHA_CUTOFF / 255.0:
				continue                     # 透明像素（R4 透明侧）
			if c.a < 0.99:
				push_error("R4 半透明像素 @%d,%d alpha=%.2f" % [x, y, c.a])
				return false                # R4 硬阻断
			var hex := c.to_html(false).to_upper()
			used[hex] = true
	# R1
	if used.size() > cap:
		push_error("R1 调色板 %d > %d" % [used.size(), cap])
		return false
	# R2 + R3
	for col in used.keys():
		if not MASTER.has(col):
			push_error("R2 母库外色: %s" % col)
			return false
		if SCENE.has(scene) and not SCENE[scene].has(col):
			push_error("R3 场景%s子集外色: %s" % [scene, col])
			return false
	return true

# ---------------------------------------------------------------------------
# R5：与 asset-manifest.csv 一致性（color_count + checksum）。返回是否一致。
# ---------------------------------------------------------------------------
func validate_against_manifest(asset_path: String, checksum: String, color_count: int) -> bool:
	var f := FileAccess.open("res://src/core/asset_pipeline/asset_manifest.csv", FileAccess.READ)
	if f == null:
		push_warning("R5 manifest 不存在，跳过一致性比对")
		return true
	var header := f.get_line().split(",")
	var idx_path := header.find("asset_path")
	var idx_cc := header.find("color_count")
	var idx_cs := header.find("checksum")
	while not f.eof_reached():
		var row := f.get_line().split(",")
		if row.size() <= idx_path or row[idx_path] != asset_path:
			continue
		if row[idx_cc].to_int() != color_count:
			push_error("R5 color_count 不一致: manifest=%s 实际=%d" % [row[idx_cc], color_count])
			return false
		if row[idx_cs] != checksum:
			push_error("R5 checksum 不一致(可能被重量化/篡改): manifest=%s 实际=%s" % [row[idx_cs], checksum])
			return false
		return true
	push_error("R5 未在 manifest 找到 %s" % asset_path)
	return false

# ---------------------------------------------------------------------------
# R6：命名符合 {category}_{entity}_{variant}_{size}.png 且 entity ∈ slug（软警告）。
#   entity 可含下划线（如瓦片 upper_floor），故 entity = 首段之后、末两段(variant/size)之前的所有段拼接。
# ---------------------------------------------------------------------------
func validate_naming(file_name: String) -> bool:
	var base := file_name.get_file().get_basename()
	var parts := base.split("_")
	if parts.size() < 4:
		push_warning("R6 命名不符合 {category}_{entity}_{variant}_{size}: %s" % file_name)
		return false
	if not CATEGORIES.has(parts[0]):
		push_warning("R6 未知 category: %s" % parts[0])
		return false
	var size_str: String = parts[parts.size() - 1]
	if not (size_str.is_valid_int() and int(size_str) in [16, 24, 32, 48]):
		push_warning("R6 size 非法(需16/24/32/48): %s" % size_str)
		return false
	# entity = parts[1 .. -3] 拼接（末两段为 variant、size）
	var entity := ""
	for i in range(1, parts.size() - 2):
		if entity != "":
			entity += "_"
		entity += parts[i]
	if not SLUGS.has(entity):
		push_warning("R6 entity 非登记 slug: %s" % entity)
		return false
	return true

# ---------------------------------------------------------------------------
# headless -s 入口：依据 asset-manifest.csv 逐资产校验（R1–R6）。
#   调用：godot --headless --path . -s res://src/core/asset_pipeline/palette_validator.gd
#   退出码 = 失败资产数（0 = 全通过）。
# ---------------------------------------------------------------------------
func _initialize() -> void:
	var manifest := "res://src/core/asset_pipeline/asset_manifest.csv"
	var f := FileAccess.open(manifest, FileAccess.READ)
	if f == null:
		push_error("PaletteValidator: 找不到 manifest %s" % manifest)
		quit(1)
		return
	var header := f.get_line().split(",")
	var i_path := header.find("asset_path")
	var i_scene := header.find("scene")
	var i_cc := header.find("color_count")
	var i_cs := header.find("checksum")
	var total := 0; var fails := 0
	while not f.eof_reached():
		var row := f.get_line().split(",")
		if row.size() <= i_path or row[i_path] == "":
			continue
		total += 1
		var path: String = row[i_path]
		# manifest 用仓库根相对路径；FileAccess 读 res:// 资源需 res:// 前缀
		var res_path: String = path if path.begins_with("res://") else "res://" + path
		var scene: String = row[i_scene] if i_scene >= 0 and row.size() > i_scene else "upper"
		validate_naming(path.get_file())
		if not validate_file(res_path, scene):
			fails += 1
			continue
		if i_cs >= 0 and row.size() > i_cs and row[i_cs] != "":
			var cc := count_colors_file(res_path)
			if not validate_against_manifest(path, row[i_cs], cc):
				fails += 1
	print("PaletteValidator: 共 %d 资产，失败 %d（见上方 error/warning）" % [total, fails])
	quit(fails)

func count_colors_file(path: String) -> int:
	var img := _load_png(path)
	if img.is_empty():
		return -1
	var used := {}
	var w := img.get_width(); var h := img.get_height()
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			if c.a >= ALPHA_CUTOFF / 255.0 and c.a >= 0.99:
				used[c.to_html(false).to_upper()] = true
	return used.size()

# pouch_screen.gd — 灵囊屏（Epic F3 / ux-spec §3.2）
# =====================================================================
# 三栏分段控件（灵兽/符文/物资），每栏标题命中区 ≥48px。
# 灵兽格：slug 立绘位 + 数量角标（ENG-2 裁定：重复灵兽 = +1 计数，角标 ×N）。
# 每物品格 ≥48px；所有格常驻热区（点选记录 last_selected），分段切换仅改显示焦点。
# 长按需查看详情、拖拽装备（交互逻辑留 UI 集成层，本模块仅暴露命中区与选择态）。
# 无随机（ADR-5）。
# =====================================================================

class_name PouchScreen
extends UiScreen

const CELL_H := 56.0
const SEG_H := 48.0
const PAD := 8.0
const COLS := ["spirits", "runes", "materials"]

var view_data: PouchViewData
var current_column: String = "spirits"
var last_selected: String = ""


func _init() -> void:
	id = "pouch"


func _build() -> void:
	view_data = PouchViewData.new()
	if ctx != null:
		view_data.build_from_pouch(ctx.pouch, ctx.bestiary)
	_layout()


func _column_for(seg_id: String) -> String:
	match seg_id:
		"seg_spirits": return "spirits"
		"seg_runes": return "runes"
		"seg_materials": return "materials"
	return ""


func _items_for(col: String) -> Array:
	if view_data == null:
		return []
	match col:
		"spirits": return view_data.spirits
		"runes": return view_data.runes
		"materials": return view_data.materials
	return []


func _layout() -> void:
	_zones.clear()
	hit_zone.clear()
	var region := Rect2(Vector2.ZERO, Vector2(720, 1280))
	var top := region.position.y + SEG_H + PAD
	var col_w := (region.size.x - PAD * 4.0) / 3.0
	for ci in range(COLS.size()):
		var cx := region.position.x + PAD + float(ci) * (col_w + PAD)
		# 分段控件标题（每栏，≥48px）
		var seg_id := "seg_" + COLS[ci]
		_add_rect(seg_id, Rect2(cx, region.position.y + PAD * 0.5, col_w, SEG_H))
		# 该栏物品格
		var items: Array = _items_for(COLS[ci])
		for i in range(items.size()):
			var ry := top + float(i) * (CELL_H + PAD)
			var zid := COLS[ci] + "_" + str(i)
			_add_rect(zid, Rect2(cx, ry, col_w, CELL_H))


func on_enter() -> void:
	active = true
	if ctx != null:
		view_data.build_from_pouch(ctx.pouch, ctx.bestiary)
	_layout()


func on_action(zone_id: String) -> void:
	if zone_id.begins_with("seg_"):
		var col := _column_for(zone_id)
		if col != "":
			current_column = col
		return
	if zone_id.find("_") > 0:
		last_selected = zone_id

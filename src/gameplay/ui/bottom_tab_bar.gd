# bottom_tab_bar.gd — 底部固定 Tab 栏（UX 规格 §2 / F1）
# =====================================================================
# 四槽 [总览][灵囊][灵脉][地图]，每槽 ≥56×56px，间距 ≥8px（a11y §3.2）。
# 单手拇指热区：置于屏幕底部条带，水平居中。文字标签优先（弱图标·政务式审美，
# ux-spec §0.2）。仅含布局元数据，无随机（ADR-5）。
# =====================================================================

class_name BottomTabBar
extends RefCounted

const TAB_IDS := ["overview", "pouch", "spirit_vein", "map"]
const TAB_LABELS := ["总览", "灵囊", "灵脉", "地图"]
const TAB_SIZE := 56.0            # 主操作建议 ≥56（a11y §3.2 / ux-spec §2）
const TAB_SPACING := 8.0          # 相邻 ≥8px（a11y §3.2）

var hit_zone = null
var selected_index: int = 0
var _rects: Array = []
var _labels: Dictionary = {}      # id -> 文字标签（弱图标：文字优先）


func _init() -> void:
	hit_zone = HitZone.new()
	for i in range(TAB_IDS.size()):
		_labels[TAB_IDS[i]] = TAB_LABELS[i]


# 在底部条带内水平居中布局 4 个等距 tab（单手拇指热区）。
func build(bottom_region: Rect2) -> void:
	hit_zone.clear()
	_rects.clear()
	var n := float(TAB_IDS.size())
	var total_w := n * TAB_SIZE + (n - 1.0) * TAB_SPACING
	var start_x := bottom_region.position.x + (bottom_region.size.x - total_w) * 0.5
	var y := bottom_region.position.y + (bottom_region.size.y - TAB_SIZE) * 0.5
	for i in range(TAB_IDS.size()):
		var x := start_x + float(i) * (TAB_SIZE + TAB_SPACING)
		var r := Rect2(x, y, TAB_SIZE, TAB_SIZE)
		_rects.append(r)
		hit_zone.register_rect(TAB_IDS[i], r, TAB_IDS[i])


# 把 tab 热区注册进给定 HitZone（供组合）。
func apply_zones(hz: HitZone) -> void:
	for i in range(TAB_IDS.size()):
		hz.register_rect(TAB_IDS[i], _rects[i], TAB_IDS[i])


func select_by_id(zone_id: String) -> bool:
	var idx := TAB_IDS.find(zone_id)
	if idx >= 0:
		selected_index = idx
		return true
	return false


func selected_id() -> String:
	if selected_index >= 0 and selected_index < TAB_IDS.size():
		return TAB_IDS[selected_index]
	return ""


func label_for(id: String) -> String:
	return _labels.get(id, "")


func hit_rect_for(id: String) -> Rect2:
	var idx := TAB_IDS.find(id)
	if idx >= 0 and idx < _rects.size():
		return _rects[idx]
	return Rect2()


func tab_ids() -> Array:
	return TAB_IDS.duplicate()


func rects() -> Array:
	return _rects

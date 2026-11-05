# spirit_vein_screen.gd — 灵脉图谱屏（Epic F4 / ux-spec §3.3）
# =====================================================================
# 节点：视觉 44px，命中区 ≥48px（a11y §3.2 澄清，半径 24 → 直径 48）。
# 连接：已激活路径高亮、未激活灰（状态由 shape 表达：星=已点/锁=未解锁/高亮=可点）。
# 缩放/平移：边缘按钮（≥48px），保证单手可触达中心节点；缩放改变布局后通知
# router 重建合并热区（rebuild_combined）。
# 节点激活：点击 → can_activate 校验 → VeinGraph.activate 扣 ember 并刷新状态。
# 无随机（ADR-5）。
# =====================================================================

class_name SpiritVeinScreen
extends UiScreen

const NODE_RADIUS := 24.0      # 直径 48 = 命中区下限
const ZOOM_BTN := 56.0
const PAD := 12.0
const MIN_SCALE := 0.6
const MAX_SCALE := 1.8

var view_data: SpiritVeinViewData
var _scale: float = 1.0
var _offset: Vector2 = Vector2.ZERO


func _init() -> void:
	id = "spirit_vein"


func _build() -> void:
	view_data = SpiritVeinViewData.new()
	_refresh()
	_layout()


func _refresh() -> void:
	if ctx != null and ctx.vein_graph != null:
		view_data.build_from_graph(ctx.vein_graph, ctx.ember)


func _screen_pos(pos: Vector2) -> Vector2:
	return pos * _scale + _offset


func _layout() -> void:
	_zones.clear()
	hit_zone.clear()
	if view_data != null:
		# 节点命中区（圆形，直径 = 2*NODE_RADIUS = 48 ≥48px）
		for nd in view_data.nodes:
			var p := _screen_pos(Vector2(float(nd["x"]), float(nd["y"])))
			_add_circle(nd["id"], p, NODE_RADIUS)
	# 缩放按钮（左上角落，≥48px）
	var region := Rect2(Vector2.ZERO, Vector2(720, 1280))
	_add_rect("zoom_in", Rect2(region.position.x + PAD, region.position.y + PAD, ZOOM_BTN, ZOOM_BTN))
	_add_rect("zoom_out", Rect2(region.position.x + PAD, region.position.y + PAD + ZOOM_BTN + 8.0, ZOOM_BTN, ZOOM_BTN))


func zoom_in() -> void:
	_scale = min(MAX_SCALE, _scale + 0.2)
	_layout()
	if router != null:
		router.rebuild_combined()


func zoom_out() -> void:
	_scale = max(MIN_SCALE, _scale - 0.2)
	_layout()
	if router != null:
		router.rebuild_combined()


func on_enter() -> void:
	active = true
	_refresh()
	_layout()


func on_action(zone_id: String) -> void:
	if zone_id == "zoom_in":
		zoom_in()
		return
	if zone_id == "zoom_out":
		zoom_out()
		return
	# 节点激活意图
	if ctx != null and ctx.vein_graph != null:
		var g = ctx.vein_graph
		if g.nodes.has(zone_id):
			if g.can_activate(zone_id, ctx.ember):
				var rem := g.activate(zone_id, ctx.ember)
				if rem >= 0:
					ctx.ember = rem
					_refresh()   # 状态变化（positions 不变，无需 re-layout）

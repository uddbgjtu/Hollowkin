# ui_screen.gd — UI 屏基类（Epic F / UX 规格 §2-§3）
# =====================================================================
# 每屏持有自身 HitZone 与热区清单；ScreenRouter 通过 apply_zones() 把 tab 热区
# + 当前屏热区合并进同一 HitZone，交由 Epic C 的 InputQueue 做帧末结算（ADR-2）。
# 设计为 RefCounted，可无场景树单测；真实 Godot Control 节点可组合/持有本实例。
# 仅含布局与路由元数据，不含任何随机（ADR-5）。
# =====================================================================

class_name UiScreen
extends RefCounted

const THUMB_ZONE_RATIO := 0.40   # 竖屏拇指热区：底部 40% 扇形（ux-spec §1）

var id: String = ""
var active: bool = false
var hit_zone = null              # HitZone（自身热区，独立可用）
var ctx = null                   # UiContext（领域对象引用，bind 注入）
var router = null                # ScreenRouter（用于屏内导航意图）
var _zones: Array = []           # Array[Dictionary]: {id, type:"rect", rect:Rect2} | {id, type:"circle", center:Vector2, radius:float}


func _init(p_id: String = "") -> void:
	id = p_id
	hit_zone = HitZone.new()


# 注入领域上下文（Pouch / VeinGraph / CombatDirector 等），触发一次布局构建。
func bind(p_ctx) -> void:
	ctx = p_ctx
	_build()


# 注入路由（屏内导航意图用）。由 ScreenRouter.register 自动调用。
func set_router(r) -> void:
	router = r


# 子类重写：构建自身热区与视图数据。bind() 时调用一次。
func _build() -> void:
	pass


func on_enter() -> void:
	active = true


func on_exit() -> void:
	active = false


# 屏内导航意图（如 总览"进入地牢"→ battle）。经 router 延迟切换，避免帧末重入。
func request_navigation(target_id: String) -> void:
	if router != null:
		router.request_switch(target_id)


func on_action(zone_id: String) -> void:
	pass


# 把本屏热区注册进给定 HitZone（供 ScreenRouter 组合 tab+屏热区，ADR-2 路由）。
func apply_zones(hz: HitZone) -> void:
	for z in _zones:
		if z["type"] == "rect":
			hz.register_rect(z["id"], z["rect"], z["id"])
		else:
			hz.register_circle(z["id"], z["center"], z["radius"], z["id"])


func _add_rect(id: String, rect: Rect2) -> void:
	_zones.append({"id": id, "type": "rect", "rect": rect})
	hit_zone.register_rect(id, rect, id)


func _add_circle(id: String, center: Vector2, radius: float) -> void:
	_zones.append({"id": id, "type": "circle", "center": center, "radius": radius})
	hit_zone.register_circle(id, center, radius, id)


func zones() -> Array:
	return _zones


# 单手可达性软度量（a11y §3 / ux-spec §1）：rect 中心落在底部 THUMB_ZONE_RATIO 区域。
# 仅作布局审计，不强制阻断（主操作须热区化）。viewport_h 为逻辑高度（@1x）。
func is_in_thumb_zone(rect: Rect2, viewport_h: float) -> bool:
	var bottom := viewport_h * (1.0 - THUMB_ZONE_RATIO)
	return rect.position.y + rect.size.y * 0.5 >= bottom

# overview_screen.gd — 探索总览屏（Epic F 总览 / ux-spec §3.4）
# =====================================================================
# 顶部：当前层/种子/资源计数（文字标签，非纯图标）。
# 中部：进入地牢主按钮（≥64px，置于热区）。
# 底部：固定 Tab 栏（由 router 注入热区）。
# 进入地牢 → 经 router 延迟切换到 battle 屏。
# 无随机（ADR-5）。
# =====================================================================

class_name OverviewScreen
extends UiScreen

const VIEWPORT := Vector2(720, 1280)
const ENTER_W := 220.0
const ENTER_H := 64.0     # ≥64px 主按钮（ux-spec §3.4）

var view: Dictionary = {}   # HUD 数据：floor/seed/ember/coin/spirit_count/party_count


func _init() -> void:
	super._init("overview")


func _build() -> void:
	_build_view()
	var region := Rect2(Vector2.ZERO, VIEWPORT)
	var cx := region.position.x + region.size.x * 0.5
	var by := region.position.y + region.size.y * 0.78   # 热区偏下（单手可达）
	_add_rect("enter_dungeon", Rect2(cx - ENTER_W * 0.5, by, ENTER_W, ENTER_H))


func _build_view() -> void:
	if ctx == null:
		return
	view = {
		"floor": ctx.floor_index,
		"seed": ctx.run_seed,
		"ember": ctx.ember,
		"coin": ctx.pouch.coin_temp if ctx.pouch != null else 0,
		"spirit_count": ctx.pouch.spirits.size() if ctx.pouch != null else 0,
		"party_count": ctx.party.get_party().size() if ctx.party != null else 0,
	}


func on_enter() -> void:
	active = true
	_build_view()    # 每次进入刷新资源计数


func on_action(zone_id: String) -> void:
	if zone_id == "enter_dungeon":
		request_navigation("battle")

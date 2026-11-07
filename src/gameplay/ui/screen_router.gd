# screen_router.gd — 屏路由 + 帧末输入分发（Epic F / ADR-2）
# =====================================================================
# 持有四主屏与底部 Tab 栏；仅一屏激活；复用 Epic C 的 InputQueue/HitZone
# 做帧末结算（输入不立即改 UI 状态，ADR-2）。tab 区始终可用，当前激活屏
# 热区叠加其上；路由时 tab 优先，否则派发给当前屏。
# 非 tab 屏（如战斗）进入时隐藏底部 Tab，避免误触切走（ux-spec §3.1）。
# 仅路由元数据，无随机（ADR-5）。
# =====================================================================

class_name ScreenRouter
extends RefCounted

var tab_bar: BottomTabBar
var screens: Dictionary = {}
var _order: Array = []        # tab_index -> screen id
var active_id: String = ""
var queue: InputQueue
var _combined: HitZone
var _pending_switch: String = ""
var _tab_bar_enabled: bool = true


func _init() -> void:
	tab_bar = BottomTabBar.new()
	queue = InputQueue.new()
	_combined = HitZone.new()


# tab_index: 该屏在底部 Tab 的位置（-1 表示非 Tab 屏，如战斗，由 overview 启动）。
func register(screen: UiScreen, tab_index: int = -1) -> void:
	screens[screen.id] = screen
	screen.set_router(self)
	if tab_index >= 0 and tab_index < tab_bar.tab_ids().size():
		while _order.size() <= tab_index:
			_order.append("")
		_order[tab_index] = screen.id


func build(bottom_region: Rect2) -> void:
	tab_bar.build(bottom_region)
	# 底部 Tab 为导航热区，豁免技能 0.5s 重触发 cd（tab 始终可用，ux-spec §2）。
	queue.set_cooldown_exempt(tab_bar.tab_ids())


func switch_to(screen_id: String) -> bool:
	if not screens.has(screen_id):
		return false
	if active_id != "" and screens.has(active_id):
		screens[active_id].on_exit()
	active_id = screen_id
	screens[active_id].on_enter()
	# 非 tab 屏（如战斗）隐藏底部 Tab，避免误触切换。
	_tab_bar_enabled = _order.has(screen_id)
	_rebuild_combined()
	var idx := _order.find(screen_id)
	if idx >= 0:
		tab_bar.selected_index = idx
	return true


func is_tab_bar_enabled() -> bool:
	return _tab_bar_enabled


# 屏内导航意图：延迟到帧末 flush 后切换，避免 consume 重入。
func request_switch(screen_id: String) -> void:
	_pending_switch = screen_id


# 由屏（如灵脉缩放）在自身布局变化后调用，重建合并热区。
func rebuild_combined() -> void:
	_rebuild_combined()


func _rebuild_combined() -> void:
	_combined.clear()
	if _tab_bar_enabled:
		tab_bar.apply_zones(_combined)
	if active_id != "" and screens.has(active_id):
		screens[active_id].apply_zones(_combined)
	queue.set_hit_zone(_combined)


# 外部（pc_input_adapter 集成层）把 InputEvent 抽为 position 后入队（ADR-2）。
func push_pointer(position: Vector2, touch_id: int = -1) -> void:
	queue.push({"position": position, "touch_id": touch_id})


# 帧末结算（由 SimulationClock 每 tick 调用，ADR-2）。
func flush(dt: float = 0.1) -> void:
	queue.advance_time(dt)
	queue.consume_into(self)
	if _pending_switch != "":
		switch_to(_pending_switch)
		_pending_switch = ""


# InputQueue 回调：tab 优先，否则派发给当前激活屏。
func on_action(zone_id: String) -> void:
	var idx := tab_bar.tab_ids().find(zone_id)
	if idx >= 0:
		if not _tab_bar_enabled:
			return   # 战斗中忽略 tab 热区，避免误切
		var sid: String = _order[idx]
		if sid != "" and sid != active_id:
			_pending_switch = sid
		return
	if active_id != "" and screens.has(active_id):
		screens[active_id].on_action(zone_id)

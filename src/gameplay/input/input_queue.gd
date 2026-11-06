# input_queue.gd — ADR-2 输入队列（生产版）
# =====================================================================
# 职责（architecture-doc.md §1.6 / ADR-2）：所有触屏事件入队，帧末结算
#       （consume_into），不立即改仿真。按命中区（hit-zone id）归并去重；
#       技能重触发 cd 下限钳 0.5s（GDD §6.4），防卡死 / 防抖动重触发。
#       浮杆 touch_id 由 JoystickPointer 独占，本队列只管技能/按钮热区；
#       位置→热区经 HitZone 解析。全程无全局随机（ADR-5）；无全局输入读取，
#       事件由外部（InputArbiter 节点）从 InputEventScreenTouch/Drag 抽取后 push。
# 设计为 RefCounted，可无场景树单测。
# =====================================================================

class_name InputQueue
extends RefCounted

const CD_FLOOR := 0.5   # 秒；GDD §6.4 cd 下限钳 0.5s

var hit_zone = null     # HitZone（注入）：位置→热区 id 解析
var _events: Array = []                 # Array[Dictionary]: {"position": Vector2, "touch_id": int}
var _last_fire: Dictionary = {}         # zone_id -> 上次命中仿真时刻
var _cooldown_exempt: Dictionary = {}   # zone_id -> true：导航/UI 热区豁免 0.5s 重触发 cd
var _sim_time: float = 0.0              # 内部累加仿真时刻（由 advance_time 推进）


func set_hit_zone(hz) -> void:
    hit_zone = hz


# 标记导航/UI 热区（如底部 Tab）豁免 0.5s 重触发 cd：cd 仅用于技能防抖，
# 不应阻塞 Tab 切换等显式导航意图（tab 始终可用）。
func set_cooldown_exempt(ids: Array) -> void:
    _cooldown_exempt.clear()
    for id in ids:
        _cooldown_exempt[id] = true


# 事件由 InputArbiter 从 InputEventScreenTouch/Drag 抽取 position 后入队。
# 事件字典至少含 "position"（Vector2）；"touch_id" 仅作透传/审计用。
func push(event: Dictionary) -> void:
    _events.append({"position": event.get("position", Vector2.ZERO), "touch_id": event.get("touch_id", -1)})


# 推进内部仿真时刻（由 SimulationClock 每 tick 调用，使 0.5s 下限钳基于仿真时间）。
func advance_time(dt: float) -> void:
    _sim_time += dt


# 帧末结算：解析位置→热区，按热区去重，0.5s 下限钳，回调 target.on_action(id)。
# target 需提供 on_action(id: String)（如 CombatDirector）；为空则仅做去重/钳制。
func consume_into(target) -> void:
    var seen: Dictionary = {}
    for e in _events:
        var zone_id := _resolve(e)
        if zone_id == "":
            continue
        if seen.has(zone_id):
            continue  # 同 tick 内同热区去重
        # cd 下限钳 0.5s：距上次命中不足 0.5s 则跳过（跨 tick 去重重触发）。
        # 导航/UI 热区（如底部 Tab）豁免，避免阻塞显式切换意图。
        if not _cooldown_exempt.has(zone_id):
            var last: float = float(_last_fire.get(zone_id, -INF))
            if _sim_time - last < CD_FLOOR:
                continue
        seen[zone_id] = true
        _last_fire[zone_id] = _sim_time
        if target != null and target.has_method("on_action"):
            target.on_action(zone_id)
    _events.clear()


func _resolve(e: Dictionary) -> String:
    if hit_zone == null:
        return ""
    return hit_zone.resolve(e["position"])

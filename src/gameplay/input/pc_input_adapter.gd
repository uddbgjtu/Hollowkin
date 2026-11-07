# pc_input_adapter.gd — ADR-6 键鼠输入适配层（Wave 3）
# =====================================================================
# 把 Windows Desktop 的鼠标 / 键盘 InputEvent 统一翻译成 ADR-2 的同构字典
# {"position": Vector2, "touch_id": 0}，再交给 InputQueue.push()。
# 关键约束：
#   - 不在这里改任何仿真 / UI 状态（帧末结算仍由 InputQueue.consume_into 负责）。
#   - 键盘按键不是直接调 on_action，而是映射到对应热区中心坐标后走同一队列，
#     因此热区去重、0.5s cd 钳、tab 豁免、pending 延迟切换全部原样保留。
#   - 移动端 InputEventScreenTouch/Drag 已按 ADR-6 彻底放弃，不再兼容。
# 设计为 RefCounted，可无场景树单测；不加 class_name（全局类缓存保持 40 类）。
# 无任何随机（ADR-5）。
# =====================================================================

extends RefCounted

const POINTER_ID := 0

var _zone_centers: Dictionary = {}   # zone_id -> Vector2（热区中心）
var _key_map: Dictionary = {}        # keycode(int) -> zone_id(String)


# 由主场景在 router.build() 之后注入：把热区 id 与其中心坐标登记进来。
func bind_zone(zone_id: String, center: Vector2) -> void:
    _zone_centers[zone_id] = center


func bind_key(keycode: int, zone_id: String) -> void:
    _key_map[keycode] = zone_id


func zone_center(zone_id: String) -> Vector2:
    if _zone_centers.has(zone_id):
        var c: Vector2 = _zone_centers[zone_id]
        return c
    return Vector2.ZERO


func key_binding_count() -> int:
    return _key_map.size()


# 返回 0..1 个同构事件字典；未知事件返回空数组，绝不臆造输入。
func translate(event: InputEvent) -> Array:
    var out: Array = []
    if event is InputEventMouseButton:
        var mb: InputEventMouseButton = event as InputEventMouseButton
        if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
            out.append(_pointer(mb.position))
        return out
    if event is InputEventMouseMotion:
        var mm: InputEventMouseMotion = event as InputEventMouseMotion
        if (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
            out.append(_pointer(mm.position))
        return out
    if event is InputEventKey:
        var k: InputEventKey = event as InputEventKey
        if not k.pressed or k.echo:
            return out
        if _key_map.has(k.keycode):
            var zone_id: String = str(_key_map[k.keycode])
            if _zone_centers.has(zone_id):
                var center: Vector2 = _zone_centers[zone_id]
                out.append(_pointer(center))
        return out
    return out


# 便捷入口：把翻译结果直接入队，返回入队条数（仍不触发结算）。
func push_into(queue, event: InputEvent) -> int:
    var events: Array = translate(event)
    for e in events:
        queue.push(e)
    return events.size()


func _pointer(position: Vector2) -> Dictionary:
    return {"position": position, "touch_id": POINTER_ID}

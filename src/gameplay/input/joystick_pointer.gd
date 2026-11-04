# joystick_pointer.gd — ADR-2 浮动摇杆（生产版，单 touch_id 独占）
# =====================================================================
# 职责（architecture-doc.md §1.6 / GDD §2）：单虚拟摇杆 8 向，角色自动朝向；
#       浮杆独占单一 touch_id，不与技能热区抢占。无全局输入读取，由方法驱动
#       （press/move/release/get_direction），便于无头测试。
# GDD §2：死区 15%（magnitude < 0.15 * max_radius → 零向量）。
# 设计为 RefCounted，可无场景树单测。
# =====================================================================

class_name JoystickPointer
extends RefCounted

const DEADZONE_FRACTION := 0.15

var max_radius: float = 64.0   # 死区参考半径（像素），外部按 HUD 设定（默认 64px）

var _touch_id: int = -1
var _active: bool = false
var _origin: Vector2 = Vector2.ZERO
var _current: Vector2 = Vector2.ZERO


# 按下：以按下点为浮杆原点，独占该 touch_id。
func press(touch_id: int, origin: Vector2) -> void:
    _touch_id = touch_id
    _origin = origin
    _current = origin
    _active = true


# 拖动：仅当 touch_id 匹配且激活时更新当前点。
func move(touch_id: int, pos: Vector2) -> void:
    if not _active or touch_id != _touch_id:
        return
    _current = pos


# 抬起：释放独占。默认 touch_id=-1 表示不校验（呼应由外部一致传递）。
func release(touch_id: int = -1) -> void:
    if touch_id != -1 and touch_id != _touch_id:
        return
    _active = false
    _touch_id = -1
    _current = _origin


func is_active() -> bool:
    return _active


# 当前方向：8 向吸附 + 15% 死区。未激活 → 零向量。
func get_direction() -> Vector2:
    if not _active:
        return Vector2.ZERO
    var raw := _current - _origin
    var len := raw.length()
    if len < DEADZONE_FRACTION * max_radius:
        return Vector2.ZERO
    var dir := raw / len
    return _snap_8(dir)


func _snap_8(dir: Vector2) -> Vector2:
    # 吸附到最近的 45° 方向（8 向）。
    var angle := dir.angle()
    var step := PI / 4.0
    var snapped_angle := round(angle / step) * step
    return Vector2(cos(snapped_angle), sin(snapped_angle))

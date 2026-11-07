# hit_zone.gd — ADR-2 热区注册表（生产版）
# =====================================================================
# 职责（architecture-doc.md §1.6 / ADR-2）：注册技能/按钮热区
#       {id, shape(rect 或 circle, ≥48px), skill_binding}，并提供
#       resolve(position) -> zone_id。仅支持轴对齐矩形或圆，保持最小。
# ADR-6 a11y：点击区域 ≥24x24px + 全功能键盘可达；低于下限时 push_warning（不阻断）。
# 设计为 RefCounted，可无场景树单测。
# =====================================================================

class_name HitZone
extends RefCounted

const MIN_TARGET_PX := 24.0   # ADR-6 a11y：键鼠可操作目标下限 ≥24x24px

var _zones: Array = []        # Array[Dictionary]: {"id","type","rect"|"center"/"radius","skill"}


# 轴对齐矩形热区。rect.size 任一维 < 24px 触发 a11y 警告（仍注册）。
func register_rect(id: String, rect: Rect2, skill_binding: String = "") -> void:
    if rect.size.x < MIN_TARGET_PX or rect.size.y < MIN_TARGET_PX:
        push_warning("HitZone: 热区 '%s' 尺寸 %.0fx%.0f 小于 24px 下限(ADR-6 a11y)" % [id, rect.size.x, rect.size.y])
    _zones.append({"id": id, "type": "rect", "rect": rect, "skill": skill_binding})


# 圆形热区。直径 < 24px 触发 a11y 警告（仍注册）。
func register_circle(id: String, center: Vector2, radius: float, skill_binding: String = "") -> void:
    if radius * 2.0 < MIN_TARGET_PX:
        push_warning("HitZone: 热区 '%s' 直径 %.0f 小于 24px 下限(ADR-6 a11y)" % [id, radius * 2.0])
    _zones.append({"id": id, "type": "circle", "center": center, "radius": radius, "skill": skill_binding})


# 命中判定：后注册者优先（上层 UI 覆盖下层），返回 id 或 ""。
func resolve(position: Vector2) -> String:
    for i in range(_zones.size() - 1, -1, -1):
        var z: Dictionary = _zones[i]
        if z["type"] == "rect":
            if z["rect"].has_point(position):
                return z["id"]
        else:
            if z["center"].distance_to(position) <= z["radius"]:
                return z["id"]
    return ""


func clear() -> void:
    _zones.clear()

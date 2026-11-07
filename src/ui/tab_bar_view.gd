# tab_bar_view.gd — 横屏底部 Tab 栏视图（Wave 3）
# =====================================================================
# 只绘制 BottomTabBar 已注册的真实热区矩形，不另算坐标，保证「看到的可点区域」
# 与 HitZone.resolve() 判定完全一致。选中态以边框 / 填充区分（a11y 双编码）。
# 不加 class_name，全局类缓存保持 40 类；无随机（ADR-5）。
# =====================================================================

extends Control

const LayoutConfig := preload("res://src/ui/layout_config.gd")

var bar = null
var active_id: String = ""


func bind(p_bar) -> void:
    bar = p_bar
    queue_redraw()


func set_active(id: String) -> void:
    active_id = id
    queue_redraw()


func _draw() -> void:
    if bar == null:
        return
    var strip_rect: Rect2 = LayoutConfig.tab_bar_rect()
    var strip_top: float = strip_rect.position.y
    var strip: Color = Color(0.10, 0.13, 0.17, 1.0)
    draw_rect(strip_rect, strip)
    draw_line(Vector2(0.0, strip_top), Vector2(strip_rect.size.x, strip_top),
        Color(0.30, 0.42, 0.48, 1.0), 2.0)
    var ids: Array = bar.tab_ids()
    for i in range(ids.size()):
        var id: String = str(ids[i])
        var r: Rect2 = bar.hit_rect_for(id)
        var selected: bool = (id == active_id)
        var fill: Color
        if selected:
            fill = Color(0.20, 0.46, 0.52, 1.0)
        else:
            fill = Color(0.14, 0.18, 0.23, 1.0)
        draw_rect(r, fill)
        draw_rect(r, Color(0.45, 0.80, 0.85, 1.0), false, 2.0)

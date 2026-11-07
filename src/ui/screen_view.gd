# screen_view.gd — 四主屏 / 战斗屏的可运行视图（Wave 3）
# =====================================================================
# 只做「把 Epic F 逻辑层的热区与标签画出来」，不复制任何布局真值：
# 所有矩形 / 圆形热区都来自 UiScreen.zones()，因此画面与 ADR-2 命中判定同源。
# 不持有仿真状态、不调用随机（ADR-5）。刻意不加 class_name，全局类缓存保持 40 类。
# 文字用 Label 子节点（headless 下比 draw_string 更稳，避免字体加载噪音）。
# =====================================================================

extends Control

@export var screen_id: String = ""
@export var title: String = ""
@export var hint: String = ""

var logic_screen = null
var accent: Color = Color(0.45, 0.80, 0.85, 1.0)


func _ready() -> void:
    var tl: Label = get_node_or_null("TitleLabel") as Label
    if tl != null:
        tl.text = title
    var hl: Label = get_node_or_null("HintLabel") as Label
    if hl != null:
        hl.text = hint


func bind_logic(screen) -> void:
    logic_screen = screen
    queue_redraw()


func refresh() -> void:
    queue_redraw()


# Wave 3b：地图屏挂有 FloorTilemap / EntityLayer 时转发布局渲染；
# 其他屏没有这两个子节点则安全跳过（通用视图不绑定地图专用逻辑）。
func render_floor(layout: Dictionary, view: Rect2i) -> int:
    var tm = get_node_or_null("FloorTilemap")
    if tm == null:
        return 0
    var n: int = int(tm.build_from_layout(layout, view))
    var el = get_node_or_null("EntityLayer")
    if el != null:
        el.update_from_layout(layout, view)
    return n


func _draw() -> void:
    var bg: Color = Color(0.08, 0.10, 0.13, 1.0)
    var header: Color = Color(0.13, 0.17, 0.21, 1.0)
    draw_rect(Rect2(Vector2.ZERO, size), bg)
    draw_rect(Rect2(0.0, 0.0, size.x, 92.0), header)
    draw_line(Vector2(0.0, 92.0), Vector2(size.x, 92.0), accent, 2.0)
    if logic_screen == null:
        return
    var zones: Array = logic_screen.zones()
    var fill: Color = Color(0.16, 0.34, 0.40, 0.55)
    var line: Color = accent
    for z in zones:
        var zd: Dictionary = z
        if zd["type"] == "rect":
            var r: Rect2 = zd["rect"]
            draw_rect(r, fill)
            draw_rect(r, line, false, 2.0)
        else:
            var c: Vector2 = zd["center"]
            var rad: float = float(zd["radius"])
            draw_arc(c, rad, 0.0, TAU, 24, line, 2.0)

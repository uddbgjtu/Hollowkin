# layout_config.gd — ADR-6 PC 布局单一真源（Wave 3）
# =====================================================================
# 取代散落在 4 个 UI 屏与 test_ui.gd 中的 720x1280 竖屏硬编码。
# 新契约：横屏 1280x720 @1x，整数倍缩放（2x -> 2560x1440）护 ADR-4
# filter=false 像素资产；底部 Tab 条带单独占位，内容屏只使用 content_rect()。
# 刻意不加 class_name：保持 .godot/global_script_class_cache.cfg 仍为 40 类，
# 所有调用方以 const preload 取得，避免全局类注册时序问题。
# 纯常量与纯函数，无任何随机（ADR-5）。
# =====================================================================

extends RefCounted

const VIEWPORT_W := 1280.0
const VIEWPORT_H := 720.0
const TAB_BAR_H := 64.0
const MIN_CLICK_W := 24.0          # ADR-6 a11y：键鼠可操作目标下限
const MIN_CLICK_H := 24.0


static func viewport() -> Vector2:
    return Vector2(VIEWPORT_W, VIEWPORT_H)


# 全屏逻辑区域（战斗屏等非 Tab 屏使用）。
static func screen_rect() -> Rect2:
    return Rect2(0.0, 0.0, VIEWPORT_W, VIEWPORT_H)


# 四主屏内容区：避开底部 Tab 条带，避免屏内热区与导航热区重叠。
static func content_rect() -> Rect2:
    return Rect2(0.0, 0.0, VIEWPORT_W, VIEWPORT_H - TAB_BAR_H)


static func tab_bar_rect() -> Rect2:
    return Rect2(0.0, VIEWPORT_H - TAB_BAR_H, VIEWPORT_W, TAB_BAR_H)


static func min_click_size() -> Vector2:
    return Vector2(MIN_CLICK_W, MIN_CLICK_H)


# 整数倍缩放：窗口尺寸只允许 1x / 2x / 3x，否则回落到最近的整数倍。
static func snapped_scale(window_size: Vector2) -> int:
    var sx: float = window_size.x / VIEWPORT_W
    var sy: float = window_size.y / VIEWPORT_H
    var raw: float = min(sx, sy)
    var s: int = int(floor(raw))
    if s < 1:
        s = 1
    if s > 3:
        s = 3
    return s

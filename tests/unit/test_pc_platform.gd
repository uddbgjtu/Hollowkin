extends GutTest

# Wave 3 / ADR-6 PC 平台契约回归（headless Godot 4.3 + GUT 9.3.0 真跑）。
# 覆盖：横屏布局真源、所有 UI 热区落在横屏内、键鼠适配层输出同构字典、
#       ADR-2「输入只入队、帧末才改状态」不被适配层破坏。
# 本文件为逻辑/结构断言，不含任何性能测量数字，不冒充 PC 帧预算基线。
# ADR-5：全文件无全局随机调用。

const LayoutConfig := preload("res://src/ui/layout_config.gd")
const PcInputAdapter := preload("res://src/gameplay/input/pc_input_adapter.gd")


func test_layout_contract_is_landscape_1280x720() -> void:
    assert_eq(LayoutConfig.viewport(), Vector2(1280.0, 720.0), "ADR-6 横屏逻辑分辨率")
    assert_eq(LayoutConfig.screen_rect().size, Vector2(1280.0, 720.0), "全屏区域")
    assert_eq(LayoutConfig.tab_bar_rect(), Rect2(0.0, 656.0, 1280.0, 64.0), "底部 Tab 条带")
    assert_eq(LayoutConfig.content_rect().size.y, 656.0, "内容区避开 Tab 条带")
    assert_eq(LayoutConfig.min_click_size(), Vector2(24.0, 24.0), "键鼠点击目标下限 ≥24x24px")
    assert_eq(LayoutConfig.snapped_scale(Vector2(2560.0, 1440.0)), 2, "2x 整数倍缩放")
    assert_eq(LayoutConfig.snapped_scale(Vector2(1920.0, 1080.0)), 1, "1.5x 回落到 1x")
    assert_eq(LayoutConfig.snapped_scale(Vector2(640.0, 360.0)), 1, "小于 1x 钳到 1x")


func test_tab_bar_fits_bottom_strip() -> void:
    var tb = BottomTabBar.new()
    var strip: Rect2 = LayoutConfig.tab_bar_rect()
    tb.build(strip)
    assert_eq(tb.rects().size(), 4, "四个主屏 Tab")
    for r in tb.rects():
        var rect: Rect2 = r
        assert_true(strip.encloses(rect), "Tab 命中区完全落在底部条带内")
        assert_true(rect.size.x >= 24.0 and rect.size.y >= 24.0, "满足 PC 点击目标下限")


func test_all_screen_zones_fit_landscape() -> void:
    var ctx = UiContext.new()
    var screens: Array = [
        OverviewScreen.new(), PouchScreen.new(), SpiritVeinScreen.new(),
        MapScreen.new(), BattleScreen.new()
    ]
    var full: Rect2 = LayoutConfig.screen_rect()
    var total: int = 0
    for s in screens:
        s.bind(ctx)
        for z in s.zones():
            var zd: Dictionary = z
            total += 1
            if zd["type"] == "rect":
                var r: Rect2 = zd["rect"]
                assert_true(full.encloses(r),
                    "%s 热区 %s 必须落在 1280x720 横屏内" % [s.id, str(zd["id"])])
            else:
                var c: Vector2 = zd["center"]
                assert_true(full.has_point(c),
                    "%s 圆形热区 %s 圆心必须在横屏内" % [s.id, str(zd["id"])])
    assert_true(total >= 8, "逻辑层热区总数应与主场景自检一致（≥8）")


func test_adapter_mouse_left_press_is_isomorphic() -> void:
    var a = PcInputAdapter.new()
    var mb = InputEventMouseButton.new()
    mb.position = Vector2(314.0, 271.0)
    mb.button_index = MOUSE_BUTTON_LEFT
    mb.pressed = true
    var out: Array = a.translate(mb)
    assert_eq(out.size(), 1, "左键按下产生 1 个事件")
    var e: Dictionary = out[0]
    assert_eq(e["position"], Vector2(314.0, 271.0), "位置原样透传")
    assert_eq(int(e["touch_id"]), 0, "PC 指针固定 touch_id=0")
    assert_true(e.has("position") and e.has("touch_id"), "与 InputQueue.push 同构")

    var right = InputEventMouseButton.new()
    right.position = Vector2(1.0, 1.0)
    right.button_index = MOUSE_BUTTON_RIGHT
    right.pressed = true
    assert_eq(a.translate(right).size(), 0, "右键不产生业务事件")

    var release = InputEventMouseButton.new()
    release.button_index = MOUSE_BUTTON_LEFT
    release.pressed = false
    assert_eq(a.translate(release).size(), 0, "抬起不重复触发")


func test_adapter_drag_and_keyboard_map_to_zone_centers() -> void:
    var a = PcInputAdapter.new()
    a.bind_zone("pouch", Vector2(500.0, 688.0))
    a.bind_key(KEY_2, "pouch")

    var mm = InputEventMouseMotion.new()
    mm.position = Vector2(88.0, 99.0)
    mm.button_mask = MOUSE_BUTTON_MASK_LEFT
    var drag: Array = a.translate(mm)
    assert_eq(drag.size(), 1, "左键拖拽产生 1 个事件")
    assert_eq(drag[0]["position"], Vector2(88.0, 99.0), "拖拽位置透传")

    var k = InputEventKey.new()
    k.keycode = KEY_2
    k.pressed = true
    var key_events: Array = a.translate(k)
    assert_eq(key_events.size(), 1, "已绑定按键映射到热区中心")
    assert_eq(key_events[0]["position"], Vector2(500.0, 688.0), "键盘走同一热区坐标")
    assert_eq(int(key_events[0]["touch_id"]), 0, "键盘同样使用 PC 指针 id")

    k.echo = true
    assert_eq(a.translate(k).size(), 0, "按键重复回显被忽略")
    k.echo = false
    k.pressed = false
    assert_eq(a.translate(k).size(), 0, "按键抬起被忽略")

    var unmapped = InputEventKey.new()
    unmapped.keycode = KEY_F12
    unmapped.pressed = true
    assert_eq(a.translate(unmapped).size(), 0, "未绑定按键不臆造事件")


func test_adapter_keeps_adr2_frame_end_settlement() -> void:
    var r = ScreenRouter.new()
    var ctx = UiContext.new()
    var ov = OverviewScreen.new()
    var po = PouchScreen.new()
    var sv = SpiritVeinScreen.new()
    var mp = MapScreen.new()
    r.register(ov, 0)
    r.register(po, 1)
    r.register(sv, 2)
    r.register(mp, 3)
    ov.bind(ctx); po.bind(ctx); sv.bind(ctx); mp.bind(ctx)
    r.build(LayoutConfig.tab_bar_rect())
    r.switch_to("overview")

    var a = PcInputAdapter.new()
    var pr: Rect2 = r.tab_bar.hit_rect_for("pouch")
    var center: Vector2 = pr.position + pr.size * 0.5
    a.bind_zone("pouch", center)
    a.bind_key(KEY_2, "pouch")
    var k = InputEventKey.new()
    k.keycode = KEY_2
    k.pressed = true
    var pushed: int = a.push_into(r.queue, k)
    assert_eq(pushed, 1, "适配层只入队一条")
    assert_eq(r.active_id, "overview", "入队后、flush 前不得改 UI 状态（ADR-2）")
    r.flush(0.1)
    assert_eq(r.active_id, "pouch", "帧末 flush 后才切换")

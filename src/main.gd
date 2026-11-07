# main.gd — PC 主场景入口（ADR-6 / Wave 3）
# =====================================================================
# 职责：
#   1) 保留 Epic A 存档 / RNG 链路（ADR-1 / ADR-5）；
#   2) 组装 Epic F 逻辑层（UiContext + 5 个 UiScreen + ScreenRouter）；
#   3) 挂接四主屏 / 战斗屏视图 *.tscn，绘制与 HitZone 同源的热区；
#   4) 键鼠事件经 pc_input_adapter 转同构字典入 InputQueue，帧末 flush 结算（ADR-2）。
# 设计约束：所有布局数值来自 LayoutConfig 单一真源；本文件不含 720/1280 硬编码。
# 无全局随机（floor RNG 为 RNGService 派生实例，ADR-5）。
# =====================================================================

extends Control

const RNGServiceMod := preload("res://src/core/rng/rng_service.gd")
const LayoutConfig := preload("res://src/ui/layout_config.gd")
const FloorGrid := preload("res://src/gameplay/render/floor_grid.gd")
const DungeonGeneratorMod := preload("res://src/core/dungeon_gen/dungeon_generator.gd")
const PcInputAdapter := preload("res://src/gameplay/input/pc_input_adapter.gd")
const OverviewView := preload("res://src/ui/screens/overview_screen.tscn")
const PouchView := preload("res://src/ui/screens/pouch_screen.tscn")
const SpiritVeinView := preload("res://src/ui/screens/spirit_vein_screen.tscn")
const MapView := preload("res://src/ui/screens/map_screen.tscn")
const BattleView := preload("res://src/ui/screens/battle_screen.tscn")

var router: ScreenRouter
var adapter
var _screens: Dictionary = {}
var _views: Dictionary = {}
var _last_active: String = ""
var _map_built: bool = false
# 视图脚本无 class_name（保持全局类缓存 40 类），故用动态引用调用 bind/refresh。
var _tab_view = null
var _status: Label
var _hint: Label


func _ready() -> void:
    var run: Dictionary = SaveSvc.load_run()
    if run.is_empty():
        var seed_value: int = int(SaveSvc.new_run_seed())
        run = {"run_seed": seed_value, "floor_index": 1, "event_log": []}
        SaveSvc.save_run(seed_value, 1, [])
        print("[Main] 新 run 起始 run_seed=%d floor=1" % seed_value)
    else:
        print("[Main] 读档 run_seed=%d floor=%d event_log_len=%d" % [
            run["run_seed"], run["floor_index"], run["event_log"].size()
        ])
    var rng = RNGServiceMod.floor_rng(run["run_seed"], run["floor_index"])
    print("[Main] floor RNG 首抽=%d（同 (run_seed,floor) 必一致）" % rng.randi())

    _tab_view = get_node("TabBarView")
    _status = get_node("StatusLabel") as Label
    _hint = get_node("HintLabel") as Label

    var ctx: UiContext = UiContext.new()
    ctx.run_seed = int(run["run_seed"])
    ctx.floor_index = int(run["floor_index"])

    var ov: OverviewScreen = OverviewScreen.new()
    var po: PouchScreen = PouchScreen.new()
    var sv: SpiritVeinScreen = SpiritVeinScreen.new()
    var mp: MapScreen = MapScreen.new()
    var bt: BattleScreen = BattleScreen.new()
    _screens = {"overview": ov, "pouch": po, "spirit_vein": sv, "map": mp, "battle": bt}

    router = ScreenRouter.new()
    router.register(ov, 0)
    router.register(po, 1)
    router.register(sv, 2)
    router.register(mp, 3)
    router.register(bt, -1)
    for key in _screens.keys():
        var scr: UiScreen = _screens[key]
        scr.bind(ctx)
    router.build(LayoutConfig.tab_bar_rect())
    router.switch_to("overview")

    _mount_views()
    _bind_keyboard()
    _tab_view.bind(router.tab_bar)
    _sync_active(true)
    print("[Main] ADR-6 横屏 %s 启动，active=%s" % [str(LayoutConfig.viewport()), router.active_id])

    if _selftest_requested():
        _run_selftest()


func _mount_views() -> void:
    var root: Control = get_node("Views") as Control
    var scenes: Dictionary = {
        "overview": OverviewView, "pouch": PouchView,
        "spirit_vein": SpiritVeinView, "map": MapView, "battle": BattleView
    }
    for key in scenes.keys():
        var packed = scenes[key]
        var view = packed.instantiate()
        root.add_child(view)
        view.bind_logic(_screens[key])
        view.visible = false
        _views[key] = view


func _bind_keyboard() -> void:
    adapter = PcInputAdapter.new()
    var ids: Array = router.tab_bar.tab_ids()
    for i in range(ids.size()):
        var id: String = str(ids[i])
        var r: Rect2 = router.tab_bar.hit_rect_for(id)
        adapter.bind_zone(id, r.position + r.size * 0.5)
        adapter.bind_key(KEY_1 + i, id)
    for key in _screens.keys():
        var scr: UiScreen = _screens[key]
        for z in scr.zones():
            var zd: Dictionary = z
            if zd["type"] == "rect":
                var r2: Rect2 = zd["rect"]
                adapter.bind_zone(str(zd["id"]), r2.position + r2.size * 0.5)
            else:
                adapter.bind_zone(str(zd["id"]), zd["center"])
    adapter.bind_key(KEY_ENTER, "enter_dungeon")
    adapter.bind_key(KEY_Q, "lingji")
    adapter.bind_key(KEY_W, "fuling")


func _input(event: InputEvent) -> void:
    if router == null or adapter == null:
        return
    # Tab / Esc 是「下一屏 / 返回总览」的动态意图，无法静态绑定单一热区，
    # 在此换算成目标 tab 的中心坐标后仍走同一 InputQueue（ADR-2 不破）。
    if event is InputEventKey:
        var k: InputEventKey = event as InputEventKey
        if k.pressed and not k.echo:
            if k.keycode == KEY_TAB:
                var ids: Array = router.tab_bar.tab_ids()
                var idx: int = ids.find(router.active_id)
                var next: int = (idx + 1) % ids.size()
                if idx < 0:
                    next = 0
                var nid: String = str(ids[next])
                var c: Vector2 = adapter.zone_center(nid)
                router.queue.push({"position": c, "touch_id": 0})
                return
            if k.keycode == KEY_ESCAPE:
                # 战斗中 Tab 热区按设计隐藏，不能靠 overview 热区返回；
                # 改用 router 的延迟切换意图，仍在 flush 帧末生效（ADR-2）。
                router.request_switch("overview")
                return
    adapter.push_into(router.queue, event)


func _process(delta: float) -> void:
    if router == null:
        return
    router.flush(delta)
    _sync_active(false)


func _sync_active(force: bool) -> void:
    if not force and router.active_id == _last_active:
        return
    _last_active = router.active_id
    for key in _views.keys():
        var v = _views[key]
        v.visible = (key == router.active_id)
        if v.visible:
            v.refresh()
    _tab_view.set_active(router.active_id)
    _tab_view.visible = router.is_tab_bar_enabled()
    var label: String = router.tab_bar.label_for(router.active_id)
    if label == "":
        label = router.active_id
    _status.text = "当前屏：%s  |  分辨率 %s" % [label, str(LayoutConfig.viewport())]
    _hint.text = "鼠标左键点击热区；1-4 切屏；Tab 循环；Enter 主操作；Esc 返回总览"
    if router.active_id == "map" and not _map_built:
        _build_map_view()


# Wave 3b：首次进入地图屏时按 (run_seed, floor_index) 确定性重建布局（ADR-1/ADR-5），
# 交给 TileMapLayer / MultiMesh 视图做格映射 + 屏外剔除。只建一次，避免每次切屏重复 set_cell。
func _build_map_view() -> void:
    var run: Dictionary = SaveSvc.load_run()
    if run.is_empty():
        return
    var seed_value: int = int(run["run_seed"])
    var floor_index: int = int(run["floor_index"])
    var dg = DungeonGeneratorMod.new()
    var layout: Dictionary = dg.generate_sync(seed_value, floor_index, 0)
    var view: Rect2i = FloorGrid.view_rect_for_layout(layout)
    var mv = _views["map"]
    var written: int = int(mv.render_floor(layout, view))
    _map_built = true
    print("[Main] 地图屏渲染 seed=%d floor=%d visible_cells=%d asset=%s" % [
        seed_value, floor_index, written, FloorGrid.ASSET_SOURCE
    ])
    dg.free()


func _selftest_requested() -> bool:
    for a in OS.get_cmdline_args():
        if a == "--wave3-selftest":
            return true
    for a in OS.get_cmdline_user_args():
        if a == "--wave3-selftest":
            return true
    return false


# headless 自检：验证场景能加载、逻辑层能切换、视图绑定生效、ADR-2 帧末结算成立。
# 只输出结构性结论，不产出任何性能测量数字。
func _run_selftest() -> void:
    var ok: bool = true
    var notes: Array = []
    var vp: Vector2 = LayoutConfig.viewport()
    if vp.x != 1280.0 or vp.y != 720.0:
        ok = false
        notes.append("viewport_mismatch")
    if _views.size() != 5:
        ok = false
        notes.append("views=%d" % _views.size())
    var zones_total: int = 0
    for key in _screens.keys():
        var scr: UiScreen = _screens[key]
        zones_total += scr.zones().size()
    notes.append("zones=%d" % zones_total)

    var pr: Rect2 = router.tab_bar.hit_rect_for("pouch")
    router.push_pointer(pr.position + pr.size * 0.5)
    if router.active_id != "overview":
        ok = false
        notes.append("adr2_violated_before_flush")
    router.flush(0.1)
    _sync_active(true)
    if router.active_id != "pouch":
        ok = false
        notes.append("tab_switch_failed")
    var pv = _views["pouch"]
    if not pv.visible:
        ok = false
        notes.append("pouch_view_hidden")

    # 战斗中 Tab 热区隐藏，Esc 必须仍能经 pending 意图返回总览。
    router.switch_to("battle")
    router.request_switch("overview")
    router.flush(0.1)
    if router.active_id != "overview":
        ok = false
        notes.append("esc_return_failed")
    _sync_active(true)

    # Wave 3b：地图屏 TileMapLayer / MultiMesh / 战斗屏粒子层就位且有可见格。
    router.switch_to("map")
    _sync_active(true)
    var mv2 = _views["map"]
    var tm = mv2.get_node_or_null("FloorTilemap")
    if tm == null:
        ok = false
        notes.append("tilemap_missing")
    else:
        var used: int = tm.get_used_cells().size()
        notes.append("tile_cells=%d" % used)
        if used <= 0:
            ok = false
            notes.append("tilemap_empty")
        if str(tm.asset_source()) != "DEBUG_PLACEHOLDER":
            ok = false
            notes.append("asset_source_not_marked")
    var el = mv2.get_node_or_null("EntityLayer")
    if el == null:
        ok = false
        notes.append("entity_layer_missing")
    else:
        notes.append("visible_entities=%d" % int(el.last_visible))
    var bv = _views["battle"]
    var bp = bv.get_node_or_null("BattleParticles")
    if bp == null or not bp.emitting:
        ok = false
        notes.append("particles_not_emitting")
    else:
        notes.append("particles_amount=%d" % int(bp.amount))

    var mb: InputEventMouseButton = InputEventMouseButton.new()
    mb.position = Vector2(10.0, 10.0)
    mb.button_index = MOUSE_BUTTON_LEFT
    mb.pressed = true
    var translated: Array = adapter.translate(mb)
    if translated.size() != 1:
        ok = false
        notes.append("adapter_mouse_failed")
    else:
        var e: Dictionary = translated[0]
        if int(e["touch_id"]) != 0 or e["position"] != Vector2(10.0, 10.0):
            ok = false
            notes.append("adapter_shape_failed")

    print("[WAVE3_SELFTEST] viewport=%s tab_rect=%s screens=%d views=%d %s result=%s" % [
        str(vp), str(LayoutConfig.tab_bar_rect()), _screens.size(), _views.size(),
        str(notes), "OK" if ok else "FAIL"
    ])
    if ok:
        print("WAVE3_SELFTEST_OK")
    else:
        print("WAVE3_SELFTEST_FAIL")
    get_tree().quit(0 if ok else 1)

# probe_runner.gd — R1 / R3 PC 基线采集入口场景（最小可导出构建，ADR-6）
# =====================================================================
# 为什么需要这个文件：src/main.tscn 只有一个空 Node2D（读档后打印日志即结束），
# 没有挂 SimulationClock / InputQueue / CombatDirector，也没有渲染与键鼠输入，
# 因此无法在 PC 基线上触发归档 runbook docs/qa/archive/r1r3-device-test-plan.md §2 / §3 的测量场景。
# 本场景把「可立即测分项」的生产模块按固定种子驱动起来，逐样本打点后输出 CSV。
#
# PC 基线采集三步（ADR-6）：
#   1) 导出前把本文件 PROBE_BUILD_SHA 填成被测构建的 git SHA（UNSET 会被 §6 退回），
#      并把 project.godot 的 run/main_scene 临时指向 res://src/qa/probe_runner.tscn；
#   2) 导出 Windows Desktop exe 并在目标 PC 运行，点「Start R1/R3 probe」；预热 >=5s 后再点；
#   3) 取回 user://hollowkin_probe_metrics.csv（或 console / stdout 的 METRIC| 行）交给主理人。
#      测完把 main_scene 改回 res://src/main.tscn。
#
# 本地 / CI 无头自检：
#   godot --headless --path . res://src/qa/probe_runner.tscn -- --probe-auto
#   （--probe-auto 跑完自动退出；仅验证脚本可执行，产出的数字不是 PC 基线正式数据。）
#
# 纪律：零预置测量值；不使用全局随机（ADR-5）；不声明 class_name（不改全局类缓存）。
#       渲染 / 粒子 / 合计占帧比一律标 blocked，见 r1r3_probe.gd::add_blocked。
# =====================================================================

extends Control

const Probe := preload("res://tools/qa/r1r3_probe.gd")
const DungeonGeneratorMod := preload("res://src/core/dungeon_gen/dungeon_generator.gd")
const HitZoneMod := preload("res://src/gameplay/input/hit_zone.gd")
const InputQueueMod := preload("res://src/gameplay/input/input_queue.gd")
const CombatDirectorMod := preload("res://src/gameplay/combat/combat_director.gd")

# ---------------------------------------------------------------------
# 采集前必须人工填写（导出 Windows exe 之前）
# ---------------------------------------------------------------------
const PROBE_BUILD_SHA := "UNSET"   # <- 改成 git rev-parse HEAD 的 SHA
# ---------------------------------------------------------------------

const SEED := 20261106          # 固定种子（确定性输入，不是测量值）
const FLOOR_START := 1
const TIER_HIGH := 0            # RoomStitcher.DeviceTier.HIGH
const TIER_LOW := 1             # RoomStitcher.DeviceTier.LOW

const N_LOGIC := 100            # §2：单层生成逻辑 >=100 层
const N_FALLBACK := 10          # §2：保底切换 >=10 次注入
const N_DENSITY := 30           # §2：高 / 低档各 >=30 次
const N_INPUT := 100            # §3：输入仲裁 >=100 帧
const N_TICK := 200             # §3：AI tick >=200 tick

const USER_CSV := "user://hollowkin_probe_metrics.csv"

var _status: Label
var _button: Button


# consume_into(target) 的回调桩：只承接 on_action，不把业务逻辑计入仲裁耗时。
class Sink extends RefCounted:
    func on_action(_zone_id: String) -> void:
        pass


func _ready() -> void:
    _build_ui()
    if _auto_requested():
        call_deferred("_run_and_quit")


func _build_ui() -> void:
    var box := VBoxContainer.new()
    box.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(box)
    _status = Label.new()
    _status.text = _intro_text()
    box.add_child(_status)
    _button = Button.new()
    _button.text = "Start R1/R3 PC baseline probe"
    _button.pressed.connect(_on_start_pressed)
    box.add_child(_button)


func _intro_text() -> String:
    var t := "Hollowkin R1/R3 PC baseline probe\n"
    t += "Godot %s | build_type=%s | device=%s\n" % [_godot_version(), _build_type(), _device_id()]
    if PROBE_BUILD_SHA == "UNSET":
        t += "WARNING: PROBE_BUILD_SHA=UNSET -> set git SHA before export\n"
    t += "Warm up >=5s, then press the button. CSV: " + USER_CSV + "\n"
    t += "Fill MANUAL_REQUIRED fields (see docs/qa/evidence/_template/README.md)."
    return t


func _auto_requested() -> bool:
    for a in OS.get_cmdline_args():
        if a == "--probe-auto":
            return true
    for a in OS.get_cmdline_user_args():
        if a == "--probe-auto":
            return true
    return false


func _on_start_pressed() -> void:
    _button.disabled = true
    var r := _run()
    _status.text = str(r["summary"])
    _button.disabled = false


func _run_and_quit() -> void:
    var r := _run()
    print("PROBE_SUMMARY|" + str(r["summary"]))
    get_tree().quit(0 if bool(r["ok"]) else 1)


func _run() -> Dictionary:
    var probe := Probe.new(_build_meta())
    _collect_r1_logic(probe)
    _collect_r1_fallback(probe)
    _collect_r1_density(probe)
    _collect_r3_input(probe)
    _collect_r3_ai_tick(probe)
    _mark_blocked(probe)

    var csv := probe.to_csv()
    var err := OK
    var f := FileAccess.open(USER_CSV, FileAccess.WRITE)
    if f == null:
        err = FileAccess.get_open_error()
    else:
        f.store_string(csv)
        f.close()
    probe.print_rows()

    var summary := "rows=%d csv=%s err=%d" % [probe.row_count(), USER_CSV, err]
    var complete := probe.row_count() == 10
    if not complete:
        summary += " | ERROR: expected 10 rows (possible module load failure)"
    if PROBE_BUILD_SHA == "UNSET":
        summary += " | WARNING: PROBE_BUILD_SHA=UNSET (fill before export)"
    summary += " | verdict=auto pre-judgement; final per PC baseline README section 5"
    return {"ok": err == OK and complete, "summary": summary, "csv": csv}


# ---------------------------------------------------------------------
# 环境字段：能自动取的自动取；Godot 无跨平台 API 的一律标 MANUAL_REQUIRED，
# 由采集人按 docs/qa/evidence/_template/README.md §1 手工补齐，绝不猜值。
# ---------------------------------------------------------------------
func _build_meta() -> Dictionary:
    return {
        "device_id": _device_id(),
        "os_version": OS.get_version(),
        # Godot 4.3 无跨平台的 GPU 后端字符串；这里取 rendering_method 作代理。
        # Vulkan / D3D12 / GLES3 仍需采集人按 PC 基线 README §1 手工核对，勿当作已填。
        "gpu_backend": str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "unknown")),
        "build_sha": PROBE_BUILD_SHA,
        "godot_version": _godot_version(),
        "build_type": _build_type(),
        # PC 下 thermal_state / battery_pct 可填 N/A，但须注明降频与省电策略。
        "thermal_state": "MANUAL_REQUIRED",
        "battery_pct": "MANUAL_REQUIRED",
        "background_policy": "MANUAL_REQUIRED",
        "evidence_path": USER_CSV,
        "measured_at": Time.get_datetime_string_from_system(true) + "Z",
        "operator": "MANUAL_REQUIRED"
    }


func _device_id() -> String:
    var model := OS.get_model_name()
    if model == "" or model == "GenericDevice":
        return OS.get_name()
    return model


func _build_type() -> String:
    return "debug" if OS.is_debug_build() else "release"


func _godot_version() -> String:
    var vi := Engine.get_version_info()
    return "%d.%d.%s" % [int(vi.get("major", 0)), int(vi.get("minor", 0)), str(vi.get("status", "unknown"))]


# ---------------------------------------------------------------------
# §2 R1：单层生成逻辑耗时（每次清缓存，避免命中短路）
# ---------------------------------------------------------------------
func _collect_r1_logic(probe) -> void:
    var dg := DungeonGeneratorMod.new()
    var samples: Array = []
    for i in range(N_LOGIC):
        dg.clear_cache()
        var t0 := Time.get_ticks_usec()
        var layout: Dictionary = dg.generate_sync(SEED, FLOOR_START + i, TIER_HIGH)
        var t1 := Time.get_ticks_usec()
        if layout.is_empty():
            probe.note("r1_logic_elapsed: empty layout at floor %d" % (FLOOR_START + i))
        samples.append(float(t1 - t0) / 1000.0)
    dg.free()
    probe.add_measured("r1_logic_elapsed", "ms", samples, "≤ 1", 1.0)


# §2 R1：保底模板切换（非法 floor 注入，校验 fallback 标记与耗时）
func _collect_r1_fallback(probe) -> void:
    var dg := DungeonGeneratorMod.new()
    var samples: Array = []
    var ok_count := 0
    for i in range(N_FALLBACK):
        var bad_floor := -1 if i % 2 == 0 else 10000
        var t0 := Time.get_ticks_usec()
        var layout: Dictionary = dg.generate_sync(SEED, bad_floor, TIER_HIGH)
        var t1 := Time.get_ticks_usec()
        samples.append(float(t1 - t0) / 1000.0)
        if bool(layout.get("fallback", false)):
            ok_count += 1
    dg.free()
    probe.note("r1_fallback_switch: fallback_flag_true=%d/%d" % [ok_count, N_FALLBACK])
    probe.add_measured_verdict("r1_fallback_switch", "bool + ms", samples, "不阻断流程",
        "pass" if ok_count == N_FALLBACK else "fail")


# §2 R1：下限档降密度（高 / 低档各 N_DENSITY 次；数量证据走日志）
func _collect_r1_density(probe) -> void:
    var dg := DungeonGeneratorMod.new()
    var samples: Array = []
    var high_rooms := 0
    var high_enemies := 0
    var low_rooms := 0
    var low_enemies := 0
    for tier in [TIER_HIGH, TIER_LOW]:
        for i in range(N_DENSITY):
            dg.clear_cache()
            var t0 := Time.get_ticks_usec()
            var layout: Dictionary = dg.generate_sync(SEED, FLOOR_START + i, tier)
            var t1 := Time.get_ticks_usec()
            samples.append(float(t1 - t0) / 1000.0)
            var rooms: Array = layout.get("rooms", [])
            var enemies: Array = layout.get("enemy_spawns", [])
            if tier == TIER_HIGH:
                high_rooms += rooms.size()
                high_enemies += enemies.size()
            else:
                low_rooms += rooms.size()
                low_enemies += enemies.size()
    dg.free()
    var ok := low_rooms <= high_rooms and low_enemies <= high_enemies
    probe.note("r1_low_tier_density: HIGH rooms=%d enemies=%d ; LOW rooms=%d enemies=%d (over %d runs each)" % [
        high_rooms, high_enemies, low_rooms, low_enemies, N_DENSITY
    ])
    probe.add_measured_verdict("r1_low_tier_density", "ms", samples, "上限下调",
        "pass" if ok else "fail")


# ---------------------------------------------------------------------
# §3 R3：输入仲裁（HitZone 解析 + 队列去重 + 0.5s cd 钳）
# ADR-6 Wave 3：夹具坐标改到 1280x720 横屏内容区（原 900/948 为竖屏遗留）。
# ---------------------------------------------------------------------
func _collect_r3_input(probe) -> void:
    var hz := HitZoneMod.new()
    hz.register_rect("skill_lingji", Rect2(24.0, 560.0, 96.0, 96.0))
    hz.register_rect("skill_fuling", Rect2(160.0, 560.0, 96.0, 96.0))
    var q := InputQueueMod.new()
    q.set_hit_zone(hz)
    var sink := Sink.new()
    var samples: Array = []
    for i in range(N_INPUT):
        q.push({"position": Vector2(72.0, 608.0), "touch_id": i})
        q.advance_time(0.1)
        var t0 := Time.get_ticks_usec()
        q.consume_into(sink)
        var t1 := Time.get_ticks_usec()
        samples.append(float(t1 - t0) / 1000.0)
    probe.add_measured("r3_input_arbitration", "ms", samples, "< 0.5 / < 1.0", 0.5)


# §3 R3：AI tick（CombatDirector.step_simulation，10Hz 定步长）
func _collect_r3_ai_tick(probe) -> void:
    var cd := CombatDirectorMod.new()
    var player_stats := {"hp": 1000.0, "atk": 10.0, "def": 5.0, "spd": 1.0, "aps": 1.0, "pos": Vector2.ZERO}
    var enemy_specs: Array = []
    for i in range(12):
        enemy_specs.append({
            "hp": 100.0, "atk": 2.0, "def": 1.0, "spd": 0.5, "aps": 0.5,
            "pos": Vector2(float(i), 0.0)
        })
    cd.setup(SEED, FLOOR_START, player_stats, enemy_specs)
    var samples: Array = []
    for i in range(N_TICK):
        var t0 := Time.get_ticks_usec()
        cd.step_simulation(0.1)
        var t1 := Time.get_ticks_usec()
        samples.append(float(t1 - t0) / 1000.0)
    probe.add_measured("r3_ai_tick", "ms", samples, "~1.66 / ~3.3", 1.66)


# ---------------------------------------------------------------------
# 前置依赖未满足项：只标 blocked，绝不代填数值
# （归档 runbook §7 方法学 + PC 基线 README §2）
# ---------------------------------------------------------------------
func _mark_blocked(probe) -> void:
    probe.add_blocked("r1_render_mean", "ms", "≤ 16.6",
        "BLOCKED-BY-SCENE: TileMapLayer.set_cell 未落地")
    probe.add_blocked("r1_render_p95_spike", "ms", "< 50",
        "BLOCKED-BY-SCENE: 无瓦片渲染态")
    probe.add_blocked("r3_entity_render", "ms", "< 4 / < 8",
        "BLOCKED-BY-SCENE: 无场景 / MultiMesh / 屏外剔除")
    probe.add_blocked("r3_particles", "ms", "< 3 / < 6",
        "BLOCKED-BY-SCENE: 无粒子系统")
    probe.add_blocked("r3_total_frame_share", "ms", "< 9.16（55%）",
        "分项缺失，不得拼接部分和判 pass")

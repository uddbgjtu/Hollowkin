# probe_runner.gd — R1 / R3 PC 基线采集入口场景（最小可导出构建，ADR-6）
# =====================================================================
# 为什么需要这个文件：src/main.tscn 只有一个空 Node2D（读档后打印日志即结束），
# 没有挂 SimulationClock / InputQueue / CombatDirector，也没有渲染与键鼠输入，
# 因此无法在 PC 基线上触发归档 runbook docs/qa/archive/r1r3-device-test-plan.md §2 / §3 的测量场景。
# 本场景把「可立即测分项」的生产模块按固定种子驱动起来，逐样本打点后输出 CSV。
#
# PC 基线采集（ADR-6，2026-11-07 插桩补齐后）：
#   1) 导出前把 PROBE_BUILD_SHA 填成被测构建的 git SHA（UNSET 会被 §5 退回），
#      并把 project.godot 的 run/main_scene 临时指向 res://src/qa/probe_runner.tscn；
#   2) 导出 Windows Desktop exe 后在 PC 上运行，预热 >=5s 再点按钮（或 --probe-auto）；
#   3) 每轮窗口/全屏 × 60/30fps 单独跑，取回两份文件：
#      user://hollowkin_probe_metrics_<round>.csv      （19 列汇总，结构不变）
#      user://hollowkin_probe_metrics_raw_<round>.csv  （逐样本长表，供复算 mean / p95）
#      连同 METRIC| / METRIC_NOTE| / FRAME_CAPTURE| / PROBE_SUMMARY| 日志交给主理人。
#      测完把 main_scene 改回 res://src/main.tscn。
#
# 命令行参数（写在 -- 之后，或作为常规参数均可）：
#   --probe-auto                    跑完自动退出
#   --round-id=win_60_release      轮次标识；进入汇总 / 原始文件名，禁止跨轮混算
#   --window-mode=windowed|fullscreen
#   --fps-cap=60|30                用 Engine.max_fps 固定目标帧率档
#   --frame-samples=120            逐帧 GPU / CPU / 墙钟样本数（0 = 跳过帧采集）
#   --warmup-frames=30             预热帧剔除（在脚本内剔除，不删原始值）
#   --build-sha=<sha>              覆盖 PROBE_BUILD_SHA，便于不改源码即可标定构建
#
# 本地 / CI 无头自检（窗口与 GPU 计时不可用，自动降级并如实记录，不填 0、不臆造）：
#   godot --headless --path . res://src/qa/probe_runner.tscn -- --probe-auto
#   （仅验证脚本可执行；产出的数字不是 PC 基线正式数据。）
#
# 纪律：零预置测量值；不使用全局随机（ADR-5）；不声明 class_name（不改全局类缓存）。
#       渲染 / 粒子 / 合计占帧比：headless（无 GPU 帧采集链）一律标 blocked；
#       真实 GPU PC（_frame_available）下构建 E1 真实渲染负载，五项均可测：
#         · r1 三项（整帧渲染预算）取自 full 态聚合帧 GPU 时间；
#         · r3_entity_render / r3_particles 用四态显隐 Δ 隔离法测得边际 GPU 成本，见 _collect_render_metrics。
#       帧时间只写逐样本长表并标 E1_PNG8_FRAME_NOT_A_BASELINE（a 阶段后负载为 E1），
#       绝不进 19 列 verdict —— 无头无 GPU 帧采集链，不构成正式判据，须 PC 实测（G1）。
#
# a 阶段更新（渲染集成已实施）：TileMapLayer / MultiMesh + 屏外剔除 / CPUParticles2D
#   现已接 ADR-4 E1 真实像素原图（asset_source=E1_PNG8，已提交 f1c79c2），资产阻塞解除。
#   headless 无 GPU 帧采集链，5 项仍 blocked（BLOCKED-BY-HARDWARE / 资产未集成时 ASSET）。
#   G1 本地落地后（本批次）：真实 GPU PC（_frame_available）下构建 E1 真实渲染负载，
#   五项均可测——r1 三项取 full 态整帧 GPU 时间；r3_entity_render / r3_particles 用
#   四态显隐 Δ 隔离法（full / no_entity / no_particles / base）测得边际 GPU 成本，
#   闭合校验经 delta_isolation 笔记输出。headless 行为不变、不构建负载，CI 不受影响；
#   R1/R3 不因采集完成或 CI 全绿自动翻转，仍须 G1（实测）+ G2 + G3 三件套。
# =====================================================================

extends Control

const Probe := preload("res://tools/qa/r1r3_probe.gd")
const DungeonGeneratorMod := preload("res://src/core/dungeon_gen/dungeon_generator.gd")
const HitZoneMod := preload("res://src/gameplay/input/hit_zone.gd")
const InputQueueMod := preload("res://src/gameplay/input/input_queue.gd")
const CombatDirectorMod := preload("res://src/gameplay/combat/combat_director.gd")
const FloorGridMod := preload("res://src/gameplay/render/floor_grid.gd")
const FloorTilemapMod := preload("res://src/gameplay/render/floor_tilemap.gd")
const EntityLayerMod := preload("res://src/gameplay/render/entity_layer.gd")
const BattleParticlesMod := preload("res://src/gameplay/render/battle_particles.gd")

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
const USER_RAW_CSV := "user://hollowkin_probe_metrics_raw.csv"

const FRAME_SAMPLES_DEFAULT := 120
const WARMUP_FRAMES_DEFAULT := 30
const FRAME_NOTE := "E1_PNG8 负载；已接 ADR-4 真实资产（f1c79c2），但无头无 GPU 帧采集链，不进 19 列 verdict，须 PC 窗口实测（G1）"

var _status: Label
var _button: Button

var _round_id: String = "default"
var _window_mode: String = "windowed"
var _fps_cap: int = 0
var _frame_target: int = FRAME_SAMPLES_DEFAULT
var _warmup_initial: int = WARMUP_FRAMES_DEFAULT
var _build_sha_override: String = ""
var _auto_quit: bool = false

var _capturing: bool = false
var _frame_available: bool = false
var _frame_reason: String = ""
var _vp: RID
var _frame_gpu: Array = []
var _frame_cpu: Array = []
var _frame_wall: Array = []

# ── Δ 隔离四态采集（让 r3_entity_render / r3_particles 可测，R3 可闭合）──
# Godot 不暴露按 mesh / 粒子的单独 GPU 计时；在同一确定性负载下成对显隐目标层，
# 帧 GPU 时间的差即该子系统边际渲染成本。四态：full / no_entity / no_particles / base。
# 仅真实 GPU PC（_frame_available）下构建负载并采集；headless 不构建、不采集、不污染 CI。
var _render_load_built: bool = false
var _tm: Node = null
var _el: Node = null
var _bp: Node = null
var _phase_keys: Array = ["full", "no_entity", "no_particles", "base"]
var _phase_idx: int = 0
var _phase_warmup_left: int = 0
var _phase_target: int = 0
var _phase_samples: Dictionary = {}


# consume_into(target) 的回调桩：只承接 on_action，不把业务逻辑计入仲裁耗时。
class Sink extends RefCounted:
    func on_action(_zone_id: String) -> void:
        pass


func _ready() -> void:
    _parse_args()
    _apply_window_settings()
    _detect_frame_capture()
    _build_ui()
    if _auto_requested():
        call_deferred("_begin_and_quit")


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


# ---------------------------------------------------------------------
# 轮次编排：窗口 / 全屏 × 60 / 30fps 各单独一轮，参数本身即证据的一部分。
# ---------------------------------------------------------------------
func _all_args() -> Array:
    var out: Array = []
    for a in OS.get_cmdline_args():
        out.append(str(a))
    for a in OS.get_cmdline_user_args():
        out.append(str(a))
    return out


func _parse_args() -> void:
    for a in _all_args():
        if not a.begins_with("--") or "=" not in a:
            continue
        var parts: Array = a.split("=", true, 1)
        var key: String = str(parts[0])
        var val: String = str(parts[1])
        match key:
            "--round-id": _round_id = val
            "--window-mode": _window_mode = val
            "--fps-cap": _fps_cap = int(val)
            "--frame-samples": _frame_target = int(val)
            "--warmup-frames": _warmup_initial = int(val)
            "--build-sha": _build_sha_override = val


func _apply_window_settings() -> void:
    if DisplayServer.get_name() == "headless":
        return
    if _window_mode == "fullscreen":
        DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
    else:
        DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
    if _fps_cap > 0:
        Engine.max_fps = _fps_cap


func _detect_frame_capture() -> void:
    # headless 下没有窗口也没有 GPU 渲染计时；如实记录不可用，绝不填 0 冒充样本。
    if DisplayServer.get_name() == "headless":
        _frame_available = false
        _frame_reason = "headless: no window, no GPU render timing"
        return
    _vp = get_viewport().get_viewport_rid()
    if not _vp.is_valid():
        _frame_available = false
        _frame_reason = "viewport RID invalid"
        return
    RenderingServer.viewport_set_measure_render_time(_vp, true)
    _frame_available = true
    _frame_reason = "RenderingServer.viewport_get_measured_render_time_gpu via %s" % DisplayServer.get_name()


func _begin_and_quit() -> void:
    _begin(true)


func _begin(p_auto_quit: bool = false) -> void:
    _auto_quit = p_auto_quit
    _button.disabled = true
    _frame_gpu.clear()
    _frame_cpu.clear()
    _frame_wall.clear()
    if _frame_available and _frame_target > 0:
        # 构建与游戏同等的真实渲染负载（固定 seed 布局，确定性）；
        # headless 不进入此分支，故不构建、不污染 CI。
        var dg := DungeonGeneratorMod.new()
        var layout: Dictionary = dg.generate_sync(SEED, FLOOR_START, TIER_HIGH)
        var view: Rect2i = FloorGridMod.view_rect_for_layout(layout)
        dg.free()
        _build_render_load(layout, view)
        # 初始化四态 Δ 隔离采集：full / no_entity / no_particles / base 各采一段。
        _phase_samples = {}
        for k in _phase_keys:
            _phase_samples[k] = []
        _phase_idx = 0
        _phase_target = _frame_target
        _phase_warmup_left = _warmup_initial
        _apply_phase_visibility(_phase_keys[0])
        _capturing = true
        set_process(true)
        _status.text = "Δ 隔离采集中：round=%s mode=%s fps_cap=%d 四态×%d" % [
            _round_id, _window_mode, _fps_cap, _phase_target
        ]
    else:
        _finish()


func _process(delta: float) -> void:
    if not _capturing:
        return
    if _phase_warmup_left > 0:
        _phase_warmup_left -= 1
        return
    var key: String = _phase_keys[_phase_idx]
    var g := float(RenderingServer.viewport_get_measured_render_time_gpu(_vp))
    _phase_samples[key].append(g)
    # full 态同时填整帧三通道，保持 r1 三项与帧时间证据的原有口径。
    if key == "full":
        _frame_gpu.append(g)
        _frame_cpu.append(float(RenderingServer.viewport_get_measured_render_time_cpu(_vp)))
        _frame_wall.append(delta * 1000.0)
    if _phase_samples[key].size() >= _phase_target:
        _phase_idx += 1
        if _phase_idx >= _phase_keys.size():
            _capturing = false
            set_process(false)
            _finish()
            return
        _apply_phase_visibility(_phase_keys[_phase_idx])
        _phase_warmup_left = _warmup_initial


func _intro_text() -> String:
    var paths: Array = _csv_paths()
    var t := "Hollowkin R1/R3 PC baseline probe\n"
    t += "Godot %s | build_type=%s | device=%s\n" % [_godot_version(), _build_type(), _device_id()]
    t += "round=%s | mode=%s | fps_cap=%d | frame=%s\n" % [
        _round_id, _window_mode, _fps_cap, "available" if _frame_available else "unavailable"
    ]
    if _effective_build_sha() == "UNSET":
        t += "WARNING: PROBE_BUILD_SHA=UNSET -> set git SHA before export\n"
    t += "Warm up >=5s, then press the button.\n"
    t += "CSV: " + str(paths[0]) + "\nRAW: " + str(paths[1]) + "\n"
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
    _begin(false)


func _csv_paths() -> Array:
    # 默认轮次沿用旧文件名，保持既有 headless 自检与文档记录兼容；
    # 正式轮次按 round_id 分文件，禁止跨轮混算。
    if _round_id == "default":
        return [USER_CSV, USER_RAW_CSV]
    return [
        "user://hollowkin_probe_metrics_%s.csv" % _round_id,
        "user://hollowkin_probe_metrics_raw_%s.csv" % _round_id
    ]


func _write_csv(path: String, text: String) -> int:
    var f := FileAccess.open(path, FileAccess.WRITE)
    if f == null:
        return FileAccess.get_open_error()
    f.store_string(text)
    f.close()
    return OK


func _effective_build_sha() -> String:
    return _build_sha_override if _build_sha_override != "" else PROBE_BUILD_SHA


func _finish() -> void:
    var probe := Probe.new(_build_meta())
    probe.set_round(_round_id)
    probe.note("ROUND|id=%s mode=%s fps_cap=%d display=%s vsync=%d build_sha=%s raw=%s" % [
        _round_id, _window_mode, _fps_cap, DisplayServer.get_name(),
        (DisplayServer.window_get_vsync_mode() if DisplayServer.get_name() != "headless" else -1),
        _effective_build_sha(), str(_csv_paths()[1])
    ])
    _collect_r1_logic(probe)
    _collect_r1_fallback(probe)
    _collect_r1_density(probe)
    _collect_r3_input(probe)
    _collect_r3_ai_tick(probe)
    _collect_render_metrics(probe)
    _note_render_structure(probe)
    _record_frame_times(probe)

    var paths: Array = _csv_paths()
    var csv_path: String = str(paths[0])
    var raw_path: String = str(paths[1])
    var err := _write_csv(csv_path, probe.to_csv())
    var raw_err := _write_csv(raw_path, probe.to_raw_csv())
    probe.print_rows()

    var summary := "rows=%d csv=%s err=%d" % [probe.row_count(), csv_path, err]
    summary += " | raw_rows=%d raw=%s raw_err=%d" % [probe.raw_row_count(), raw_path, raw_err]
    var frame_state: String = "samples=%d" % _frame_gpu.size() if _frame_available else "UNAVAILABLE (%s)" % _frame_reason
    summary += " | round=%s mode=%s fps_cap=%d frame=%s" % [
        _round_id, _window_mode, _fps_cap, frame_state
    ]
    var complete: bool = probe.row_count() == 10 and err == OK and raw_err == OK
    if not complete:
        summary += " | ERROR: expected 10 rows (possible module load failure)"
    if _effective_build_sha() == "UNSET":
        summary += " | WARNING: PROBE_BUILD_SHA=UNSET (fill before export)"
    summary += " | verdict=auto pre-judgement; final per PC baseline README section 5"

    _button.disabled = false
    _status.text = summary
    print("PROBE_SUMMARY|" + summary)
    if _auto_quit:
        get_tree().quit(0 if complete else 1)


# 帧时间只写逐样本长表：不进 19 列、不参与 verdict、不构成正式基线。
# Δ 隔离法的底层证据：四态各自 frame_gpu_ms 原始样本 + full 态 cpu/wall 补充。
func _record_frame_times(probe) -> void:
    if not _frame_available:
        probe.note("FRAME_CAPTURE_UNAVAILABLE|%s|no frame timings recorded; 19 列渲染项仍 blocked" % _frame_reason)
        return
    var note := "round=%s mode=%s fps_cap=%d warmup_dropped=%d | %s" % [
        _round_id, _window_mode, _fps_cap, _warmup_initial, FRAME_NOTE
    ]
    # 四态逐样本 GPU 时间（Δ 隔离底层证据，供闭合校验与独立复算）。
    for key in _phase_keys:
        var g: Array = _phase_samples.get(key, [])
        if not g.is_empty():
            probe.record_frame_samples("frame_gpu_ms_%s" % key, g, note)
    # full 态 CPU / 墙钟补充证据（Δ 仅看 GPU，cpu/wall 仅记整帧）。
    probe.record_frame_samples("frame_cpu_ms", _frame_cpu, note)
    probe.record_frame_samples("frame_wall_ms", _frame_wall, note)
    probe.note("FRAME_CAPTURE|round=%s mode=%s fps_cap=%d samples_per_phase=%d load=E1_PNG8 NOT_A_BASELINE" % [
        _round_id, _window_mode, _fps_cap, _frame_target
    ])


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
        "build_sha": _effective_build_sha(),
        "godot_version": _godot_version(),
        "build_type": _build_type(),
        # PC 下 thermal_state / battery_pct 可填 N/A，但须注明降频与省电策略。
        "thermal_state": "MANUAL_REQUIRED",
        "battery_pct": "MANUAL_REQUIRED",
        "background_policy": "MANUAL_REQUIRED",
        "evidence_path": str(_csv_paths()[0]),
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
# 渲染 / 粒子 / 合计占帧比指标发射：
#   - headless（无窗口 / 无 GPU 帧采集链）：五项全 blocked（BLOCKED-BY-HARDWARE / ASSET）。
#   - 真实 GPU PC（_frame_available 且已采到帧）：构建 E1 真实渲染负载后五项均可测——
#       · r1_render_mean / r1_render_p95_spike / r3_total_frame_share：full 态整帧 GPU 时间；
#       · r3_entity_render / r3_particles：四态显隐 Δ 隔离法边际成本（见函数内实现）。
#     数值一律来自真实帧采集与四态差值，绝不代填、可经 verify_probe_evidence.py 复算。
# （归档 runbook §7 方法学 + PC 基线 README §2 / pc_win_02/README.md §4 Δ 隔离协议）
# ---------------------------------------------------------------------

# 真实 GPU PC 上构建与游戏同等的渲染负载（地板 TileMapLayer + 实体 MultiMesh +
# 浮尘 CPUParticles2D，固定 seed 布局，确定性）；仅 _frame_available 下调用，
# headless 不构建、不污染 CI。
func _build_render_load(layout: Dictionary, view: Rect2i) -> void:
    if _render_load_built:
        return
    _tm = FloorTilemapMod.new()
    add_child(_tm)
    _tm.build_from_layout(layout, view)
    _el = EntityLayerMod.new()
    add_child(_el)
    _el.update_from_layout(layout, view)
    _bp = BattleParticlesMod.new()
    add_child(_bp)
    _bp.configure(false)   # 高档 24 粒子（_ready 已 configure，显式保证）
    _render_load_built = true


# 四态可见性：full=全可见；no_entity=隐实体层；no_particles=隐粒子层；
# base=实体+粒子全隐（仅剩地板 TileMapLayer + UI）。地板层始终可见。
func _apply_phase_visibility(key: String) -> void:
    if _el != null:
        _el.visible = (key != "no_entity")
    if _bp != null:
        _bp.visible = (key != "no_particles")


func _mean(a: Array) -> float:
    if a.is_empty():
        return 0.0
    var t := 0.0
    for v in a:
        t += float(v)
    return t / float(a.size())


func _collect_render_metrics(probe) -> void:
    var assets_integrated: bool = (FloorTilemapMod.ASSET_SOURCE == "E1_PNG8")

    if not _frame_available or _frame_gpu.is_empty():
        # headless 或采不到帧：仍 blocked；资产已集成则理由为 HARDWARE，否则 ASSET。
        var hw_reason: String
        if assets_integrated:
            hw_reason = "BLOCKED-BY-HARDWARE: E1 原图已接入（f1c79c2），资产阻塞解除；剩余阻塞=无头无 GPU 帧采集链，须 PC 窗口实测（G1）"
        else:
            hw_reason = "BLOCKED-BY-ASSET: 渲染层纹理仍为 DEBUG_PLACEHOLDER，须 E1 原图 + PC 窗口实测"
        probe.add_blocked("r1_render_mean", "ms", "≤ 16.6", hw_reason)
        probe.add_blocked("r1_render_p95_spike", "ms", "< 50", hw_reason)
        probe.add_blocked("r3_entity_render", "ms", "< 4 / < 8", hw_reason)
        probe.add_blocked("r3_particles", "ms", "< 3 / < 6", hw_reason)
        probe.add_blocked("r3_total_frame_share", "ms", "< 9.16（55%）",
            "分项缺失，不得拼接部分和判 pass")
        return

    # 真实 GPU PC（已接 E1 真实渲染负载，非空场景）：
    #   - 整帧渲染预算（r1 三项）取 full 态聚合帧 GPU 时间。
    #   - 子系统（r3_entity_render / r3_particles）用四态显隐 Δ 隔离法测得边际 GPU 成本：
    #       Δ_entity    = mean(full) - mean(no_entity)    （实体 MultiMesh 边际）
    #       Δ_particles = mean(full) - mean(no_particles) （粒子边际）
    #     逐对索引构造 Δ 样本使 mean 严格等于两段均值差、p95 反映逐帧边际波动，
    #     原始 Δ 样本写入 raw 长表供 verify_probe_evidence.py 复算（不伪造、可核验）。
    var full: Array = _phase_samples.get("full", [])
    probe.add_measured("r1_render_mean", "ms", full, "≤ 16.6", 16.6)
    probe.add_measured("r1_render_p95_spike", "ms", full, "< 50", 50.0)
    probe.add_measured("r3_total_frame_share", "ms", full, "< 9.16（55%）", 9.16)

    var no_entity: Array = _phase_samples.get("no_entity", [])
    var no_particles: Array = _phase_samples.get("no_particles", [])
    var base: Array = _phase_samples.get("base", [])
    var delta_entity: Array = []
    var delta_particles: Array = []
    var n_ent: int = mini(full.size(), no_entity.size())
    var n_par: int = mini(full.size(), no_particles.size())
    for i in range(n_ent):
        delta_entity.append(float(full[i]) - float(no_entity[i]))
    for i in range(n_par):
        delta_particles.append(float(full[i]) - float(no_particles[i]))
    probe.add_measured("r3_entity_render", "ms", delta_entity, "< 4 / < 8", 4.0)
    probe.add_measured("r3_particles", "ms", delta_particles, "< 3 / < 6", 3.0)

    # 闭合校验：base 态（地板+UI）的边际应≈ Δ_entity + Δ_particles，残差过大即告警。
    if not base.is_empty() and n_ent > 0 and n_par > 0:
        var d_entity := _mean(full) - _mean(no_entity)
        var d_particles := _mean(full) - _mean(no_particles)
        var d_base_total := _mean(full) - _mean(base)
        var residual := d_base_total - (d_entity + d_particles)
        var tol := max(0.3, 0.2 * abs(d_base_total))
        probe.note("delta_isolation: mean_full=%.4f mean_base=%.4f d_entity=%.4f d_particles=%.4f d_base_total=%.4f residual=%.4f tol=%.4f %s" % [
            _mean(full), _mean(base), d_entity, d_particles, d_base_total, residual, tol,
            ("CLOSED" if abs(residual) <= tol else "WARN_CLOSURE_DRIFT")
        ])


# 结构计数（格数 / 实例数）只作证据日志，**不是性能耗时**，不进 CSV 数值列。
# 用于证明 Wave 3b 的格映射与屏外剔除确实可用，而非「场景未落地」。
func _note_render_structure(probe) -> void:
    var dg := DungeonGeneratorMod.new()
    var layout: Dictionary = dg.generate_sync(SEED, FLOOR_START, TIER_HIGH)
    var view: Rect2i = FloorGridMod.view_rect_for_layout(layout)
    var all_tiles: Dictionary = FloorGridMod.build_tiles(layout)
    var visible: Dictionary = FloorGridMod.cull_tiles(all_tiles, view)
    var ents: Array = FloorGridMod.visible_entities(layout, view)
    probe.note("render_structure (counts_only_not_ms): total_cells=%d visible_cells=%d visible_entities=%d view=%s logic_asset=%s render_asset=%s" % [
        all_tiles.size(), visible.size(), ents.size(), str(view),
        FloorGridMod.ASSET_SOURCE, FloorTilemapMod.ASSET_SOURCE
    ])
    dg.free()

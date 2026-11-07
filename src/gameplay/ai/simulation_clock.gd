# simulation_clock.gd — ADR-3 定步长仿真时钟（生产版，由 R3 原型晋升）
# =====================================================================
# 职责（architecture-doc.md §1.7 / ADR-3）：固定 10Hz tick（TICK_DT=0.1），
#       MAX_CATCHUP=3 追帧上限（防后台恢复雪崩），tick 内先消费输入队列
#       （ADR-2 帧末结算）再驱动 CombatDirector.step_simulation；连续超帧
#       预算 → 自适应降 5Hz（TICK_DT_SLOW=0.2）。屏外剔除（offscreen_culler）
#       为渲染层职责（Wave 3b 的 FloorGrid.cull_tiles），本文件不内联。
#       本文件不进入全局随机 lint（无 randf/randi）。
#
# 【2026-11-07 _adapt 修复 · 必读】
#   旧实现用 `delta > 1/60` 判「超预算」，把**帧间隔长**误当成**单帧超时**：
#   30fps 设备每帧 delta=1/30 必然命中，连续 30 帧后误降 5Hz。Godot 4.3
#   headless 实跑证据：30fps 600 帧（20s）只得 104 tick（记账基准期望 200）；
#   10s 墙钟对比 60fps 99 tick vs 30fps 54 tick。该偏差自 Phase 3 原型即存在，
#   会污染 PC 30fps 下限档的 r3_ai_tick 测量。
#   修复：超预算**只认实测单帧耗时** frame_cost_s，与帧间隔 delta 彻底解耦：
#     - advance(delta, frame_cost_s) 第二参数由调用方注入（秒）；
#     - _process 自动取 Performance.TIME_PROCESS（CPU 侧逻辑耗时，ms→s），
#       或由主循环用真实 profiler 调 report_frame_cost() 注入更完整的帧耗时；
#     - frame_cost_s < 0 表示无插桩数据 → **保守不降频**（streak 归零），
#       绝不拿 delta 兜底猜测；
#     - 帧间隔长（30fps 稳态）不再触发降频，单帧真实超时仍会触发。
#   注意：TIME_PROCESS 只覆盖 CPU 脚本耗时，不含 GPU / 渲染；它是保守近似，
#   正式 PC 帧预算结论仍须按 docs/qa/evidence/_template/README.md 实测。
#
# 与 R3 原型（src/prototype/r3_frame_budget/gd_simulation_clock.gd）的差异（晋升清理）：
#   - 去除原型注释与 InputQueue 草图，消费逻辑直接落 tick()；
#   - 超预算阈值提为命名常量 BUDGET_FRAME_DT（=1/60），语义见上；
#   - advance(delta) 公开，供 _process 调用，也供无头测试直接驱动 ticks。
# =====================================================================

class_name SimulationClock
extends Node

const TICK_DT           := 0.1        # 10Hz 主频
const MAX_CATCHUP       := 3          # 追帧上限，超出丢弃积压防雪崩
const TICK_DT_SLOW      := 0.2        # 5Hz 自适应降频
const OVER_BUDGET_LIMIT := 30         # 连续超预算帧数阈值 → 触发降频
const BUDGET_FRAME_DT   := 1.0 / 60.0 # 单帧预算（60fps），仅与实测耗时比较
const COST_UNAVAILABLE  := -1.0       # 无插桩数据的哨兵值

const COST_SOURCE_AUTO := "cpu_process_monitor"
const COST_SOURCE_INJECTED := "injected_profiler"
const COST_SOURCE_NONE := "unavailable"

var combat_director = null   # CombatDirector（注入；step_simulation 在此驱动）
var input_queue = null       # InputQueue（注入；帧末结算在此消费）
var tick_count: int = 0      # 测试可观测：累计 tick 数

var last_frame_cost_s: float = COST_UNAVAILABLE   # 最近一次用于判定的单帧耗时
var last_frame_cost_source: String = COST_SOURCE_NONE

var _accum := 0.0
var _slow := false
var _over_budget_streak := 0
var _pending_frame_cost: float = COST_UNAVAILABLE


func _process(delta: float) -> void:
    # 解耦纪律：_process 只做累加与调度，绝不做锁敌/寻路/技能决策（ADR-3）。
    advance(delta, _measured_frame_cost())


# 外部真实 profiler 插桩入口：传入完整单帧耗时（秒），优先于 CPU 侧近似值。
func report_frame_cost(cost_s: float) -> void:
    if cost_s < 0.0:
        return
    if _pending_frame_cost < 0.0 or cost_s > _pending_frame_cost:
        _pending_frame_cost = cost_s


func _measured_frame_cost() -> float:
    if _pending_frame_cost >= 0.0:
        var injected: float = _pending_frame_cost
        _pending_frame_cost = COST_UNAVAILABLE
        last_frame_cost_source = COST_SOURCE_INJECTED
        return injected
    # CPU 侧逻辑耗时（毫秒）→ 秒；不含 GPU，属保守近似。
    var cpu_ms: float = float(Performance.get_monitor(Performance.TIME_PROCESS))
    last_frame_cost_source = COST_SOURCE_AUTO
    return cpu_ms / 1000.0


# 累加器主循环：固定步长 tick + 追帧钳制 + 自适应降频。
# frame_cost_s 为本帧实测耗时（秒）；COST_UNAVAILABLE 表示无插桩数据。
# 无头测试可循环调用本方法驱动 tick（每调用一次模拟一帧）。
func advance(delta: float, frame_cost_s: float = COST_UNAVAILABLE) -> void:
    _accum += delta
    var dt := TICK_DT if not _slow else TICK_DT_SLOW
    var n := 0
    while _accum >= dt and n < MAX_CATCHUP:
        _tick(dt)
        _accum -= dt
        n += 1
    if n >= MAX_CATCHUP:
        _accum = 0.0   # 丢弃积压，防雪崩（ADR-3）
    _adapt(frame_cost_s)


func _tick(dt: float) -> void:
    # ADR-2 帧末结算：先消费输入队列（去重 + cd 钳 0.5s），再推仿真。
    if input_queue != null:
        input_queue.advance_time(dt)
        input_queue.consume_into(combat_director)
    # ADR-3：锁敌/伤害结算（非每帧）由 CombatDirector 在 10Hz tick 内完成。
    if combat_director != null:
        combat_director.step_simulation(dt)
    tick_count += 1


func _adapt(frame_cost_s: float) -> void:
    last_frame_cost_s = frame_cost_s
    if frame_cost_s < 0.0:
        # 无实测数据：不猜、不降频。帧间隔长（30fps/后台恢复）不等于单帧超时。
        _over_budget_streak = 0
        _slow = false
        return
    var over: bool = frame_cost_s > BUDGET_FRAME_DT
    if over:
        _over_budget_streak += 1
    else:
        _over_budget_streak = 0
    if _over_budget_streak >= OVER_BUDGET_LIMIT and not _slow:
        _slow = true
    elif _over_budget_streak == 0 and _slow:
        _slow = false


# 观测辅助：当前是否处于 5Hz 降频态（测试与外部 HUD 可用）。
func is_slow() -> bool:
    return _slow


# 观测辅助：超预算连续帧数（供 QA 插桩与 HUD 使用）。
func over_budget_streak() -> int:
    return _over_budget_streak

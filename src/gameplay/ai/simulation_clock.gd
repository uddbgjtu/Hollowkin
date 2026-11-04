# simulation_clock.gd — ADR-3 定步长仿真时钟（生产版，由 R3 原型晋升）
# =====================================================================
# 职责（architecture-doc.md §1.7 / ADR-3）：固定 10Hz tick（TICK_DT=0.1），
#       MAX_CATCHUP=3 追帧上限（防后台恢复雪崩），tick 内先消费输入队列
#       （ADR-2 帧末结算）再驱动 CombatDirector.step_simulation；连续超帧
#       预算 → 自适应降 5Hz（TICK_DT_SLOW=0.2）。屏外剔除（offscreen_culler）
#       为 Epic-C 后续桩（见架构 §1.7），本文件保持最小，不内联剔除逻辑。
#       本文件不进入全局随机 lint（无 randf/randi）。
#
# 与 R3 原型（src/prototype/r3_frame_budget/gd_simulation_clock.gd）的差异（晋升清理）：
#   - 去除原型注释与 InputQueue 草图，消费逻辑直接落 tick()；
#   - 超预算阈值提为命名常量 BUDGET_FRAME_DT（=1/60），语义更清晰；
#   - advance(delta) 公开，供 _process 调用，也供无头测试直接驱动 ticks。
# =====================================================================

class_name SimulationClock
extends Node

const TICK_DT           := 0.1        # 10Hz 主频
const MAX_CATCHUP       := 3          # 追帧上限，超出丢弃积压防雪崩
const TICK_DT_SLOW      := 0.2        # 5Hz 自适应降频
const OVER_BUDGET_LIMIT := 30         # 连续超预算帧数阈值 → 触发降频
const BUDGET_FRAME_DT   := 1.0 / 60.0 # 单帧预算（60fps），用于超预算启发式判定

var combat_director = null   # CombatDirector（注入；step_simulation 在此驱动）
var input_queue = null       # InputQueue（注入；帧末结算在此消费）
var tick_count: int = 0      # 测试可观测：累计 tick 数

var _accum := 0.0
var _slow := false
var _over_budget_streak := 0


func _process(delta: float) -> void:
    # 解耦纪律：_process 只做累加与调度，绝不做锁敌/寻路/技能决策（ADR-3）。
    advance(delta)


# 累加器主循环：固定步长 tick + 追帧钳制 + 自适应降频。
# 无头测试可循环调用本方法驱动 tick（每调用一次模拟一帧）。
func advance(delta: float) -> void:
    _accum += delta
    var dt := TICK_DT if not _slow else TICK_DT_SLOW
    var n := 0
    while _accum >= dt and n < MAX_CATCHUP:
        _tick(dt)
        _accum -= dt
        n += 1
    if n >= MAX_CATCHUP:
        _accum = 0.0   # 丢弃积压，防雪崩（ADR-3）
    _adapt(delta)


func _tick(dt: float) -> void:
    # ADR-2 帧末结算：先消费输入队列（去重 + cd 钳 0.5s），再推仿真。
    if input_queue != null:
        input_queue.advance_time(dt)
        input_queue.consume_into(combat_director)
    # ADR-3：锁敌/伤害结算（非每帧）由 CombatDirector 在 10Hz tick 内完成。
    if combat_director != null:
        combat_director.step_simulation(dt)
    tick_count += 1


func _adapt(delta: float) -> void:
    # 超预算启发式：单帧 delta 越过 60fps 预算即视为超预算。
    # 真机应在各子系统插桩取真实耗时；此处以单帧时长作预算判定，符合 R3 原型方法论。
    var over := delta > BUDGET_FRAME_DT
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

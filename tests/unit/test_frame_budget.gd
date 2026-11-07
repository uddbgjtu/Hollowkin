# test_frame_budget.gd — G4 记账级帧预算断言（GUT）
# =====================================================================
# 【性质声明 · 先读】本文件为【记账级 · 非设备帧时间】验证：
#   仅用 headless Godot 驱动生产 SimulationClock / InputQueue 的 tick 计数，
#   校验 ADR-2（帧末队列）与 ADR-3（10Hz 定步长）的记账逻辑、跨帧率一致性。
#   **不测量、不推算任何设备 CPU/GPU 运行时耗时（ms）**，不得把 tick 数换算成
#   R1/R3 帧预算结论，也不得据此关闭 architecture-doc.md §6 的 CONCERNS。
#   设备指标口径见已归档的 docs/qa/archive/r1r3-device-test-plan.md（仅历史方法学）；
#   ADR-6 后判据改由 PC 窗口 / 全屏基线采集（Wave 4）。
#
# 与 tests/unit/test_combat.gd 的分工（避免重复造轮子）：
#   test_combat.gd 已覆盖：60fps 稳态 10Hz、5s 卡顿追帧钳 3、
#   连续【实测超预算】降 5Hz、帧间隔长但耗时低不降频。
#   本文件只补其未覆盖的：30fps 稳态记账、跨帧率一致、降频恢复、
#   ADR-2 tick 内「先消费队列 → 再推仿真」、无插桩数据的保守策略、
#   report_frame_cost 注入链路。
# ADR-5：本文件不含任何全局随机调用。
#
# 【2026-11-06 发现 → 2026-11-07 修复】
#   旧 `simulation_clock.gd::_adapt()` 以 `delta > 1/60` 判超预算，30fps 每帧
#   1/30 必然命中，连续 30 帧后误降 5Hz。实跑证据：30fps 20s 得 104 tick
#   （记账基准 200）；10s 墙钟 60fps 99 tick vs 30fps 54 tick。
#   本文件 (1)(2) 曾改为「偏差探测」如实锁定缺陷；本次修复后已**还原为正确断言**：
#   30fps ≈200 tick / 跨帧率一致 / 不降频。超预算改由实测单帧耗时注入触发。
#   影响范围：PC 30fps 下限档（R3）不再被误判降载，r3_ai_tick 测量不再受污染。
# =====================================================================

extends GutTest

const SimulationClock = preload("res://src/gameplay/ai/simulation_clock.gd")
const InputQueue      = preload("res://src/gameplay/input/input_queue.gd")
const HitZone         = preload("res://src/gameplay/input/hit_zone.gd")


# 轻量记账目标：统计 tick 内驱动的仿真次数与动作，不产生真实战斗或渲染。
class Recorder extends RefCounted:
    var steps := 0
    var actions := []
    var sim_dt_sum := 0.0
    func step_simulation(dt: float) -> void:
        steps += 1
        sim_dt_sum += dt
    func on_action(id: String) -> void:
        actions.append(id)


# ----------------------------------------------------------------------
# (1) 30fps 稳态：600 帧 @30fps = 20s → ≈200 tick，且不降频
#     （修复前实跑 104 tick / is_slow()=true）
# ----------------------------------------------------------------------
func test_30fps_steady_state_20s_yields_200_ticks():
    var rec := Recorder.new()
    var c := SimulationClock.new()
    c.combat_director = rec
    for i in range(600):
        c.advance(1.0 / 30.0)   # 无插桩数据：帧间隔长不得推断为单帧超时
    assert_false(c.is_slow(), "修复后 30fps 稳态不应误降 5Hz")
    assert_true(c.tick_count >= 199 and c.tick_count <= 201,
        "30fps 20s 应≈200 tick（10Hz 记账），得 %d" % c.tick_count)
    assert_true(abs(rec.sim_dt_sum - 20.0) < 0.25,
        "累计仿真步长应≈20s，得 %s" % rec.sim_dt_sum)
    assert_eq(rec.steps, c.tick_count, "每 tick 恰驱动一次 step_simulation")
    c.free()


# ----------------------------------------------------------------------
# (2) 跨帧率一致性：相同仿真时长不因 60/30fps 改变记账结果
#     （修复前实跑 99 vs 54）
# ----------------------------------------------------------------------
func test_cross_framerate_same_elapsed_same_accounting():
    var rec_a := Recorder.new()
    var rec_b := Recorder.new()
    var a := SimulationClock.new()
    var b := SimulationClock.new()
    a.combat_director = rec_a
    b.combat_director = rec_b
    for i in range(600):
        a.advance(1.0 / 60.0)   # 10s @60fps
    for i in range(300):
        b.advance(1.0 / 30.0)   # 10s @30fps
    assert_false(a.is_slow(), "60fps 稳态不应触发降频")
    assert_false(b.is_slow(), "30fps 稳态不应触发降频")
    # 浮点累加器在 6 帧 / 3 帧分界上允许 ±1 tick 抖动，与既有 60fps 用例同口径。
    assert_true(abs(a.tick_count - b.tick_count) <= 1,
        "相同仿真时长（10s）不应因帧率产生不同 tick 数：%d vs %d" % [a.tick_count, b.tick_count])
    assert_true(abs(rec_a.sim_dt_sum - rec_b.sim_dt_sum) < 0.25,
        "两种帧率累计仿真步长应一致：%s vs %s" % [rec_a.sim_dt_sum, rec_b.sim_dt_sum])
    a.free()
    b.free()


# ----------------------------------------------------------------------
# (3) 自适应降频可逆：注入真实超预算耗时触发 5Hz，回到预算内即恢复 10Hz
# ----------------------------------------------------------------------
func test_adaptive_5hz_recovers_when_frames_return_to_budget():
    var c := SimulationClock.new()
    c.combat_director = Recorder.new()
    for i in range(31):
        c.advance(0.02, 0.02)    # 实测单帧 20ms > 16.67ms 预算
    assert_true(c.is_slow(), "连续 31 帧实测超预算应进入 5Hz 降频态")
    assert_eq(c.over_budget_streak(), 31, "连续超预算帧数可观测")
    for i in range(5):
        c.advance(1.0 / 60.0, 0.005)   # 实测单帧 5ms，预算内
    assert_false(c.is_slow(), "预算内帧应使 streak 归零并退出降频态")
    assert_eq(c.over_budget_streak(), 0, "streak 应归零")
    c.free()


# ----------------------------------------------------------------------
# (4) ADR-2 链路：tick 内先消费输入队列（去重 + 0.5s cd 钳）再推仿真
#     cd 钳基于「仿真时间」而非墙钟时间，故可直接用 headless 验证。
# ----------------------------------------------------------------------
func test_adr2_tick_consumes_queue_before_simulation():
    var hz := HitZone.new()
    hz.register_rect("skill_a", Rect2(0.0, 0.0, 64.0, 64.0))
    var iq := InputQueue.new()
    iq.set_hit_zone(hz)
    var rec := Recorder.new()
    var c := SimulationClock.new()
    c.combat_director = rec
    c.input_queue = iq

    # 同一 tick 两个事件落同热区 → 帧末结算去重为 1 次
    iq.push({"position": Vector2(10.0, 10.0), "touch_id": 1})
    iq.push({"position": Vector2(20.0, 20.0), "touch_id": 2})
    c.advance(0.1)
    assert_eq(rec.actions.size(), 1, "同 tick 同热区应去重为 1 次")
    assert_eq(rec.actions[0], "skill_a")
    assert_eq(c.tick_count, 1, "0.1s 应恰触发 1 个 tick")
    assert_eq(rec.steps, 1, "tick 内应驱动 1 次仿真")

    # 0.5s 仿真下限钳：随后两个 tick 内重触发应被拦截
    iq.push({"position": Vector2(10.0, 10.0), "touch_id": 3})
    c.advance(0.1)
    c.advance(0.1)
    assert_eq(rec.actions.size(), 1, "0.5s 仿真内重触发应被 cd 下限钳拦截")

    # 仿真时刻推进到 ≥0.6s 后重触发应放行
    for i in range(3):
        c.advance(0.1)
    iq.push({"position": Vector2(10.0, 10.0), "touch_id": 4})
    c.advance(0.1)
    assert_eq(rec.actions.size(), 2, "仿真时刻 ≥0.5s 后应可再次触发")
    c.free()


# ----------------------------------------------------------------------
# (5) 无插桩数据时保守不降频：帧间隔再长也不得兜底猜测
# ----------------------------------------------------------------------
func test_no_instrumentation_data_never_downclocks():
    var c := SimulationClock.new()
    c.combat_director = Recorder.new()
    for i in range(200):
        c.advance(0.05)          # 20fps 的帧间隔，但无任何实测耗时
    assert_false(c.is_slow(), "无实测耗时不得用 delta 推断超预算")
    assert_eq(c.last_frame_cost_s, SimulationClock.COST_UNAVAILABLE,
        "应记录为无插桩数据")
    assert_eq(c.over_budget_streak(), 0, "streak 应始终保持 0")
    c.free()


# ----------------------------------------------------------------------
# (6) report_frame_cost 注入链路：真实 profiler 数据优先于 CPU 侧近似
# ----------------------------------------------------------------------
func test_reported_frame_cost_drives_downclock():
    var c := SimulationClock.new()
    c.combat_director = Recorder.new()
    for i in range(31):
        c.report_frame_cost(0.03)   # 30ms 实测完整帧耗时
        c.advance(0.02, c._measured_frame_cost())
    assert_true(c.is_slow(), "注入的真实单帧耗时应触发降频")
    assert_eq(c.last_frame_cost_source, SimulationClock.COST_SOURCE_INJECTED,
        "来源应标记为外部注入")
    assert_true(c.last_frame_cost_s > SimulationClock.BUDGET_FRAME_DT,
        "注入值应超过单帧预算")
    c.free()

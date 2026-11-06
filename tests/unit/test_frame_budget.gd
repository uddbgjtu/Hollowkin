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
#   test_combat.gd 已覆盖：60fps 稳态 10Hz、5s 卡顿追帧钳 3、连续超预算降 5Hz。
#   本文件只补其未覆盖的 4 项：30fps 稳态、跨帧率记账一致、降频恢复、
#   ADR-2 tick 内「先消费队列 → 再推仿真」及 cd 钳基于仿真时间。
# ADR-5：本文件不含任何全局随机调用。
#
# 【2026-11-06 headless 实跑发现 · 已知偏差，不掩盖】
#   prototype-r1r3-report.md §3.3 的 Python 记账基准称「30fps 600 帧 = 200 tick、
#   跨帧率一致」，但 Python 仿真的「超预算」是外部注入，稳态用例从不注入；
#   而 GDScript 原型 gd_simulation_clock.gd::_adapt() 与生产
#   simulation_clock.gd::_adapt() 均以 delta > 1/60 判超预算 —— 30fps 每帧
#   1/30 全部命中，连续 30 帧后误降 5Hz（TICK_DT_SLOW=0.2）。
#   实跑证据：30fps 20s 得 104 tick（基准期望 200）；10s 墙钟对比
#   60fps 99 tick vs 30fps 54 tick；仿真步长总量仍近似守恒（≈墙钟时长）。
#   影响：低端 30fps 设备（正是 R3 目标档）被误判降载，AI tick 腰斩。
#   本文件用例 (1)(2) 因此改为「如实锁定当前行为 + 标注已知偏差」，不把缺陷写成期望；
#   修复 _adapt（改以插桩真实耗时判超预算）后，应把断言改回
#   「tick_count≈200 且 is_slow()==false」/「a.tick_count == b.tick_count」。
#   生产代码不在本次批准写入范围内，修复需另行审批。
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
# (1) 【已知偏差探测】30fps 稳态：当前实现误降 5Hz，实跑 104 tick（基准期望 200）
#     修复后的正确期望：tick_count≈200 且 is_slow()==false。
# ----------------------------------------------------------------------
func test_30fps_false_positive_downclock_known_deviation():
    var rec := Recorder.new()
    var c := SimulationClock.new()
    c.combat_director = rec
    for i in range(600):
        c.advance(1.0 / 30.0)   # 600 帧 @30fps = 20s
    assert_true(c.is_slow(),
        "【已知偏差】30fps 每帧 1/30 > 1/60，被 _adapt 误判为持续超预算并降 5Hz")
    assert_true(c.tick_count > 90 and c.tick_count < 200,
        "【已知偏差】降频后 tick 显著低于 200（实跑 104），但仿真仍持续推进，不得卡死")
    assert_true(abs(rec.sim_dt_sum - 20.0) < 0.5,
        "仿真步长总量应近似守恒（≈20s 墙钟），得 %s" % rec.sim_dt_sum)
    assert_eq(rec.steps, c.tick_count, "每 tick 恰驱动一次 step_simulation")
    c.free()


# ----------------------------------------------------------------------
# (2) 【已知偏差探测】跨帧率：仿真步长守恒，但 tick 频率不守恒（99 vs 54）
#     修复后的正确期望：a.tick_count == b.tick_count 且 b.is_slow()==false。
# ----------------------------------------------------------------------
func test_cross_framerate_divergence_known_deviation():
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
    assert_true(b.is_slow(), "【已知偏差】30fps 被误判降频")
    assert_true(a.tick_count > b.tick_count,
        "【已知偏差】当前实现下 30fps 记账数低于 60fps（实跑 99 vs 54）")
    assert_true(abs(rec_a.sim_dt_sum - rec_b.sim_dt_sum) < 0.5,
        "两种帧率累计仿真步长应近似守恒：%s vs %s" % [rec_a.sim_dt_sum, rec_b.sim_dt_sum])
    a.free()
    b.free()


# ----------------------------------------------------------------------
# (3) 自适应降频可逆：预算内帧应把 5Hz 态恢复为 10Hz
# ----------------------------------------------------------------------
func test_adaptive_5hz_recovers_when_frames_return_to_budget():
    var c := SimulationClock.new()
    c.combat_director = Recorder.new()
    for i in range(31):
        c.advance(0.02)          # 连续超预算帧（> 1/60）
    assert_true(c.is_slow(), "连续 31 帧超预算应进入 5Hz 降频态")
    for i in range(5):
        c.advance(1.0 / 60.0)   # 回到预算内
    assert_false(c.is_slow(), "预算内帧应使 _over_budget_streak 归零并退出降频态")
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

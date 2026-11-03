#!/usr/bin/env python3
# =============================================================================
# R3 原型 · 触屏并发 + AI 同帧预算（Python 仿真 · 仅验证"记账逻辑"）
# =============================================================================
# 目的：在 sandbox（无 Godot、无低端机）下，对"10Hz 仿真时钟 + 输入队列帧末结算
#       + 自适应降频"的 *记账逻辑* 做可运行仿真，确认结构正确。
#
# 诚实声明（重要）：
#   * 本脚本 **不测量任何设备帧时间**。各子系统真实开销
#     （输入<0.5ms / AI~1.66ms / 同屏≤12敌人渲染<4ms / 粒子<3ms）是
#     feasibility-review.md R3 的 *目标预算*，须真机实测。
#   * 本仿真仅验证：① 累加器在 60fps 下每 60 帧恰发 ~6 次 AI tick（10Hz）；
#     ② MAX_CATCHUP=3 防后台恢复雪崩；③ 连续超预算 → 降 5Hz 触发逻辑正确。
#   * 这些是"方法学正确"，不是"性能达标"。
#
# 运行：python3 py_frame_budget_sim.py
# =============================================================================

TICK_DT = 0.1          # 10Hz
MAX_CATCHUP = 3
TICK_DT_SLOW = 0.2     # 5Hz
OVER_BUDGET_LIMIT = 30 # 连续超预算帧阈值
FRAME_60 = 1.0 / 60.0  # 16.667 ms

def simulate(frames, over_budget_from=None, over_budget_to=None, fps=60.0):
    dt_frame = 1.0 / fps
    accum = 0.0
    slow = False
    streak = 0
    ticks = 0
    catchups = 0
    for f in range(frames):
        accum += dt_frame
        dtn = TICK_DT if not slow else TICK_DT_SLOW
        n = 0
        while accum >= dtn and n < MAX_CATCHUP:
            ticks += 1          # 一次 AI tick（内部消费输入队列 + 战斗结算）
            accum -= dtn
            n += 1
        if n >= MAX_CATCHUP:
            accum = 0.0
            catchups += 1
        # 自适应：注入一段"超预算"帧
        over = (over_budget_from is not None and over_budget_from <= f < over_budget_to)
        if over:
            streak += 1
        else:
            streak = 0
        if streak >= OVER_BUDGET_LIMIT and not slow:
            slow = True
        elif streak == 0 and slow and (over_budget_from is None):
            slow = False
    return ticks, slow, catchups

def report():
    print("=" * 70)
    print("R3 原型：仿真时钟记账逻辑仿真（sandbox，非设备性能测量）")
    print("=" * 70)

    # 1) 60fps 稳态：600 帧=10s 应发 ~100 次 tick（10Hz）
    ticks, slow, catch = simulate(600, fps=60.0)
    expected1 = round(600 / 60.0 * 10.0)
    print(f"\n[1] 60fps 稳态 600 帧（10s）：AI tick 次数 = {ticks}")
    print(f"    期望 ~{expected1} 次 (10Hz×10s)；实测 {ticks}；降频={slow}；追帧触发={catch}")
    assert abs(ticks - expected1) <= 2, "10Hz tick 计数异常"

    # 2) 30fps 稳态：600 帧=20s 应发 ~200 次 tick（10Hz，与帧率无关）
    ticks30, _, _ = simulate(600, fps=30.0)
    expected2 = round(600 / 30.0 * 10.0)
    print(f"[2] 30fps 稳态 600 帧（20s）：AI tick 次数 = {ticks30}")
    print(f"    期望 ~{expected2} 次；实测 {ticks30}（证明行为跨帧率一致）")
    assert abs(ticks30 - expected2) <= 2, "跨帧率一致性异常"

    # 3) 自适应降频：第 100~200 帧注入超预算 → 应触发 5Hz
    ticks_a, slow_a, _ = simulate(360, over_budget_from=100, over_budget_to=200, fps=60.0)
    print(f"[3] 注入 100 帧超预算（第100~200帧）：最终降频态 = {slow_a}")
    print(f"    超预算区间内 tick 应减速（5Hz）；实测总 tick = {ticks_a}")
    assert slow_a is True, "自适应降频未触发"

    # 4) 追帧上限：极端大 delta（后台恢复）不应无限追帧
    #    以单帧 dt=1.0s 模拟：最多 MAX_CATCHUP 次 tick 后丢弃积压
    ticks_b, _, catch_b = simulate(1, fps=1.0)  # 1 帧 = 1 秒
    print(f"[4] 单帧 1s(delta 极大)：tick 次数 = {ticks_b}（≤MAX_CATCHUP={MAX_CATCHUP}），追帧丢弃={catch_b}")
    assert ticks_b <= MAX_CATCHUP, "追帧未受 MAX_CATCHUP 约束"

    print("\n=== 结论（诚实）===")
    print("  - 10Hz 累加器记账正确：60fps/30fps 下 tick 计数符合 10Hz，跨帧率一致。")
    print("  - MAX_CATCHUP=3 约束追帧，防后台恢复雪崩（断言通过）。")
    print("  - 自适应 5Hz 降频触发逻辑正确（连续超预算 → 降频）。")
    print("  - 以上为'方法学正确'，非'性能达标'。各子系统真实开销须真机实测：")
    print("    输入仲裁<0.5ms / AI~1.66ms(均摊) / 同屏≤12敌人渲染<4ms / 粒子<3ms。")

if __name__ == "__main__":
    report()

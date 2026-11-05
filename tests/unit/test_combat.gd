# combat_test.gd — Epic C 战斗系统单测（GUT）
# =====================================================================
# 覆盖（studio lead 任务书）：
#   (a) DamageCalc 确定性 / 钳制边界 / 无负值 / Variance 落在 [0.90,1.10]×理想
#   (b) SimulationClock 10Hz 稳态 / 长卡顿追帧钳 3 / 连续超预算降 5Hz
#   (c) InputQueue 同热区去重 + 0.5s cd 下限钳
#   (d) JoystickPointer 8 向 + 15% 死区归零
#   (e) DeathSettlement 30% 转化
#   (f) StatBlock C1 公式
# ADR-5：测试内随机一律走 RNGService.floor_rng(...)，禁用全局随机。
# 注意：本 sandbox 无 Godot，本文件不可执行，仅按 GUT 规范正确书写（见文末声明）。
# =====================================================================

extends GutTest

const RNGService       = preload("res://src/core/rng/rng_service.gd")
const DamageCalc      = preload("res://src/gameplay/combat/damage_calc.gd")
const SimulationClock = preload("res://src/gameplay/ai/simulation_clock.gd")
const InputQueue      = preload("res://src/gameplay/input/input_queue.gd")
const HitZone         = preload("res://src/gameplay/input/hit_zone.gd")
const JoystickPointer = preload("res://src/gameplay/input/joystick_pointer.gd")
const CombatDirector  = preload("res://src/gameplay/combat/combat_director.gd")
const DeathSettlement = preload("res://src/gameplay/combat/death_settlement.gd")
const StatBlock       = preload("res://src/core/stats/stat_block.gd")

const SEED := 13579
const FLOOR := 2


# 轻量伪目标：承接 step_simulation / on_action，统计调用次数（用于时钟/队列测试）。
class FakeDirector extends RefCounted:
    var step_count := 0
    var actions := []
    func step_simulation(dt: float) -> void:
        step_count += 1
    func on_action(id: String) -> void:
        actions.append(id)


# ----------------------------------------------------------------------
# (a) DamageCalc
# ----------------------------------------------------------------------
func test_damage_calc_deterministic():
    var r1 := RNGService.floor_rng(SEED, FLOOR)
    var r2 := RNGService.floor_rng(SEED, FLOOR)
    for i in range(300):
        var a := DamageCalc.compute(50.0, 4.0, 1.6, 5.0, 150.0, 1.0, r1)
        var b := DamageCalc.compute(50.0, 4.0, 1.6, 5.0, 150.0, 1.0, r2)
        assert_eq(a, b, "同 (seed,floor) 同参数应逐次一致 第 %d" % i)


func test_damage_calc_clamp_bounds_and_non_negative():
    for s in range(50):
        var rng := RNGService.floor_rng(SEED + s, FLOOR)
        for k in range(50):
            # 极端大攻击（测试上限钳 99999）
            var big := DamageCalc.compute(99999.0, 0.0, 5.0, 0.0, 100.0, 1.0, rng)
            assert_true(big <= 99999, "伤害不得超上限 99999 (seed=%d,k=%d)" % [s, k])
            assert_true(big >= 1, "伤害不得低于下限 1 (seed=%d,k=%d)" % [s, k])
            # 极端小攻击 + 高防御（测试下限钳 1）
            var small := DamageCalc.compute(1.0, 999.0, 1.0, 0.0, 100.0, 1.0, rng)
            assert_true(small >= 1, "低伤不得低于下限 1")
            assert_true(small <= 99999, "低伤不得超上限")


# Variance 落在 [0.90,1.10]×理想；floor 至多改变 ±1，故用 ±1 容差带。
func test_damage_calc_variance_within_band():
    var atk := 200.0
    var def := 4.0
    var coeff := 1.0
    var mitigated := atk * coeff * 100.0 / (100.0 + def * 8.0)  # K=8
    var rng := RNGService.floor_rng(SEED, FLOOR)
    for i in range(200):
        var dmg := DamageCalc.compute(atk, def, coeff, 0.0, 100.0, 1.0, rng)
        assert_true(dmg >= 0.90 * mitigated - 1.0, "Variance 不应明显低于 0.90×理想 (第 %d)" % i)
        assert_true(dmg <= 1.10 * mitigated + 1.0, "Variance 不应高于 1.10×理想 (第 %d)" % i)


func test_damage_calc_crit_applied():
    # 暴击率 100%、crit_dmg 150%：result ≈ Mitigated × 1.5 × Variance
    var atk := 100.0
    var def := 4.0
    var coeff := 1.0
    var mitigated := atk * coeff * 100.0 / (100.0 + def * 8.0)
    var rng := RNGService.floor_rng(SEED, FLOOR)
    for i in range(100):
        var dmg := DamageCalc.compute(atk, def, coeff, 100.0, 150.0, 1.0, rng)
        assert_true(dmg >= 1.35 * mitigated - 1.0, "暴击应 ≥ 1.5×0.90×理想 (第 %d)" % i)
        assert_true(dmg <= 1.65 * mitigated + 1.0, "暴击应 ≤ 1.5×1.10×理想 (第 %d)" % i)


func test_damage_calc_compute_from_stats_matches_compute():
    # 两个同 (seed,floor) 的 rng 实例：compute_from_stats 与 compute 取相同字段，
    # 且各消耗相同次数的 rng，故结果必一致。
    var r1 := RNGService.floor_rng(SEED, FLOOR)
    var r2 := RNGService.floor_rng(SEED, FLOOR)
    var stats := {"atk": 30.0, "def": 4.0, "crit_rate": 0.0, "crit_dmg": 100.0}
    var a := DamageCalc.compute_from_stats(stats, 1.6, 1.0, r1)
    var b := DamageCalc.compute(30.0, 4.0, 1.6, 0.0, 100.0, 1.0, r2)
    assert_eq(a, b, "compute_from_stats 应与 compute(同参同rng) 一致")


# ----------------------------------------------------------------------
# (b) SimulationClock
# ----------------------------------------------------------------------
func test_clock_steady_state_10hz():
    var clock := SimulationClock.new()
    var fake := FakeDirector.new()
    clock.combat_director = fake
    clock.input_queue = null
    # 600 帧 @ 1/60 ≈ 10s；10Hz → ~100 ticks（每 tick reset 累加器，无漂移）
    for i in range(600):
        clock.advance(1.0 / 60.0)
    assert_true(clock.tick_count >= 99 and clock.tick_count <= 101, "稳态应≈10 ticks/秒，得 %d" % clock.tick_count)


func test_clock_stall_capped_at_max_catchup():
    var clock := SimulationClock.new()
    var fake := FakeDirector.new()
    clock.combat_director = fake
    # 一次巨幅 delta（5s）：追帧钳 3，且积压丢弃（accum 归零）
    clock.advance(5.0)
    assert_eq(clock.tick_count, 3, "长卡顿追帧应钳制为 MAX_CATCHUP=3")
    # 之后小幅推进不应因残留 accum 立即再 tick
    clock.advance(0.05)
    assert_eq(clock.tick_count, 3, "accum 已重置，残留不应触发额外 tick")


func test_clock_adaptive_5hz_after_over_budget():
    var clock := SimulationClock.new()
    var fake := FakeDirector.new()
    clock.combat_director = fake
    # 连续 feed 超预算帧（delta=0.02 > 1/60）直至触发 5Hz
    for i in range(31):
        clock.advance(0.02)
    assert_true(clock.is_slow(), "连续超预算应触发 5Hz 降频")
    # 降频后 4s（200 帧 @0.02）@5Hz → ~20 ticks
    var before := clock.tick_count
    for i in range(200):
        clock.advance(0.02)
    var delta_ticks := clock.tick_count - before
    assert_true(delta_ticks >= 19 and delta_ticks <= 21, "降频后应≈5 ticks/秒，得 %d" % delta_ticks)


# ----------------------------------------------------------------------
# (c) InputQueue
# ----------------------------------------------------------------------
func test_input_queue_dedupe_same_zone():
    var hz := HitZone.new()
    hz.register_rect("skill_a", Rect2(0.0, 0.0, 64.0, 64.0))
    var iq := InputQueue.new()
    iq.set_hit_zone(hz)
    var target := FakeDirector.new()
    # 两事件均落在 skill_a 区域 → 单次结算
    iq.push({"position": Vector2(10.0, 10.0), "touch_id": 1})
    iq.push({"position": Vector2(20.0, 20.0), "touch_id": 2})
    iq.consume_into(target)
    assert_eq(target.actions.size(), 1, "同热区多事件应去重为 1 次")
    assert_eq(target.actions[0], "skill_a")


func test_input_queue_cd_floor_clamp():
    var hz := HitZone.new()
    hz.register_rect("skill_a", Rect2(0.0, 0.0, 64.0, 64.0))
    var iq := InputQueue.new()
    iq.set_hit_zone(hz)
    var target := FakeDirector.new()

    iq.push({"position": Vector2(10.0, 10.0), "touch_id": 1})
    iq.consume_into(target)           # t=0 命中
    assert_eq(target.actions.size(), 1)

    iq.advance_time(0.1)              # t=0.1，距上次 <0.5s
    iq.push({"position": Vector2(10.0, 10.0), "touch_id": 2})
    iq.consume_into(target)           # 应被 0.5s 下限钳拦截
    assert_eq(target.actions.size(), 1, "0.5s 内重触发应被 cd 下限钳拦截")

    iq.advance_time(0.5)              # t=0.6，距上次 ≥0.5s
    iq.push({"position": Vector2(10.0, 10.0), "touch_id": 3})
    iq.consume_into(target)
    assert_eq(target.actions.size(), 2, "超过 0.5s 后可再次触发")


func test_input_queue_no_zone_no_action():
    var hz := HitZone.new()
    hz.register_rect("skill_a", Rect2(0.0, 0.0, 64.0, 64.0))
    var iq := InputQueue.new()
    iq.set_hit_zone(hz)
    var target := FakeDirector.new()
    iq.push({"position": Vector2(500.0, 500.0), "touch_id": 1})  # 区外
    iq.consume_into(target)
    assert_eq(target.actions.size(), 0, "热区外事件不应触发动作")


# ----------------------------------------------------------------------
# (d) JoystickPointer
# ----------------------------------------------------------------------
func test_joystick_8_direction_and_deadzone():
    var jp := JoystickPointer.new()
    jp.max_radius = 100.0
    jp.press(1, Vector2(100.0, 100.0))

    # 死区：移动 10px < 0.15*100=15 → 零向量
    jp.move(1, Vector2(110.0, 100.0))
    assert_eq(jp.get_direction(), Vector2.ZERO, "死区内应归零")

    # 右
    jp.move(1, Vector2(200.0, 100.0))
    assert_eq(jp.get_direction(), Vector2(1.0, 0.0), "应指向右")

    # 下（Godot y 向下）
    jp.move(1, Vector2(100.0, 200.0))
    assert_eq(jp.get_direction(), Vector2(0.0, 1.0), "应指向下")

    # 右下 45°
    jp.move(1, Vector2(200.0, 200.0))
    var d45 := jp.get_direction()
    assert_true(abs(d45.x - 0.7071) < 0.001 and abs(d45.y - 0.7071) < 0.001, "应吸附 45° (得 %s)" % d45)

    # 释放 → 零向量
    jp.release(1)
    assert_eq(jp.get_direction(), Vector2.ZERO, "释放后应归零")


# ----------------------------------------------------------------------
# (e) DeathSettlement
# ----------------------------------------------------------------------
func test_death_settlement_30_percent():
    assert_eq(DeathSettlement.settle(100), 30, "100 → 30")
    assert_eq(DeathSettlement.settle(10), 3, "10 → 3")
    assert_eq(DeathSettlement.settle(0), 0, "0 → 0")
    assert_eq(DeathSettlement.settle(33), 9, "33 → floor(9.9)=9")
    assert_eq(DeathSettlement.settle(99999), 29999, "99999 → floor(29999.7)=29999")


# ----------------------------------------------------------------------
# (f) StatBlock C1
# ----------------------------------------------------------------------
func test_stat_block_c1_formula():
    var sb := StatBlock.new()
    var base := {"hp": 100.0, "atk": 12.0, "def": 4.0, "spd": 3.0, "aps": 1.2, "crit_rate": 5.0, "crit_dmg": 150.0}
    var vein := {"atk": 3.0, "def": 2.0}
    sb.build_run_base(base, vein)
    var runes := [{"mult": {"atk": 1.5}}, {"mult": {"atk": 1.2}}]
    sb.recompute_rune_mult(runes)

    # FinalStat(atk) = (12+3) × (1.5×1.2) = 15 × 1.8 ≈ 27.0（浮点容差）
    assert_true(abs(sb.final_stat("atk") - 27.0) < 0.001, "C1 atk 公式，得 %s" % sb.final_stat("atk"))
    # def 无常驻符文乘区 → (4+2) × 1.0 = 6.0
    assert_eq(sb.final_stat("def"), 6.0, "C1 def 公式")
    # 未经灵脉修正的字段
    assert_eq(sb.final_stat("hp"), 100.0, "hp 应为 base")


func test_stat_block_negative_atk_def_clamped():
    var sb := StatBlock.new()
    var base := {"atk": -5.0, "def": -2.0, "hp": 50.0}
    sb.build_run_base(base, {})
    assert_eq(sb.final_stat("atk"), 0.0, "负 atk 应钳为 0")
    assert_eq(sb.final_stat("def"), 0.0, "负 def 应钳为 0")


func test_stat_block_rune_mult_independent_per_stat():
    var sb := StatBlock.new()
    sb.build_run_base({"atk": 10.0, "crit_dmg": 100.0}, {})
    var runes := [{"mult": {"atk": 2.0}}, {"mult": {"crit_dmg": 1.5}}]
    sb.recompute_rune_mult(runes)
    assert_eq(sb.final_stat("atk"), 20.0, "atk 乘区独立")
    assert_eq(sb.final_stat("crit_dmg"), 150.0, "crit_dmg 乘区独立")


# ----------------------------------------------------------------------
# 附加：CombatDirector 确定性 + 边界（强化 (a) 与 GDD §6.1）
# ----------------------------------------------------------------------
func _new_director(enemy_specs: Array) -> CombatDirector:
    var d := CombatDirector.new()
    var pstats := {"hp": 100.0, "atk": 20.0, "def": 4.0, "spd": 3.0, "aps": 1.2, "crit_rate": 5.0, "crit_dmg": 150.0}
    d.setup(SEED, FLOOR, pstats, enemy_specs)
    return d


func test_combat_director_deterministic():
    var specs := [
        {"hp": 30.0, "atk": 6.0, "def": 1.0, "spd": 2.0, "aps": 1.0, "pos": Vector2(2.0, 0.0)},
        {"hp": 30.0, "atk": 6.0, "def": 1.0, "spd": 2.0, "aps": 1.0, "pos": Vector2(0.0, 2.0)}
    ]
    var a := _new_director(specs)
    var b := _new_director(specs)
    for i in range(200):
        a.step_simulation(0.1)
        b.step_simulation(0.1)
        # 偶发触发技能（on_action 在 tick 内由队列调用；此处直接驱动）
        if i % 7 == 0:
            a.on_action("lingji")
            b.on_action("lingji")
        if i % 13 == 0:
            a.on_action("fuling")
            b.on_action("fuling")
    assert_eq(a.player.hp, b.player.hp, "主角 HP 应一致")
    assert_eq(a.enemy_count(), b.enemy_count(), "敌人存活数应一致")
    assert_eq(a.coin_temp, b.coin_temp, "临时货币应一致")


func test_combat_director_idle_with_no_enemies():
    # GDD §6.1：无敌人 → 主角 idle 且不报错、不死亡
    var d := _new_director([])
    for i in range(50):
        d.step_simulation(0.1)
    assert_false(d.is_player_dead(), "无敌人时主角应存活(idle)")

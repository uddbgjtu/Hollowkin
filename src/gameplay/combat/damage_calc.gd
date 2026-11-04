# damage_calc.gd — 战斗伤害公式（GDD §3.5，生产版）
# =====================================================================
# 统一公式：
#   Raw        = ATK × SkillCoeff
#   Mitigated  = Raw × 100 / (100 + DEF × K)        # K = 8
#   CritMult   = (crit_dmg/100) 当 rng.randf() < crit_rate/100 否则 1.0
#   Variance  ∈ [0.90, 1.10]  uniform（rng.randf_range）
#   RuneMult   = 乘区乘积（来自 StatBlock，默认 1.0）
#   Final      = Mitigated × CritMult × RuneMult × Variance
#   Final      = clamp(Final, 1, 99999)
#   ΔHP        = floor(Final)
# ADR-5：所有随机走传入的 rng 实例（本层 floor RNG），禁止全局随机。
# 设计为 RefCounted + 静态方法，可无场景树单测。
# =====================================================================

class_name DamageCalc
extends RefCounted

const K := 8.0                 # 减伤曲率常数（GDD §3.5）
const VARIANCE_MIN := 0.90
const VARIANCE_MAX := 1.10
const MIN_FINAL := 1.0
const MAX_FINAL := 99999.0


# 主入口：以离散最终属性计算单击伤害（int）。
static func compute(final_atk: float, def: float, coeff: float, crit_rate: float, crit_dmg: float, rune_mult: float, rng: RandomNumberGenerator) -> int:
    var raw := final_atk * coeff
    var mitigated := raw * 100.0 / (100.0 + def * K)
    var crit_mult := 1.0
    if rng.randf() < crit_rate / 100.0:
        crit_mult = crit_dmg / 100.0
    var variance := rng.randf_range(VARIANCE_MIN, VARIANCE_MAX)
    var final_dmg := mitigated * crit_mult * rune_mult * variance
    final_dmg = clamp(final_dmg, MIN_FINAL, MAX_FINAL)
    return int(floor(final_dmg))


# 便捷入口：从最终属性字典取 atk/crit_rate/crit_dmg/def 计算单击伤害。
# stats 需含攻击方 atk/crit_rate/crit_dmg 与目标 def（缺失取默认）。
static func compute_from_stats(stats: Dictionary, coeff: float, rune_mult: float, rng: RandomNumberGenerator) -> int:
    var atk := float(stats.get("atk", 0.0))
    var def := float(stats.get("def", 0.0))
    var crit_rate := float(stats.get("crit_rate", 0.0))
    var crit_dmg := float(stats.get("crit_dmg", 100.0))
    return compute(atk, def, coeff, crit_rate, crit_dmg, rune_mult, rng)

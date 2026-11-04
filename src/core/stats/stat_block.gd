# stat_block.gd — StatBlock 单一真源（C1 契约，Epic C 最小前置版）
# =====================================================================
# MINIMAL C-prerequisite version of StatBlock (Epic D1 overlap);
# full Pouch/SpiritVein integration lands in Epic D.
#
# 契约（architecture-doc.md §1.9 / C1 / CLAUDE.md §7）：
#   FinalStat = (Base + ΣVeinAdd) × ΠRuneMult
#   - build_run_base(base, vein_adds): 缓存 run_base[stat] = base[stat] + Σvein_adds[stat]
#       （负 ATK/DEF 钳为 0，GDD §6.3）
#   - recompute_rune_mult(runes): 缓存 rune_mult[stat] = Π factor
#       每个 rune 为 {"mult": {stat: factor}}（C1 要求乘算字段）
#   - final_stat(stat): run_base[stat] × rune_mult.get(stat, 1.0)  —— O(1)
# ADR-5：无随机。纯数据，确定可测。
# 设计为 Resource（C1 真源，可被场景/序列化持有）。
# =====================================================================

class_name StatBlock
extends Resource

const STAT_KEYS := ["hp", "atk", "def", "spd", "aps", "crit_rate", "crit_dmg"]

var run_base: Dictionary = {}
var rune_mult: Dictionary = {}


func build_run_base(base: Dictionary, vein_adds: Dictionary) -> void:
    run_base.clear()
    for key in STAT_KEYS:
        var b := float(base.get(key, 0.0))
        var add := float(vein_adds.get(key, 0.0))
        var v := b + add
        # 灵脉/符文合成时负 ATK/DEF 钳为 0（GDD §6.3 / C1）
        if (key == "atk" or key == "def") and v < 0.0:
            v = 0.0
        run_base[key] = v


func recompute_rune_mult(runes: Array) -> void:
    rune_mult.clear()
    for key in STAT_KEYS:
        rune_mult[key] = 1.0
    for r in runes:
        var mults: Dictionary = r.get("mult", {})
        for stat in mults.keys():
            rune_mult[stat] = float(rune_mult.get(stat, 1.0)) * float(mults[stat])


func final_stat(stat: String) -> float:
    var base := float(run_base.get(stat, 0.0))
    var mult := float(rune_mult.get(stat, 1.0))
    return base * mult

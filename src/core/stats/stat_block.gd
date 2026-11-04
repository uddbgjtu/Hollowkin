# stat_block.gd — StatBlock 单一真源（full D1 version）
# =====================================================================
# full D1 version of StatBlock (Epic D)；扩展自 Epic C 最小前置版。
# 承载 C1 契约 + 灵囊/灵脉注入链（architecture-doc.md §1.9 / §3.3）。
#
# 契约（C1）：
#   FinalStat = (Base + ΣVeinAdd) × ΠRuneMult
#   - build_run_base(base, vein_adds): 缓存 run_base[stat] = base[stat] + Σvein_adds[stat]
#       （负 ATK/DEF 钳为 0，GDD §6.3）
#   - recompute_rune_mult(runes): 缓存 rune_mult[stat] = Π factor
#       每个 rune 为 {"mult": {stat: factor}}（C1 要求乘算字段）
#   - final_stat(stat): run_base[stat] × rune_mult.get(stat, 1.0)  —— O(1)
# D1 新增（增量 API，供灵脉/灵囊动态修正，无需每次重传全量 dict）：
#   - set_base_stat(stat, value) / get_base(stat): 读写原始 base 缓存
#   - add_vein_add(stat, amount): 累积灵脉加算到 vein_adds 缓存并惰性重算 run_base
#   - reset(): 清空全部缓存（base_stats/vein_adds/run_base/rune_mult）
# ADR-5：无随机。纯数据，确定可测。
# 设计为 Resource（C1 真源，可被场景/序列化持有）。
# =====================================================================

class_name StatBlock
extends Resource

const STAT_KEYS := ["hp", "atk", "def", "spd", "aps", "crit_rate", "crit_dmg"]

# 原始 base（可增量 set）与灵脉加算累积缓存
var base_stats: Dictionary = {}
var vein_adds: Dictionary = {}
# 缓存层：run_base = base + vein_adds；rune_mult = Π factor
var run_base: Dictionary = {}
var rune_mult: Dictionary = {}


func _init() -> void:
	base_stats = {}
	vein_adds = {}
	run_base = {}
	rune_mult = {}


# 重算 run_base 缓存（唯一派生点）：run_base[stat] = base[stat] + Σvein_adds[stat]
# 灵脉/符文合成时负 ATK/DEF 钳为 0（GDD §6.3 / C1）
func _recompute_run_base() -> void:
	run_base.clear()
	for key in STAT_KEYS:
		var b := float(base_stats.get(key, 0.0))
		var add := float(vein_adds.get(key, 0.0))
		var v := b + add
		if (key == "atk" or key == "def") and v < 0.0:
			v = 0.0
		run_base[key] = v


func build_run_base(base: Dictionary, vein_adds: Dictionary) -> void:
	# C1 契约：从外部传入的 base 与 vein_adds 同步内部缓存并重算 run_base。
	base_stats = base.duplicate()
	self.vein_adds = vein_adds.duplicate()
	_recompute_run_base()


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


# --- D1 增量 API ------------------------------------------------------
func set_base_stat(stat: String, value: float) -> void:
	base_stats[stat] = float(value)
	_recompute_run_base()


func get_base(stat: String) -> float:
	return float(base_stats.get(stat, 0.0))


func add_vein_add(stat: String, amount: float) -> void:
	vein_adds[stat] = float(vein_adds.get(stat, 0.0)) + float(amount)
	_recompute_run_base()


func reset() -> void:
	base_stats.clear()
	vein_adds.clear()
	run_base.clear()
	rune_mult.clear()

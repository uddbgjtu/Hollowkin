# run_snapshot.gd — run 起始属性快照
# =====================================================================
# 职责（spirit-vein-gdd.md §3 / architecture-doc.md §3.3 C1 注入链）：
#   - build_base: 返回 {stat: base_stats[stat] + ΣVeinAdd[stat]}
#   - apply_to: 把灵脉修正后的基底喂给 StatBlock.build_run_base（C1 run 起始算一次）
# ADR-5：纯数据，无随机。
# =====================================================================

class_name RunSnapshot
extends RefCounted


func build_base(base_stats: Dictionary, vein_graph: VeinGraph) -> Dictionary:
	var vein_adds: Dictionary = vein_graph.get_activated_modify_stats(base_stats)
	var out: Dictionary = {}
	for key in base_stats.keys():
		out[key] = float(base_stats[key]) + float(vein_adds.get(key, 0.0))
	return out


func apply_to(sb: StatBlock, base_stats: Dictionary, vein_graph: VeinGraph) -> void:
	var vein_adds: Dictionary = vein_graph.get_activated_modify_stats(base_stats)
	sb.build_run_base(base_stats, vein_adds)

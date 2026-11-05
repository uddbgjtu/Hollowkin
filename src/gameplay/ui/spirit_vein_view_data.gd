# spirit_vein_view_data.gd — 灵脉图谱屏视图 DTO（Epic F4，绑定真实 VeinGraph / Epic D3）
# =====================================================================
# 直接消费 Epic D 的 VeinGraph，状态用形状编码（lock/star/highlight）而非仅亮度
# （ux-spec §3.3 / accessibility-requirements.md §3.1）。
#   - 已激活 → "active"（星）
#   - 可激活（前置全激活且 ember≥cost）→ "available"（高亮）
#   - 其余 → "locked"（锁）
# 纯数据，确定性，无随机（ADR-5）。
# =====================================================================

class_name SpiritVeinViewData
extends RefCounted

var nodes: Array = []   # [{id, x, y, tier, type, cost, state:"locked"|"available"|"active"}]
var edges: Array = []   # [{from, to}]
var ember: int = 0


# state 分类（ux-spec §3.3）：已激活=星、可激活=高亮、其余=锁。
static func classify(graph: VeinGraph, id: String, ember: int) -> String:
	if graph.is_activated(id):
		return "active"
	if graph.can_activate(id, ember):
		return "available"
	return "locked"


func build_from_graph(graph: VeinGraph, ember_amount: int) -> void:
	nodes.clear()
	edges.clear()
	ember = ember_amount
	var ids: Array = graph.nodes.keys()
	ids.sort()
	for id in ids:
		var n = graph.nodes[id]
		nodes.append({
			"id": id,
			"x": n.pos.x,
			"y": n.pos.y,
			"tier": n.tier,
			"type": n.type,
			"cost": n.cost,
			"state": classify(graph, id, ember_amount),
		})
		for p in n.prereq:
			edges.append({"from": p, "to": id})

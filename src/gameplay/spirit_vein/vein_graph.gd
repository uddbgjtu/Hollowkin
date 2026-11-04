# vein_graph.gd — 灵脉图谱（DAG）
# =====================================================================
# 职责（spirit-vein-gdd.md §3/§6.3）：
#   - register_node / is_activated / get_activated_node_ids
#   - assert_acyclic: DFS 检测前置依赖有向环（有环返回 false + push_error）
#   - can_activate / activate: 前置全激活且 ember>=cost；activate 返回剩余 ember（-1 失败）
#   - get_activated_modify_stats: 聚合 ΣVeinAdd（add 直接加；pct = base*frac，base 缺省按 0）
#   - to_dict / from_dict: 持久化节点定义 + 已激活集合
# ADR-5：纯数据，无随机。
# =====================================================================

class_name VeinGraph
extends RefCounted

var nodes: Dictionary = {}          # node_id -> VeinNode
var activated: Dictionary = {}      # node_id -> bool


func _init() -> void:
	nodes = {}
	activated = {}


func register_node(n: VeinNode) -> void:
	nodes[n.node_id] = n


func is_activated(id: String) -> bool:
	return bool(activated.get(id, false))


func get_activated_node_ids() -> Array:
	var out: Array = []
	for id in activated.keys():
		if activated[id]:
			out.append(id)
	return out


# DFS 检测前置依赖（node -> prereq）有向环；有环返回 false 并 push_error。
func assert_acyclic() -> bool:
	var WHITE := 0
	var GRAY := 1
	var BLACK := 2
	var color: Dictionary = {}
	for id in nodes.keys():
		color[id] = WHITE
	var has_cycle := false
	var stack: Array = []
	for start in nodes.keys():
		if color[start] != WHITE:
			continue
		stack.push_back({"id": start, "i": 0})
		color[start] = GRAY
		while not stack.is_empty():
			var top: Dictionary = stack.back()
			var id: String = top["id"]
			var n: VeinNode = nodes[id]
			var prereqs: Array = n.prereq
			if top["i"] < prereqs.size():
				var p = prereqs[top["i"]]
				top["i"] += 1
				if not nodes.has(p):
					continue
				var c: int = color[p]
				if c == GRAY:
					has_cycle = true
					break
				elif c == WHITE:
					color[p] = GRAY
					stack.push_back({"id": p, "i": 0})
			else:
				color[id] = BLACK
				stack.pop_back()
		if has_cycle:
			break
	if has_cycle:
		push_error("VeinGraph: detected cycle in prerequisite DAG (nodes=%d)" % nodes.size())
		return false
	return true


func can_activate(id: String, ember: int) -> bool:
	if not nodes.has(id):
		return false
	if is_activated(id):
		return false
	var n: VeinNode = nodes[id]
	if ember < n.cost:
		return false
	for p in n.prereq:
		if not is_activated(p):
			return false
	return true


# 成功返回剩余 ember（已扣 cost）；失败返回 -1。
func activate(id: String, ember: int) -> int:
	if not can_activate(id, ember):
		return -1
	activated[id] = true
	var n: VeinNode = nodes[id]
	return ember - n.cost


# 聚合 ΣVeinAdd：遍历已激活 MODIFY_STAT 节点。
# add 直接加；pct 加 base*frac（base 缺省按 0，保证确定性）。
func get_activated_modify_stats(base_stats: Dictionary = {}) -> Dictionary:
	var out: Dictionary = {}
	for id in get_activated_node_ids():
		var n: VeinNode = nodes[id]
		if n.type != "MODIFY_STAT":
			continue
		var stat: String = n.effect.get("stat", "")
		var add: float = float(n.effect.get("add", 0.0))
		var pct: float = float(n.effect.get("pct", 0.0))
		var base: float = float(base_stats.get(stat, 0.0))
		var delta: float = add + base * pct
		out[stat] = float(out.get(stat, 0.0)) + delta
	return out


func to_dict() -> Dictionary:
	var nodes_out: Array = []
	for id in nodes.keys():
		nodes_out.append(nodes[id].to_dict())
	var activated_out: Array = get_activated_node_ids()
	return {"nodes": nodes_out, "activated": activated_out}


func from_dict(d: Dictionary) -> void:
	nodes.clear()
	activated.clear()
	var nodes_in: Array = d.get("nodes", [])
	for nd in nodes_in:
		var n := VeinNode.new()
		n.from_dict(nd)
		nodes[n.node_id] = n
	var activated_in: Array = d.get("activated", [])
	for id in activated_in:
		activated[id] = true

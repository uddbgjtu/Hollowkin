# vein_node.gd — 灵脉节点
# =====================================================================
# 数据模型（spirit-vein-gdd.md §3）：
#   - type: MODIFY_STAT | UNLOCK_SKILL | GRANT_START
#   - MODIFY_STAT effect: {"stat":"atk","add":5.0}（加算）或
#                         {"stat":"atk","pct":0.05}（基础百分比，base*frac）
#   - prereq: 前置节点 id 列表（DAG 无环，构建期校验）
# ADR-5：纯数据，无随机。
# =====================================================================

class_name VeinNode
extends RefCounted

var node_id: String = ""
var pos: Vector2 = Vector2.ZERO
var tier: int = 0
var type: String = "MODIFY_STAT"    # MODIFY_STAT | UNLOCK_SKILL | GRANT_START
var effect: Dictionary = {}         # MODIFY_STAT: {"stat":..,"add":..} 或 {"stat":..,"pct":..}
var cost: int = 0
var prereq: Array = []              # 前置 node_id 列表


func _init() -> void:
	effect = {}
	prereq = []


func to_dict() -> Dictionary:
	return {
		"node_id": node_id,
		"pos": [pos.x, pos.y],
		"tier": tier,
		"type": type,
		"effect": effect,
		"cost": cost,
		"prereq": prereq,
	}


func from_dict(d: Dictionary) -> void:
	node_id = d.get("node_id", "")
	var p: Array = d.get("pos", [0.0, 0.0])
	pos = Vector2(float(p[0]), float(p[1]))
	tier = int(d.get("tier", 0))
	type = d.get("type", "MODIFY_STAT")
	effect = d.get("effect", {})
	cost = int(d.get("cost", 0))
	prereq = d.get("prereq", [])

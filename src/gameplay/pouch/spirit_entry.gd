# spirit_entry.gd — 灵兽条目（灵囊·灵兽栏）
# =====================================================================
# 数据模型（spirit-pouch-gdd.md §3 / ENG-2）：
#   - species_id: 唯一 slug（bestiary v1.3 §0.1）
#   - state: "egg" | "tamed"
#   - count: ENG-2 裁定 +1 堆叠（同 species 一条记录，不新增条目）
#   - equipped_runes: 已镶嵌符文 id 列表（运行时叠加；序列化边界见 pouch.gd）
# ADR-5：纯数据，无随机。RefCounted 便于无场景树单测。
# =====================================================================

class_name SpiritEntry
extends RefCounted

var species_id: String = ""
var name: String = ""
var state: String = "egg"          # "egg" | "tamed"
var level: int = 1
var equipped_runes: Array = []      # rune_id 列表
var count: int = 1                  # ENG-2 堆叠计数


func _init() -> void:
	equipped_runes = []


func to_dict() -> Dictionary:
	return {
		"species_id": species_id,
		"name": name,
		"state": state,
		"level": level,
		"equipped_runes": equipped_runes,
		"count": count,
	}


func from_dict(d: Dictionary) -> void:
	species_id = d.get("species_id", "")
	name = d.get("name", "")
	state = d.get("state", "egg")
	level = int(d.get("level", 1))
	equipped_runes = d.get("equipped_runes", [])
	count = int(d.get("count", 1))

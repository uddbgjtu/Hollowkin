# rune_entry.gd — 符文条目（灵囊·符文栏）
# =====================================================================
# 数据模型（spirit-pouch-gdd.md §3 / C1 契约）：
#   - mult: {stat: factor} 乘算（非 mods 加算）；如 atk +20% -> {"atk":1.2}
#   - slot: "spirit" | "tamer" 可装备位置
# ADR-5：纯数据，无随机。
# =====================================================================

class_name RuneEntry
extends RefCounted

var rune_id: String = ""
var name: String = ""
var slot: String = "spirit"         # "spirit" | "tamer"
var mult: Dictionary = {}           # {"atk":1.2}
var rarity: String = ""


func _init() -> void:
	mult = {}


func to_dict() -> Dictionary:
	return {
		"rune_id": rune_id,
		"name": name,
		"slot": slot,
		"mult": mult,
		"rarity": rarity,
	}


func from_dict(d: Dictionary) -> void:
	rune_id = d.get("rune_id", "")
	name = d.get("name", "")
	slot = d.get("slot", "spirit")
	mult = d.get("mult", {})
	rarity = d.get("rarity", "")


func mult_dict() -> Dictionary:
	return mult

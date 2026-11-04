# bestiary.gd — 图鉴（灵兽发现记录）
# =====================================================================
# 数据模型（mvp-spirit-bestiary.md v1.3 §0.1）：
#   KNOWN_SLUGS = [mossback, emberhorn, frostling, voltsprite, tamer]
#   unlock: 首次发现返回 true（触发图鉴解锁），重复返回 false。
# ADR-5：纯数据，无随机。
# =====================================================================

class_name Bestiary
extends RefCounted

const KNOWN_SLUGS := ["mossback", "emberhorn", "frostling", "voltsprite", "tamer"]
var discovered: Dictionary = {}     # slug -> bool


func _init() -> void:
	discovered = {}


func unlock(slug: String) -> bool:
	if discovered.get(slug, false):
		return false                # 已发现，不重复触发
	discovered[slug] = true
	return true


func is_discovered(slug: String) -> bool:
	return bool(discovered.get(slug, false))


func to_dict() -> Dictionary:
	var out: Dictionary = {}
	for slug in discovered.keys():
		if discovered[slug]:
			out[slug] = true
	return out


func from_dict(d: Dictionary) -> void:
	discovered.clear()
	for slug in d.keys():
		discovered[slug] = bool(d[slug])

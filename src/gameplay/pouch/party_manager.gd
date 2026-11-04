# party_manager.gd — 队伍编制（灵囊）
# =====================================================================
# 数据模型（spirit-pouch-gdd.md §3）：party_slots = 3（单局携带上限 1–3 只）
# 招募满员返回 false（不自动替换，GDD §6.5 边界）。
# ADR-5：纯数据，无随机。
# =====================================================================

class_name PartyManager
extends RefCounted

const PARTY_SLOTS := 3
var party: Array = []               # slug 列表


func _init() -> void:
	party = []


func recruit(slug: String) -> bool:
	if party.size() >= PARTY_SLOTS:
		return false                # 满员拒绝，不静默替换
	party.append(slug)
	return true


func remove(slug: String) -> void:
	party.erase(slug)


func get_party() -> Array:
	return party


func is_full() -> bool:
	return party.size() >= PARTY_SLOTS


func can_recruit() -> bool:
	return party.size() < PARTY_SLOTS

# pouch_view_data.gd — 灵囊屏视图 DTO（Epic F3，绑定真实 Pouch / Epic D2）
# =====================================================================
# 直接消费 Epic D 的 Pouch 与 Bestiary，避免把域逻辑拉入 F。
#   - 灵兽 count>1 → +1 堆叠角标（ENG-2 裁定：重复灵兽 = +1 计数，角标显示 ×N）
#   - 符文 mult 为乘算字段（C1 契约：{stat: factor}）
#   - 物资为 {name, count} 条目
# 纯数据，确定性，无随机（ADR-5）。
# =====================================================================

class_name PouchViewData
extends RefCounted

const COLUMN_IDS := ["spirits", "runes", "materials"]
const COLUMN_LABELS := ["灵兽", "符文", "物资"]

var spirits: Array = []    # [{slug, name, count, discovered}]
var runes: Array = []      # [{rune_id, name, slot, mult, rarity}]
var materials: Array = []  # [{name, count}]
var column_labels: Dictionary = {}


func _init() -> void:
	for i in range(COLUMN_IDS.size()):
		column_labels[COLUMN_IDS[i]] = COLUMN_LABELS[i]


# 从真实 Pouch + Bestiary 构建视图模型（确定性，无随机）。
func build_from_pouch(pouch: Pouch, bestiary: Bestiary) -> void:
	spirits.clear()
	runes.clear()
	materials.clear()
	var slugs: Array = pouch.spirits.keys()
	slugs.sort()
	for slug in slugs:
		var e = pouch.spirits[slug]
		spirits.append({
			"slug": slug,
			"name": e.name,
			"count": e.count,
			"discovered": bestiary.is_discovered(slug),
		})
	for r in pouch.runes:
		runes.append({
			"rune_id": r.rune_id,
			"name": r.name,
			"slot": r.slot,
			"mult": r.mult,
			"rarity": r.rarity,
		})
	for m in pouch.materials:
		materials.append({"name": m.get("name", ""), "count": int(m.get("count", 1))})


# 是否存在 +1 堆叠角标（ENG-2）：任一灵兽 count>1。
func has_stack_badge() -> bool:
	for s in spirits:
		if int(s["count"]) > 1:
			return true
	return false


func column_label(col: String) -> String:
	return column_labels.get(col, "")

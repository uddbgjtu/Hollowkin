# pouch.gd — 灵囊（三栏：灵兽/符文/物资）
# =====================================================================
# 数据模型（spirit-pouch-gdd.md §3 / ENG-2 / C1）：
#   - spirits: {slug -> SpiritEntry}，ENG-2 +1 堆叠；序列化 {slug: count}
#   - runes: RuneEntry 数组（容量 CAP_RUNE，满则拒绝不静默丢弃）
#   - materials: Dictionary 数组（容量 CAP_MATERIAL）
#   - coin_temp: 地窟内临时货币（死亡清空）
#   - tamer_runes: 主角(tamer)槽已装备符文 id（主角无 SpiritEntry，单独存）
#   - recompute_stat_block: 收集已装备符文乘区喂给 StatBlock（C1 ΠRuneMult）
# ADR-5：纯数据，无随机。
#
# 序列化边界（ENG-2 / 灵囊 GDD §6.4）：spirits 仅以 {slug: count} 持久化，不展开逐蛋；
# 单灵兽的 equipped_runes 是运行时叠加层，进局时由符文栏重建（本 MVP 不持久化）。
# =====================================================================

class_name Pouch
extends RefCounted

const CAP_SPIRIT := 12
const CAP_RUNE := 24
const CAP_MATERIAL := 24

var spirits: Dictionary = {}        # slug -> SpiritEntry
var runes: Array = []               # RuneEntry
var materials: Array = []           # Dictionary 物资条目
var coin_temp: int = 0
var tamer_runes: Array = []         # 主角(tamer)槽已装备 rune_id


func _init() -> void:
	spirits = {}
	runes = []
	materials = []
	tamer_runes = []


# --- 灵兽蛋（ENG-2 +1 堆叠） -----------------------------------------
func add_spirit_egg(slug: String, name: String = "") -> void:
	if spirits.has(slug):
		spirits[slug].count += 1
	else:
		var e := SpiritEntry.new()
		e.species_id = slug
		e.name = name
		e.state = "egg"
		e.level = 1
		e.count = 1
		spirits[slug] = e


func get_spirit_count(slug: String) -> int:
	if spirits.has(slug):
		return spirits[slug].count
	return 0


# --- 符文 / 物资（容量满则拒绝，不静默丢弃） -------------------------
func add_rune(r: RuneEntry) -> bool:
	if runes.size() >= CAP_RUNE:
		return false
	runes.append(r)
	return true


func add_material(item: Dictionary) -> bool:
	if materials.size() >= CAP_MATERIAL:
		return false
	materials.append(item)
	return true


# --- 符文镶嵌 ---------------------------------------------------------
# 把 rune_id 标记为某灵兽(slug)或主角("tamer")装备；返回是否成功。
func equip_rune(spirit_slug: String, rune_id: String) -> bool:
	var rune: RuneEntry = null
	for rr in runes:
		if rr.rune_id == rune_id:
			rune = rr
			break
	if rune == null:
		return false
	if spirit_slug == "tamer":
		if not tamer_runes.has(rune_id):
			tamer_runes.append(rune_id)
		return true
	if not spirits.has(spirit_slug):
		return false
	if not spirits[spirit_slug].equipped_runes.has(rune_id):
		spirits[spirit_slug].equipped_runes.append(rune_id)
	return true


# 收集所有已装备 rune 的 mult dict，供 StatBlock.recompute_rune_mult 使用。
# 返回元素形如 {"mult": {stat: factor}}（与 C1 recompute_rune_mult 契约对齐）。
func get_equipped_rune_mults() -> Array:
	var out: Array = []
	var ids: Array = []
	ids.append_array(tamer_runes)
	for slug in spirits.keys():
		ids.append_array(spirits[slug].equipped_runes)
	for rid in ids:
		for rr in runes:
			if rr.rune_id == rid:
				out.append({"mult": rr.mult})
				break
	return out


func recompute_stat_block(sb: StatBlock) -> void:
	sb.recompute_rune_mult(get_equipped_rune_mults())


# --- 序列化（确定性） ------------------------------------------------
func to_dict() -> Dictionary:
	var spirits_out: Dictionary = {}
	var slugs: Array = spirits.keys()
	slugs.sort()                    # 按 slug 排序保证确定性
	for slug in slugs:
		spirits_out[slug] = spirits[slug].count
	var runes_out: Array = []
	for r in runes:
		runes_out.append(r.to_dict())
	var mats_out: Array = []
	for m in materials:
		mats_out.append(m)
	return {
		"spirits": spirits_out,
		"runes": runes_out,
		"materials": mats_out,
		"coin_temp": coin_temp,
		"tamer_runes": tamer_runes,
	}


func from_dict(d: Dictionary) -> void:
	spirits.clear()
	runes.clear()
	materials.clear()
	coin_temp = 0
	tamer_runes.clear()
	var spirits_in: Dictionary = d.get("spirits", {})
	for slug in spirits_in.keys():
		var e := SpiritEntry.new()
		e.species_id = slug
		e.name = ""
		e.state = "egg"
		e.level = 1
		e.count = int(spirits_in[slug])
		spirits[slug] = e
	var runes_in: Array = d.get("runes", [])
	for rd in runes_in:
		var r := RuneEntry.new()
		r.from_dict(rd)
		runes.append(r)
	var mats_in: Array = d.get("materials", [])
	for m in mats_in:
		materials.append(m)
	coin_temp = int(d.get("coin_temp", 0))
	tamer_runes = d.get("tamer_runes", [])

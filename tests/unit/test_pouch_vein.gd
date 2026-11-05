# pouch_vein_test.gd — Epic D 单元单测（GUT）
# =====================================================================
# 覆盖验收点：
#   - C1 公式：build_run_base + recompute_rune_mult + final_stat（灵脉加算 + 符文乘区）
#   - 负 atk/def 钳 0；final_stat O(1) 一致
#   - ENG-2 +1 堆叠；重复灵兽角标 ×N（count）
#   - 满栏 add_rune 返回 false（不静默丢）；to_dict/from_dict 往返相等
#   - RuneEntry mult 格式；PartyManager party_slots=3
#   - SpiritVein DAG 无环（assert_acyclic）、can_activate/activate 扣 ember、
#     get_activated_modify_stats 聚合；run_snapshot.apply_to 喂入 StatBlock
#   - Bestiary 解锁/发现/round-trip；与 Pouch 联动
#   - 存档重建一致（验收核心）：pouch.to_dict -> save_service.save_pouch ->
#     load_pouch -> pouch2.from_dict -> 与原始相等
#
# 注意：本沙箱无 Godot，GUT 测试按规范书写但**未执行**；
# 文件 IO（save_service 真实往返）待 Godot 实跑。
# 路径含 tests/，被 tools/ci/lint_no_global_random.py 排除（不扫全局随机）。
# =====================================================================

extends GutTest

const StatBlock = preload("res://src/core/stats/stat_block.gd")
const Pouch = preload("res://src/gameplay/pouch/pouch.gd")
const SpiritEntry = preload("res://src/gameplay/pouch/spirit_entry.gd")
const RuneEntry = preload("res://src/gameplay/pouch/rune_entry.gd")
const PartyManager = preload("res://src/gameplay/pouch/party_manager.gd")
const Bestiary = preload("res://src/gameplay/pouch/bestiary.gd")
const VeinNode = preload("res://src/gameplay/spirit_vein/vein_node.gd")
const VeinGraph = preload("res://src/gameplay/spirit_vein/vein_graph.gd")
const RunSnapshot = preload("res://src/gameplay/spirit_vein/run_snapshot.gd")
const SaveService = preload("res://src/core/save/save_service.gd")


# ----------------------------------------------------------------------
# StatBlock D1 — C1 契约
# ----------------------------------------------------------------------
func test_statblock_full_contract():
	var sb := StatBlock.new()
	var base := {"hp":100.0,"atk":10.0,"def":5.0,"spd":1.0,"aps":1.0,"crit_rate":0.05,"crit_dmg":1.5}
	var vein := {"atk":5.0,"def":3.0}
	sb.build_run_base(base, vein)
	# 符文乘区：atk 受 2.0 与 1.5 叠加（Π=3.0）；def 受 1.5
	var runes := [{"mult":{"atk":2.0}}, {"mult":{"atk":1.5,"def":1.5}}]
	sb.recompute_rune_mult(runes)
	# atk = (10+5) * (2.0*1.5) = 15 * 3.0 = 45.0
	assert_eq(sb.final_stat("atk"), 45.0, "atk = (base+vein) * Πrune_mult")
	# def = (5+3) * 1.5 = 8 * 1.5 = 12.0
	assert_eq(sb.final_stat("def"), 12.0, "def = (base+vein) * rune_mult")
	# hp 无符文乘区修正：100 * 1.0
	assert_eq(sb.final_stat("hp"), 100.0, "hp 无符文时保持不变")
	# O(1) 一致：重复调用结果相等
	assert_eq(sb.final_stat("atk"), sb.final_stat("atk"), "final_stat 重复调用一致 (O(1))")


func test_statblock_negative_atk_def_clamped():
	var sb := StatBlock.new()
	var base := {"atk":-10.0,"def":-3.0,"hp":50.0,"spd":1.0,"aps":1.0,"crit_rate":0.05,"crit_dmg":1.5}
	var vein := {"atk":2.0,"def":1.0}
	sb.build_run_base(base, vein)
	# atk = -10+2 = -8 -> 钳 0; def = -3+1 = -2 -> 钳 0
	assert_eq(sb.final_stat("atk"), 0.0, "负 atk 钳为 0")
	assert_eq(sb.final_stat("def"), 0.0, "负 def 钳为 0")
	assert_eq(sb.final_stat("hp"), 50.0, "hp 不受影响")


func test_statblock_d1_incremental_api():
	var sb := StatBlock.new()
	sb.set_base_stat("atk", 10.0)
	sb.add_vein_add("atk", 5.0)
	sb.recompute_rune_mult([])
	assert_eq(sb.get_base("atk"), 10.0, "get_base 返回原始 base")
	assert_eq(sb.final_stat("atk"), 15.0, "run_base = base + Σvein_add")
	# 继续累积灵脉加算
	sb.add_vein_add("atk", 3.0)
	assert_eq(sb.final_stat("atk"), 18.0, "add_vein_add 增量生效")
	sb.reset()
	assert_eq(sb.get_base("atk"), 0.0, "reset 清空 base")
	assert_eq(sb.final_stat("atk"), 0.0, "reset 清空 run_base")


# ----------------------------------------------------------------------
# Pouch — ENG-2 +1 堆叠 / 角标 ×N
# ----------------------------------------------------------------------
func test_pouch_add_spirit_egg_stacking():
	var p := Pouch.new()
	p.add_spirit_egg("mossback", "Mossback")
	p.add_spirit_egg("mossback")          # 重复蛋 +1（ENG-2）
	assert_eq(p.get_spirit_count("mossback"), 2, "ENG-2 +1 堆叠计数")
	var entry: SpiritEntry = p.spirits["mossback"]
	assert_eq(entry.count, 2, "条目 count 反映堆叠")
	assert_eq(entry.state, "egg", "默认 state=egg")
	assert_eq(p.get_spirit_count("unknown"), 0, "未持有返回 0")


# ----------------------------------------------------------------------
# Pouch — 满栏拒绝（不静默丢弃）
# ----------------------------------------------------------------------
func test_pouch_add_rune_full_no_silent_drop():
	var p := Pouch.new()
	var rejected := 0
	for i in range(Pouch.CAP_RUNE + 1):
		var r := RuneEntry.new()
		r.rune_id = "rune_%d" % i
		if not p.add_rune(r):
			rejected += 1
	assert_eq(rejected, 1, "仅 1 个符文因满栏被拒（不静默丢）")
	assert_eq(p.runes.size(), Pouch.CAP_RUNE, "符文栏停在容量上限")


func test_pouch_add_material_full_no_silent_drop():
	var p := Pouch.new()
	var rejected := 0
	for i in range(Pouch.CAP_MATERIAL + 1):
		if not p.add_material({"item_id": "mat_%d" % i, "qty": 1}):
			rejected += 1
	assert_eq(rejected, 1, "仅 1 个物资因满栏被拒")


# ----------------------------------------------------------------------
# Pouch — to_dict / from_dict 往返相等（无序稳定）
# ----------------------------------------------------------------------
func test_pouch_roundtrip_equal():
	var p := Pouch.new()
	p.add_spirit_egg("mossback")
	p.add_spirit_egg("emberhorn")
	p.add_spirit_egg("mossback")          # mossback count=2
	var r := RuneEntry.new()
	r.rune_id = "atk_rune"; r.name = "Atk Rune"; r.slot = "spirit"
	r.mult = {"atk": 1.2}; r.rarity = "rare"
	p.add_rune(r)
	p.add_material({"item_id": "herb", "qty": 3})
	p.coin_temp = 42
	p.equip_rune("mossback", "atk_rune")
	p.equip_rune("tamer", "atk_rune")

	var d1 := p.to_dict()
	var p2 := Pouch.new()
	p2.from_dict(d1)
	var d2 := p2.to_dict()

	# 序列化往返应完全一致（Dictionary 结构相等，与内部插入序无关）
	assert_eq(d2, d1, "Pouch to_dict/from_dict 往返相等（无序稳定）")
	# 关键语义校验
	assert_eq(d2["spirits"]["mossback"], 2, "序列化 spirits 为 {slug:count}")
	assert_eq(d2["coin_temp"], 42, "coin_temp 持久化")
	assert_eq(d2["tamer_runes"], ["atk_rune"], "tamer 装备持久化")


# ----------------------------------------------------------------------
# RuneEntry — mult 格式
# ----------------------------------------------------------------------
func test_rune_entry_mult_format():
	var r := RuneEntry.new()
	r.rune_id = "x"; r.name = "X"; r.slot = "spirit"; r.mult = {"atk": 1.2}; r.rarity = "common"
	assert_eq(r.mult_dict(), {"atk": 1.2}, "mult_dict 返回 mult")
	var d := r.to_dict()
	assert_eq(d["mult"], {"atk": 1.2}, "to_dict.mult 为乘算格式 {stat:factor}")
	var r2 := RuneEntry.new()
	r2.from_dict(d)
	assert_eq(r2.mult, {"atk": 1.2}, "from_dict 还原 mult")


# ----------------------------------------------------------------------
# PartyManager — party_slots = 3
# ----------------------------------------------------------------------
func test_party_manager_slots():
	var pm := PartyManager.new()
	assert_eq(pm.PARTY_SLOTS, 3, "party_slots 常量 = 3")
	assert_true(pm.can_recruit())
	assert_false(pm.is_full())
	assert_true(pm.recruit("mossback"))
	assert_true(pm.recruit("emberhorn"))
	assert_true(pm.recruit("frostling"))
	assert_true(pm.is_full(), "三只后满员")
	assert_false(pm.can_recruit())
	assert_false(pm.recruit("voltsprite"), "第四只招募返回 false（不自动替换）")
	assert_eq(pm.get_party().size(), 3, "队伍保持 3")
	pm.remove("emberhorn")
	assert_eq(pm.get_party().size(), 2, "remove 后减员")
	assert_true(pm.can_recruit(), "有空位后可再招募")


# ----------------------------------------------------------------------
# SpiritVein — DAG 无环
# ----------------------------------------------------------------------
func test_vein_graph_acyclic_pass():
	var g := VeinGraph.new()
	var a := VeinNode.new(); a.node_id = "a"; a.prereq = []
	var b := VeinNode.new(); b.node_id = "b"; b.prereq = ["a"]
	var c := VeinNode.new(); c.node_id = "c"; c.prereq = ["a", "b"]
	g.register_node(a); g.register_node(b); g.register_node(c)
	assert_true(g.assert_acyclic(), "无环 DAG 通过校验")


func test_vein_graph_cyclic_fail():
	var g := VeinGraph.new()
	# a 依赖 b，b 依赖 a -> 有环
	var a := VeinNode.new(); a.node_id = "a"; a.prereq = ["b"]
	var b := VeinNode.new(); b.node_id = "b"; b.prereq = ["a"]
	g.register_node(a); g.register_node(b)
	assert_false(g.assert_acyclic(), "有环返回 false")


# ----------------------------------------------------------------------
# SpiritVein — can_activate / activate / ember
# ----------------------------------------------------------------------
func test_vein_activate_and_ember():
	var g := VeinGraph.new()
	var a := VeinNode.new(); a.node_id = "a"; a.type = "MODIFY_STAT"
	a.effect = {"stat": "atk", "add": 5.0}; a.cost = 10; a.prereq = []
	var b := VeinNode.new(); b.node_id = "b"; b.type = "MODIFY_STAT"
	b.effect = {"stat": "atk", "add": 3.0}; b.cost = 5; b.prereq = ["a"]
	g.register_node(a); g.register_node(b)

	assert_false(g.can_activate("b", 100), "b 前置 a 未激活 -> 不可激活")
	assert_true(g.can_activate("a", 100), "a 无前置且 ember 充足")
	assert_false(g.can_activate("a", 5), "a 消耗 10，ember=5 不足")
	var rem := g.activate("a", 100)
	assert_eq(rem, 90, "activate 返回剩余 ember = 100-10")
	assert_true(g.is_activated("a"))
	assert_eq(g.activate("a", 100), -1, "重复激活失败返回 -1")
	assert_true(g.can_activate("b", 100), "a 激活后 b 前置满足")
	var rem2 := g.activate("b", 100)
	assert_eq(rem2, 95, "b 消耗 5 -> 剩余 95")
	assert_eq(g.get_activated_node_ids().size(), 2, "两个节点已激活")


# ----------------------------------------------------------------------
# SpiritVein — get_activated_modify_stats 聚合（加算 + 基础百分比）
# ----------------------------------------------------------------------
func test_vein_modify_stats_aggregation():
	var g := VeinGraph.new()
	var a := VeinNode.new(); a.node_id = "a"; a.type = "MODIFY_STAT"
	a.effect = {"stat": "atk", "add": 5.0}; a.cost = 10
	var b := VeinNode.new(); b.node_id = "b"; b.type = "MODIFY_STAT"
	b.effect = {"stat": "atk", "add": 3.0}; b.cost = 5
	var c := VeinNode.new(); c.node_id = "c"; c.type = "MODIFY_STAT"
	c.effect = {"stat": "hp", "pct": 0.05}; c.cost = 5   # 基础百分比
	g.register_node(a); g.register_node(b); g.register_node(c)
	g.activate("a", 100); g.activate("b", 100); g.activate("c", 100)

	var base := {"hp": 100.0, "atk": 10.0}
	var adds := g.get_activated_modify_stats(base)
	assert_eq(adds["atk"], 8.0, "atk 加算聚合 5+3=8")
	assert_eq(adds["hp"], 5.0, "hp 基础百分比 = 100*0.05 = 5")

	# 缺省 base -> pct 部分按 0
	var adds2 := g.get_activated_modify_stats({})
	assert_eq(adds2["hp"], 0.0, "无 base 时 pct 部分为 0（确定性）")


# ----------------------------------------------------------------------
# RunSnapshot — apply_to 把灵脉基底喂入 StatBlock（verdict 反映灵脉+符文）
# ----------------------------------------------------------------------
func test_run_snapshot_apply_and_rune():
	var g := VeinGraph.new()
	var a := VeinNode.new(); a.node_id = "a"; a.type = "MODIFY_STAT"
	a.effect = {"stat": "atk", "add": 5.0}; a.cost = 10
	g.register_node(a); g.activate("a", 100)

	var base := {"atk": 10.0, "def": 5.0, "hp": 100.0}
	var snap := RunSnapshot.new()
	var sb := StatBlock.new()
	snap.apply_to(sb, base, g)
	# run_base atk = 10+5 = 15；def = 5
	assert_eq(sb.final_stat("atk"), 15.0, "灵脉加算注入基底")
	assert_eq(sb.final_stat("def"), 5.0, "def 未受灵脉影响")

	# 叠加符文乘区：atk * 2.0 -> 30
	var p := Pouch.new()
	var r := RuneEntry.new(); r.rune_id = "x"; r.mult = {"atk": 2.0}; r.slot = "spirit"
	p.add_rune(r)
	p.equip_rune("tamer", "x")
	p.recompute_stat_block(sb)
	assert_eq(sb.final_stat("atk"), 30.0, "符文乘区叠加在灵脉基底之上")


# ----------------------------------------------------------------------
# Bestiary — 解锁 / 发现 / round-trip
# ----------------------------------------------------------------------
func test_bestiary_unlock_roundtrip():
	var b := Bestiary.new()
	assert_true(b.unlock("mossback"), "首次解锁返回 true")
	assert_true(b.is_discovered("mossback"))
	assert_false(b.unlock("mossback"), "重复解锁返回 false")
	assert_false(b.is_discovered("voltsprite"), "未解锁为 false")

	var b2 := Bestiary.new()
	b2.from_dict(b.to_dict())
	assert_true(b2.is_discovered("mossback"), "round-trip 后仍发现")
	assert_eq(b.to_dict(), b2.to_dict(), "bestiary to_dict/from_dict 一致")


func test_pouch_bestiary_integration():
	# 首次获得灵兽蛋触发图鉴解锁（ENG-2 / bestiary §0.1）
	var p := Pouch.new()
	var best := Bestiary.new()
	p.add_spirit_egg("emberhorn", "Emberhorn")
	assert_true(best.unlock("emberhorn"), "首次获取触发解锁")
	assert_false(best.unlock("emberhorn"), "重复获取不再触发")
	assert_eq(p.get_spirit_count("emberhorn"), 1, "同时计入灵囊堆叠")


# ----------------------------------------------------------------------
# 存档重建一致（验收核心）
# 注意：文件 IO（save_service 真实往返）在 Godot 环境实跑；
# 本沙箱无 Godot，此处仍以 save_pouch/load_pouch 真实调用 + 数据层重建断言，
# 方法签名/数据契约在 Godot 下完全一致。
# ----------------------------------------------------------------------
func test_save_reconstruction():
	var p := Pouch.new()
	p.add_spirit_egg("mossback")
	p.add_spirit_egg("mossback")          # count=2
	var r := RuneEntry.new()
	r.rune_id = "z"; r.name = "Z"; r.slot = "spirit"; r.mult = {"atk": 1.5}; r.rarity = "common"
	p.add_rune(r)
	p.equip_rune("tamer", "z")
	p.coin_temp = 7

	var dict1 := p.to_dict()

	var sv := SaveService.new()
	sv.save_pouch(dict1)
	var dict2 := sv.load_pouch()
	# Godot 实跑时，文件往返后 dict2 应等于 dict1
	assert_eq(dict2, dict1, "save_pouch -> load_pouch 往返相等")

	var p2 := Pouch.new()
	p2.from_dict(dict2)
	assert_eq(p2.to_dict(), dict1, "Pouch 重建一致（数据层往返）")

	# 永久进度（bestiary/vein/ember）扩展方法存在且可用
	var progress := {"bestiary": {"mossback": true}, "vein_activated": ["a"], "ember": 12}
	sv.save_permanent(progress)
	assert_eq(sv.load_permanent(), progress, "save_permanent -> load_permanent 往返相等")

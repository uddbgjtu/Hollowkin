extends GutTest

const LayoutConfig := preload("res://src/ui/layout_config.gd")

# Epic F 静态断言：绑定真实 Pouch / VeinGraph / CombatDirector / BottomTabBar /
# ScreenRouter / Accessibility（均为 Epic D/C 生产类）。无 Godot 环境下仅按规范书写，
# 由 CI（.github/workflows/test.yml）在装有 Godot 4.3 的 runner 上真跑。
# 断言全部基于真实 API 表面（已与源码逐一对账），非臆造。

func test_bottom_tab_bar_layout() -> void:
	var tb = BottomTabBar.new()
	tb.build(LayoutConfig.tab_bar_rect())
	assert_eq(tb.rects().size(), 4, "应 4 个 tab")
	for r in tb.rects():
		assert_true(r.size.x >= 48.0 and r.size.y >= 48.0, "tab 命中区 ≥48px")
	var r0 = tb.rects()[0]
	var r1 = tb.rects()[1]
	assert_true(r1.position.x - (r0.position.x + r0.size.x) >= 8.0, "tab 间距 ≥8px")
	assert_eq(tb.label_for("pouch"), "灵囊", "弱图标：文字标签优先")


func test_accessibility_helpers() -> void:
	assert_eq(Accessibility.clamp_font(10, false), 14, "正文 ≥14px")
	assert_eq(Accessibility.clamp_font(10, true), 18, "标题 ≥18px")
	var dc = Accessibility.dual_code("low_hp")
	assert_true(dc.has("shape"), "状态双编码含形状")
	assert_true(dc.get("border", false), "低血配形状提示（a11y §3.4）")
	assert_false(Accessibility.is_cvd_safe("#FF4D4D", false), "危险红无形状→不安全")
	assert_true(Accessibility.is_cvd_safe("#FF4D4D", true), "危险红配形状→安全")


func test_pouch_view_data_binds_real_pouch() -> void:
	var p = Pouch.new()
	p.add_spirit_egg("mossback", "苔藓背")
	p.add_spirit_egg("mossback")            # ENG-2 +1 堆叠
	var r = RuneEntry.new()
	r.rune_id = "r_atk"
	r.name = "攻击符"
	r.mult = {"atk": 1.2}
	p.add_rune(r)
	var b = Bestiary.new()
	b.unlock("mossback")
	var vd = PouchViewData.new()
	vd.build_from_pouch(p, b)
	assert_eq(vd.spirits.size(), 1, "按 slug 聚合为单条")
	assert_eq(vd.spirits[0]["count"], 2, "重复灵兽 +1 计数")
	assert_true(vd.has_stack_badge(), "+1 堆叠角标（ENG-2）")
	assert_eq(vd.runes.size(), 1)
	assert_eq(vd.runes[0]["mult"].get("atk", 0.0), 1.2, "符文乘区（C1）")


func test_vein_view_data_classifies_states() -> void:
	var g = VeinGraph.new()
	var a = VeinNode.new()
	a.node_id = "root"; a.cost = 0; a.prereq = []; a.pos = Vector2(100, 100)
	var c = VeinNode.new()
	c.node_id = "child"; c.cost = 2; c.prereq = ["root"]; c.pos = Vector2(200, 200)
	g.register_node(a)
	g.register_node(c)
	var vd = SpiritVeinViewData.new()
	vd.build_from_graph(g, 5)
	assert_eq(vd.nodes.size(), 2)
	var root_state = ""
	var child_state = ""
	for nd in vd.nodes:
		if nd["id"] == "root":
			root_state = nd["state"]
		elif nd["id"] == "child":
			child_state = nd["state"]
	assert_eq(root_state, "available", "未激活但可激活")
	assert_eq(child_state, "locked", "前置未激活→锁")
	g.activate("root", 5)
	vd.build_from_graph(g, 5)
	for nd in vd.nodes:
		if nd["id"] == "root":
			root_state = nd["state"]
		elif nd["id"] == "child":
			child_state = nd["state"]
	assert_eq(root_state, "active", "已激活→星")
	assert_eq(child_state, "available", "前置已激活、ember 足够→可点")


func test_battle_screen_skill_hotzones() -> void:
	var cd = CombatDirector.new()
	var pstats = {"hp": 100.0, "atk": 10.0, "def": 5.0, "spd": 1.0, "aps": 1.0}
	var enemies = [{"name": "敌", "hp": 30.0, "atk": 5.0, "def": 2.0, "spd": 1.0, "aps": 1.0, "pos": Vector2(50, 0)}]
	cd.setup(123, 0, pstats, enemies)
	var ctx = UiContext.new()
	ctx.combat = cd
	var bs = BattleScreen.new()
	bs.bind(ctx)
	assert_eq(bs.skill_ids.size(), 2, "灵击+缚灵 双技能")
	assert_eq(bs.zones().size(), 4, "2 技能 + 防御 + 跳过")
	var ok = cd.skills["lingji"].trigger()
	assert_true(ok, "首放立即就绪")
	bs.on_action("lingji")
	assert_false(cd.skills["lingji"].is_ready(), "触发后进入冷却")
	assert_eq(bs.view.get("enemy_count", -1), 1, "HUD 暴露敌数")


func test_router_tab_dispatch_and_battle_disables_tab() -> void:
	var r = ScreenRouter.new()
	var ctx = UiContext.new()
	var ov = OverviewScreen.new()
	var po = PouchScreen.new()
	var sv = SpiritVeinScreen.new()
	var mp = MapScreen.new()
	var bt = BattleScreen.new()
	r.register(ov, 0)
	r.register(po, 1)
	r.register(sv, 2)
	r.register(mp, 3)
	r.register(bt, -1)
	ov.bind(ctx); po.bind(ctx); sv.bind(ctx); mp.bind(ctx); bt.bind(ctx)
	r.build(LayoutConfig.tab_bar_rect())

	assert_true(r.switch_to("pouch"), "切到灵囊")
	assert_eq(r.active_id, "pouch")
	assert_true(r.is_tab_bar_enabled())

	var pr = r.tab_bar.hit_rect_for("pouch")
	r.push_pointer(pr.position + pr.size * 0.5)
	r.flush(0.1)
	assert_eq(r.active_id, "pouch", "已在 pouch，重复点不切走")

	r.switch_to("overview")
	r.push_pointer(pr.position + pr.size * 0.5)
	r.flush(0.1)
	assert_eq(r.active_id, "pouch", "从 overview 点 pouch tab 切到 pouch")

	r.switch_to("battle")
	assert_false(r.is_tab_bar_enabled(), "战斗中隐藏 Tab")
	r.push_pointer(pr.position + pr.size * 0.5)
	r.flush(0.1)
	assert_eq(r.active_id, "battle", "战斗中 tab 误触被忽略")

	r.switch_to("overview")
	var er = Rect2()
	for z in ov.zones():
		if z["id"] == "enter_dungeon":
			er = z["rect"]
	assert_true(er.size.x > 0, "进入地牢按钮存在")
	r.push_pointer(er.position + er.size * 0.5)
	r.flush(0.1)
	assert_eq(r.active_id, "battle", "总览→地牢 经 pending 切换")

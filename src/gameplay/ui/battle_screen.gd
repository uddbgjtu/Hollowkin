# battle_screen.gd — 战斗屏（Epic F2 / ux-spec §3.1）
# =====================================================================
# 下半屏：技能键（≥56px 圆角方块，置于拇指热区）+ 防御/跳过键。
# 上半屏：敌我血条 / 状态（由 HUD view 暴露，渲染层做形状+色相双编码）。
# 低血量：heart + 屏幕红框脉冲（不只变红，a11y §3.4）。
# 冷却/禁用：置灰 + 锁形 + 环形遮罩（由 HUD skill_ready 表达，a11y §3.4）。
# 技能触发：zone_id 对应 CombatDirector 技能 id（lingji/fuling），经帧末输入队列。
# 非 tab 屏：由 router 在激活时隐藏底部 Tab，避免误触（ux-spec §3.1）。
# 无随机（ADR-5）：本屏只读 CombatDirector 状态并转发意图。
# =====================================================================

class_name BattleScreen
extends UiScreen

const SKILL_SIZE := 56.0
const SKILL_GAP := 8.0
const PAD := 24.0
const LOW_HP_RATIO := 0.30      # 低血量阈值（a11y §3.4 双编码触发）

var view: Dictionary = {}
var skill_ids: Array = []


func _init() -> void:
	super._init("battle")


func _build() -> void:
	_build_skill_zones()
	_refresh_hud()


func _build_skill_zones() -> void:
	_zones.clear()
	hit_zone.clear()
	var region := Rect2(Vector2.ZERO, Vector2(720, 1280))
	var base_y := region.position.y + region.size.y - SKILL_SIZE - PAD
	var ids: Array = []
	if ctx != null and ctx.combat != null:
		for sk_id in ctx.combat.skills.keys():
			ids.append(sk_id)
	skill_ids = ids
	# 技能键（置于拇指热区，右下布局）
	var n := float(ids.size())
	var total_w := n * SKILL_SIZE + (n - 1.0) * SKILL_GAP
	var start_x := region.position.x + region.size.x - total_w - PAD
	for i in range(ids.size()):
		var x := start_x + float(i) * (SKILL_SIZE + SKILL_GAP)
		_add_rect(ids[i], Rect2(x, base_y, SKILL_SIZE, SKILL_SIZE))
	# 防御/跳过键（左下，双编码为锁定态占位）
	_add_rect("defend", Rect2(region.position.x + PAD, base_y, SKILL_SIZE, SKILL_SIZE))
	_add_rect("skip", Rect2(region.position.x + PAD + SKILL_SIZE + SKILL_GAP, base_y, SKILL_SIZE, SKILL_SIZE))


func _refresh_hud() -> void:
	view = {}
	if ctx == null or ctx.combat == null:
		return
	var c = ctx.combat
	var p = c.player
	if p != null:
		var ratio: float = p.hp / max(p.max_hp, 1.0)
		view["hp"] = p.hp
		view["max_hp"] = p.max_hp
		view["low_hp"] = ratio <= LOW_HP_RATIO   # 低血双编码触发（a11y §3.4）
		view["low_hp_ratio"] = ratio
	view["enemy_count"] = c.enemy_count()
	view["run_ended"] = c.run_ended
	# 每技能就绪态（渲染层据此做置灰/锁形/环形遮罩）
	var ready: Dictionary = {}
	for sk_id in c.skills.keys():
		ready[sk_id] = c.skills[sk_id].is_ready()
	view["skill_ready"] = ready


func on_enter() -> void:
	active = true
	_build_skill_zones()
	_refresh_hud()


func on_action(zone_id: String) -> void:
	if ctx == null or ctx.combat == null:
		return
	if zone_id == "defend" or zone_id == "skip":
		return  # MVP：防御/跳过为占位（双编码为锁定态），不阻断仿真
	if ctx.combat.skills.has(zone_id):
		ctx.combat.on_action(zone_id)
	_refresh_hud()

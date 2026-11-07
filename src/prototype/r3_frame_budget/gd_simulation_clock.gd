# =============================================================================
# R3 原型 · 触屏并发 + 自动战斗 AI 同帧预算（GDScript 忠实战 port）
# =============================================================================
# 用途：佐证 feasibility-review.md ADR-2/ADR-3 + 工程风险 R3（触屏+AI 同帧开销）。
#       - SimulationClock：固定 10Hz tick（每 0.1s 一步），MAX_CATCHUP=3（防雪崩）
#       - tick() 内先消费 InputQueue（ADR-2 帧末结算），再驱动 CombatDirector
#       - 自适应：连续超帧预算 → 降 5Hz + 降同屏敌人/粒子（无感降级，R3 缓解 4）
#       - 屏外实体经 VisibleOnScreenNotifier2D 停用 AI/动画（R3 缓解 2）
# 【历史偏差注 2026-11-07】本原型以帧 delta 判「超预算」，30fps 每帧必然命中并误降
# 5Hz；生产版 src/gameplay/ai/simulation_clock.gd::_adapt() 已改为只认实测单帧耗时。
# 本文件保留原型原貌作审计证据，不得据其推导现行设计或性能结论。
# 注意：本文件为原型佐证，不进入正式 src/ 业务目录；须在 Godot 编辑器真机/桌面运行。
#       本 sandbox 无 Godot，无法在此运行，仅交付代码 + 测量方法学。
# =============================================================================

extends Node

# ---- 仿真时钟（ADR-3）-------------------------------------------------------
const TICK_DT        := 0.1      # 10Hz
const MAX_CATCHUP    := 3        # 防后台恢复追帧雪崩
const TICK_DT_SLOW   := 0.2      # 5Hz 自适应降频
const OVER_BUDGET_LIMIT := 30    # 连续超预算帧数阈值 → 触发降频

var _accum := 0.0
var _slow := false
var _over_budget_streak := 0

# 预算表（feasibility R3；真机实测对照目标，非本沙箱测量值）
#   输入仲裁 <0.5ms / AI tick ~1.66ms(均摊) / 同屏≤12敌人渲染<4ms / 粒子<3ms
func _process(delta: float) -> void:
	_accum += delta
	var dt := TICK_DT if not _slow else TICK_DT_SLOW
	var n := 0
	while _accum >= dt and n < MAX_CATCHUP:
		_tick()
		_accum -= dt
		n += 1
	if n >= MAX_CATCHUP:
		_accum = 0.0   # 丢弃积压，防雪崩

	# 自适应降频（R3 缓解 4）：连续超预算 → 降 5Hz
	_adapt(delta)

func _tick() -> void:
	# ADR-2 帧末结算：每 tick 消费一次输入队列（去重 + cd 钳 0.5s）
	InputQueue.consume_into(self)
	# ADR-3：锁敌/寻路/协战决策/伤害结算（非每帧）
	CombatDirector.step_simulation(TICK_DT if not _slow else TICK_DT_SLOW)
	# 移动/动画逐帧插值（读 AI 目标，不在此重算决策）—— 见 _physics_process 或动画树

func _adapt(delta: float) -> void:
	# 简化：以单帧总仿真耗时是否越过预算上限（16.6ms@60fps）判断
	# 真机应在各子系统插桩取真实耗时；此处仅演示触发逻辑结构
	var over := delta > 0.0166   # 60fps 预算上限
	if over:
		_over_budget_streak += 1
	else:
		_over_budget_streak = 0
	if _over_budget_streak >= OVER_BUDGET_LIMIT and not _slow:
		_slow = true
		print("R3 自适应：连续 %d 帧超预算 → AI 降频至 5Hz" % OVER_BUDGET_LIMIT)
	elif _over_budget_streak == 0 and _slow:
		_slow = false
		print("R3 自适应：恢复正常 10Hz")

# ---- 屏外剔除（R3 缓解 2）--------------------------------------------------
# 在实体节点上挂 VisibleOnScreenNotifier2D，屏外停用 AI/动画：
#   func _on_visibility_changed(v): set_physics_process(v); set_process(v)
# 同屏敌人上限 12（feasibility R3 预算表），超出按距离剔除最远者。

# ---- 输入队列（ADR-2，节选自 feasibility §6.2）----------------------------
# class_name InputQueue extends RefCounted
# func push(e): _events.append(e)
# func consume_into(target):
#     var seen := {}
#     for e in _events:
#         if e is InputEventScreenTouch and e.pressed:
#             var hi := HitZone.resolve(e.position)
#             if hi != null and not seen.has(hi.id):
#                 seen[hi.id] = true; target.on_action(hi.id)
#     _events.clear()

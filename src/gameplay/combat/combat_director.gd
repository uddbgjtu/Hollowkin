# combat_director.gd — 战斗仿真主管（GDD §3 / architecture-doc.md §1.2，生产版）
# =====================================================================
# 职责：地窟内实时战斗仿真。step_simulation(dt)（由 SimulationClock 在 10Hz
#       tick 内调用，ADR-3）：
#   1) 锁敌：主角/灵兽锁定最近敌人；
#   2) 自动普攻：按 APS 累加发射（无目标 → idle，GDD §6.1）；
#   3) 灵兽协战：每只存活灵兽锁定最近敌人并普攻；
#   4) 技能 CD 推进（就绪技能经 on_action 由帧末输入触发）；
#   5) 敌人 AI：朝主角移动并普攻（最小实现，EnemyAI 接缝）；
#   6) 死亡结算：清理死亡实体；主角死亡 → run 结束 → C3 30% 转化（DeathSettlement）。
# 确定性（ADR-5）：所有随机走本层 floor RNG（_rng）；给定相同 (_rng 序列, 输入, dt)
#       必产生一致结果。SpiritAI/EnemyAI 接缝保持最小（thin enemy_ai，后续 Epic 扩）；
#       架构 §1.7 的 enemy_ai.gd / spirit_ai.gd 为 Epic-C 后续桩，本文件不内联其文件。
# 读 StatBlock.final_stat() 取每击最终值；本模块持 player.rune_mult（由上层喂入）。
# 设计为 RefCounted（无场景树可单测 / 可序列化）。
# =====================================================================

class_name CombatDirector
extends RefCounted

const K := 8.0
const ENEMY_ATTACK_RANGE := 1.0     # 格（1 格 = 16px）
const CONE_HALF_ANGLE := PI / 4.0   # 90° 锥形（半角 45°）
const CONE_RANGE := 3.0             # 格


var _rng: RandomNumberGenerator
var run_seed: int = 0
var floor_index: int = 0

var player: CombatEntity
var spirits: Array = []   # Array[CombatEntity]
var enemies: Array = []   # Array[CombatEntity]
var skills: Dictionary = {}  # id -> SkillRuntime

var coin_temp: int = 0
var ember_gained: int = 0
var run_ended: bool = false
var tick_count: int = 0


# 战斗实体（纯数据承载，RefCounted 便于无头测试与序列化友好）。
class CombatEntity extends RefCounted:
    var id: String = ""
    var display_name: String = ""
    var kind: int = 0            # 0 主角 / 1 灵兽 / 2 敌人
    var hp: float = 1.0
    var max_hp: float = 1.0
    var atk: float = 0.0
    var def: float = 0.0
    var spd: float = 0.0         # 格/秒
    var aps: float = 0.0         # 自动普攻 次/秒
    var crit_rate: float = 0.0   # %
    var crit_dmg: float = 100.0  # %
    var rune_mult: float = 1.0   # 来自 StatBlock（默认 1.0）
    var pos: Vector2 = Vector2.ZERO
    var alive: bool = true
    var worth: int = 1           # 临时货币掉落（Epic D 接管具体经济）
    var target: CombatEntity = null
    var _atk_accum: float = 0.0  # 普攻累加计时


func setup(p_run_seed: int, p_floor_index: int, player_stats: Dictionary, enemy_specs: Array) -> void:
    run_seed = p_run_seed
    floor_index = p_floor_index
    _rng = RNGService.floor_rng(p_run_seed, p_floor_index)

    player = _make_entity("player", "灯童", 0, player_stats)

    var spirit_specs: Array = player_stats.get("spirits", [])
    for i in range(spirit_specs.size()):
        var sp: Dictionary = spirit_specs[i]
        var e := _make_entity("spirit_%d" % i, sp.get("name", "灵兽"), 1, sp)
        spirits.append(e)

    for i in range(enemy_specs.size()):
        var es: Dictionary = enemy_specs[i]
        var e := _make_entity("enemy_%d" % i, es.get("name", "敌人"), 2, es)
        enemies.append(e)

    # 玩家主动技能（GDD §3.2 双技能）
    var lingji := SkillRuntime.make_lingji()
    var fuling := SkillRuntime.make_fuling()
    skills[lingji.id] = lingji
    skills[fuling.id] = fuling


func _make_entity(p_id: String, p_name: String, p_kind: int, spec: Dictionary) -> CombatEntity:
    var e := CombatEntity.new()
    e.id = p_id
    e.display_name = p_name
    e.kind = p_kind
    e.hp = float(spec.get("hp", 1.0))
    e.max_hp = e.hp
    e.atk = float(spec.get("atk", 0.0))
    e.def = float(spec.get("def", 0.0))
    e.spd = float(spec.get("spd", 0.0))
    e.aps = float(spec.get("aps", 0.0))
    e.crit_rate = float(spec.get("crit_rate", 0.0))
    e.crit_dmg = float(spec.get("crit_dmg", 100.0))
    e.rune_mult = float(spec.get("rune_mult", 1.0))
    e.pos = spec.get("pos", Vector2.ZERO)
    e.worth = int(spec.get("worth", 1))
    e.alive = true
    return e


# ADR-3：每 tick 调用一次。dt 为 TICK_DT（10Hz）或 TICK_DT_SLOW（5Hz）。
# 输入触发（on_action）已在 tick 内消费队列时执行，故此处只推演仿真。
func step_simulation(dt: float) -> void:
    tick_count += 1
    if player == null:
        return
    if not player.alive:
        _settle_deaths()
        return

    # 1) + 2) 主角锁敌 + 自动普攻
    var nearest := _nearest_enemy_to(player)
    player.target = nearest
    _tick_auto_attack(dt, player, nearest)

    # 3) 灵兽协战
    for s in spirits:
        if not s.alive:
            continue
        var t := _nearest_enemy_to(s)
        s.target = t
        _tick_auto_attack(dt, s, t)

    # 4) 技能 CD 推进
    for sk in skills.values():
        sk.tick_cd(dt)

    # 5) 敌人 AI（朝主角移动并普攻）
    for e in enemies:
        if not e.alive:
            continue
        _enemy_ai(dt, e, player)

    # 6) 死亡结算
    _settle_deaths()


func _nearest_enemy_to(ent: CombatEntity) -> CombatEntity:
    var best: CombatEntity = null
    var best_d := INF
    for e in enemies:
        if not e.alive:
            continue
        var d := ent.pos.distance_to(e.pos)
        if d < best_d:
            best_d = d
            best = e
    return best


func _tick_auto_attack(dt: float, ent: CombatEntity, target: CombatEntity) -> void:
    if target == null or not target.alive:
        return  # GDD §6.1 无目标 → idle
    if ent.aps <= 0.0:
        return
    ent._atk_accum += dt
    var interval := 1.0 / ent.aps
    while ent._atk_accum >= interval:
        ent._atk_accum -= interval
        _apply_attack(ent, target, 1.0)  # 普攻 coeff = 1.0


func _apply_attack(attacker: CombatEntity, target: CombatEntity, coeff: float) -> void:
    if target == null or not target.alive:
        return
    # 伤害公式（GDD §3.5，K=8，Variance 取本层 RNG，RuneMult 来自 StatBlock）。
    var dmg := DamageCalc.compute(attacker.atk, target.def, coeff, attacker.crit_rate, attacker.crit_dmg, attacker.rune_mult, _rng)
    target.hp -= dmg
    if target.hp <= 0.0:
        target.hp = 0.0
        target.alive = false


func _enemy_ai(dt: float, e: CombatEntity, p: CombatEntity) -> void:
    if p == null or not p.alive:
        return
    var to_p := p.pos - e.pos
    var dist := to_p.length()
    if dist > 0.0001:
        var step_len := min(e.spd * dt, dist)
        e.pos += to_p / dist * step_len
    if e.aps <= 0.0:
        return
    e._atk_accum += dt
    var interval := 1.0 / e.aps
    if dist <= ENEMY_ATTACK_RANGE and e._atk_accum >= interval:
        e._atk_accum -= interval
        _apply_attack(e, p, 1.0)


# ADR-2 帧末结算入口：玩家主动技能触发（zone_id 对应技能 id，如 "lingji"/"fuling"）。
func on_action(zone_id: String) -> void:
    if not skills.has(zone_id):
        return
    var sk: SkillRuntime = skills[zone_id]
    var tgt = _skill_target(sk)
    if sk.trigger():
        _cast_skill(sk, tgt)


func _skill_target(sk: SkillRuntime):
    if sk.target == "cone":
        return _enemies_in_cone(player)
    return _nearest_enemy_to(player)


func _enemies_in_cone(origin: CombatEntity) -> Array:
    var out: Array = []
    var nearest := _nearest_enemy_to(origin)
    var forward := Vector2.RIGHT
    if nearest != null:
        var f := nearest.pos - origin.pos
        if f.length() > 0.0001:
            forward = f / f.length()
    for e in enemies:
        if not e.alive:
            continue
        var to := e.pos - origin.pos
        var d := to.length()
        if d > CONE_RANGE or d <= 0.0001:
            continue
        var ang := forward.angle_to(to / d)
        if abs(ang) <= CONE_HALF_ANGLE:
            out.append(e)
    return out


func _cast_skill(sk: SkillRuntime, tgt) -> void:
    if sk.cast == "swipe":   # 缚灵：锥形多目标
        var list: Array = tgt if tgt is Array else []
        for e in list:
            _apply_attack(player, e, sk.coeff)
    else:                    # 灵击：单体最近
        var tgt_ent: CombatEntity = tgt if tgt is CombatEntity else null
        _apply_attack(player, tgt_ent, sk.coeff)


func _settle_deaths() -> void:
    # 敌人死亡计入临时货币；灵兽全灭不影响主角（GDD §6.5）。
    for i in range(enemies.size() - 1, -1, -1):
        if not enemies[i].alive:
            coin_temp += enemies[i].worth
            enemies.remove_at(i)
    # 主角死亡 → run 结束 → C3 30% 转化（仅此一次）。
    if player != null and not player.alive and not run_ended:
        run_ended = true
        ember_gained = DeathSettlement.settle(coin_temp)


# 观测辅助（测试 / HUD）
func is_player_dead() -> bool:
    return player != null and not player.alive


func enemy_count() -> int:
    var n := 0
    for e in enemies:
        if e.alive:
            n += 1
    return n

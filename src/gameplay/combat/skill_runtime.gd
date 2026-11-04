# skill_runtime.gd — 玩家主动技能运行时（GDD §3.2，生产版）
# =====================================================================
# 技能定义（MVP 双技能）：
#   灵击（tap）：cd 4s，coeff 1.6，target=nearest（单体）
#   缚灵（swipe）：cd 8s，coeff 1.0，target=cone（前方 90°/3 格）
# ADR-2 / GDD §6.4：trigger() 强制 0.5s cd 下限钳（防卡死 + 去重重触发），
#       冷却中重触发返回 false。tick_cd(dt) 推进冷却并累计距上次触发时长。
# 设计为 RefCounted，可无场景树单测。
# =====================================================================

class_name SkillRuntime
extends RefCounted

const CD_FLOOR := 0.5          # GDD §6.4 cd 下限钳 0.5s
const LINGJI_ID := "lingji"
const FULING_ID := "fuling"


var id: String = ""
var skill_name: String = ""
var cast: String = "tap"       # "tap" | "swipe"
var cd: float = 0.0
var coeff: float = 1.0
var target: String = "nearest" # "nearest" | "cone"

var _cd_remaining: float = 0.0
var _since_trigger: float = CD_FLOOR   # 初始化为下限，使首次释放立即就绪


func _init(p_id: String = "", p_name: String = "", p_cast: String = "tap", p_cd: float = 0.0, p_coeff: float = 1.0, p_target: String = "nearest") -> void:
    id = p_id
    skill_name = p_name
    cast = p_cast
    cd = p_cd
    coeff = p_coeff
    target = p_target


static func make_lingji() -> SkillRuntime:
    return SkillRuntime.new(LINGJI_ID, "灵击", "tap", 4.0, 1.6, "nearest")


static func make_fuling() -> SkillRuntime:
    return SkillRuntime.new(FULING_ID, "缚灵", "swipe", 8.0, 1.0, "cone")


# 推进冷却 + 累计距上次触发时长（用于 0.5s 下限判定）。
func tick_cd(dt: float) -> void:
    if _cd_remaining > 0.0:
        _cd_remaining = max(0.0, _cd_remaining - dt)
    if _since_trigger < CD_FLOOR:
        _since_trigger += dt


func is_ready() -> bool:
    return _cd_remaining <= 0.0 and _since_trigger >= CD_FLOOR


# 触发：0.5s 下限未到或冷却中 → 返回 false（去重重触发 / 防卡死）。
func trigger() -> bool:
    if _since_trigger < CD_FLOOR:
        return false
    if _cd_remaining > 0.0:
        return false
    _cd_remaining = cd
    _since_trigger = 0.0
    return true

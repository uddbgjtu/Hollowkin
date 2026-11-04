# death_settlement.gd — 死亡 / 中断结算（C3 转化率 30%，生产版）
# =====================================================================
# GDD §5：本层临时货币 coin_temp 在「run 结束（死亡或中断）」时按 30% 转化为
#       永久货币 ember_eternal。本类只算转化，不持有状态。
# 仅在 run 结束调用一次（见 CombatDirector._settle_deaths 的收尾路径）。
# 设计为 RefCounted + 静态方法，可无场景树单测。
# =====================================================================

class_name DeathSettlement
extends RefCounted

const CONVERSION_RATE := 0.30   # C3 转化率 30%


# coin_temp → ember_eternal。仅在 run 结束（死亡/中断）时调用一次。
static func settle(coin_temp: int) -> int:
    return int(floor(float(coin_temp) * CONVERSION_RATE))

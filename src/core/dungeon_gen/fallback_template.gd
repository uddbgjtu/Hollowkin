# fallback_template.gd — 地窟生成保底安全层（Epic B / R1 缓解 2）
# =====================================================================
# 当 floor_index 非法、生成超时或异常时，DungeonGenerator 切换到此预制安全层，
# 保证流程不阻断（战斗 GDD §6 边界 2 / 架构 §1.1）。
# 该层是固定布局、无随机（seed=-1, floor=-1, fallback=true），不可重建依赖它。
# 所有随机一律走 RNGService，本层不含任何随机调用（ADR-5）。
# =====================================================================

class_name FallbackTemplate
extends RefCounted

# 返回固定的安全层：1 个 10x10 房间在 0,0、1 个 mob 在 5,5、1 个 heal 在 8,8。
# 镜像 R1 原型 fallback_template() 的字段与取值（含 seed/floor/fallback 标记）。
static func build() -> Dictionary:
	return {
		"seed": -1,
		"floor": -1,
		"fallback": true,
		"rooms": [{"x": 0, "y": 0, "w": 10, "h": 10}],
		"corridors": [],
		"enemy_spawns": [{"x": 5, "y": 5, "tier": "mob"}],
		"loot": [{"kind": "heal", "x": 8, "y": 8}]
	}

# rng_service.gd — ADR-5 随机性唯一出口
# =====================================================================
# 职责：集中提供种子化随机源。禁止业务代码直接使用全局
#       randf() / randi() / randf_range() / randi_range() / randomize()
#       （由 tools/ci/lint_no_global_random.py 拦截，本文件为白名单例外）。
#
# 设计纪律：
#   - 所有随机必须经由本类，或其返回的 RandomNumberGenerator 实例
#     （实例方法 rng.randf() 等因前置 '.' 被 lint 放行）。
#   - 同 (seed) 必产生逐字节一致的序列 —— 这是 ADR-1 种子化可恢复
#     存档（层间落盘）与事件日志对齐的基础。
#   - 跨 Godot 次版本算法一致性以 4.3 签字基线为准（见
#     docs/engine-reference/godot/VERSION.md）。
# =====================================================================

class_name RNGService
extends RefCounted

# 全局默认基（任意固定常数，避免 seed=0 与未初始化歧义）。非机密。
const SEED_BASE := 0x9E3779B9


# 创建一个以 seed 确定性初始化的 RandomNumberGenerator。
# 同 seed -> 同序列。用于地牢生成、战斗 AI tick、掉落等一切需可复现随机之处。
# 返回的实例请用其方法 rng.randi() / rng.randi_range(a, b) / rng.randf() 等。
static func new_floor_rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	# Godot 4：设置 seed 即确定性初始化；32 位无符号截断保证跨平台一致。
	rng.seed = int(seed_value) & 0x7FFFFFFF
	return rng


# 便捷：由字符串 slug 派生确定性 seed（如实体 slug、资产文件名）。
# 同一 slug 永远映射到同一 seed，避免散列漂移（与 bestiary §0.1 命名源协同）。
static func seed_from_string(s: String) -> int:
	var h := SEED_BASE
	var chars := s.to_utf8_buffer()
	for b in chars:
		h = (h * 31 + b) & 0x7FFFFFFF
	return h


# 便捷：组合多个整型因子派生 seed（如 floor 层号 + 房间坐标 + 实体 id）。
static func derive_seed(factors: Array) -> int:
	var h := SEED_BASE
	for f in factors:
		h = (h * 31 + int(f)) & 0x7FFFFFFF
	return h


# 便捷：从已有 RNG 实例抽取当前 64 位 state（用于 ADR-1 存档序列化）。
# 读档时用 restore_state() 还原，保证后续序列一致。
static func capture_state(rng: RandomNumberGenerator) -> int:
	return rng.state


# 便捷：将 state 还原到 RNG 实例（与 capture_state 配对，支撑存档重建）。
static func restore_state(rng: RandomNumberGenerator, state_value: int) -> void:
	rng.state = state_value

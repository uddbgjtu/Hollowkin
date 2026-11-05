# floor_cache.gd — 同 run 内 (run_seed, floor_index) 布局缓存（Epic B / 架构 §1.1）
# =====================================================================
# 缓存同一 (run_seed, floor_index) 的确定性布局，避免重复抽取。
# 同步路径（generate_sync）与异步路径（generate_floor）共用同一缓存实例。
# 不含任何随机调用（ADR-5）；键为 "%d:%d" % [run_seed, floor]。
# =====================================================================

class_name FloorCache
extends RefCounted

# 内部存储：key 字符串 -> 布局 Dictionary。
var _store := {}


# 计算缓存键（与 docs 规范一致）。
static func _key(run_seed: int, floor: int) -> String:
	return "%d:%d" % [run_seed, floor]


# 取缓存布局；miss 返回 null。
# 注：方法名 fetch（非 get）——Godot 4.x 的 Object.get 已移除，
# 自定义名为 get 的成员会与解析器冲突，导致调用方报 "Could not resolve external class member 'get'"。
func fetch(run_seed: int, floor: int) -> Dictionary:
	var k := _key(run_seed, floor)
	if _store.has(k):
		return _store[k]
	return {}


# 写入缓存。
func put(run_seed: int, floor: int, layout: Dictionary) -> void:
	_store[_key(run_seed, floor)] = layout


# 是否存在 (run_seed, floor) 的缓存。
func has(run_seed: int, floor: int) -> bool:
	return _store.has(_key(run_seed, floor))


# 清空全部缓存。
func clear() -> void:
	_store.clear()

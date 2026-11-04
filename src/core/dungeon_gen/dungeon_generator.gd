# dungeon_generator.gd — 地窟生成入口（Epic B / 架构 §1.1）
# =====================================================================
# 职责：按 (run_seed, floor_index) 确定性重建地窟布局——房间拼接、敌人模板
# 挑选、掉落表抽取。产出逻辑网格 + 实体放置表（不含瓦片渲染态，渲染交
# Godot TileMapLayer）。
# 依赖：
#   - RNGService（ADR-5 唯一随机出口，floor_rng 派生层 RNG；禁内联哈希）
#   - RoomStitcher（确定性核心）
#   - FloorCache（同 run 内 (seed,floor) 缓存）
#   - FallbackTemplate（生成超时/异常/非法 floor 的保底安全层）
# =====================================================================

class_name DungeonGenerator
extends Node

var _cache := FloorCache.new()


# 同步生成（不依赖场景树，供单测 / 即时重建使用，对齐 ADR-1 种子化重建）。
# 非法 floor (<0 或 >9999) → 返回保底模板；否则先查缓存，miss 则抽取并回填
# run_seed 后缓存。
func generate_sync(run_seed: int, floor_index: int, tier: int) -> Dictionary:
	if floor_index < 0 or floor_index > 9999:
		return FallbackTemplate.build()
	if _cache.has(run_seed, floor_index):
		return _cache.get(run_seed, floor_index)
	var rng := RNGService.floor_rng(run_seed, floor_index)
	var layout := RoomStitcher.build(rng, floor_index, tier)
	layout["run_seed"] = run_seed
	_cache.put(run_seed, floor_index, layout)
	return layout


# 异步协程：合法层时按 RoomStitcher 局部构建函数分段生成，每段之间插入
# await get_tree().process_frame 让帧（R1 缓解 1，避免单帧尖峰）。
# 抽取顺序与 build() 完全一致，确保 await generate_floor(s,f,t) 与
# generate_sync(s,f,t) 产出相同布局。非法 floor / 命中缓存则短路返回。
func generate_floor(run_seed: int, floor_index: int, tier: int) -> Dictionary:
	if floor_index < 0 or floor_index > 9999:
		return FallbackTemplate.build()
	if _cache.has(run_seed, floor_index):
		return _cache.get(run_seed, floor_index)
	var rng := RNGService.floor_rng(run_seed, floor_index)
	var rooms := RoomStitcher.build_rooms(rng, tier)
	await get_tree().process_frame
	var corridors := RoomStitcher.build_corridors(rng, rooms)
	await get_tree().process_frame
	var enemy_spawns := RoomStitcher.build_enemies(rng, rooms, tier)
	await get_tree().process_frame
	var loot := RoomStitcher.build_loot(rng, floor_index)
	await get_tree().process_frame
	var layout := {
		"run_seed": null,
		"floor": floor_index,
		"seed": rng.seed,
		"rooms": rooms,
		"corridors": corridors,
		"enemy_spawns": enemy_spawns,
		"loot": loot
	}
	layout["run_seed"] = run_seed
	_cache.put(run_seed, floor_index, layout)
	return layout


# 清空布局缓存（委托 FloorCache）。
func clear_cache() -> void:
	_cache.clear()

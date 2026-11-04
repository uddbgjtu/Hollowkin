# room_stitcher.gd — 地窟拼接 + 敌人/掉落抽取（确定性核心，Epic B / 架构 §1.1）
# =====================================================================
# 承载架构 §1.1 的"确定性核心"：一切随机走传入的 RNGService 派生 RNG 实例
# （ADR-5），不创建任何内联 RandomNumberGenerator，不使用 R1 原型的 floor_seed 哈希。
#
# 抽取顺序（build 与异步路径必须完全一致，保证 generate_sync == await generate_floor）：
#   1) 房间：room_count = rng.randi_range(6, max_rooms)
#   2) 走廊：顺序连接相邻房间，L 形，bend = rng.randi() % 2
#   3) 敌人：enemy_count = rng.randi_range(max_enemies/2, max_enemies);
#            tier 按 rng.randf()：>0.92 boss / >0.75 elite / 其余 mob
#   4) 掉落：count = rng.randi_range(2, 5+floor_index);
#            kind 按 rng.randf()：<0.5 coin / <0.8 rune / 否则 spirit
# 本地构建函数供异步路径在每段间插入 await 而不改变抽取顺序。
# =====================================================================

class_name RoomStitcher
extends RefCounted

enum DeviceTier { HIGH, LOW }
const MAX_ROOMS_HIGH   := 14
const MAX_ROOMS_LOW    := 8
const MAX_ENEMIES_HIGH := 24
const MAX_ENEMIES_LOW  := 12


# 完整确定性构建（同步路径与异步路径共用同一抽取顺序）。
# run_seed 不由本层持有（build 仅收 rng/floor/tier），故先置 null，
# 由 DungeonGenerator 在入口处回填真实 run_seed。
static func build(rng: RandomNumberGenerator, floor_index: int, tier: int) -> Dictionary:
	var rooms := build_rooms(rng, tier)
	var corridors := build_corridors(rng, rooms)
	var enemy_spawns := build_enemies(rng, rooms, tier)
	var loot := build_loot(rng, floor_index)
	return {
		"run_seed": null,
		"floor": floor_index,
		"seed": rng.seed,
		"rooms": rooms,
		"corridors": corridors,
		"enemy_spawns": enemy_spawns,
		"loot": loot
	}


# --- 局部构建函数（供异步分片 + 顺序保证）--------------------------------

# 房间拼接：先抽房间数，再逐个抽 w/h/x/y（镜像 R1 原型 _place_room 抽取顺序）。
static func build_rooms(rng: RandomNumberGenerator, tier: int) -> Array:
	var max_rooms := MAX_ROOMS_HIGH if tier == DeviceTier.HIGH else MAX_ROOMS_LOW
	var room_count := rng.randi_range(6, max_rooms)
	var rooms: Array = []
	for i in room_count:
		var w := rng.randi_range(4, 9)
		var h := rng.randi_range(4, 9)
		var x := rng.randi_range(0, 64 - w)
		var y := rng.randi_range(0, 64 - h)
		rooms.append({"x": x, "y": y, "w": w, "h": h, "idx": i})
	return rooms


# 走廊：顺序连接相邻房间（L 形），bend 取本层 RNG（镜像 R1 原型 _connect）。
static func build_corridors(rng: RandomNumberGenerator, rooms: Array) -> Array:
	var corridors: Array = []
	for i in range(1, rooms.size()):
		var a: Dictionary = rooms[i - 1]
		var b: Dictionary = rooms[i]
		corridors.append({
			"ax": a["x"] + a["w"] / 2,
			"ay": a["y"] + a["h"] / 2,
			"bx": b["x"] + b["w"] / 2,
			"by": b["y"] + b["h"] / 2,
			"bend": rng.randi() % 2
		})
	return corridors


# 敌人：先抽敌人数，再逐个抽 tier（randf 阈值）与坐标（镜像 R1 原型 _pick_enemy）。
# tier（设备档位）决定 max_enemies 上限（R1 缓解 5 低端机降密度）；
# 默认 HIGH 以保留 build_enemies(rng, rooms) 的二元可调用形式。
static func build_enemies(rng: RandomNumberGenerator, rooms: Array, tier: int = DeviceTier.HIGH) -> Array:
	var max_enemies := MAX_ENEMIES_HIGH if tier == DeviceTier.HIGH else MAX_ENEMIES_LOW
	var enemy_count := rng.randi_range(int(max_enemies / 2), max_enemies)
	var enemy_spawns: Array = []
	for i in enemy_count:
		var room: Dictionary = rooms[i % rooms.size()]
		var roll := rng.randf()
		var tier_name := "mob"
		if roll > 0.92:
			tier_name = "boss"
		elif roll > 0.75:
			tier_name = "elite"
		var ex := rng.randi_range(0, room["w"])
		var ey := rng.randi_range(0, room["h"])
		enemy_spawns.append({"x": ex, "y": ey, "tier": tier_name})
	return enemy_spawns


# 掉落表：先抽数量，再逐个抽 kind（randf 阈值）与 r（镜像 R1 原型 _roll_loot）。
static func build_loot(rng: RandomNumberGenerator, floor_index: int) -> Array:
	var out: Array = []
	var n := rng.randi_range(2, 5 + floor_index)
	for _i in n:
		var roll := rng.randf()
		var kind := "coin" if roll < 0.5 else ("rune" if roll < 0.8 else "spirit")
		out.append({"kind": kind, "r": rng.randf()})
	return out

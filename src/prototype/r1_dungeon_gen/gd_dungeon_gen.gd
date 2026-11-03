# =============================================================================
# R1 原型 · 地窟生成（GDScript 忠实战 port）
# =============================================================================
# 用途：佐证 feasibility-review.md ADR-1/ADR-5 + 工程风险 R1（程序生成地窟）。
#       - 确定性：floor_seed = hash_mix(run_seed, floor_index)，全随机源走本层 RNG
#       - 分步生成 + await get_tree().process_frame 让帧（R1 缓解 1）
#       - 保底模板层（R1 缓解 2）
#       - 低端机降密度（R1 缓解 5）
# 注意：本文件为原型佐证，不进入正式 src/ 业务目录；须在 Godot 编辑器真机/桌面运行。
#       本文档库（sandbox）无 Godot，无法在此运行，仅交付代码 + 测量方法学。
# =============================================================================

extends Node

# ---- 设备档位（R1 缓解 5：低端机降密度）------------------------------------
enum DeviceTier { HIGH, LOW }
const MAX_ROOMS_HIGH   := 14
const MAX_ROOMS_LOW    := 8
const MAX_ENEMIES_HIGH := 24
const MAX_ENEMIES_LOW  := 12

# ---- 确定性哈希（与 feasibility-review.md §6.4 一致）------------------------
static func floor_seed(run_seed: int, floor_index: int) -> int:
	var h := run_seed ^ (floor_index * 0x9E3779B1)
	h = (h ^ (h >> 16)) * 0x85EBCA6B
	return h & 0x7FFFFFFF

# ---- 单层生成（分步 + await 让帧）------------------------------------------
# 返回逻辑布局（不含瓦片渲染状态）：rooms / corridors / enemy_spawns / loot
func generate_floor(run_seed: int, floor_index: int, tier: DeviceTier) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = floor_seed(run_seed, floor_index)   # ADR-5：本层唯一 RNG 实例

	var max_rooms   := MAX_ROOMS_HIGH if tier == DeviceTier.HIGH else MAX_ROOMS_LOW
	var max_enemies := MAX_ENEMIES_HIGH if tier == DeviceTier.HIGH else MAX_ENEMIES_LOW

	var layout := {
		"seed": rng.seed, "floor": floor_index,
		"rooms": [], "corridors": [], "enemy_spawns": [], "loot": []
	}

	# 分片 1：房间拼接（让帧）
	var room_count := rng.randi_range(6, max_rooms)
	for i in room_count:
		var r := _place_room(rng, i)
		layout.rooms.append(r)
		if i % 3 == 2:
			await get_tree().process_frame          # R1 缓解 1：每 3 间让一帧

	# 分片 2：走廊连接（让帧）
	for i in range(1, layout.rooms.size()):
		layout.corridors.append(_connect(layout.rooms[i-1], layout.rooms[i], rng))
		if i % 3 == 2:
			await get_tree().process_frame

	# 分片 3：敌人刷新（取本层 RNG，ADR-5）
	var enemy_count := rng.randi_range(max_enemies / 2, max_enemies)
	for i in enemy_count:
		layout.enemy_spawns.append(_pick_enemy(rng, layout.rooms, i))

	# 分片 4：掉落表（取本层 RNG，ADR-5）
	layout.loot = _roll_loot(rng, floor_index)

	return layout

# ---- 保底模板层（R1 缓解 2：生成异常/超时不阻断流程）-----------------------
func fallback_template() -> Dictionary:
	# 预制的 1 个安全层（固定布局，无随机），仅作兜底
	return {
		"seed": -1, "floor": -1, "fallback": true,
		"rooms": [{"x":0,"y":0,"w":10,"h":10}],
		"corridors": [], "enemy_spawns": [{"x":5,"y":5,"tier":"mob"}],
		"loot": [{"kind":"heal","x":8,"y":8}]
	}

# ---- 生成入口（带超时/异常 → 保底）----------------------------------------
func generate_with_fallback(run_seed: int, floor_index: int, tier: DeviceTier) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var layout: Dictionary
	if floor_index < 0 or floor_index > 9999:
		layout = fallback_template()
	else:
		layout = await generate_floor(run_seed, floor_index, tier)
	var elapsed_ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("R1 generate floor=%d elapsed(逻辑,不含渲染)=%.3f ms" % [floor_index, elapsed_ms])
	return layout

# ---- 以下为逻辑子例程（纯数据，不触 Godot 渲染）----------------------------
func _place_room(rng: RandomNumberGenerator, idx: int) -> Dictionary:
	var w := rng.randi_range(4, 9)
	var h := rng.randi_range(4, 9)
	var x := rng.randi_range(0, 64 - w)
	var y := rng.randi_range(0, 64 - h)
	return {"x": x, "y": y, "w": w, "h": h, "idx": idx}

func _connect(a: Dictionary, b: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	# L 形走廊
	return {"ax": a.x + a.w/2, "ay": a.y + a.h/2, "bx": b.x + b.w/2, "by": b.y + b.h/2,
	        "bend": rng.randi() % 2}

func _pick_enemy(rng: RandomNumberGenerator, rooms: Array, i: int) -> Dictionary:
	var room: Dictionary = rooms[i % rooms.size()]
	var roll := rng.randf()
	var tier_name := "mob"
	if roll > 0.92: tier_name = "boss"
	elif roll > 0.75: tier_name = "elite"
	return {"x": room.x + rng.randi_range(0, room.w),
	        "y": room.y + rng.randi_range(0, room.h), "tier": tier_name}

func _roll_loot(rng: RandomNumberGenerator, floor_index: int) -> Array:
	var out := []
	var n := rng.randi_range(2, 5 + floor_index)
	for _i in n:
		var roll := rng.randf()
		var kind := "coin" if roll < 0.5 else ("rune" if roll < 0.8 else "spirit")
		out.append({"kind": kind, "r": rng.randf()})
	return out

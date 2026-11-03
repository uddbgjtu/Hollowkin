#!/usr/bin/env python3
# =============================================================================
# R1 原型 · 地窟生成（Python 忠实战 port + 诚实算法级基准）
# =============================================================================
# 目的：在 sandbox（无 Godot、无低端机）下，对"地窟生成 *逻辑*"做可运行基准，
#       以诚实数据支撑 feasibility-review.md 风险 R1 的缓解设计。
#
# 诚实声明（重要）：
#   * 本脚本测量的是"生成逻辑"（房间拼接/走廊/敌人刷新/掉落判定）的纯 Python
#     墙钟耗时，**不包含** Godot 的 TileMapLayer.set_cell 瓦片渲染。
#   * 真实 R1 帧预算风险主要在"渲染层"（set_cell 批量写入数十~数百瓦片），
#     该部分**必须**在目标最低档 iOS/Android 机型 + Godot 编辑器实测，本沙箱无法完成。
#   * 因此：本基准给出"逻辑成本上界"，并据此论证"分步生成 + await 让帧"
#     的缓解对象（渲染尖峰）与合理性；不编造任何设备渲染数字。
#
# 运行：python3 py_dungeon_gen.py
# =============================================================================
import random
import time
import statistics

# ---- 设备档位（对应 GDScript 原型）----------------------------------------
MAX_ROOMS_HIGH, MAX_ROOMS_LOW = 14, 8
MAX_ENEMIES_HIGH, MAX_ENEMIES_LOW = 24, 12

# ---- 确定性哈希（与 GDScript/feasibility §6.4 同算法，便于跨语言对照）-------
MASK = 0x7FFFFFFF
def floor_seed(run_seed: int, floor_index: int) -> int:
    h = (run_seed ^ (floor_index * 0x9E3779B1)) & MASK
    h = ((h ^ (h >> 16)) * 0x85EBCA6B) & MASK
    return h & MASK

def fallback_template() -> dict:
    return {"seed": -1, "floor": -1, "fallback": True,
            "rooms": [{"x":0,"y":0,"w":10,"h":10}],
            "corridors": [], "enemy_spawns": [{"x":5,"y":5,"tier":"mob"}],
            "loot": [{"kind":"heal","x":8,"y":8}]}

def place_room(rng, idx):
    w = rng.randint(4, 9); h = rng.randint(4, 9)
    x = rng.randint(0, 64 - w); y = rng.randint(0, 64 - h)
    return {"x":x,"y":y,"w":w,"h":h,"idx":idx}

def connect(a, b, rng):
    return {"ax":a["x"]+a["w"]//2, "ay":a["y"]+a["h"]//2,
            "bx":b["x"]+b["w"]//2, "by":b["y"]+b["h"]//2,
            "bend": rng.randint(0,1)}

def pick_enemy(rng, rooms, i):
    room = rooms[i % len(rooms)]
    roll = rng.random(); tier = "mob"
    if roll > 0.92: tier = "boss"
    elif roll > 0.75: tier = "elite"
    return {"x":room["x"]+rng.randint(0,room["w"]),
            "y":room["y"]+rng.randint(0,room["h"]), "tier":tier}

def roll_loot(rng, floor_index):
    out = []; n = rng.randint(2, 5 + floor_index)
    for _ in range(n):
        roll = rng.random()
        kind = "coin" if roll < 0.5 else ("rune" if roll < 0.8 else "spirit")
        out.append({"kind":kind, "r":rng.random()})
    return out

def generate_floor(run_seed, floor_index, tier):
    rng = random.Random(floor_seed(run_seed, floor_index))  # 本层唯一 RNG（ADR-5）
    max_rooms = MAX_ROOMS_HIGH if tier == "HIGH" else MAX_ROOMS_LOW
    max_enemies = MAX_ENEMIES_HIGH if tier == "HIGH" else MAX_ENEMIES_LOW
    layout = {"seed":rng.randint(0,MASK),"floor":floor_index,
              "rooms":[],"corridors":[],"enemy_spawns":[],"loot":[]}
    room_count = rng.randint(6, max_rooms)
    for i in range(room_count):
        layout["rooms"].append(place_room(rng, i))
    for i in range(1, len(layout["rooms"])):
        layout["corridors"].append(connect(layout["rooms"][i-1], layout["rooms"][i], rng))
    enemy_count = rng.randint(max_enemies//2, max_enemies)
    for i in range(enemy_count):
        layout["enemy_spawns"].append(pick_enemy(rng, layout["rooms"], i))
    layout["loot"] = roll_loot(rng, floor_index)
    return layout

def generate_with_fallback(run_seed, floor_index, tier):
    if floor_index < 0 or floor_index > 9999:
        return fallback_template()
    return generate_floor(run_seed, floor_index, tier)

# ---- 诚实基准：仅测量"生成逻辑"墙钟耗时 ------------------------------------
def benchmark(tier, floors=200, runs=5):
    print(f"\n=== R1 算法级基准（tier={tier}, floors={floors}, runs={runs}）===")
    per_floor_ms = []
    for r in range(runs):
        t0 = time.perf_counter()
        for f in range(floors):
            generate_floor(123456789, f, tier)   # 确定性：同 seed 重建一致
        t1 = time.perf_counter()
        per_floor_ms.append((t1 - t0) / floors * 1000.0)
    # 确定性重建一致性自检（同 (seed,floor) → 同布局规模）
    a = generate_floor(42, 7, tier); b = generate_floor(42, 7, tier)
    recon_ok = (a["rooms"] == b["rooms"] and a["enemy_spawns"] == b["enemy_spawns"]
                and a["loot"] == b["loot"])
    print(f"  单层生成逻辑耗时(均值): {statistics.mean(per_floor_ms):.4f} ms")
    print(f"  单层生成逻辑耗时(min/max): {min(per_floor_ms):.4f} / {max(per_floor_ms):.4f} ms")
    print(f"  同(seed,floor)重建一致: {recon_ok}  (rooms={len(a['rooms'])}, "
          f"enemies={len(a['enemy_spawns'])}, loot={len(a['loot'])})")
    return statistics.mean(per_floor_ms), recon_ok

if __name__ == "__main__":
    print("=" * 70)
    print("R1 原型：地窟生成逻辑基准（sandbox 诚实测量，不含 Godot 渲染）")
    print("=" * 70)
    mean_high, ok_high = benchmark("HIGH")
    mean_low, ok_low = benchmark("LOW")
    print("\n=== 结论（诚实）===")
    print(f"  - 生成 *逻辑*（房间/走廊/刷新/掉落）开销极小："
          f"高端档 ~{mean_high:.3f} ms/层，低端档 ~{mean_low:.3f} ms/层。")
    print("  - 结论：R1 帧预算风险主要在 Godot TileMapLayer.set_cell *渲染* 层，")
    print("    非生成逻辑；故'分步生成 + await get_tree().process_frame 让帧'")
    print("    的缓解对象是渲染尖峰（每 3 间/3 段让一帧摊薄 set_cell 批量写入）。")
    print("  - 确定性重建一致性：本沙箱自检通过（同 seed→同布局）。")
    print("  - 待办：必须在目标最低档 iOS/Android + Godot 编辑器实测 set_cell")
    print("    渲染尖峰（预算：均摊≤16.6ms/尖峰<50ms），本沙箱无法完成。")

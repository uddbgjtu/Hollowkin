# dungeon_gen_test.gd — Epic B 确定性单测（GUT）
# =====================================================================
# 验证：
#   - 同 (run_seed, floor_index, tier) 布局逐字节一致（ADR-1 重建 / ADR-5 种子化）；
#   - 不同 floor 必分叉；
#   - 非法 floor 切保底模板。
# 仅用 generate_sync（不依赖场景树），可在无 tree 下运行。
# 本文件位于 tests/，被 tools/ci/lint_no_global_random.py 排除（白名单 /tests/）。
# =====================================================================

extends GutTest

const DungeonGenerator = preload("res://src/core/dungeon_gen/dungeon_generator.gd")
const FallbackTemplate = preload("res://src/core/dungeon_gen/fallback_template.gd")


func test_same_seed_floor_is_deterministic():
	var g1 = DungeonGenerator.new().generate_sync(12345, 3, 0)
	var g2 = DungeonGenerator.new().generate_sync(12345, 3, 0)
	# 主断言：整层序列化逐字节一致
	assert_eq(JSON.stringify(g1), JSON.stringify(g2), "同 (seed,floor,tier) 应逐字节一致")
	# 冗余字段级断言：房间数 / 首房坐标 / 敌人数 / loot 数
	assert_eq(g1["rooms"].size(), g2["rooms"].size(), "房间数应一致")
	assert_eq(g1["rooms"][0]["x"], g2["rooms"][0]["x"], "首房 x 应一致")
	assert_eq(g1["enemy_spawns"].size(), g2["enemy_spawns"].size(), "敌人数应一致")
	assert_eq(g1["loot"].size(), g2["loot"].size(), "loot 数应一致")


func test_different_floor_differs():
	var a = DungeonGenerator.new().generate_sync(12345, 3, 0)
	var b = DungeonGenerator.new().generate_sync(12345, 4, 0)
	assert_ne(JSON.stringify(a), JSON.stringify(b), "不同 floor 应产生不同布局")


func test_invalid_floor_uses_fallback():
	var g = DungeonGenerator.new().generate_sync(12345, -1, 0)
	assert_true(g.has("fallback") and g["fallback"] == true, "非法 floor 应返回保底模板")
	assert_eq(g["seed"], -1, "保底 seed 应为 -1")
	assert_eq(g["floor"], -1, "保底 floor 应为 -1")

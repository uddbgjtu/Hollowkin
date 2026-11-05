# rng_service_test.gd — RNGService 确定性单测（Epic A1）
# ============================================================
# 承载 ADR-5（随机性唯一出口）的核心断言：
#   - 同 seed 必产生逐字节一致的序列；
#   - 不同 seed 必分叉；
#   - 按 (run_seed, floor_index) 派生的 floor_rng 同样确定性。
# 运行：GUT（res://tests/unit/）。本文件不进入全局随机 lint 扫描
#       （路径含 tests/，被 tools/ci/lint_no_global_random.py 排除）。
# ============================================================

extends GutTest

const RNGService = preload("res://src/core/rng/rng_service.gd")


func test_same_seed_same_sequence():
	var a := RNGService.new_floor_rng(12345)
	var b := RNGService.new_floor_rng(12345)
	for i in range(200):
		assert_eq(a.randi(), b.randi(), "同 seed 第 %d 次抽取应一致" % i)


func test_different_seed_diverges():
	var a := RNGService.new_floor_rng(1)
	var b := RNGService.new_floor_rng(2)
	assert_ne(a.randi(), b.randi(), "不同 seed 首抽应分叉")


func test_seed_from_string_stable():
	# 同一 slug 永远映射到同一 seed（与 bestiary §0.1 命名源协同）
	assert_eq(
		RNGService.seed_from_string("ember-wisp"),
		RNGService.seed_from_string("ember-wisp"),
		"同一字符串应派生同一 seed"
	)
	assert_ne(
		RNGService.seed_from_string("ember-wisp"),
		RNGService.seed_from_string("frost-wisp"),
		"不同字符串应派生不同 seed"
	)


func test_floor_rng_deterministic_per_layer():
	# 架构 §3.1：(run_seed, floor_index) 一一对应确定 RNG
	var r1 := RNGService.floor_rng(987654, 3)
	var r2 := RNGService.floor_rng(987654, 3)
	for i in range(200):
		assert_eq(r1.randi(), r2.randi(), "同 (run_seed,floor_index) 应一致 第 %d 次" % i)

	# 不同层必须分叉
	var r_other_floor := RNGService.floor_rng(987654, 4)
	assert_ne(r1.randi(), r_other_floor.randi(), "不同 floor_index 应分叉")


func test_floor_rng_independent_of_call_order():
	# 同一层的两次独立构造应等价（不依赖调用时序）
	var seq_a := []
	var ra := RNGService.floor_rng(42, 1)
	for i in range(50):
		seq_a.append(ra.randi())

	var seq_b := []
	var rb := RNGService.floor_rng(42, 1)
	for i in range(50):
		seq_b.append(rb.randi())

	assert_eq(seq_a, seq_b, "同 (run_seed,floor_index) 独立构造应等价序列")

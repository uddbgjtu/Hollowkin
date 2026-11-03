# ============================================================
# RNGService 确定性测试（模板，未启用）
# 位置：tests/templates/ —— 不进入 GUT 扫描目录，避免引用
#       尚未创建的 RNGService 导致解析失败。
# 启用方式：Epic A1 完成后，将本文件复制到 tests/unit/
#           并去掉下方注释即可。
# ============================================================
#
# extends GutTest
#
# const RNGService = preload("res://src/core/rng/rng_service.gd")
#
# func test_same_seed_same_sequence():
#     var a = RNGService.new_floor_rng(12345)
#     var b = RNGService.new_floor_rng(12345)
#     for i in range(100):
#         assert_eq(a.randi(), b.randi(), "同 seed 第 %d 次应一致" % i)
#
# func test_different_seed_diverges():
#     var a = RNGService.new_floor_rng(1)
#     var b = RNGService.new_floor_rng(2)
#     assert_ne(a.randi(), b.randi(), "不同 seed 应分叉")
#
# func test_global_random_blocked_by_lint():
#     # 本文件不得出现裸 randf()/randi()/randomize()
#     # （tools/ci/lint_no_global_random.py 会拦截，见 ADR-5）
#     pass

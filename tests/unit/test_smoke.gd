extends GutTest

# Phase 4 脚手架冒烟测试：仅用于验证 GUT harness 在目标机可达。
# 不依赖任何尚未创建的模块，确保 CI 在模块落地前即可跑通。
func test_harness_runs():
	assert_eq(1, 1, "GUT harness reachable")

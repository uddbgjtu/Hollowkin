# main.gd — Epic A 工程骨架入口（Main 场景根脚本）
# =====================================================================
# MVP 职责：启动即尝试读档；无档则生成新 run seed 并落入第 1 层。
# 真实地牢/战斗在后续 Epic（B/C/D）接入；此处只验证
# Save（ADR-1）与 RNGService（ADR-5）链路在 Autoload 下可跑通。
# =====================================================================

extends Node2D


func _ready() -> void:
	var run := SaveService.load_run()

	if run.is_empty():
		var seed := SaveService.new_run_seed()
		run = {"run_seed": seed, "floor_index": 1, "event_log": []}
		SaveService.save_run(seed, 1, [])
		print("[Main] 新 run 起始 run_seed=%d floor=1" % seed)
	else:
		print("[Main] 读档 run_seed=%d floor=%d event_log_len=%d" % [
			run["run_seed"], run["floor_index"], run["event_log"].size()
		])

	# 演示 ADR-5 链路：取本层 floor RNG（同 seed 必一致）。
	var rng := RNGService.floor_rng(run["run_seed"], run["floor_index"])
	print("[Main] floor RNG 首抽=%d（同 (run_seed,floor) 必一致）" % rng.randi())

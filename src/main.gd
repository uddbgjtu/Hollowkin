# main.gd — Epic A 工程骨架入口（Main 场景根脚本）
# =====================================================================
# MVP 职责：启动即尝试读档；无档则生成新 run seed 并落入第 1 层。
# 真实地牢/战斗在后续 Epic（B/C/D）接入；此处只验证
# Save（ADR-1）与 RNGService（ADR-5）链路在 Autoload 下可跑通。
# =====================================================================

extends Node2D

# RNGService 全静态 API：用 preload 取得脚本类后调用静态方法，
# 避免依赖全局 class_name 注册时机（与 save_service.gd 内部引用 RNG 的写法一致）。
const RNGServiceMod := preload("res://src/core/rng/rng_service.gd")


func _ready() -> void:
	# SaveService 以 autoload（键名 SaveSvc）形式存在：load_run/save_run 为实例方法，
	# new_run_seed 为静态方法，二者经 autoload 实例均可调用。
	var run := SaveSvc.load_run()

	if run.is_empty():
		var seed := SaveSvc.new_run_seed()
		run = {"run_seed": seed, "floor_index": 1, "event_log": []}
		SaveSvc.save_run(seed, 1, [])
		print("[Main] 新 run 起始 run_seed=%d floor=1" % seed)
	else:
		print("[Main] 读档 run_seed=%d floor=%d event_log_len=%d" % [
			run["run_seed"], run["floor_index"], run["event_log"].size()
		])

	# 演示 ADR-5 链路：取本层 floor RNG（同 seed 必一致）。
	var rng := RNGServiceMod.floor_rng(run["run_seed"], run["floor_index"])
	print("[Main] floor RNG 首抽=%d（同 (run_seed,floor) 必一致）" % rng.randi())

# save_service.gd — ADR-1 可恢复存档（层间落盘）
# =====================================================================
# 职责（architecture-doc.md §1.5 / ADR-1）：
#   - run 存档：save_run.cfg = { run_seed, floor_index, event_log }，体积极小（数百字节）。
#   - meta 存档：save_meta.cfg = { ember, activated_nodes }（永久进度，独立、不被 run 回退影响）。
#   - 仅「层间硬存档点」写入 run（E-A 拍板：层内中断 = 放弃本层，只靠层间落盘点）。
#   - NOTIFICATION_APPLICATION_PAUSED 同步落盘（仍须真机双保险，见 R2）。
#   - 读档损坏 → 丢弃 run、回退庇护所（永久进度 meta 不受影响）。
#
# 确定性纪律（ADR-5）：
#   - 本服务自身不产生任何随机；新 run_seed 经 RNGService 派生（禁全局随机）。
#   - 同 (run_seed, floor_index) 由 DungeonGen/Combat 从 floor RNG 确定性重建，
#     Save 只负责可靠地存/取 seed 与层号 + 记录无法由 seed 推导的玩家决策(event_log)。
# =====================================================================

class_name SaveService
extends Node

const RUN_PATH := "user://save_run.cfg"
const META_PATH := "user://save_meta.cfg"

# 内存镜像，用于 paused 同步落盘（仅回写已落过的档）
var _last_run: Dictionary = {}
var _last_meta: Dictionary = {}


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		_flush()


func _flush() -> void:
	if not _last_run.is_empty():
		_write_run(_last_run)
	if not _last_meta.is_empty():
		_write_meta(_last_meta)


# ----------------------------------------------------------------------
# 新 run seed（ADR-5 合规：不经全局随机，走 RNGService 派生）
# ----------------------------------------------------------------------
static func new_run_seed() -> int:
	# 用系统时间 + 进程 id 作熵源，经 RNGService 混出 32 位 seed。
	# 这是「初始」种子，本身不要求可复现；可复现的是之后由它派生的各层 RNG。
	return RNGService.derive_seed([int(Time.get_unix_time_from_system()), OS.get_process_id()])


# ----------------------------------------------------------------------
# RUN 存档（种子 + 层号 + 事件日志）
# ----------------------------------------------------------------------
# 仅应在层间硬存档点调用（进入/完成某一层后）。
func save_run(run_seed: int, floor_index: int, event_log: Array) -> bool:
	_last_run = {"run_seed": run_seed, "floor_index": floor_index, "event_log": event_log}
	return _write_run(_last_run)


func _write_run(d: Dictionary) -> bool:
	var cfg := ConfigFile.new()
	cfg.set_value("run", "run_seed", d["run_seed"])
	cfg.set_value("run", "floor_index", d["floor_index"])
	cfg.set_value("run", "event_log", d["event_log"])
	return cfg.save(RUN_PATH) == OK


# 读 run 档；无档或读取失败返回 {}（调用方据此新开 run）。
# 损坏（seed 非法/解析异常）则清空回庇护所并回 {}。
func load_run() -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(RUN_PATH) != OK:
		clear_run()
		return {}

	var out := {}
	out["run_seed"] = cfg.get_value("run", "run_seed", 0)
	out["floor_index"] = cfg.get_value("run", "floor_index", 1)
	out["event_log"] = cfg.get_value("run", "event_log", [])

	if typeof(out["run_seed"]) != TYPE_INT or int(out["run_seed"]) == 0:
		clear_run()
		return {}

	_last_run = out
	return out


func has_run() -> bool:
	return FileAccess.file_exists(RUN_PATH)


# 回退庇护所：丢弃 run（保留 meta，ADR-1 永久进度独立）。
func clear_run() -> void:
	if FileAccess.file_exists(RUN_PATH):
		DirAccess.remove(RUN_PATH)
	_last_run = {}


# ----------------------------------------------------------------------
# META 存档（永久进度：embers + 已激活灵脉节点）
# ----------------------------------------------------------------------
func save_meta(ember: int, activated_nodes: Array) -> bool:
	_last_meta = {"ember": ember, "activated_nodes": activated_nodes}
	return _write_meta(_last_meta)


func _write_meta(d: Dictionary) -> bool:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "ember", d["ember"])
	cfg.set_value("meta", "activated_nodes", d["activated_nodes"])
	return cfg.save(META_PATH) == OK


# 读 meta 档；无档返回零值（ember=0, 节点空）。
func load_meta() -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(META_PATH) != OK:
		return {"ember": 0, "activated_nodes": []}
	var out := {}
	out["ember"] = cfg.get_value("meta", "ember", 0)
	out["activated_nodes"] = cfg.get_value("meta", "activated_nodes", [])
	_last_meta = out
	return out

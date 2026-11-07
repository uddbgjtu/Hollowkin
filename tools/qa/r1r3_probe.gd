# r1r3_probe.gd — R1 / R3 PC 基线采集插桩与 19 列 CSV 输出（纯工具，零测量值）
# =====================================================================
# 用途：在 Windows Desktop（PC）的 Godot 4.3 导出构建中，对
#       归档 runbook docs/qa/archive/r1r3-device-test-plan.md §2 / §3 的方法学逐样本打点，
#       输出该文件 §5 规定的 19 列 CSV。
#
# 纪律（对齐 runbook §9 诚实性约束）：
#   - 本文件不含任何预置测量值；所有数值由 PC 运行时真实产生。
#   - 渲染 / 粒子 / 合计占帧比只标 blocked，绝不代填数字。a 阶段后技术层
#     （TileMapLayer / MultiMesh + 剔除 / CPUParticles2D）已接 E1 真实像素原图
#     （asset_source=E1_PNG8），故阻塞理由由 BLOCKED-BY-ASSET 改为 BLOCKED-BY-HARDWARE
#     （无头无 GPU 帧采集链，须 PC 窗口实测 G1）。
#   - 不使用全局随机（ADR-5）；采集种子固定，随机由生产模块经 RNGService 派生。
#   - 不声明 class_name，避免污染 .godot/global_script_class_cache.cfg（保持 40 类）。
#
# 用法：由 res://src/qa/probe_runner.gd 以 preload 实例化；本文件不单独运行。
# 定位：输出为「证据初稿」，verdict 是自动初判，最终判定以
#       docs/qa/evidence/_template/README.md §5 核验签字为准。
#
# PC 基线插桩补齐（2026-11-07）：
#   - 19 列汇总 CSV 结构不变；另输出逐样本长表 metrics_raw，使 §5 第 3 条的
#     mean / p95 可复算（此前只有汇总值，核验必然被退回）。
#   - 窗口 / 全屏 × 60 / 30fps 分轮：round_id 写入逐样本长表；每轮汇总与原始
#     证据按 round_id 分文件归档，禁止跨轮混算。
#   - 帧时间（GPU / CPU / 墙钟）只写逐样本长表并标 load_kind，不进 19 列
#     verdict：a 阶段后负载为 E1_PNG8，但无头无 GPU 帧采集链，不构成正式判据。
# =====================================================================

extends RefCounted

const CSV_COLUMNS := [
    "device_id", "os_version", "gpu_backend", "build_sha", "godot_version",
    "build_type", "thermal_state", "battery_pct", "background_policy",
    "metric", "unit", "samples", "mean", "p95", "target", "verdict",
    "evidence_path", "measured_at", "operator"
]

# 逐样本长表：一行一个真实样本，不写任何统计量，供独立脚本复算 mean / p95。
const RAW_COLUMNS := [
    "round_id", "metric", "sample_index", "value_ms", "unit",
    "load_kind", "note"
]

const LOAD_CPU_MODULE := "CPU_MODULE"
const LOAD_FRAME_DEBUG := "E1_PNG8_FRAME_NOT_A_BASELINE"

var _meta: Dictionary = {}
var _rows: Array = []
var _raw_rows: Array = []
var _round_id: String = "default"


func _init(p_meta: Dictionary) -> void:
    _meta = p_meta


# 实测项：samples 为 PC 运行时真实样本（单位 ms）；pass_limit 是目标预算（非测量值）。
# 初判取 P95（较严口径）；30fps 档需另跑一轮，最终判定归 §6 核验人。
func set_round(p_round_id: String) -> void:
    _round_id = p_round_id


func round_id() -> String:
    return _round_id


# 逐样本落盘：只记原始值，不写 mean / p95，避免「用统计量自证统计量」。
func record_samples(metric: String, samples: Array, unit: String,
        load_kind: String, p_note: String = "") -> void:
    for i in range(samples.size()):
        _raw_rows.append({
            "round_id": _round_id,
            "metric": metric,
            "sample_index": str(i),
            "value_ms": "%.6f" % float(samples[i]),
            "unit": unit,
            "load_kind": load_kind,
            "note": p_note
        })


func to_raw_csv() -> String:
    var out := _join(RAW_COLUMNS) + "\n"
    for row in _raw_rows:
        var fields: Array = []
        for c in RAW_COLUMNS:
            fields.append(str(row.get(c, "")))
        out += _join(fields) + "\n"
    return out


func raw_row_count() -> int:
    return _raw_rows.size()


func add_measured(metric: String, unit: String, samples: Array, target: String, pass_limit: float) -> void:
    record_samples(metric, samples, unit, LOAD_CPU_MODULE, "19 列汇总行 %s" % metric)
    var st := _stats(samples)
    var verdict := "pass" if float(st["p95"]) <= pass_limit else "fail"
    _emit(metric, unit, st["n"], "%.4f" % float(st["mean"]), "%.4f" % float(st["p95"]), target, verdict)


# 判据为布尔/设计约束（如「不阻断流程」「上限下调」）的实测项。
func add_measured_verdict(metric: String, unit: String, samples: Array, target: String, verdict: String) -> void:
    record_samples(metric, samples, unit, LOAD_CPU_MODULE, "19 列汇总行 %s" % metric)
    var st := _stats(samples)
    _emit(metric, unit, st["n"], "%.4f" % float(st["mean"]), "%.4f" % float(st["p95"]), target, verdict)


# 帧时间样本只作链路证据：不产生 19 列汇总行、不参与 verdict。
func record_frame_samples(metric: String, samples: Array, p_note: String) -> void:
    record_samples(metric, samples, "ms", LOAD_FRAME_DEBUG, p_note)


# 前置依赖未满足项：数值栏一律留空，绝不代填。
func add_blocked(metric: String, unit: String, target: String, reason: String) -> void:
    _emit(metric, unit, "", "", "", target, "blocked", "—")
    note("%s: blocked (%s)" % [metric, reason])


# 补充证据（数量、回退成功率等）走日志，不混入 CSV 的数值列。
func note(text: String) -> void:
    print("METRIC_NOTE|" + text)


func _stats(samples: Array) -> Dictionary:
    var n: int = samples.size()
    if n == 0:
        return {"n": 0, "mean": 0.0, "p95": 0.0}
    var total := 0.0
    var sorted: Array = samples.duplicate()
    for v in samples:
        total += float(v)
    sorted.sort()
    var idx: int = int(ceil(0.95 * float(n))) - 1
    if idx < 0:
        idx = 0
    if idx >= n:
        idx = n - 1
    return {"n": n, "mean": total / float(n), "p95": float(sorted[idx])}


func _emit(metric: String, unit: String, samples_s, mean_s, p95_s, target: String, verdict: String, evidence = null) -> void:
    var row := {
        "metric": metric,
        "unit": unit,
        "samples": str(samples_s),
        "mean": str(mean_s),
        "p95": str(p95_s),
        "target": target,
        "verdict": verdict,
        "evidence_path": _meta.get("evidence_path", "") if evidence == null else str(evidence)
    }
    _rows.append(row)


func _field(row: Dictionary, key: String) -> String:
    if row.has(key):
        return str(row[key])
    return str(_meta.get(key, ""))


func _join(fields: Array) -> String:
    var out := ""
    for i in range(fields.size()):
        if i > 0:
            out += ","
        out += _csv_escape(str(fields[i]))
    return out


func _csv_escape(s: String) -> String:
    if s.contains(",") or s.contains("\"") or s.contains("\n"):
        return "\"" + s.replace("\"", "\"\"") + "\""
    return s


func to_csv() -> String:
    var out := _join(CSV_COLUMNS) + "\n"
    for row in _rows:
        var fields: Array = []
        for c in CSV_COLUMNS:
            fields.append(_field(row, c))
        out += _join(fields) + "\n"
    return out


func print_rows() -> void:
    print("METRIC|" + _join(CSV_COLUMNS))
    for row in _rows:
        var fields: Array = []
        for c in CSV_COLUMNS:
            fields.append(_field(row, c))
        print("METRIC|" + _join(fields))


func row_count() -> int:
    return _rows.size()

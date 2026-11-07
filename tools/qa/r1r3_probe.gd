# r1r3_probe.gd — R1 / R3 PC 基线采集插桩与 19 列 CSV 输出（纯工具，零测量值）
# =====================================================================
# 用途：在 Windows Desktop（PC）的 Godot 4.3 导出构建中，对
#       归档 runbook docs/qa/archive/r1r3-device-test-plan.md §2 / §3 的方法学逐样本打点，
#       输出该文件 §5 规定的 19 列 CSV。
#
# 纪律（对齐 runbook §9 诚实性约束）：
#   - 本文件不含任何预置测量值；所有数值由 PC 运行时真实产生。
#   - 渲染 / 粒子 / 合计占帧比只标 blocked，绝不代填数字。Wave 3b 后技术层
#     （TileMapLayer / MultiMesh + 剔除 / CPUParticles2D）已就位，但纹理仍是
#     DEBUG_PLACEHOLDER，故阻塞理由为 BLOCKED-BY-ASSET（E1 原图未产出）。
#   - 不使用全局随机（ADR-5）；采集种子固定，随机由生产模块经 RNGService 派生。
#   - 不声明 class_name，避免污染 .godot/global_script_class_cache.cfg（保持 40 类）。
#
# 用法：由 res://src/qa/probe_runner.gd 以 preload 实例化；本文件不单独运行。
# 定位：输出为「证据初稿」，verdict 是自动初判，最终判定以
#       docs/qa/evidence/_template/README.md §5 核验签字为准。
# =====================================================================

extends RefCounted

const CSV_COLUMNS := [
    "device_id", "os_version", "gpu_backend", "build_sha", "godot_version",
    "build_type", "thermal_state", "battery_pct", "background_policy",
    "metric", "unit", "samples", "mean", "p95", "target", "verdict",
    "evidence_path", "measured_at", "operator"
]

var _meta: Dictionary = {}
var _rows: Array = []


func _init(p_meta: Dictionary) -> void:
    _meta = p_meta


# 实测项：samples 为 PC 运行时真实样本（单位 ms）；pass_limit 是目标预算（非测量值）。
# 初判取 P95（较严口径）；30fps 档需另跑一轮，最终判定归 §6 核验人。
func add_measured(metric: String, unit: String, samples: Array, target: String, pass_limit: float) -> void:
    var st := _stats(samples)
    var verdict := "pass" if float(st["p95"]) <= pass_limit else "fail"
    _emit(metric, unit, st["n"], "%.4f" % float(st["mean"]), "%.4f" % float(st["p95"]), target, verdict)


# 判据为布尔/设计约束（如「不阻断流程」「上限下调」）的实测项。
func add_measured_verdict(metric: String, unit: String, samples: Array, target: String, verdict: String) -> void:
    var st := _stats(samples)
    _emit(metric, unit, st["n"], "%.4f" % float(st["mean"]), "%.4f" % float(st["p95"]), target, verdict)


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

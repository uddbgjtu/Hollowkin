#!/usr/bin/env python
"""核验 PC 基线证据：从逐样本长表复算 mean / p95，与 19 列汇总逐行比对。

对应 docs/qa/evidence/_template/README.md §5 第 3 条。纯只读，不修改任何证据文件。

用法：
    python tools/qa/verify_probe_evidence.py <summary.csv> <metrics_raw.csv>

退出码 0 = 复算一致 / 结构合规；1 = 存在不一致或臆造风险。
"""
import csv
import io
import math
import sys
from collections import defaultdict

SUMMARY_COLUMNS = [
    "device_id", "os_version", "gpu_backend", "build_sha", "godot_version",
    "build_type", "thermal_state", "battery_pct", "background_policy",
    "metric", "unit", "samples", "mean", "p95", "target", "verdict",
    "evidence_path", "measured_at", "operator",
]
RAW_COLUMNS = ["round_id", "metric", "sample_index", "value_ms", "unit", "load_kind", "note"]

FRAME_LOAD = "E1_PNG8_FRAME_NOT_A_BASELINE"
BLOCKED_NUMERIC = ("", "—")
# 汇总保留 4 位小数、逐样本保留 6 位，两次舍入合计的合法偏差 < 1 个 4 位小数单位。
# 值恰落在 x.xxxx50 边界时差异正好是 0.00005，用 0.0001 才不会把舍入误判为臆造；
# 任何 >= 0.0001 的不一致仍会被抓出，远超舍入噪声。
TOL = 0.0001


def read_csv(path):
    with io.open(path, "r", encoding="utf-8-sig", newline="") as f:
        rows = list(csv.reader(f))
    if not rows:
        raise SystemExit("FAIL 空文件: %s" % path)
    return rows[0], rows[1:]


def stats(values):
    n = len(values)
    if n == 0:
        return 0, 0.0, 0.0
    ordered = sorted(values)
    idx = max(0, min(n - 1, int(math.ceil(0.95 * n)) - 1))
    return n, sum(values) / n, ordered[idx]


def main(argv):
    if len(argv) != 3:
        print(__doc__)
        return 1

    s_head, s_rows = read_csv(argv[1])
    r_head, r_rows = read_csv(argv[2])
    errors = []
    warns = []

    if s_head != SUMMARY_COLUMNS:
        errors.append("汇总表头不是约定的 19 列: %s" % s_head)
    if r_head != RAW_COLUMNS:
        errors.append("逐样本表头不是约定的 7 列: %s" % r_head)
    if errors:
        for e in errors:
            print("FAIL", e)
        return 1

    raw = defaultdict(list)
    rounds = set()
    frame_metrics = set()
    for r in r_rows:
        if len(r) != len(RAW_COLUMNS):
            errors.append("逐样本行列数异常: %s" % r)
            continue
        row = dict(zip(RAW_COLUMNS, r))
        rounds.add(row["round_id"])
        if row["load_kind"] == FRAME_LOAD:
            frame_metrics.add(row["metric"])
            continue  # 帧时间不对应 19 列汇总行
        try:
            raw[(row["round_id"], row["metric"])].append(float(row["value_ms"]))
        except ValueError:
            errors.append("逐样本 value_ms 非数值: %s" % row)

    summary_metrics = set()
    checked = 0
    for r in s_rows:
        if len(r) != len(SUMMARY_COLUMNS):
            errors.append("汇总行列数异常: %s" % r)
            continue
        row = dict(zip(SUMMARY_COLUMNS, r))
        metric = row["metric"]
        summary_metrics.add(metric)

        if row["verdict"] == "blocked":
            for col in ("samples", "mean", "p95"):
                if row[col] not in BLOCKED_NUMERIC:
                    errors.append("blocked 行 %s 的数值栏 %s 非空: %r" % (metric, col, row[col]))
            continue

        # 汇总表不含 round_id；要求所有轮次的该 metric 样本数一致才可无歧义复算。
        keys = [k for k in raw if k[1] == metric]
        if not keys:
            errors.append("汇总行 %s 在逐样本长表中无样本" % metric)
            continue
        for key in keys:
            values = raw[key]
            n, mean, p95 = stats(values)
            if n != int(row["samples"]):
                errors.append("%s / round=%s 样本数不一致: 汇总 %s vs 复算 %d"
                              % (metric, key[0], row["samples"], n))
            for col, computed in (("mean", mean), ("p95", p95)):
                try:
                    declared = float(row[col])
                except ValueError:
                    errors.append("%s 的 %s 非数值: %r" % (metric, col, row[col]))
                    continue
                if abs(declared - computed) > TOL:
                    errors.append("%s / round=%s 的 %s 不一致: 汇总 %.4f vs 复算 %.6f"
                                  % (metric, key[0], col, declared, computed))
            checked += 1

    for metric in frame_metrics:
        if metric in summary_metrics:
            errors.append("帧时间样本 %s 出现在 19 列汇总行（应只作链路证据）" % metric)

    for r in s_rows:
        if len(r) != len(SUMMARY_COLUMNS):
            continue
        row = dict(zip(SUMMARY_COLUMNS, r))
        if row["build_sha"] in ("", "UNSET"):
            warns.append("build_sha 未标定（正式采集前须填 git SHA）")
            break
    for r in s_rows:
        if len(r) != len(SUMMARY_COLUMNS):
            continue
        row = dict(zip(SUMMARY_COLUMNS, r))
        for col in ("thermal_state", "battery_pct", "background_policy", "operator"):
            if row[col] == "MANUAL_REQUIRED":
                warns.append("%s 仍为 MANUAL_REQUIRED，须人工补齐" % col)
                break
        else:
            continue
        break

    print("汇总行          : %d（可测 %d / blocked %d）"
          % (len(s_rows), len([r for r in s_rows if len(r) == 19 and r[15] != "blocked"]),
             len([r for r in s_rows if len(r) == 19 and r[15] == "blocked"])))
    print("逐样本行        : %d" % len(r_rows))
    print("轮次            : %s" % (", ".join(sorted(rounds)) or "(none)"))
    print("复算比对        : %d 组" % checked)
    print("帧时间证据指标  : %s" % (", ".join(sorted(frame_metrics)) or "(none)"))
    for w in sorted(set(warns)):
        print("WARN", w)
    if errors:
        for e in errors:
            print("FAIL", e)
        print("RESULT: FAIL (%d)" % len(errors))
        return 1
    print("RESULT: PASS（mean / p95 可由逐样本复算，blocked 数值栏为空）")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

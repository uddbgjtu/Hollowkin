# R1 / R3 PC 基线四轮采集 · 纯 SHA 终版交付清单

> **构建**：`674542194592c39acf27cf3f6ac28ba572c1c5da`（`6745421`），工作树干净，`--export-release`，`build_type=release`。
> **状态**：四轮真实实跑、逐样本可复算、人工字段已按客观读数补齐、§5 机器可核验项通过（见 `verification.md`）。
> **边界**：核验签字仍待主理人；R1 / R3 仍 **CONCERNS**；`CONCERNS → PASS` 属独立审批。

## 1. 四轮结果

| round_id | 窗口 | 目标档 | 实测 `frame_wall_ms` 均值 | 帧样本 | GPU 非零 | 归档版复算 |
|---|---|---|---|---|---|---|
| `windowed_60_release` | windowed | 60fps | 16.6667（预期 16.6667） | 120 | 120/120 | PASS |
| `fullscreen_60_release` | fullscreen | 60fps | 16.6657 | 120 | 120/120 | PASS |
| `windowed_30_release` | windowed | 30fps | 33.3333 | 120 | 120/120 | PASS |
| `fullscreen_30_release` | fullscreen | 30fps | 33.3352 | 120 | 120/120 | PASS |

`ALL_ROUNDS_OK=True`；四轮 `run_exit=0`、`console.log` 无 `SCRIPT ERROR`/`ERROR`、`PROBE_SUMMARY` 均 `rows=10 err=0 raw_err=0`。全屏档的 16.6657 / 33.3352 是真实测量噪声，非人为取整。

## 2. 文件清单

| 路径 | 内容 |
|---|---|
| `MANIFEST.md` / `environment.md` / `verification.md` | 交付清单、客观环境读数、§5 核验记录 |
| `build_provenance.json` | 纯 SHA、工作树干净证明、main_scene 临时切换记录 |
| `export_release.log` / `collection_manifest.json` / `finalize_result.json` | 导出日志、四轮机器可校验结果、归档版复算结果 |
| `<round_id>/metrics_original.csv` | **采集原始输出，逐字节保留**（审计链） |
| `<round_id>/metrics.csv` | 归档版：只补齐 8 个元数据列，数值列与原始逐字段一致 |
| `<round_id>/metrics_raw.csv` | 逐样本长表，830 行/轮（470 CPU + 360 帧） |
| `<round_id>/console.log` | 引擎日志（含 `METRIC|` / `METRIC_NOTE|` / `FRAME_CAPTURE|` / `ROUND|` / `PROBE_SUMMARY|`） |
| `<round_id>/verify.log` / `verify_archived.log` | 原始 / 归档版两次复算结果 |
| `<round_id>/stdout.log` | GUI exe stdout（通常为空，以 `--log-file` 为准） |
| `hollowkin_probe.exe` / `.pck` | 本机构建产物 81MB / 192896 bytes，**不入仓** |

补齐的人工字段（依据 `environment.md`，无臆造）：`device_id=pc_win_01`、`gpu_backend=Vulkan`、`build_sha=<纯 SHA>`、`thermal_state=N/A (WMI 无温度/降频读数; 电源计划=平衡; 未做降频监控)`、`battery_pct=92->95 (AC charging; session-level)`、`background_policy=电源计划=平衡; 未做后台进程隔离; WorkBuddy 会话与常规后台服务在运行`、`operator=WorkBuddy Agent (automated collection; human sign-off pending)`、`evidence_path=docs/qa/evidence/...`。

## 3. 预采集批次的关系

`C:/tmp/hollowkin_baseline_20261107/` 为上一批**预采集**：HEAD `91552b2` + 9 个未提交插桩改动，标定为 `91552b2+LOCAL_UNCOMMITTED`，按 §5 第 2 条不可签字。本批次在插桩改动提交后以纯 SHA 重新导出并重跑四轮，取代其作为基线候选；旧目录保留作审计链，**两批数据不混算、不合并**。

## 4. §5 第 5 条归档复核

按 §4 入仓后逐轮检查 `evidence_path` 存在性与轮次对应关系，结果记于此：

四轮归档已完成（§4），`archive_check.json` 逐轮确认 `file_exists=True` / `round_matches=True` / `single_path_per_round=True`，共 36 个证据文件入仓。 详见 `archive_check.json`。

## 5. 后续动作与待办

- **归档入仓**：四轮按 `docs/qa/evidence/pc_win_01/<sha>/<round_id>/` 落盘；模板 `measurement_template.csv` 只回填主档 `windowed_60_release` 的 5 行可测值，5 行 blocked 保持空白，四轮不混算。
- **人工签字**：`verification.md` 的六条为机器可核验结果，核验签字仍待主理人；`operator` 如需改填主理人请告知。
- **受限项**：电池未按轮记录首尾、无温控监控、帧时间为 DEBUG_PLACEHOLDER 负载，详见 `verification.md`。
- **仍未闭环**：ADR-4 E1 真实像素原图未产出，5 项渲染 / 粒子指标仍 `BLOCKED-BY-ASSET`；R1 / R3 仍 CONCERNS。
- **未 push**：插桩提交 `6745421` 目前仅在本地（ahead 1）；是否推送由主理人决定。

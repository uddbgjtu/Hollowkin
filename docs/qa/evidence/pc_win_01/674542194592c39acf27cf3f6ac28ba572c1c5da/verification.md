# §5 核验记录（纯 SHA 终版批次，2026-11-07）

> **性质**：机器可核验项的逐条复核结果。**人工签字仍待主理人**，本文件不构成
> `CONCERNS → PASS` 翻转；R1 / R3 仍为 **CONCERNS**。
> 依据：`docs/qa/evidence/_template/README.md §5` 六条。

## 被核验数据（四轮 19 列归档版，mean / p95，单位 ms）

| round_id | r1_logic_elapsed | r1_fallback_switch | r1_low_tier_density | r3_input_arbitration | r3_ai_tick |
|---|---|---|---|---|---|
| windowed_60_release | 0.0819 / 0.1220 | 0.0033 / 0.0040 | 0.0349 / 0.0520 | 0.0016 / 0.0020 | 0.0120 / 0.0160 |
| fullscreen_60_release | 0.0680 / 0.0970 | 0.0032 / 0.0050 | 0.0338 / 0.0480 | 0.0015 / 0.0020 | 0.0154 / 0.0260 |
| windowed_30_release | 0.0589 / 0.0810 | 0.0031 / 0.0040 | 0.0346 / 0.0510 | 0.0016 / 0.0020 | 0.0145 / 0.0250 |
| fullscreen_30_release | 0.0624 / 0.0860 | 0.0034 / 0.0040 | 0.0455 / 0.0720 | 0.0018 / 0.0020 | 0.0116 / 0.0150 |

四轮共 10 行/轮：5 行可测（自动初判 `pass`）+ 5 行 `blocked`。逐样本长表每轮 830 行（470 CPU 模块 + 360 帧时间）。

## 六条核验

| # | 规则 | 结果 | 依据 |
|---|---|---|---|
| 1 | 机器规格与 `os_version` / `gpu_backend` 一致，属约定 PC 档位 | **PASS** | `environment.md`：Windows 11 build 26100 / i7-1185G7 / 31.75GB / Iris Xe + MX450；引擎日志 Vulkan 1.3.205 Forward+。归档版 `gpu_backend=Vulkan` 已按日志核对改写，非沿用 `forward_plus` 代理值 |
| 2 | `build_sha` 与被测构建一致、`4.3.stable`、debug/release 未混算 | **PASS** | `build_provenance.json`：导出前后工作树均干净，纯 SHA `674542194592c39acf27cf3f6ac28ba572c1c5da`；唯一构建期差异 `run/main_scene` 临时切换已记录并恢复；四轮 CSV `build_type=release` |
| 3 | 单位 ms、样本达下限、mean / p95 复算一致 | **PASS** | 4 份 `verify_archived.log` 均 `RESULT: PASS`、无 WARN；样本 100 / 10 / 60 / 100 / 200 达 §3 下限；逐样本长表 830 行/轮可独立复算 |
| 4 | `verdict` 与数值及 `target` 一致，`blocked` 数值栏为空 | **PASS** | 初判阈值：`r1_logic_elapsed` p95≤1.0、`r3_input_arbitration` p95≤0.5、`r3_ai_tick` p95≤1.66，实测 p95 最大 0.1220 / 0.0020 / 0.0260，余量充足；2 项布尔判据由 `fallback_flag_true=10/10` 与 LOW≤HIGH 房间/敌人数支撑（见 `console.log`）。5 行 blocked 的 `samples/mean/p95` 四轮均为空 |
| 5 | `evidence_path` 指向真实存在的原始证据、轮次可对应 | **PASS（归档后复核）** | 归档版已写为 `docs/qa/evidence/pc_win_01/<sha>/<round_id>/metrics.csv`；按 §4 落盘后逐轮检查文件存在性与轮次对应关系，结果见文末补记 |
| 6 | 无臆造值、无【PC 基线待实测】占位残留 | **PASS** | `metrics_original.csv` 逐字节保留采集原始输出；归档版只改 8 个元数据列，`metric/unit/samples/mean/p95/target/verdict` 与原始逐字段一致（程序化比对 `numeric_columns_unchanged=True`）；无占位符、无 headless smoke 或 `cap_probe` 试跑数据混入 |

## 受限项（如实列出，不掩饰）

- **`battery_pct`**：三次会话级只读读数 92% → 93% → 95%（AC 充电），**未按轮记录首尾电量**，与 §1「笔记本填首尾电量」有差距，按受限数据处理；不影响 5 项 CPU 侧数值。
- **`thermal_state`**：WMI 未提供温度 / 降频读数，未做降频监控，填 `N/A` 并注明电源计划=平衡；不声称「未发生降频」。
- **`operator`**：填 `WorkBuddy Agent (automated collection; human sign-off pending)`，如实标注自动化采集执行者，**不是主理人签字**；核验签字仍需人工完成，可由主理人改填。
- **帧时间**：`load_kind=DEBUG_PLACEHOLDER_FRAME_NOT_A_BASELINE`，只作链路证据，不进 19 列、不参与 verdict。GPU 耗时极小反映 Probe 近乎空负载，不能推断正式渲染开销达标。
- **5 项渲染 / 粒子指标**仍 `BLOCKED-BY-ASSET`（E1 原图未产出），数值栏空白；`r3_total_frame_share` 未拼部分和。

## 结论

四轮 PC 窗口 / 全屏 × 60 / 30fps 采集数据**机器可核验项通过**，5 项 CPU 侧可测分项的 mean / p95 可用于汇总回填；四轮互不混算，主档取 `windowed_60_release`。

**本记录不等于质量门判定**：R1 / R3 仍为 **CONCERNS**，5 项渲染 / 粒子 / 合计占帧比仍缺正式资产与正式负载实测。`CONCERNS → PASS` 需要 ADR-4 E1 真实像素资产到位、核验签字与主理人独立审批，与本次采集无关。

---

*归档后复核补记：四轮归档已完成（§4），`archive_check.json` 逐轮确认 `file_exists=True` / `round_matches=True` / `single_path_per_round=True`，共 36 个证据文件入仓。*

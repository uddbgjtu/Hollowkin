# PC 帧预算基线证据落区 · pc_win_02（a 阶段后 · E1_PNG8 已集成）

> **承接**：`pc_win_01`（纯 SHA `6745421`，四轮采集：5 行 CPU 侧可测 + 5 行渲染 blocked）。
> **本批目的**：a 阶段（提交 `9a2270d`）已将 ADR-4 E1 真实 PNG-8 接入渲染层（`asset_source=E1_PNG8`），解除 `BLOCKED-BY-ASSET`；本批须由**带 GPU 的 PC** 窗口 / 全屏实测，闭合 G1。
> **纪律**：本目录只承载真实 PC 实测证据；headless / GUT / 仿真数据不得回填。R1/R3 不因采集完成或 CI 全绿自动翻转，翻转须 G1（实测）+ G2（核验签字）+ G3（独立审批）三件套。

---

## 0. 与 pc_win_01 的差异（关键）

- **渲染层真实负载**：`DEBUG_PLACEHOLDER` → `E1_PNG8`（资产纪律标记已翻转，a 阶段提交 `9a2270d`）。
- **探针行为**（`src/qa/probe_runner.gd::_collect_render_metrics`）：
  - `headless`（无窗口 / 无 GPU 帧采集链）：5 项渲染指标仍 `blocked`（`BLOCKED-BY-HARDWARE`），与 `pc_win_01` 同口径。
  - **真实 GPU PC**（`_frame_available` 为真）：`r1_render_mean` / `r1_render_p95_spike` / `r3_total_frame_share` 三项由聚合帧 GPU 时间（`frame_gpu_ms`）派生为 `measured`；`r3_entity_render` / `r3_particles` 仍 `blocked`（`BLOCKED-BY-METHOD`，须子系统 Δ 隔离法，见 §4）。
- **结论**：本批 G1 可闭合 **R1** 的渲染预算；**R3** 仍须 `r3_entity_render` / `r3_particles` 实测后方可闭合（见 §4）。

---

## 1. 落区结构（镜像 pc_win_01）

```
pc_win_02/<build_sha>/
  MANIFEST.md
  environment.md
  build_provenance.json
  collection_manifest.json
  windowed_60_release/   {metrics.csv, metrics_raw.csv, console.log, stdout.log, verify.log, verify_archived.log}
  windowed_30_release/   {同上}
  fullscreen_60_release/ {同上}
  fullscreen_30_release/ {同上}
```

`<build_sha>` = 实测构建的 `git rev-parse HEAD`（a 阶段后为 `9a2270d`，或其后含 G1 回填的提交）。

---

## 2. 采集步骤（post-a 阶段）

1. **导出前**：把 `src/qa/probe_runner.gd` 顶部 `PROBE_BUILD_SHA` 改为 `git rev-parse HEAD`（或用 `--build-sha=` 覆盖，免改源码）；把 `project.godot` 的 `run/main_scene` 临时指向 `res://src/qa/probe_runner.tscn`。
2. **导出** Windows Desktop（release）exe。
3. **PC 上分别跑四轮**（预热 ≥5s 后开始采集；每轮单独进程，禁止跨轮混算）：
   - `exe -- --round-id=windowed_60_release   --window-mode=windowed   --fps-cap=60 --frame-samples=120 --warmup-frames=30`
   - `exe -- --round-id=windowed_30_release   --window-mode=windowed   --fps-cap=30 --frame-samples=120 --warmup-frames=30`
   - `exe -- --round-id=fullscreen_60_release --window-mode=fullscreen --fps-cap=60 --frame-samples=120 --warmup-frames=30`
   - `exe -- --round-id=fullscreen_30_release --window-mode=fullscreen --fps-cap=30 --frame-samples=120 --warmup-frames=30`
4. **取回**每轮的 `user://hollowkin_probe_metrics_<round>.csv`（19 列汇总）与 `..._raw_<round>.csv`（7 列逐样本），连同 console / stdout 日志，按 §1 结构落盘。
5. **手工补齐** `MANUAL_REQUIRED` 字段（`thermal_state` / `battery_pct` / `background_policy` / `operator`），`gpu_backend` 按 PC 实际（Vulkan / D3D12 / GLES3）核对，勿以脚本代理值充当已填。
6. **逐轮核验**：`python tools/qa/verify_probe_evidence.py <metrics.csv> <metrics_raw.csv>`，须 `RESULT: PASS`（mean / p95 由逐样本复算一致、blocked 数值栏为空、手动字段齐全）。
7. **回填治理包**：将 §3 映射的 5 项指标 mean / p95 / 样本数 / 判定写入 `docs/architecture/r1r3-verification-approval.md` §2.1，并按轮次分文件归档（禁跨轮混算）。
8. **复位**：测完把 `main_scene` 改回 `res://src/main.tscn`。

---

## 3. 回填映射（探针输出 → 治理包 §2.1）

| 治理包指标 | 探针 metric | 来源 / 阈值 |
|---|---|---|
| `r1_render_mean` | `r1_render_mean` | 19 列 mean（frame_gpu_ms 均值），target ≤ 16.6 |
| `r1_render_p95_spike` | `r1_render_p95_spike` | 19 列 p95（frame_gpu_ms），target < 50 |
| `r3_total_frame_share` | `r3_total_frame_share` | 19 列 mean（frame_gpu_ms 均值），target < 9.16（55%） |
| `r3_entity_render` | （本批仍 `blocked`） | 须 §4 Δ 隔离法 |
| `r3_particles` | （本批仍 `blocked`） | 须 §4 Δ 隔离法 |

> 帧时间样本（`frame_gpu_ms` / `frame_cpu_ms` / `frame_wall_ms`）只写逐样本长表、标 `E1_PNG8_FRAME_NOT_A_BASELINE`，不进 19 列 verdict，仅作链路证据。

---

## 4. 已知缺口（R3 闭合前置，须补测量方法学）

`r3_entity_render` / `r3_particles` 为**子系统级** GPU 时间；Godot `RenderingServer` 不暴露按 mesh / 粒子的单独计时。须实现「**层显隐 Δ 隔离**」测量法（分别仅渲染实体层、仅渲染粒子层，测各自帧 GPU 时间差）方可实测；当前未仪表化，故标 `BLOCKED-BY-METHOD`。

**该缺口闭合前，R3 不能由 CONCERNS 升 PASS**——即使本批 R1 渲染预算已实测通过。

---

## 5. 诚实性约束（沿用 _template）

- 严禁把 GUT tick 数 / Python 仿真 / headless 自检输出换算成设备 ms 耗时。
- 严禁抄目标预算充当实测值。
- G1 实测数据**只**来自真实 GPU PC 窗口 / 全屏采集；headless 输出不得回填本表。
- R1/R3 CONCERNS 不因平台变更、导出成功、采集完成、数据回填或 CI 全绿自动翻转。

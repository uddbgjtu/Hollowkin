# PC 帧预算基线证据落区 · pc_win_02（a 阶段后 · E1_PNG8 已集成）

> **承接**：`pc_win_01`（纯 SHA `6745421`，四轮采集：5 行 CPU 侧可测 + 5 行渲染 blocked）。
> **本批目的**：a 阶段（提交 `9a2270d`）已将 ADR-4 E1 真实 PNG-8 接入渲染层（`asset_source=E1_PNG8`），解除 `BLOCKED-BY-ASSET`；本批须由**带 GPU 的 PC** 窗口 / 全屏实测，闭合 G1。
> **纪律**：本目录只承载真实 PC 实测证据；headless / GUT / 仿真数据不得回填。R1/R3 不因采集完成或 CI 全绿自动翻转，翻转须 G1（实测）+ G2（核验签字）+ G3（独立审批）三件套。

---

## 0. 与 pc_win_01 的差异（关键）

- **渲染层真实负载**：`DEBUG_PLACEHOLDER` → `E1_PNG8`（资产纪律标记已翻转，a 阶段提交 `9a2270d`）。
- **探针行为**（`src/qa/probe_runner.gd::_collect_render_metrics`）：
  - `headless`（无窗口 / 无 GPU 帧采集链）：5 项渲染指标仍 `blocked`（`BLOCKED-BY-HARDWARE`），与 `pc_win_01` 同口径。
  - **真实 GPU PC**（`_frame_available` 为真）：构建 E1 真实渲染负载（地板 + 实体 + 粒子三层）后五项均可测——`r1_render_mean` / `r1_render_p95_spike` / `r3_total_frame_share` 取 full 态整帧 GPU 时间；`r3_entity_render` / `r3_particles` 用四态显隐 Δ 隔离法（full / no_entity / no_particles / base）测得边际 GPU 成本，并经 `delta_isolation` 闭合校验。
- **结论**：本批 G1 在真实 GPU PC 上可闭合 **R1** 与 **R3** 的渲染预算（`r3_entity_render` / `r3_particles` 已由四态 Δ 隔离法实测）。

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
   - **一键封装（推荐）**：上述四轮 + 逐轮 `verify` + `project.godot` 自动还原，可用脚本 `tools/qa/run_g1_probe.ps1` 完成（用法见脚本头部 `.EXAMPLE`）。脚本以 `--user-data-dir` 把 CSV 落到 `evidence/pc_win_02/userdata/<round_id>/`，并自动调用 `verify_probe_evidence.py`；`--build-sha` 必填实际构建 SHA。
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
| `r3_entity_render` | `r3_entity_render` | 四态 Δ 隔离：Δ = mean(full) − mean(no_entity)（frame_gpu_ms），target < 4 / < 8 |
| `r3_particles` | `r3_particles` | 四态 Δ 隔离：Δ = mean(full) − mean(no_particles)（frame_gpu_ms），target < 3 / < 6 |

> 帧时间样本（`frame_gpu_ms` / `frame_cpu_ms` / `frame_wall_ms`）只写逐样本长表、标 `E1_PNG8_FRAME_NOT_A_BASELINE`，不进 19 列 verdict，仅作链路证据。

---

## 4. R3 子系统测量法（四态显隐 Δ 隔离，本批次已落地）

`r3_entity_render` / `r3_particles` 为**子系统级** GPU 时间；Godot `RenderingServer` 不暴露按 mesh / 粒子的单独计时。本批次探针已落地「**四态显隐 Δ 隔离**」法（见 `src/qa/probe_runner.gd::_collect_render_metrics` + `_build_render_load` / `_apply_phase_visibility`）：

- **负载**：固定 seed 布局构建与游戏同等的渲染负载——地板 `TileMapLayer` + 实体 `MultiMeshInstance2D`（12 实例）+ 浮尘 `CPUParticles2D`（24 粒子），相机视口固定；headless 不构建。
- **四态**：`full`（全可见）/ `no_entity`（隐实体层）/ `no_particles`（隐粒子层）/ `base`（实体+粒子全隐，仅地板+UI），各采 `--frame-samples` 帧、各预热 `--warmup-frames` 帧。
- **Δ 派生**：`Δ_entity = mean(full) − mean(no_entity)`、`Δ_particles = mean(full) − mean(no_particles)`；逐对索引构造 Δ 样本，使 mean 严格等于两段均值差、p95 反映逐帧边际波动，原始 Δ 样本写入 raw 长表供 `verify_probe_evidence.py` 复算。
- **闭合校验**：`delta_isolation` 笔记输出 `d_base_total = mean(full) − mean(base)` 与残差 `d_base_total − (Δ_entity + Δ_particles)`，残差超容差（max(0.3ms, 20%)）即 `WARN_CLOSURE_DRIFT`，提示温度漂移 / 耦合，须复核。

**R3 现已可在真实 GPU PC 上由 Δ 隔离实测闭合**——五项 `verdict` 全 `pass`（R1 三项 + R3 二项）且核验脚本 PASS、手动字段齐全，即计 G1 闭合。headless 下仍 `blocked`，CI 不受影响。

---

## 5. 诚实性约束（沿用 _template）

- 严禁把 GUT tick 数 / Python 仿真 / headless 自检输出换算成设备 ms 耗时。
- 严禁抄目标预算充当实测值。
- G1 实测数据**只**来自真实 GPU PC 窗口 / 全屏采集；headless 输出不得回填本表。
- R1/R3 CONCERNS 不因平台变更、导出成功、采集完成、数据回填或 CI 全绿自动翻转。

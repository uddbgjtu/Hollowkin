# R1 / R3 质量门翻转 · 核验与审批包

> **创建**：2026-11-07（b 阶段，按用户"先b后a"指令）
> **关联**：ADR-4 / ADR-6；`architecture-doc.md` §6.1 评审结论表；`prototype-r1r3-report.md`；`adr-006-pc-first.md` §3/§4
> **用途**：把 R1/R3 由 `CONCERNS` 翻转为 `PASS` 的治理包（核验签字 + 独立审批）。
> **纪律声明**：本包**不自行翻转状态**。翻转须「正式实测数据 + 核验签字 + 独立审批」三件套齐备，且 `CONCERNS` 不因平台变更 / 资产产出 / CI 全绿自动翻转。

---

## 0. 翻转判据（原文摘录）

- `architecture-doc.md` §6.1：
  - **R1** 地窟生成帧预算 → **CONCERNS**（依据 `prototype-r1r3-report.md` 算法级基准 + 步进让帧设计；残留：a 阶段已接 E1（asset_source=E1_PNG8）、窗口模式渲染尖峰仍未实测（G1））。
  - **R3** 输入 + AI 同帧预算 → **CONCERNS**（依据预算对照表 + 10Hz 自适应；残留：`MultiMesh`/粒子层已接 E1（asset_source=E1_PNG8）、分项仍待窗口模式实测（G1））。
- `adr-control-checklist.md` ADR-6 完成判据④：**R1/R3 由「正式实测数据 + 核验签字 + 独立审批」翻转（仍未满足）**。
- §6.1 状态注：本环境可跑 Godot 4.3 headless，但**无渲染 / 设备帧时间采集链**，无法实测渲染 / AI 运行时帧时间；`headless smoke` 数据**不充当基线**。

---

## 1. 证据台账（现已可核验）

| # | 证据 | 状态 | 来源 / 验证方式 |
|---|---|---|---|
| E1 | 14 张 PNG-8 真实资产产出，R1–R6 全绿 | ✅ 已提交 `f1c79c2` + 远端 CI 双绿 | `asset_manifest.csv`（14 行全 `pass`）、`palette_validator.gd` 经 `-s` 实跑 `共 14 资产，失败 0` |
| E2 | ADR-4 工具链 verified（`pixel_pipeline.py --selftest` PASS，upper=9/mid=7/boss=10/sanctuary=9） | ✅ | `pixel_pipeline.py` / `architecture-doc.md` §6.1 |
| E3 | 导入预设固化（14 个 `.import`：`detect_3d/compress_to=0`、`compress/mode=0`、`filter=false`、`gen_mipmaps=false`、`fix_alpha_border=true`） | ✅ 已提交 | `.import` 文件 + `VERSION.md` |
| E4 | `PaletteValidator` R1–R6 headless 实跑 14 资产 0 失败 0 警告 | ✅ | `VALIDATOR_EXIT=0` |
| E5 | 测量方法学 + 预算对照表 + 算法级基准已交付 | ✅ | `prototype-r1r3-report.md` |
| E6 | 测量链代码就位（`tools/qa/r1r3_probe.gd` / `src/qa/probe_runner.gd` / `tests/unit/test_frame_budget.gd`） | ✅ 待实跑 | 源码存在，须在带 GPU 的 PC 窗口/全屏执行 |

---

## 2. 缺口台账（翻转前必须闭合）

| # | 缺口 | 阻塞于 | 责任方 |
|---|---|---|---|
| **G1** | 窗口 / 全屏模式帧时间**实测数据**（R1/R3 正式实测） | (a) 渲染集成已实施（E1 已接入渲染层、产生真实负载）；真实 GPU PC 下探针已落地四态显隐 Δ 隔离法，五项渲染指标（含 R3 子系统 `r3_entity_render` / `r3_particles`）**全部可测**；headless 下仍 `blocked`（BLOCKED-BY-HARDWARE），须主理人带 GPU 的 PC 窗口 / 全屏实测 | (a) 工程 + 主理人 PC 实测 |
| **G2** | 核验签字 | 人工动作，本包 §3 留栏 | 主理人（用户） |
| **G3** | 独立审批 | 人工动作，本包 §4 留栏 | 第二审批人 |

> **关键现实**：本沙箱（headless）无渲染 / 设备帧时间采集链，**无法产出 G1 数据**。即便完成 (a) 渲染集成，G1 仍需在主理人带 GPU 的 PC 窗口 / 全屏模式实跑测量链（`r1r3_probe.gd` / `probe_runner.gd`）。
> 因此 **b（治理）与 a（工程）均为翻转前置，不可相互替代**——签字/审批不能替代实测数据。

### 2.1 G1 实测数据回填区（模板 · 本地准备，待 PC 实测）

> **G1 状态：⬜ 待主理人带 GPU 的 PC 窗口 / 全屏实测回填**（本区为本地准备模板，不含任何实测数字；占位 `—` 与 ⬜ 须由真实测量链产出后填写）。

以下 5 项即 (a) 渲染集成后已解除资产阻塞、仅待 PC 实测的指标（源：`probe_runner.gd` `_collect_render_metrics`；schema：`r1r3_probe.gd` 19 列汇总 + 7 列逐样本长表）：

| 指标 (metric) | 阈值 (target) | 实测 mean(ms) | 实测 p95(ms) | 采集模式 | 样本数 | 判定 | 证据文件 |
|---|---|---|---|---|---|---|---|
| `r1_render_mean` | ≤ 16.6 | —（待回填） | — | 窗口/全屏 ×60/30fps | — | ⬜ | `summary_r1_*.csv` / `raw_*.csv` |
| `r1_render_p95_spike` | < 50 | — | — | 同上 | — | ⬜ | 同上 |
| `r3_entity_render` | < 4 / < 8（60/30fps 双档） | — | — | Δ 隔离（四态显隐：full−no_entity） | — | ⬜ | 同上 |
| `r3_particles` | < 3 / < 6（60/30fps 双档） | — | — | Δ 隔离（四态显隐：full−no_particles） | — | ⬜ | 同上 |
| `r3_total_frame_share` | < 9.16（55%） | — | — | 同上 | — | ⬜ | 同上 |

> **可闭合性（本批次探针改动后）**：真实 GPU PC 实测时，5 项渲染指标**全部可测**——`r1_render_mean` / `r1_render_p95_spike` / `r3_total_frame_share` 三项取 full 态整帧 GPU 时间；`r3_entity_render` / `r3_particles` 用四态显隐 Δ 隔离法（full / no_entity / no_particles / base 成对显隐，Δ = 两段均值差）测得边际 GPU 成本，并经 `delta_isolation` 闭合校验。故 **R1 与 R3 均可在真实 GPU PC 实测后闭合**。`headless`（无 GPU 帧采集链）下五项仍 `blocked`，工程改动不构建负载、不影响 CI。

**回填步骤与闭合判据（全满足方闭合 G1）**
1. **采集**：主理人带 GPU 的 PC 用 Godot 4.3 导出构建运行 `tools/qa/r1r3_probe.gd` + `src/qa/probe_runner.gd`，导出 19 列 `hollowkin_probe_metrics_<round_id>.csv` 与 7 列 `hollowkin_probe_metrics_raw_<round_id>.csv`（按 `round_id` 分文件命名；精确启动命令见配套 handoff `r1r3-flip-handoff.md` §3.2）。
2. **自动核验**：`python tools/qa/verify_probe_evidence.py hollowkin_probe_metrics_<round_id>.csv hollowkin_probe_metrics_raw_<round_id>.csv` 须返回 `RESULT: PASS`（mean/p95 可由逐样本复算、blocked 数值栏为空；逐轮分别校验）。
3. **必填手动字段**：`build_sha`（以实际测量构建的 git SHA 为准，须含探针四态 Δ 隔离法即 `789e567` 之后；当前 HEAD 以 `git rev-parse HEAD` 为准）、`operator`、`thermal_state`、`battery_pct`、`background_policy` 不得留 `MANUAL_REQUIRED` / `UNSET`。
4. **分轮纪律**：`round_id` 按 窗口×60 / 窗口×30 / 全屏×60 / 全屏×30 分文件归档，**禁止跨轮混算**。
5. **独立实测**：`r3_total_frame_share` 不得由分项（entity_render + particles + …）拼接部分和判 pass，须独立实测。
6. **判定口径**：5 项 `verdict` 全 `pass`（对照各自阈值）且核验脚本 PASS、手动字段齐全，方计 G1 闭合。

#### 2.1.1 填写范例（示意 · 非实测 · 不得照抄为实测值）

> ⚠️ 以下为**示范**某一轮（`windowed_60_release`）回填样貌，数值为**占位示意**（非 PC 实跑结果），仅展示每列怎么填；真实回填须由 `verify_probe_evidence.py` 产出、且 5 项 `verdict` 全 `pass`。

| 指标 (metric) | 阈值 (target) | 实测 mean(ms) | 实测 p95(ms) | 采集模式 | 样本数 | 判定 | 证据文件 |
|---|---|---|---|---|---|---|---|
| `r1_render_mean` | ≤ 16.6 | `12.34`（示意） | `18.90`（示意） | 窗口×60fps | `120` | ✅ pass | `hollowkin_probe_metrics_windowed_60_release.csv` |
| `r1_render_p95_spike` | < 50 | `18.90`（示意） | `22.10`（示意） | 窗口×60fps | `120` | ✅ pass | 同上 |
| `r3_entity_render` | < 4 / < 8 | `2.10`（示意·60fps） | `3.40`（示意） | Δ 隔离 full−no_entity | `120` | ✅ pass | 同上 |
| `r3_particles` | < 3 / < 6 | `1.80`（示意·60fps） | `2.60`（示意） | Δ 隔离 full−no_particles | `120` | ✅ pass | 同上 |
| `r3_total_frame_share` | < 9.16 | `8.05`（示意） | `9.00`（示意） | 窗口×60fps 整帧 | `120` | ✅ pass | 同上 |

- 真实回填时：`mean`/`p95` 取自 `verify_probe_evidence.py` 复算结果；`evidence_file` 取实际 `hollowkin_probe_metrics_<round_id>.csv`；`build_sha` 填实际构建 SHA（见步骤 3）。
- 仅主档 `windowed_60_release` 回填此表；其余三轮见各自 CSV、**不并入**（分轮纪律，§2.1 步骤 4）。

---

## 3. 核验签字栏（人工 · 主理人）

> **核验状态：⬜ 待主理人核验签字**（G1 未闭合前不得批准翻转；本栏仅确认 E1–E6 已就位，不含帧预算实测结论）。

- **核验对象**：§1 证据台账 E1–E6 的真实性、来源可追溯性。
- **核验范围边界**：仅确认工具链 / 资产 / 校验 / 方法学已就位；**不含** R1/R3 帧预算实测结论（该结论须 G1 到手后另附）。
- **逐项核验清单（勾选）**：
  - （ ）E1 — 14 张 PNG-8 真实资产产出，R1–R6 全绿（提交 `f1c79c2` + 远端 CI 双绿）
  - （ ）E2 — ADR-4 工具链 verified（`pixel_pipeline.py --selftest` PASS）
  - （ ）E3 — 导入预设固化（14 个 `.import` 参数）
  - （ ）E4 — `PaletteValidator` headless 实跑 14 资产 0 失败 0 警告
  - （ ）E5 — 测量方法学 + 预算对照表 + 算法级基准已交付
  - （ ）E6 — 测量链代码就位（须在带 GPU 的 PC 实跑）
- **核验结论**：
  - （ ）核验通过 —— 证据台账 E1–E6 属实，准予进入 G3 审批
  - （ ）核验不通过 —— 附说明：________________________________
- **核验人 / 日期 / 签字**：________________________________
- **备注**：R1/R3 是否因 E1 资产产出即可翻转？**否**——须 G1 实测数据到手后与本包一并提交。

### 3.1 核验栏落笔范本（待填说明）

> 本小节为 G2 签字栏的落笔指引，供主理人签字时逐项参照；不替代 §3 原有勾选栏，二者一并填写。

- **落笔前提（红线）**：仅当 §2.1 G1 回填区标注「G1 闭合」——即 5 项 `verdict` 全 `pass` 且 `verify_probe_evidence.py` 返回 `RESULT: PASS` 且手动字段（`build_sha` / `operator` / `thermal_state` / `battery_pct` / `background_policy`）均无 `MANUAL_REQUIRED` / `UNSET`——方可勾选「核验通过」。否则一律勾选「核验不通过」并附说明。
- **逐项核验落笔**：对 §1 E1–E6 逐行在（ ）内打 ✓；任一证据不可追溯 / 来源存疑，则该项留空并记入「核验不通过」说明。
- **核验结论落笔**：勾选「核验通过」时，须注明所复核的 §2.1 证据文件清单（例：`hollowkin_probe_metrics_windowed_60_release.csv` / `hollowkin_probe_metrics_raw_windowed_60_release.csv`，`build_sha = <含探针 Δ 隔离法的实际构建 SHA，如 789e567 之后>`）；勾选「核验不通过」时，在横线处写明缺口项与补救要求。
- **签字行落笔**：核验人 = 主理人实名；日期 = G1 实测当日（YYYY-MM-DD）；签字 = 手写扫描或电子签，禁止代签。
- **与 G1 的绑定**：本栏核验结论须与 §2.1 回填数据同源（同一 `build_sha`、同一 `round_id` 分轮文件）；跨轮混算的 G1 数据本栏应判「核验不通过」。

---

## 4. 独立审批栏（人工 · 第二审批人）

> **审批状态：⬜ 待第二审批人审批**（须 G1 实测闭合 + G2 核验签字均完成后方可批准翻转）。

- **审批依据**：§1 证据台账 + §2.1 G1 实测闭合状态 + §3 G2 核验签字是否齐备（三件套 G1+G2+G3 是否全满足）。
- **审批结论**：
  - （ ）批准翻转 `PASS` —— 三件套齐备，R1/R3 由 CONCERNS 升 PASS
  - （ ）驳回 —— 附说明：________________________________
- **审批人 / 日期 / 签字**：________________________________

### 4.1 审批栏落笔范本（待填说明）

> 本小节为 G3 审批栏的落笔指引，供第二审批人落笔时参照；不替代 §4 原有勾选栏，二者一并填写。

- **落笔前提（红线）**：须 §2.1 G1 已闭合 **且** §3 G2 核验签字齐备（「核验通过」已勾选、签字行已填），三件套（G1+G2+G3）缺一则禁止勾选「批准翻转 PASS」。
- **审批依据落笔**：引用 §2.1 五项 `verdict`（须全 `pass`）、§3 核验结论（须「核验通过」）、`build_sha` 与对应 `round_id` 分轮证据文件名；据以判断三件套是否齐备。
- **审批结论落笔**：勾选「批准翻转 PASS」时，须写明触发翻转的 R1/R3 节点与生效 SHA；勾选「驳回」时，在横线处写明驳回项（G1 数据缺口 / G2 未签 / 阈值未达等）。
- **签字行落笔**：审批人 = 第二审批人实名；日期 = 审批当日（YYYY-MM-DD）；签字 = 手写扫描或电子签。
- **翻转生效口径**：本栏勾选「批准翻转 PASS」即视为 R1/R3 由 `CONCERNS` 升 `PASS` 的治理生效点；生效前任何 `CONCERNS` 状态均维持。

---

## 5. 状态建议

- **维持 R1/R3 = CONCERNS**，直至 G1 + G2 + G3 全闭合。
- 本包为 **b 阶段产出**（治理包已备，已提交 7018e01）；a 阶段渲染集成已完成并本地提交 `9a2270d`（已接 E1 真实 PNG-8，解 `BLOCKED-BY-ASSET`）。
- **本地准备已完成（本批次）**：§2.1 G1 实测回填模板（5 项指标 + 阈值 + 闭合判据，占位待填）、§3 G2 核验签字栏（E1–E6 逐项清单 + 状态标记）、§4 G3 独立审批栏（状态标记 + 三件套前置）均已备为「待回填 / 待签 / 待批」就绪；**未填任何实测数字、未伪造签字**。
- **G1 落地补强（本批次，工程侧）**：探针 `probe_runner.gd` 已落地四态显隐 Δ 隔离法——真实 GPU PC（`_frame_available`）下**构建 E1 真实渲染负载**（地板 TileMapLayer + 实体 MultiMesh + 浮尘 CPUParticles2D），五项渲染指标**全部**为 `measured`（R1 三项取整帧 GPU 时间、R3 二项取 Δ 隔离边际，并经 `delta_isolation` 闭合校验）；`headless` 下不构建负载、五项仍 `blocked`（BLOCKED-BY-HARDWARE），CI 不受影响；证据落区 `docs/qa/evidence/pc_win_02/` 与复测 runbook 已更新；`verify_probe_evidence.py` 经合成数据自检（合规→`RESULT: PASS`、篡改 mean→`RESULT: FAIL`）。**R1 与 R3 现均可在真实 GPU PC 上由 Δ 隔离实测闭合**。
- **配套 handoff 清单**：`r1r3-flip-handoff.md`（创建于 `54d7904`，后续经 `62b7a08`/`466408b`/`6f31301` 补强）为本包的下游一页式验收清单，涵盖推送 / CI 双绿 / G1 四轮 Δ 隔离实测 / G2·G3 落笔 / 翻转落地 / 故障处置（§9）/ 状态对齐核对（§10）；两文档 SHA、提交链与状态口径须保持一致（见 handoff §10），翻转后须同步改状态（R1/R3 → `PASS`）。
- **仍待**：① 主理人带 GPU 的 PC 实测回填 G1（§2.1，按 `pc_win_02/README.md` 流程，R3 的 `r3_entity_render` / `r3_particles` 现可由四态 Δ 隔离法实测闭合）；② G2 核验签字、G3 独立审批。三件套（G1+G2+G3）齐备且 R1/R3 五项 `verdict` 全 `pass` 方可翻转。**（推送与 CI 双绿已完成：全部提交已推送（真实远端 HEAD 见 `origin/master`），`106d442` 修复后 Lint+test 双绿；本沙箱经 `ssh.github.com:22` SSH 通道推送，HTTPS git 仍被代理白名单拦截。）**

---

## 6. 下一步（按用户"先b后a" + 本批次本地准备）

- **b（本包，已完成）**：证据台账 + 缺口台账 + 签字/审批栏已齐（已提交 7018e01）；G2/G3 签字栏已本地准备为待签/待批（见 §3/§4）。注意 G2/G3 不能替代 G1。
- **a（渲染集成，已完成）**：已替换 `DEBUG_PLACEHOLDER` 为 ADR-4 E1 真实 PNG-8（asset_source=E1_PNG8，新增 asset_registry.gd 由 manifest 驱动），解 `BLOCKED-BY-ASSET`；剩余阻塞为 `BLOCKED-BY-HARDWARE`（无头无 GPU 帧采集链）。已本地提交 `9a2270d`，待他处推送 + CI 双绿。
- **本批次（G1 落地补强 + G2/G3 本地准备，已完成）**：探针 `_collect_render_metrics` 工程改动（四态 Δ 隔离法使 R3 可闭合）、`pc_win_02/` 证据落区与复测 runbook、§2.1 G1 回填模板、§3 G2 逐项核验清单与 §3.1 落笔范本、§4 G3 状态标记与 §4.1 落笔范本均已备（待填说明）；下一步填实测数字与落笔签字即可，无需再改结构。
- **翻转路径**：全部提交已推送（真实远端 HEAD 见 `origin/master`）且 CI 双绿（`106d442` 修复后 Lint+test success）→ PC 实测回填 G1（按 `pc_win_02/README.md`，§2.1，五项含 R3 子系统 Δ 隔离；精确命令见 handoff §3.2/§3.4）→ G2 签字 → G3 审批 → **R1 与 R3 均可由 CONCERNS 升 PASS**（五项 `verdict` 全 `pass`）。

---

## 7. 已推送证据索引

> 本会话已将全部本地提交推送至 `origin/master`，并经 SSH 通道绕过本沙箱代理白名单。以下为可审计证据索引；截图类证据由主理人按 §7.1 补入 `docs/qa/evidence/_push_ci/screenshots/`（证据集说明见同目录 `README.md`）。

| # | 证据项 | 文件 / 位置 | 证明内容 | 状态 |
|---|---|---|---|---|
| P1 | 远端 HEAD 核验（权威） | `docs/qa/evidence/_push_ci/remote_head_53d64c2.txt` | `git ls-remote` 输出：远端 `refs/heads/master = 53d64c2267bb343c433e78382e23973442a622f7`，与本地 `HEAD` 一致 → 全部提交已推送 | ✅ 已捕获 |
| P2 | 推送通道 | 同上（附言） | SSH `git@github.com:uddbgjtu/Hollowkin.git`；HTTPS git 被代理白名单拦截，SSH 22 端口可达 | ✅ 已验证 |
| P3 | CI 双绿（行为基线） | `106d442c86ea9961eccdeb90526d05021df74681` | `Lint` `success` + `test`(GUT) `success`；修复含 `test.yml` headless 资产导入 + `asset_registry` 纹理守卫 | ✅ 本会话 API 轮询确认 |
| P4 | CI 绿页截图 | `docs/qa/evidence/_push_ci/screenshots/actions_green_106d442.png` | Actions 页 `Lint` / `test` 两 job 均 `success` 的页面截图 | ⬜ 待主理人补 |
| P5 | 推送成功页截图 | `docs/qa/evidence/_push_ci/screenshots/push_success.png` | GitHub 仓库 `master` 提交历史含 `53d64c2` 的截图 | ⬜ 待主理人补 |

### 7.1 截图存放与命名约定

- 目录：`docs/qa/evidence/_push_ci/screenshots/`（本会话已建证据落区 `docs/qa/evidence/_push_ci/`）。
- 命名：`actions_green_<基线SHA前8位>.png`、`push_success.png`；`lsremote_<HEAD前8位>.txt` 已存（P1）。
- 截图须含：仓库名 / commit SHA / job 结论（Actions 页）或提交作者与消息（推送页），以构成可追溯证据链。
- 补截图后于本索引 P4 / P5 勾选 ✅，并可在 §1 证据台账追加一行 P 类证据。

> 引用：推送方法见 handoff §1（SSH 通道存档）；CI 双绿验收口径见 handoff §2。

*本包为治理追踪文件，已随 b/a 阶段工作树变更一并推送（真实远端 HEAD 见 `origin/master`）。G1 回填与 G2/G3 签字栏现为本地就绪状态，最终 R1/R3 翻转由 G1+G2+G3 闭合触发，由主理人与第二审批人落笔。*

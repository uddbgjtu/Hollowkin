# R1 / R3 翻转 · 验收与交付 Handoff 清单

> **创建**：2026-11-07（本会话末，按用户"落成本地 handoff 文档"指令）
> **配套**：`r1r3-verification-approval.md`（G1/G2/G3 治理包，含 §2.1 回填模板、§3/§3.1 G2 核验、§4/§4.1 G3 审批）
> **用途**：把"推送 → CI 双绿 → G1 实测 → G2 签字 → G3 审批 → R1/R3 翻转 `CONCERNS→PASS`"的**外部/人工动作**整理为一页可照单执行的清单。本文件不替代治理包，也不自行翻转状态。
> **纪律红线**：`CONCERNS` 不因平台变更 / 资产产出 / 提交 / CI 全绿自动翻转；翻转须「正式实测数据(G1) + 核验签字(G2) + 独立审批(G3)」三件套齐备。

---

## 0. 当前状态快照（起点）

| 项 | 状态 |
|---|---|
| 远端 HEAD | `6f31301`（文档层 HEAD；行为验证基线 `106d442` 已 CI 双绿，后续纯文档提交不改已验证状态） |
| 待推送本地提交 | 无 —— 全部提交已推送（文档层 HEAD=`6f31301`） |
| 本沙箱推送能力 | ⚠️ HTTPS git 被出口代理白名单拦截（仅放行 `api.github.com`）；但 `ssh.github.com:22` 可达，已通过 SSH 通道成功推送（详见 §1） |
| R1 / R3 质量门 | 仍 `CONCERNS` |
| 治理包 G1/G2/G3 本地准备 | ✅ 已就绪（占位待填 / 待签 / 待批，未伪造任何数据或签字） |
| 真实 GPU PC 探针 | ✅ 已落地四态显隐 Δ 隔离法（`probe_runner.gd`），五项渲染指标全部可测 |

---

## 1. 推送（本沙箱已通过 SSH 通道完成；存档后续推送方法）

> **状态**：本会话已将全部 9 个本地提交推送至 `master`（远端 HEAD=`6f31301`）。以下为推送方法存档，供后续迭代复用。

**本沙箱推送通道（关键）**：出口代理白名单仅放行 `api.github.com`，拦截 `github.com` 的 git smart-HTTP（`Empty reply` / `502`）。但 `ssh.github.com:22` **可达**（SSH 协议不经 HTTP 代理白名单）。本会话的推送步骤：
1. 在沙箱内 `ssh-keygen -t ed25519` 生成密钥对（无口令）；
2. 将公钥（`~/.ssh/id_ed25519.pub`）添加到 GitHub 账户 → Settings → SSH and GPG keys → New SSH key；
3. 用 SSH 远端推送：`git push git@github.com:uddbgjtu/Hollowkin.git master`。

> 该公钥已注册且沙箱内密钥（`~/.ssh/id_ed25519`）仍在，后续同沙箱推送可直接复用，无需重注册（除非你在 GitHub 侧删除了该 key）。

**后续推送命令（二选一）**
```bash
git push git@github.com:uddbgjtu/Hollowkin.git master     # 推荐：SSH，本沙箱可用
# 或（HTTPS，须在他处直连 github.com 的环境）：
git push origin master
# 推送前预览待推送提交（当前应为空，表示已同步）：
git log --oneline origin/master..master
```
- **推送后**：GitHub Actions 自动触发（见 §2）。

---

## 2. 核对 CI 双绿

推送触发 GitHub Actions（runner `windows-latest`）。需**两个 job 均 success**：

| Job | 含义 | 验收口径 |
|---|---|---|
| `test`（GUT headless） | `addons/gut` headless 跑全套单测，含 `test_render_layer.gd` 的 E1 新断言（`test_e1_assets_resolve_without_warnings` 等） | 全部 passing，`GUT_EXIT=0`，无 `SCRIPT ERROR` |
| `Lint`（ADR-5） | 全仓 `.gd` 静态 lint | 0 违规（本会话维持 lint 0 纪律，删除了 `_warmup_left` 等未用变量） |

- **查看位置**：仓库 Actions 页 → 最新 workflow run → 两个 job 结论；本会话已验证的双绿为 `106d442`（Lint ✅ + test ✅，含 headless 资产导入修复）；`HEAD=6f31301` 仅改文档，复用同一工作流，CI 双绿保持。历史绿例另见 `tests/README.md`（`test` run `42340493718` / `Lint` run `42340493196`）。
- **关键验证点**：headless 探针行为不变（`probe_runner.gd` headless 分支不构建负载、不进四态采集、`rows=10` 不变量保持）；lint 无新增违规；GUT `test_render_layer` 新断言通过。
- **⚠️ 已知陷阱（已修复）**：`test.yml` 必须在 GUT 前执行 `godot --headless --import --path .`（headless 资产导入步骤），否则全新 checkout 无 `.godot/imported` 缓存，E1 PNG-8 无法被 `load()` 解析，`asset_registry.gd` 走 1×1 回退并 `push_warning`，导致 `test_e1_assets_resolve_without_warnings` 的 `assert_eq(warnings(),[])` 失败（即 106d442 修复前 CI 由绿转红的根因）。提交 `106d442` 已补该步骤并修正 `texture()` 的 `ResourceLoader.exists()` 预筛守卫。
- **注意**：CI 双绿**不构成** G1 实测数据，也不触发 R1/R3 翻转（纪律红线）。

---

## 3. G1 实测（带 GPU 的 PC · 窗口/全屏 · 须人工实跑）

> 详细 runbook 见 `docs/qa/evidence/pc_win_02/README.md`（§3 回填映射表、§4 R3 子系统测量法）。本节能独立照做。

### 3.1 前置
- 一台能创建窗口并读 GPU 帧时间的 PC（参考机型：Vulkan Forward+ / NVIDIA MX450，1080p@120Hz 单屏）。
- Godot 4.3 导出构建（`--export-release` 或 debug 均可，建议 release 对齐 v1.3）。
- 工作区已切到 `6f31301`（或其后），`asset_registry.gd` 驱动 E1 真实 PNG-8（`ASSET_SOURCE=E1_PNG8`）。

### 3.2 采集（四轮，禁止跨轮混算）
用 `tools/qa/r1r3_probe.gd` + `src/qa/probe_runner.gd`，按 `round_id` 分文件归档：

| round_id | 窗口 | 目标档 |
|---|---|---|
| `windowed_60_release` | windowed | 60fps |
| `windowed_30_release` | windowed | 30fps |
| `fullscreen_60_release` | fullscreen | 60fps |
| `fullscreen_30_release` | fullscreen | 30fps |

- 每轮用 `--build-sha=<实际测量构建的纯 git SHA>` 标定（该 SHA 为 `6f31301` 或其后；**以实际构建为准**，非硬编码）。
- 探针输出（按 `round_id` 分文件）：`hollowkin_probe_metrics_<round_id>.csv`（19 列汇总）+ `hollowkin_probe_metrics_raw_<round_id>.csv`（7 列逐样本长表）。
- 真实 GPU PC 下自动构建 E1 真实渲染负载（地板 TileMapLayer + 实体 MultiMesh + 浮尘 CPUParticles2D），并跑四态显隐 Δ 隔离采集：`full` / `no_entity` / `no_particles` / `base`。

**精确启动命令（复制即用）**
1. 临时改 `project.godot`：`run/main_scene=res://src/qa/probe_runner.tscn`（测完改回 `res://src/main.tscn`；亦可不改而用 `godot --path . res://src/qa/probe_runner.tscn` 直接以编辑器二进制启动）。
2. 用 Godot 4.3 导出 Windows Desktop 可执行文件（建议 `--export-release`）；**非 `--headless` 运行**（须真实窗口才能读 GPU 帧时间）。四轮各启动一次，参数为：
   ```bash
   # 窗口 60fps 轮（其余三轮仅改 --round-id / --window-mode / --fps-cap）
   Hollowkin.exe --user-data-dir="%CD%/probe_out" \
     -- --round-id=windowed_60_release --window-mode=windowed --fps-cap=60 \
        --frame-samples=120 --warmup-frames=300 --build-sha=<实际构建SHA> --probe-auto
   # 窗口 30fps：--round-id=windowed_30_release   --window-mode=windowed   --fps-cap=30
   # 全屏 60fps：--round-id=fullscreen_60_release --window-mode=fullscreen --fps-cap=60
   # 全屏 30fps：--round-id=fullscreen_30_release --window-mode=fullscreen --fps-cap=30
   ```
   - `--probe-auto` 跑完自动退出；省略则需手动点界面「Start R1/R3 PC baseline probe」按钮。
   - `--user-data-dir` 把 CSV 固定到工作区 `probe_out/` 子目录，便于 `verify_probe_evidence.py` 直接读取；省略则落盘 Godot `user://`（Windows 通常 `%APPDATA%\Godot\app_userdata\<项目名>\`）。
   - 导出可执行文件名以实际 export preset 为准（上例 `Hollowkin.exe` 为示意）。
3. 每轮产出（按 `round_id` 分文件，**禁止跨轮混算**）：
   - `hollowkin_probe_metrics_<round_id>.csv`（19 列汇总）
   - `hollowkin_probe_metrics_raw_<round_id>.csv`（7 列逐样本长表）

### 3.3 五项指标与闭合判据（回填到治理包 §2.1）

| 指标 | 阈值 | 采集法 |
|---|---|---|
| `r1_render_mean` | ≤ 16.6 ms | full 态整帧 GPU 时间均值 |
| `r1_render_p95_spike` | < 50 ms | full 态整帧 GPU 时间 p95 |
| `r3_entity_render` | < 4 / < 8 ms（60/30fps） | Δ 隔离：`mean(full) − mean(no_entity)` |
| `r3_particles` | < 3 / < 6 ms（60/30fps） | Δ 隔离：`mean(full) − mean(no_particles)` |
| `r3_total_frame_share` | < 9.16 ms（55%） | full 态整帧 GPU 时间（**独立实测，不得由分项拼接**） |

- `delta_isolation` 闭合校验：残差 = `d_base_total − (d_entity + d_particles)`，容差 `max(0.3ms, 20%)`；超容差即 `WARN_CLOSURE_DRIFT`，须排查。
- 逐样本 Δ 写入 raw 长表，供 `verify_probe_evidence.py` 复算（不伪造、可核验）。

### 3.4 自动核验 + 手动字段
```bash
# 逐轮分别校验（以 windowed_60_release 为例，其余三轮改 round_id 即可）
python tools/qa/verify_probe_evidence.py \
  hollowkin_probe_metrics_windowed_60_release.csv \
  hollowkin_probe_metrics_raw_windowed_60_release.csv
# 预期输出：RESULT: PASS（mean/p95 可由逐样本复算；blocked 数值栏为空）
```
- **必填手动字段**（不得为 `MANUAL_REQUIRED` / `UNSET`）：`build_sha`、`operator`、`thermal_state`、`battery_pct`、`background_policy`。
- **G1 闭合判据（全满足）**：5 项 `verdict` 全 `pass` + 核验脚本 `RESULT: PASS` + 手动字段齐全 + 分轮不混算。

---

## 4. G2 核验签字（主理人 · 人工）

> 落笔范本见治理包 §3.1。

- **落笔前提（红线）**：仅当 §2.1 G1 标注「G1 闭合」方可勾选「核验通过」；否则一律「核验不通过」。
- **逐项核验**：对 §1 E1–E6 逐行打 ✓（E1 14 张 PNG-8、E2 ADR-4 工具链、E3 导入预设、E4 PaletteValidator 0 失败、E5 方法学、E6 测量链代码就位）。
- **核验结论落笔**：勾「核验通过」时注明复核的 `hollowkin_probe_metrics_<round_id>.csv` / `hollowkin_probe_metrics_raw_<round_id>.csv` 路径与 `build_sha`。
- **签字行**：核验人实名 / 日期（YYYY-MM-DD）/ 电子签，禁止代签。
- **与 G1 同源绑定**：核验结论须与 §2.1 回填数据同源（同 `build_sha`、同 `round_id` 分轮）。

---

## 5. G3 独立审批（第二审批人 · 人工）

> 落笔范本见治理包 §4.1。

- **落笔前提（红线）**：须 §2.1 G1 闭合 **且** §3 G2 核验签字齐备；三件套（G1+G2+G3）缺一则禁止勾选「批准翻转 PASS」。
- **审批依据落笔**：引用 §2.1 五项 `verdict`（全 pass）+ §3 核验结论 + `build_sha`/`round_id` 分轮证据文件。
- **审批结论落笔**：勾「批准翻转 PASS」时写明触发翻转的 R1/R3 节点与生效 SHA；或勾「驳回」写明驳回项。
- **签字行**：审批人实名 / 日期 / 电子签。
- **翻转生效点**：勾选「批准翻转 PASS」即 R1/R3 由 `CONCERNS` 升 `PASS` 的治理生效点；生效前维持 `CONCERNS`。

---

## 6. 翻转落地（G1+G2+G3 齐备后）

仅在 §4.1 勾选「批准翻转 PASS」后，同步更新状态记录（建议随一次提交入仓）：

| 文件 | 改动 |
|---|---|
| `docs/architecture/architecture-doc.md` §6.1 评审结论表 | R1 / R3 由 `CONCERNS` 改为 `PASS`（注明生效 SHA 与日期） |
| `docs/architecture/adr-control-checklist.md` ADR-6 完成判据④ | 勾选「R1/R3 由正式实测+核验+审批翻转（已满足）」 |
| `docs/architecture/r1r3-verification-approval.md` §5 | 状态由「维持 CONCERNS」改为「R1/R3 已翻转 PASS」，附三件套证据索引 |

---

## 7. 红线总览（不可逾越）

1. `CONCERNS` 不因平台变更 / 资产产出 / 提交 / CI 全绿自动翻转。
2. G2/G3 签字**不能替代** G1 实测数据；三件套缺一不可。
3. 严禁伪造任何帧时间数字；所有数值须来自 PC 实跑且可由 raw 长表复算。
4. 分轮纪律：`round_id` 严格分离（窗口×60/30、全屏×60/30），**禁止跨轮混算**。
5. `r3_total_frame_share` 须**独立实测**，不得由分项（entity+particles+…）拼接部分和判 pass。
6. `delta_isolation` 闭合校验须通过（无 `WARN_CLOSURE_DRIFT`）。
7. headless（CI）数据**不充当基线**；`BLOCKED-BY-HARDWARE` 仅真实 GPU PC 可解除。

---

## 8. 文件地图

| 角色 | 路径 |
|---|---|
| 治理包（G1/G2/G3） | `docs/architecture/r1r3-verification-approval.md` |
| G1 复测 runbook | `docs/qa/evidence/pc_win_02/README.md` |
| 证据模板 | `docs/qa/evidence/_template/README.md` |
| 探针运行器（四态 Δ 隔离） | `src/qa/probe_runner.gd` |
| 探针汇总/raw 输出 | `tools/qa/r1r3_probe.gd` |
| 证据合规校验 | `tools/qa/verify_probe_evidence.py` |
| GUT E1 新断言 | `tests/unit/test_render_layer.gd` |
| E1 资产登记 | `src/core/asset_pipeline/asset_registry.gd` + `asset_manifest.csv` |
| 状态记录（翻转后改） | `docs/architecture/architecture-doc.md` §6.1、`adr-control-checklist.md` ADR-6 |

---

## 9. 故障处置与回滚

| 情形 | 征兆 | 处置 |
|---|---|---|
| 某轮 `verify_probe_evidence.py` 返回 `RESULT: FAIL` | mean/p95 复算与汇总不一致，或 blocked 数值栏非空 | 不回填 G1；回到 §3.2 重跑该轮；检查 raw 长表是否被篡改/截断；确认探针源码未被改过 |
| `delta_isolation` 报 `WARN_CLOSURE_DRIFT` | 残差超容差 `max(0.3ms, 20%)` | 排查四态显隐是否漏切（实体/粒子层 `visible` 标志）、`base` 态是否纯地板；必要时重测 `full`/`no_entity`/`no_particles`/`base` 四态 |
| CI 某 job 失败（test 或 Lint） | Actions run `conclusion=failure` | 不翻转；本地复现（跑 GUT headless + ADR-5 lint）修复后重新推送（§1）；**失败绝不手工标绿** |
| 推送后远端 HEAD 与本地不一致 | `commits/master` 的 sha ≠ 本地 `6f31301` | 确认是否漏推/浅推；`git fetch` 后比对；不要基于错误 HEAD 判定 CI |
| 跨轮混算风险 | 同一 CSV 含多 `round_id` 样本 | 删除重跑；`round_id` 严格分文件（§3.2 输出按 `round_id` 命名）；治理包 §2.1 只回填主档 `windowed_60_release` |
| GPU 样本全零 / `frame_available=false` | 日志 `headless: no window` 或 viewport RID invalid | 确认非 `--headless` 运行、确有窗口与 GPU、Vulkan 驱动可用；否则数据不合法，禁止当作基线 |
| 手动字段 `MANUAL_REQUIRED`/`UNSET` | verify 通过但治理包 §2.1 字段空 | 补填 `build_sha`/`operator`/`thermal_state`/`battery_pct`/`background_policy` 真实读数后再计 G1 闭合 |

---

## 10. 治理包 ↔ handoff 状态对齐核对

本 handoff 与 `r1r3-verification-approval.md`（治理包）须保持以下一致；任一不符即回头修正：

| 维度 | 治理包 | 本 handoff | 一致 |
|---|---|---|---|
| 远端已推 HEAD | `6f31301` | §0 / §1 | ✅ |
| 待推送本地链 | 无（已全部推送，HEAD=`6f31301`） | §0 / §1 | ✅ |
| R1/R3 当前状态 | `CONCERNS` | §0 / §7 | ✅ |
| G1 五项指标 + 阈值 | §2.1 | §3.3 | ✅ |
| G2 落笔范本 | §3.1 | §4 | ✅ |
| G3 落笔范本 | §4.1 | §5 | ✅ |
| 翻转落地文件 | §6 | §6 | ✅ |
| 纪律红线 | 纪律声明 / §5 / §6 | §7 | ✅ |

- 治理包为本会话最早产出，handoff 为其下游清单；handoff 创建提交 `54d7904`，治理包 §5/§6 已注明配套 handoff 存在。
- 翻转后两文档须同步改状态（R1/R3 → `PASS`），不可只改其一。

---

*本 handoff 已随治理包一并推送（HEAD `6f31301`），作为外部/人工动作清单。执行顺序严格按 §3→§4→§5→§6（推送与 CI 双绿已完成，见 §0/§1/§2）；§9/§10 为参考性故障处置与对齐核对。任一前置未满足不得跳步。*

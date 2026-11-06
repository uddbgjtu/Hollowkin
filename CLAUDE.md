# CLAUDE.md · 《深窟兽语 / Hollowkin》工程协作指南

> 本文件为项目根级协作真源，规定引擎版本钉定、导入预设、随机性纪律、资产管线红线与协作禁项。
> 架构真源见 `docs/architecture/architecture-doc.md`；ADR 落地追踪见 `docs/architecture/adr-control-checklist.md`。

---

## 1. 项目身份
- **类型**：像素风 Roguelike（**PC / Windows Desktop 单平台**）
- **目标平台**：Windows Desktop；**移动端 iOS / Android 已彻底放弃**（不再是目标平台，也不作为后续可选移植，见 ADR-6）
- **引擎**：Godot 4（见 §2 钉定）
- **语言**：GDScript（主）；Python（仅离线资产后处理工具链）
- **架构真源**：`docs/architecture/architecture-doc.md`（8 业务模块 + 2 跨切服务）
- **设计契约**：`design/gdd/*`、`design/gdd/mvp-spirit-bestiary.md` v1.2（灵兽权威）
- **平台契约**：`docs/architecture/adr-006-pc-first.md`（ADR-6 · 唯一新真源）

> ⚠️ **ADR-6 平台变更（2026-11-06 · 用户批准「C · PC 优先 / 移动端彻底放弃」）**：本文件及 Phase 1–4 历史文档中的「移动端 iOS / Android、触屏单手、竖屏 720×1280、≥48px 触控命中区、单局 5–10 分钟碎片」等条款**已废止**，不再作为约束；历史原文保留在 git 变更记录中，未静默删除。**ADR-1/2/3/4/5、C1、Godot 4.3 冻结、随机性 / 资产 / 存档纪律全部不变。**

---

## 2. 引擎版本钉定（Godot 4.3 · 已签字冻结）

> ✅ **已签字确认（2026-11-03）**：Godot **4.3** 为冻结次版本。升级须走"主理人审批 + 回归测试 + 修订本文档"三步，任何人不得擅自升/降级主版本或次版本。

- **钉定版本**：Godot **4.3**（用户 2026-11-03 签字冻结；全员统一此单一次版本）。
- **钉定规则**：
  - 全工程统一单一次版本，写入本文件 §2 与工程 `project.godot` 的 `config_version` 语义范围。
  - 主版本（4.x）与次版本（4.x.**N**）一经签署即冻结；升级须走"主理人审批 + 回归测试 + 修订本文档"三步。
  - 严禁在个人或 CI 环境使用不同次版本打开工程（避免 `.import` / 资源格式漂移）。
- **知识缺口记录**：若实际采用次版本超出本模型训练数据，须先补 `docs/engine-reference/godot/VERSION.md` 并回报工程负责人，再落地相关 API。

---

## 3. 像素资产导入预设（ADR-4 · 防偏色/渗色）【强制】

> 背景：Godot 默认图片导入为 Compress（BPTC），会对像素资产**偏色/渗色**；必须显式改预设。
> 资产须由离线脚本产出 PNG-8 索引色（见 §6），Godot 仅按目录导入预设接收。

### 3.1 导入预设（目录级 `.import` 或工程 Import Presets）
对每个像素资产目录应用以下覆写：

| 属性 | 值 | 含义 |
|---|---|---|
| `compress/mode` | `0`（Lossless）或 `1`（Uncompressed） | 像素最稳用 `1`；体积敏感用 `0`。**禁止**默认 Compress |
| `filter` | `false`（即 `flags/filter=false`） | 关双线性过滤，防羽化/模糊 |
| `gen_mipmaps` | `false` | 关 mipmap，防缩小时偏色与渗色 |
| `flags/repeat` | `false` | 像素资产不重复采样 |
| `detect_3d/compress_to` | 关 | 2D 像素资产不转 3D 压缩 |

### 3.2 校验（CI / 编辑器）
- `src/core/asset_pipeline/palette_validator.gd`（`EditorScript`/`EditorPlugin`）：断言每资产 ≤16 色且取自母库（`art-bible.md` §2.2），否则**阻断导入**。
- CI 在提交资产时跑校验；偏色/超色资产不得合入。
- **预设固化真源**：`docs/engine-reference/godot/VERSION.md`（引擎版本待签字 + ADR-4 导入覆写清单）+ `docs/engine-reference/godot/pixel_texture.import.tpl`（Godot 4 `.import` 模板）。新增像素资产目录须套用该预设。

---

## 4. 随机性纪律（ADR-5 · 单一出口）【强制 · 违者 CI 拦截】

- **唯一随机出口**：所有随机性（地窟生成、掉落表、战斗方差、敌人模板）一律经 `src/core/rng/rng_service.gd` 派生的种子化 `RandomNumberGenerator` 实例。
- **种子派生**：`floor_seed = hash_mix(run_seed, floor_index)`；每层独立 `RandomNumberGenerator.seed`（见 `architecture-doc.md` §1.9 / §3.1）。
- **🚫 禁止（CI lint 拦截）**：
  - 全局 `randf()` / `randi()` / `randomize()` 调用（除 `RNGService` 内部封装）。
  - 任何模块自建未种子化的随机源或绕过 `RNGService` 直接取随机。
  - CI 落地：`tools/ci/lint_no_global_random.py`（ENG-4）扫描 `**/*.gd` 全局随机调用并阻断；白名单仅放行 `src/core/rng/rng_service.gd`（RNGService 单一出口封装本身），实例方法 `rng.randf()`/`rng.randi()` 因前置 `.` 自动放行。
- **理由**：任一随机源绕开种子即破坏 ADR-1 存档重建一致性（同 (seed,floor) 重建与事件日志错位）。CI 以正则检查 `randf()`/`randi()`/`randomize()` 的全局调用并阻断。

---

## 5. 仿真与表现解耦纪律（ADR-2 / ADR-3）【强制】

- **输入**：所有输入事件（PC 键鼠经适配层转同构 `{"position", "touch_id"}` 字典）入 `InputQueue`，**帧末结算**，不立即改仿真（ADR-2）；触屏事件专属措辞自 ADR-6 起废止，**队列语义不变**。
- **AI**：`SimulationClock` 固定 **10Hz** tick（每 0.1s 一步），`MAX_CATCHUP=3`；移动/动画逐帧插值，决策不入每帧（ADR-3）。
- **禁止**：在 `_process`/`_physics_process` 每帧做锁敌/寻路/技能决策（须走 10Hz tick）；多指即时改写仿真状态（须走队列）。

---

## 6. 资产后处理红线（ADR-4 · 脚本唯一出口）【强制 · 人工绕过即违规】

- **唯一出口**：AI 生成图 → 离线脚本（`src/core/asset_pipeline/pixel_pipeline.py`，Python + Pillow）完成「降采样→≤16 色索引→补描边→2×2 抖动」，**人工不得跳过**。
- **禁止**：手工改色/重量化/直接塞非索引 PNG 进工程；用引擎内 shader 实时像素化替代离线脚本。
- **登记**：每资产登记 `asset_manifest.csv`（seed/提示词摘要/色数/校验），作为 CI 校验与版权溯源依据（美术圣经 §6 / 附录 B）。
- **版权**：所有资产标注"AI-assisted, human-directed"；核心角色（驯导者 + 4 灵兽）最终建议人工精修金标准（美术圣经附录 B 风险 1）。

---

## 7. 数据契约纪律（C1 · StatBlock 乘算）【强制】

- **属性公式**：`FinalStat = (Base + ΣVeinAdd) × ΠRuneMult`（灵脉加算基底 + 符文独立乘区）。
- **符文字段**：灵囊符文条目用 **`mult:{stat:factor}`**（乘算），**禁止** `mods:{stat:delta}`（加算，旧命名）。
- **唯一真源**：`src/core/stats/stat_block.gd`（Resource）；run 起始算基底缓存、符文变动重算乘区缓存、每击 O(1)（见 `architecture-doc.md` §3.3）。

---

## 8. 协作规范与禁止事项（汇总）

### 8.1 必须遵守
- 任何新随机点：显式传参走 `RNGService`，不隐式取全局随机。
- 新资产：经 §6 脚本产出 + §3 导入预设 + §3.2 校验通过。
- 新模块：对齐 `architecture-doc.md` §1 模块边界；随机源/属性注入/存档须落在指定模块。
- 破坏性改动（引擎版本、导入预设、随机出口、**平台定位**）：先更本文档 + 主理人审批。ADR-6 平台变更已于 2026-11-06 履行该流程（先更本文件 §1，再改下游真源文档）。

### 8.2 禁止事项（红线）
| 禁项 | 依据 | 拦截方式 |
|---|---|---|
| 全局 `randf()/randi()/randomize()` | ADR-5 | CI lint 正则拦截 |
| 人工绕过像素后处理脚本 | ADR-4 | Code Review + manifest 校验 |
| 默认 Compress 导入像素资产（偏色） | ADR-4 | 导入预设 + 校验 |
| 符文用 `mods` 加算字段 | C1 | 静态检查 / Review |
| 每帧做 AI 决策 | ADR-3 | Review / 架构评审 |
| 直接改仿真状态的输入即时处理 | ADR-2 | Review |
| 擅自升/降级 Godot 次版本 | §2 | 工程锁 + Review |

---

## 9. 构建与 CI 建议
- **CI 检查项**：① RNG 全局随机调用拦截（§4）；② 资产 `PaletteValidator` 校验（§3.2）；③ 静态检查符文字段命名（§7）。
- **不 git commit 原则**：本文件与架构文档由负责人显式产出；自动化提交须人工审批（见团队规范）。
- **文档真源**：架构/ADR/原型结论以 `docs/architecture/*` 为准，本文档仅钉定工程纪律与版本。

---

*本 CLAUDE.md v1.1（2026-11-06 按 ADR-6 更新项目身份、平台契约与输入措辞）钉定 Godot 4.3（已签字冻结）、导入预设、随机性/资产/契约纪律与协作禁项。未执行 git commit。*

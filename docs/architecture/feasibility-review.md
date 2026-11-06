# 《深窟兽语 / Hollowkin》Phase 2 技术可行性评审报告
> ⚠️ **ADR-6 状态声明（2026-11-06 · Wave 2）**：本文件为Phase 2 技术可行性评审报告（历史评审记录）。原「移动端 iOS / Android、触屏单手、竖屏 720×1280、≥48px 触控命中区、低端机真机判据」条款**已由 `docs/architecture/adr-006-pc-first.md` 废止**；现行契约为 **Windows Desktop 单平台（横屏 1280×720、键鼠输入、单局 10–20 分钟）**。下文保留的移动端表述均为当时的评审 / 测量 / 裁定原文，仅作历史记录，不得据此推导现行设计；R1 / R3 仍为 **CONCERNS**，PC 基线待 Wave 4 建立，CONCERNS 不自动翻转。历史原文保留于 git 变更记录，未静默删除。

> **评审人**：程基岩（Cheng Jiyan）· 工程负责人 / 引擎架构
> **引擎**：Godot 4（Phase 2 评审时目标平台 iOS / Android 触屏单手；**已由 ADR-6 废止**，现为 Windows Desktop 单平台）
> **阶段**：Phase 2 设计侧文档完成 → 技术可行性评审（Lean）
> **输入文档**：概念文档 v0.1、美术圣经 v0.2、战斗/灵囊/灵脉图谱三份 GDD v0.1、可访问性需求 v1.0、MVP 灵兽剪影清单 v1.0
> **产出**：ADR ×5、逐系统可行性结论、工程风险与降级、GDD 不一致清单、需拍板项

---

## 0. 总判定：**CONCERNS（技术可行，但受 3 项产品决策 + 2 项低端机风险约束）**

- 三份 GDD 的**核心机制在 Godot 4 + 当时的移动端约束下均技术上可落地**（Phase 2 历史结论），无 FAIL 项。
- 但本评审结论成立依赖三项**外部产品决策尚未拍板**：**E-A 层内中断策略**、**C3 元进度经济转化率**、**C4 灵兽命名回填状态**。其中 E-A 直接决定 ADR-1 存档架构的形态，必须在转入实现规划前拍板。
- 另有两项**性能风险**（程序生成卡顿、输入并发+AI 同帧开销；ADR-6 后重定位为 PC 基线）需以原型验证，已给出降级路径。
- **建议**：当前可进入"Story 拆解 + 原型验证"阶段；E-A/C3/C4 拍板可与 P3 实现并行，但 ADR-1 的存档落地须等 E-A 落定。

---

## 1. ADR（架构决策记录）

> 格式：状态 / 上下文 / 决策 / 备选 / 后果 / Godot 4 落地 / 风险。所有 ADR 须与项目钉定引擎版本兼容（见 §1.6 知识缺口）。

### ADR-1 · 程序生成地窟的可恢复存档架构
- **状态**：拟采纳（**依赖 E-A 产品决策**）
- **上下文**：PC 进程被强杀 / 断电（ADR-6 等价场景；原表述为移动端 iOS/Android 来电、切后台、低电量被系统 kill）；地窟为程序生成、含战斗与构筑状态。需要（1）崩溃/中断后可恢复、（2）存档体积小、（3）低端机写入快。
- **决策**：采用 **「种子 + 层号 + 事件日志（command-log）」混合方案**：
  - **地窟布局**：不存任何瓦片状态，仅存 `run_seed` + `floor_index`；进入某层时用**确定性 RNG（ADR-5）**重建完全相同布局（房间拼接、敌人刷新、掉落表）。
  - **run 时刻决策**：以**确定性事件日志**记录玩家主动决策序列——驯服哪只灵兽、镶嵌哪枚符文、层间抉择选项——重放即还原临时构筑。
  - **永久进度**：`ember_eternal` + 灵脉节点激活记录为**独立小快照**，节点激活即存（即时存档点，见灵脉 GDD §5）。
  - **存档时机**：仅在**层间硬存档点**写入（E-A 假设：层内中断=放弃本层，不写半截战斗）。`application_paused` 时同步落盘（量极小）。
  - **损坏回退**：读档失败 → 丢弃 run 存档，回退庇护所（永久进度不受影响）。
- **备选**：
  - *A. 全状态快照*（每存档点序列化全部实体/血量/位置）：实现直白但体积大、低端机写入慢、战斗中途难保证一致性 → **否决**。
  - *B. 纯命令日志全量重放*（含战斗每击）：可恢复性最强，但战斗确定性要求极高、重放成本高 → **否决**（超出 Lean 需求）。
- **后果**：存档体积极小（种子+层号+短日志 ≈ 数百字节 / 永久快照 ≈ 数 KB），崩溃恢复稳健；要求**生成与战斗的随机性全部种子化**（ADR-5），并对"层内中断=放弃本层"做产品承诺（否则需升级为 B 方案）。
- **Godot 4 落地**：`user://save_run.cfg`（`ConfigFile`，存 seed/floor/log）、`user://save_meta.cfg`（ember+节点）。`_notification(NOTIFICATION_APPLICATION_PAUSED)` 触发同步写。原型片段见 §6.1。
- **风险**：若 E-A 改为"允许层内恢复"，本方案须扩展为持续命令日志（本格式已预留 append-only 升级空间，无需重写）；战斗随机性种子化若遗漏任一随机源，重建会与日志错位 → 须在生成/战斗模块强制走统一 RNG。

### ADR-2 · 输入并发仲裁（原「触屏输入并发仲裁」，ADR-6 后按 PC 键鼠重订）
- **状态**：拟采纳
- **上下文**：PC 键鼠并发需同时处理「移动键 + 2 个技能键 / 点击 + 自动普攻（无输入）」。多输入并发下若每事件即时作用于仿真，会出现移动吞掉技能点击、拖拽误触、冷却重复触发等问题（战斗 GDD §6.4）。
- **决策**：**单一活跃指针 + 固定热区独立命中 + 帧末事件队列结算**：
  - **浮动摇杆独占一个 pointer（touch_id）**：仅当触摸起始落在摇杆死区拖出时归摇杆所有；其余触摸不归摇杆。
  - **技能按钮/冷却环为独立 Control 热区**：各自 `_gui_input` 命中判定，与摇杆所用 pointer 互不抢占。
  - **所有输入入队**：PC 键鼠事件经适配层转同构字典、由 `_input` 推送至 `InputQueue`，**不立即改仿真状态**（ADR-2 队列语义不变）。
  - **帧末结算**：每个仿真 tick（ADR-3 的 10Hz）消费一次队列，按热区归并；技能重复触发**去重**，`cd` 下限钳 0.5s（战斗 GDD §6.4）。
- **备选**：
  - *A. 每事件即时处理*（多指针 FSM）：响应最快但并发仲裁复杂、低端机重复求值 → **否决**。
  - *C. 纯每帧轮询按钮状态*：简单但无法处理滑动手势与多指 → **否决**。
- **后果**：输入与仿真解耦，行为在 30/60fps 设备一致；滑动技能需位移 >12px 判定（战斗 GDD §2.3）天然适配队列；实现略增（需 InputQueue 单例 + 热区注册表）。
- **Godot 4 落地**：`InputQueue`（RefCounted 单例）+ `HitZone.resolve(pos)` 热区注册表；GUI 用 `Control._gui_input`；摇杆用 `Viewport` 拖拽捕获 `touch_id`。原型片段见 §6.2。
- **风险**：低。PC 下 `touch_id` 恒为 0、仅作兼容标识；原 iOS 多指 `index` / Android 指序变化风险随移动端彻底放弃而移除。

### ADR-3 · 自动战斗 / 灵兽协战 AI 定步长
- **状态**：拟采纳（对应工程默认 E-B）
- **上下文**：自动普攻 + ≤3 灵兽自动协战 + 杂兵群 + 精英/Boss，若每帧（`_process`/60Hz）做锁敌/寻路/技能决策，低端机 CPU 开销大、且 30/60fps 设备行为不一致、耗电高。
- **决策**：**AI 决策固定 10Hz tick（每 100ms 一步），非每帧**：
  - 自定义累加器时钟 `SimulationClock`：累加 `delta`，每满 0.1s 跑一次 `tick()`；上限追帧 3（防后台恢复雪崩）。
  - `tick()` 内完成：锁敌/目标选择、寻路决策、技能释放决策、灵兽协战决策、伤害事件结算（帧末队列）。
  - **移动/动画仍逐帧**（视觉平滑），但只读取 AI 给出的目标/方向，不在每帧重算决策。
  - **省电自适应**：连续超帧预算时降频至 5Hz；关屏/后台暂停 tick。
- **备选**：
  - *A. 每帧 AI*：行为最顺滑但 CPU/耗电翻倍、跨帧率不一致 → **否决**。
  - *C. 纯 `_physics_process`（60Hz）做 AI*：Godot 物理固定 60Hz，但会强制 AI 与物理同频，无法独立降到 10Hz 省电 → **否决**（方案 B 用自定义累加器更优）。
- **后果**：AI 计算量降至 1/6，跨设备行为一致，电池友好；移动插值需单独处理（否则 10Hz 转向显顿——用逐帧 lerp 朝向/位置即可）。
- **Godot 4 落地**：`SimulationClock`（`Node`，`_process` 累加）；与 ADR-2 队列联动——tick 消费输入队列。原型片段见 §6.3。
- **风险**：低。需注意「判定延迟」——10Hz 下技能响应最大 ~100ms，对低操作频率的桌面设计可接受；若实测手感偏钝，可仅对"玩家主动技能"走即时通道、AI/协战走 10Hz。

### ADR-4 · 像素资产后处理链路接入 Godot 导入管线
- **状态**：拟采纳（对应工程默认 + 美术圣经 §6）
- **上下文**：AI 生成"伪像素图"需经「降采样→≤16 色索引→补描边→2×2 抖动」后处理（美术圣经 §6.1）。须保证跨帧/跨角色一致，且导入 Godot 后**不偏色、不羽化**。
- **决策**：**离线脚本产出 PNG-8 索引色 → Godot 按目录导入预设（Lossless + 关 filter/mipmap）**：
  - 后处理用脚本（Python+Pillow）离线完成：最近邻缩放到 16/24 网格 → 套用场景 ≤16 色母库子集索引 → 补 1–2px 描边 → 2×2 抖动；输出 PNG-8 并登记 `asset-manifest.csv`（seed/提示词/色数/校验）。
  - Godot 导入：该目录 `.import` 覆写 `compress/mode=0`（Lossless）或 `1`（Uncompressed，像素最稳）、`filter=false`、`gen_mipmaps=false`、`detect_3d/compress_to=...` 关。Godot 会展开为 RGBA，但 16 色由**离线脚本+manifest 校验保证**，非引擎格式要求。
  - **入库校验**：编辑器/CI 跑 `PaletteValidator`（§6.5），断言每资产 ≤16 色且取自母库，否则阻断导入。
  - **自动战斗检索/复用**：帧动画用预烘焙 `AnimatedSprite2D`（无需运行时调色板查表）；如需队伍染色，用调色板 LUT `Shader`（可选，MVP 不做）。
- **备选**：
  - *B. 引擎内 shader 实时像素化/索引*：运行时开销、一致性难控 → **否决**。
- **后果**：资产一致性可控、零运行时后处理成本；代价是离线脚本开发与 manifest 维护（美术圣经附录 B 风险 2 已建议默认=是）。
- **Godot 4 落地**：`import` 覆写 + `EditorScript`/`EditorPlugin` 跑校验；`MultiMeshInstance2D` 批量同帧敌人贴图。原型片段见 §6.5。
- **风险**：中。PNG-8 在部分工具链会被重新量化；务必以脚本为唯一出口、禁止人工绕过（美术圣经 §6.1 强制链路）。Godot 4 默认图片导入为 Compress（BPTC），**必须显式改预设**，否则偏色/渗色。

### ADR-5 · 程序生成 RNG 种子化
- **状态**：拟采纳（ADR-1 的前置依赖）
- **上下文**：ADR-1 的地窟重建要求"同一 (run_seed, floor) → 同一布局"；否则存档恢复会与事件日志错位。
- **决策**：**单一 run 级种子派生各层种子，全随机源统一走 `RandomNumberGenerator`**：
  - `floor_seed = hash_mix(run_seed, floor_index)`，每层独立 `RandomNumberGenerator.seed`。
  - 房间拼接、敌人模板挑选、掉落表、甚至战斗暴击/方差**全部**取自此层 RNG（战斗方差属瞬时结果，无需进存档；但生成与掉落必须确定性）。
  - 禁止用 `randf()`/`randi()` 全局随机——强制 `rng.*` 实例。
- **备选**：每层用独立真随机种子 → 无法重建 → **否决**。
- **后果**：生成完全可复现，存档体积极小；代价是生成代码须集中管理 RNG 实例，新增随机点须显式传参。
- **Godot 4 落地**：`RandomNumberGenerator`（`seed` 属性）、自定义 `HashUtil.hash_mix`。原型片段见 §6.4。
- **风险**：低，但**纪律性要求高**——任一随机源绕开种子即破坏 ADR-1。建议在生成/战斗模块用封装层统一出口。

---

## 2. 逐系统可行性结论

| 系统 | 结论 | 瓶颈 / 备注 |
|---|---|---|
| **战斗系统 GDD** | **CAVEAT（中—高）** | 机制、伤害公式、10Hz AI、输入并发均可行；**瓶颈=① E-A 层中断策略（产品待决，影响存档）② E1 程序生成可靠性/低端机性能（待原型）③ 输入+AI 同帧帧预算（ADR-6 后为 PC 基线）**。无技术性阻断。 |
| **灵囊系统 GDD** | **PASS（低备注）** | 三栏自动分拣/镶嵌/序列化可行；**备注=① P1 数据契约由 C1 统一方案覆盖，但 Pouch GDD 字段命名须对齐（见 §4 冲突 1）② P2 序列化体积受 E-A 约束已界定 ③ 重复灵兽蛋处理待拍板**。 |
| **灵脉图谱 GDD** | **PASS（低备注）** | 节点激活/DAG/run 快照/永久存档可行；**V1 契约=C1 已给统一式、V2 与 run 存档解耦、V3 节点尺寸历史裁定（ADR-6 后改键鼠口径）**。无新增风险。 |

**逐系统要点**
- **战斗**：伤害公式 `Final=clamp(Mitigated×CritMult×RuneMult×Variance,1,99999)` 完整无溢出（§3.5），clamp/钳制齐备；10Hz tick（ADR-3）与帧末队列（ADR-2）已覆盖 E2/E3；E1（生成）与 E4（存档）分别对应 ADR-5/ADR-1。FAIL 项：无。
- **灵囊**：容量（12/24/24）、自动入栏、符文镶嵌、物资使用、队伍上限 `party_slots=3` 均为标准数据结构；唯一技术债是"符文 `mods` 加算 vs C1 乘算"的契约对齐（非不可行）。
- **灵脉**：`MODIFY_STAT`/`UNLOCK_SKILL`/`GRANT_START` 三类节点、DAG 静态校验（构建期断言）、run 起始快照、激活即时持久化——皆标准实现；与战斗的注入契约由 C1 解决。

---

## 3. 工程风险与降级方案

### R1 · 程序生成地窟（房间拼接 / 种子化 / 低端机性能）— **高优先**
- **风险**：每进入一层用 `TileMapLayer.set_cell()` 批量写入数十~数百瓦片，低性能设备（ADR-6 后为 PC 下限档）可能出现**生成卡顿（帧尖峰）**；房间拼接算法若失败需保底。
- **降级 / 缓解**：
  1. **分步生成 + `await` 让帧**：生成器按房间/区域分片，跨帧 `await get_tree().process_frame` 摊薄，避免单帧尖峰（不阻塞主线程）。
  2. **保底模板层**：生成超时/异常 → 切预制安全层（战斗 GDD §6.2），记录日志。
  3. **内存缓存**：同 run 内 (seed,floor) 布局缓存，重进不重算。
  4. **碰撞/导航批处理**：非碰撞瓦片不加碰撞体；用统一 `NavigationRegion2D` / 简化碰撞多边形，降物理开销。
  5. **低端机降密度**：依 `OS.get_model_name()`/GPU 档位动态下调房间数与敌人上限。
- **需实测验证（ADR-6 重定位）**：在 PC 窗口 / 全屏基线实测单层生成耗时与峰值帧时间（Wave 4），定预算（建议 ≤ 1 帧 16.6ms 均摊，尖峰 < 50ms）。

### R2 · 可中断存档（PC 进程强杀 / 断电等价场景）— **高优先 · 依赖 E-A**
- **风险**：PC 进程可被强杀 / 断电；若 E-A 为"层内中断=放弃本层"，仅层间落盘即可（简单稳健）；**若改为"层内可恢复"**，需持续命令日志，复杂度与确定性要求骤升。
- **降级 / 缓解**：
  1. **按 E-A 假设**：仅层间硬存档点写 `save_run.cfg`（种子+层号+日志），`application_paused` 同步落盘（量极小，毫秒级）。
  2. **格式前瞻兼容**：command-log 采用 append-only 结构，即便未来升级为"层内恢复"也无需重写存档层。
  3. **损坏回退**：读档异常 → 丢弃 run、回庇护所（永久进度独立、不受影响）。
  4. **依赖标注**：E-A 未拍板前，ADR-1 仅能完成"层间存档"实现，层内恢复实现须等决策。
- **知识缺口（ADR-6 重定位）**：Godot `NOTIFICATION_APPLICATION_PAUSED` 在进程被强杀 / 断电时**不一定触发**；须结合 `NOTIFICATION_WM_CLOSE_REQUEST` 与"进入庇护所/层间即存"双保险——**这是 PC 存档的真实边界，需在 Wave 4 基线中实测**。

### R3 · 输入并发 + 自动战斗 AI 同帧开销（帧预算 / PC 下限档掉帧）— **高优先**
- **风险**：键鼠移动 + 2 技能键 + 拖拽 + 自动普攻 + 10Hz AI + 多实体的同帧成本，可能击穿帧预算。
- **降级 / 缓解**（建议帧预算表）：

  | 子系统 | 60fps 预算(ms) | 30fps 预算(ms) | 策略 |
  |---|---|---|---|
  | 输入仲裁（ADR-2 队列） | < 0.5 | < 1.0 | 帧末单次结算，去重 |
  | AI tick（ADR-3，10Hz 摊薄） | ~1.66(均摊) | ~3.3 | 自适应降 5Hz |
  | 实体渲染（同屏敌人 ≤12） | < 4 | < 8 | `MultiMesh` + 离屏剔除 |
  | 粒子/特效 | < 3 | < 6 | 关屏/低档降密度 |

  1. **解耦**：输入帧末结算、AI 10Hz、移动逐帧插值——三者互不抢占（ADR-2/3）。
  2. **离屏剔除**：`VisibleOnScreenNotifier2D` 停用屏外实体 AI/动画。
  3. **对象池**：普攻弹幕/特效池化，禁每击 `instance()`。
  4. **自适应**：连续 N 帧超预算 → AI 降频 + 降同屏敌人/粒子；向玩家无感降级。
  5. **批量绘制**：同帧同类敌人/弹幕用 `MultiMeshInstance2D` 降 draw call。

### R4 · 灵脉→战斗 注入公式可行性（防"主导策略"）— **低优先 · 已解**
- **风险**：每击计算 `(Base+ΣVeinAdd)×ΠRuneMult` 若朴素实现，多符文/多源时可能成热点；更关键的是**数值层面防止单一系统主导**（设计正确性）。
- **缓解**：
  - `Base+ΣVeinAdd` **run 起始算一次**缓存；`ΠRuneMult` **符文变动时重算**缓存；每击仅 ~3 次乘算（O(1)），无热点。
  - 加算基底 + 独立乘区 = 凸增长，天然鼓励两系统并用，**避免"全堆灵脉或全堆符文"的线性主导**，契约 `FinalStat=(Base+ΣVeinAdd)×ΠRuneMult` 正确（见 §4 冲突 1 字段命名修正）。
  - `StatBlock` Resource 作唯一真源（§6 原型）。

### R5 · 像素资产后处理链路接入 Godot — **中优先**
- **风险**：AI→像素化→调色板索引→描边链路若不一致，跨帧/跨角色崩坏；Godot 默认 Compress 导入会偏色/渗色。
- **缓解**：离线脚本唯一出口（ADR-4）+ 目录导入预设（Lossless/Uncompressed + 关 filter/mipmap）+ `PaletteValidator` 编辑器/CI 阻断偏色资产。详见 ADR-4。

---

## 4. 与 GDD 不一致处（供主理人汇编）

> 含已知 C4 灵兽命名回填状态。以下冲突均"非技术阻断"，但须设计侧澄清/修订后再冻结。

1. **【C1 子冲突 · 高】符文 `mods` 加算 vs `RuneMult` 乘算**
   - 灵囊 GDD §3 定义符文条目 `mods: {stat: delta}`（读作**加算 delta**）；战斗 GDD §3.5 与工程默认 C1 明确 `RuneMult = Π(符文乘区)`（**乘算**）。
   - **结论**：采纳 C1 乘算方案（防主导策略）。**设计侧须将 Pouch GDD 的 `mods:{stat:delta}` 改名为 `mult:{stat:factor}`**（如 +20%→`mult:{atk:1.2}`），否则数据契约自相矛盾。技术可行，纯命名/语义对齐。

2. **【C4 · 路径/回填 · 中】灵兽命名引用路径 stale**
   - 战斗 GDD §3.3 / 灵囊 GDD §3 仍引用 `design/concept/mvp-beast-silhouette.md`（provisional 旧文件）；权威版为 `design/gdd/mvp-spirit-bestiary.md`（v1.0，已审计锁定）。
   - **内容已对齐**：4 只灵兽（苔背 Mossback / 焰角 Emberhorn / 霜铃 Frostling / 雷隼 Voltsprite）名称、定位、三角特征在 bestiary 与战斗 GDD 完全一致。
   - **行动**：战斗/灵囊 GDD 将引用路径改指向 `mvp-spirit-bestiary.md`；bestiary §7 待回填项（技能/数值/交互）仍由设计侧补完——**评审以 bestiary 4 只为准**，不依赖旧 provisional 文件。

3. **【C3 子歧义 · 中】"仅死亡触发"是否含"通关/胜利结束 run"**
   - 任务默认 C3：「临时币→永久灵烬 转化率 30%、**仅死亡触发**」。但核心循环存在"通关该层段→回庇护所"（非死亡）。若胜利 run 不转化 `coin_temp`，则与 P3「死亡不是惩罚，是节奏」及"单局必带回收益"矛盾。
   - **建议**：将"触发"解释为**任何 run 结束（死亡或通关）**，统一走死亡结算路径；否则胜利局将清零临时币，违背设计支柱。**需主理人/设计侧确认措辞**。

4. **【低 · 待拍板】重复灵兽蛋处理**
   - 灵囊 GDD §6.4：「同 species 蛋入栏标记 +1，不重复占格（**或独立格，待拍板**）」。未决，影响序列化结构与 UI；建议默认"+1 计数"降栏位压力。

5. **【低 · 范围注记】灵兽数量 5–8 vs 锁定 4**
   - 概念文档 §5 MVP 写"5–8 种（3–4 可驯服）"；bestiary 锁定 Lean 4 只可驯服。非冲突（概念为上限/愿景，bestiary 为 Lean 落地数），但建议概念文档补一句"Lean MVP 锁定 4 只"以消除读者歧义。

6. **【历史裁定 · ADR-6 后触控下限废止】节点视觉 44px vs 原触控命中区 ≥48px**
   - 灵脉 GDD §8/V3 已据 a11y §3.2 权威澄清闭环（视觉 44px、命中区 ≥48×48px、间距 ≥8px）。无需工程裁决。

---

## 5. 需用户 / 设计侧拍板项清单

| # | 项 | 类型 | 影响 | 建议默认 |
|---|---|---|---|---|
| **E-A** | 层内中断策略：确认"层内中断=放弃本层，保留永久灵烬，回庇护所" | 产品决策 | 决定 ADR-1 存档形态（层间 vs 层内恢复） | 采纳"放弃本层"（简洁稳健） |
| **C3** | 临时币→永久灵烬 转化率 30%；是否"仅死亡"还是"任何 run 结束" | 产品+数值 | 仅影响数值与结算触发口径，不影响架构 | 30% + 任何 run 结束均触发 |
| **C4** | 灵兽命名回填状态：战斗/灵囊 GDD 引用路径改指向 bestiary；bestiary §7 技能/数值回填排期 | 设计侧 | bestiary 已锁定 4 只，评审以此为准 | 改路径引用；回填项排期 Phase 2 |
| **P1/字段** | 灵囊符文 `mods:{stat:delta}` → 改为 `mult:{stat:factor}`（乘算，对齐 C1） | 设计侧 | 数据契约一致性 | 乘算命名 |
| **灵囊§6.4** | 重复灵兽蛋："+1 计数" vs "独立格" | 设计侧 | 序列化/UI 结构 | "+1 计数" |
| **概念§5** | 补"Lean MVP 锁定 4 只可驯服"注记 | 文档 | 消除范围歧义 | 补注 |

---

## 6. 验证原型片段（极简 GDScript，仅佐证，不落地实现）

> 仅作技术假设佐证，未写入 `src/`、未 commit、未修改 `design/` 与 `docs/` 之外目录。

### §6.1 ADR-1 种子化存档（损坏回退）
```gdscript
# 仅在层间硬存档点调用（E-A：层内中断=放弃本层）
const SAVE_RUN  := "user://save_run.cfg"   # run: seed + floor + 事件日志
const SAVE_META := "user://save_meta.cfg"  # 永久: ember + 节点激活（即时存）

func save_run(run_seed: int, floor_index: int, log: Array) -> void:
    var cfg := ConfigFile.new()
    cfg.set_value("run", "seed", run_seed)
    cfg.set_value("run", "floor", floor_index)
    cfg.set_value("run", "log", log)        # 确定性决策序列（驯服/镶嵌/层间抉择）
    assert(cfg.save(SAVE_RUN) == OK)

func load_run() -> Dictionary:
    var cfg := ConfigFile.new()
    if cfg.load(SAVE_RUN) != OK:            # 损坏/缺失 → 回退庇护所（run 清空）
        return {}
    return {"seed": cfg.get_value("run","seed"),
            "floor": cfg.get_value("run","floor"),
            "log": cfg.get_value("run","log", [])}
```

### §6.2 ADR-2 帧末输入队列（单一指针 + 热区独立 + 去重）
```gdscript
class_name InputQueue extends RefCounted
var _events: Array[InputEvent] = []

func push(e: InputEvent) -> void:
    _events.append(e)                       # GUI _input 推送，不立即改仿真

func consume_into(target: Object) -> void:  # 每个仿真 tick 消费一次（ADR-3）
    var seen := {}
    for e in _events:
        if e is InputEventScreenTouch and e.pressed:
            var hi := HitZone.resolve(e.position)   # 固定热区独立命中
            if hi != null and not seen.has(hi.id):
                seen[hi.id] = true
                target.on_action(hi.id)     # 冷却下限 0.5s 由技能系统钳制（GDD §6.4）
    _events.clear()
```

### §6.3 ADR-3 固定 10Hz 仿真时钟（与渲染解耦）
```gdscript
class_name SimulationClock extends Node
const TICK_DT := 0.1                        # 10Hz
const MAX_CATCHUP := 3                      # 防后台恢复追帧雪崩
var _accum := 0.0

func _process(delta: float) -> void:
    _accum += delta
    var n := 0
    while _accum >= TICK_DT and n < MAX_CATCHUP:
        _tick(); _accum -= TICK_DT; n += 1
    if n == MAX_CATCHUP: _accum = 0.0       # 丢弃积压

func _tick() -> void:
    InputQueue.consume_into(self)           # ADR-2：帧末队列
    CombatDirector.step_simulation(TICK_DT) # 锁敌/寻路/协战决策/伤害结算
```

### §6.4 ADR-5 种子派生（地窟可恢复重建）
```gdscript
func floor_seed(run_seed: int, floor_index: int) -> int:
    # 自定义混合哈希；同 (run_seed, floor) → 同布局
    var h := run_seed ^ (floor_index * 0x9E3779B1)
    h = (h ^ (h >> 16)) * 0x85EBCA6B
    return h & 0x7FFFFFFF

func new_floor_rng(run_seed: int, floor_index: int) -> RandomNumberGenerator:
    var rng := RandomNumberGenerator.new()
    rng.seed = floor_seed(run_seed, floor_index)
    return rng                              # 生成/掉落全程走此实例
```

### §6.5 ADR-4 调色板校验（编辑器/CI 阻断偏色）
```gdscript
func validate_palette(tex: Texture2D, allowed: Array, cap := 16) -> bool:
    var img := tex.get_image(); var used := {}
    for y in img.get_height():
        for x in img.get_width():
            var c := img.get_pixel(x, y)
            if c.a < 0.01: continue
            used[c.to_html()] = true
    if used.size() > cap: push_error("调色板 %d > %d" % [used.size(), cap]); return false
    for col in used.keys():
        if not allowed.has(col): push_error("母库外色: %s" % col); return false
    return true
```

### §6.6 C1 统一契约 `StatBlock`（加算基底 + 独立乘区）
```gdscript
# FinalStat = (Base + ΣVeinAdd) × ΠRuneMult
class_name StatBlock extends Resource
@export var base: Dictionary = {}           # stat -> float（主角原始 Base）
var _vein_add: Dictionary = {}             # run 起始结算一次
var _rune_mult_cache: Dictionary = {}      # 符文变动时重算缓存

func build_run_base() -> Dictionary:       # Base + ΣVeinAdd，仅一次
    var eff := {}
    for k in base: eff[k] = base[k] + _vein_add.get(k, 0.0)
    return eff

func recompute_rune_mult(runes: Array) -> void:   # 镶嵌/卸下时重算
    _rune_mult_cache.clear()
    for r in runes:
        for stat in r.mult:                 # ★ 对齐 C1：rune 提供乘区因子
            _rune_mult_cache[stat] = _rune_mult_cache.get(stat, 1.0) * r.mult[stat]

func final_stat(stat: String, run_base: Dictionary) -> float:  # 每击 O(1)
    return run_base.get(stat, 0.0) * _rune_mult_cache.get(stat, 1.0)
```

---

## 7. 结论与下一步

- **总判定：CONCERNS**——技术路线清晰、三系统均可行、ADR 体系完备，但受 **E-A / C3 / C4** 三项外部决策与 **R1 / R3** 两项低端机性能风险约束。
- **可立即推进**：Story 拆解、ADR-2/3/4/5 与 C1 契约的架构落地（不依赖 E-A）；灵脉 GDD 实现（PASS）。
- **须先拍板**：E-A（决定 ADR-1 实现边界）；C4（bestiary 已锁定，引用路径修订）；C3 措辞（死亡 vs 任何 run 结束）。
- **须实测验证（ADR-6 重定位）**：R1 单层生成耗时、R2 PC 进程强杀 / 断电时存档可靠性、R3 同帧帧预算——均改由 PC 窗口 / 全屏基线采集（Wave 4），原 iOS/Android 真机判据已废止。
- **工程侧建议补充**：建立 `CLAUDE.md`（钉定 Godot 4.x 次版本）+ `docs/engine-reference/godot/VERSION.md`，固化引擎版本与导入预设，避免多人协作偏离。

---

*本报告为 Phase 2 技术可行性评审产出，仅含评审/ADR 文档与佐证原型片段，未修改 `design/` 与 `docs/` 之外任何目录，未执行 git commit。*
